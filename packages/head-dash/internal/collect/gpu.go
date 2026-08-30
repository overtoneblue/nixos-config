package collect

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// GPU describes the single Intel iGPU. There is no card loop: head exposes one
// iGPU ("Iris Xe (iGPU)") and engine utilisation is streamed from the
// intel_gpu_top JSON engine, not scraped from hwmon/sysfs.
type GPU struct {
	Label      string
	FreqCur    int
	FreqMax    int
	HasFreq    bool
	RenderBusy int
	VideoBusy  int
	RC6Pct     float64
	HasPower   bool
	GPUPowerW  float64
	PkgPowerW  float64
	Client     string
	ClientBusy int
	HasClients bool
	OK         bool
	Err        string
	EngineNote string
}

const igpuDevice = "drm:/dev/dri/renderD128"

// igpuSample mirrors one intel_gpu_top -J JSON object. Only the fields the UI
// needs are unmarshalled; everything else (period, interrupts, ...) is ignored.
type igpuSample struct {
	Frequency struct {
		Requested float64 `json:"requested"`
		Actual    float64 `json:"actual"`
	} `json:"frequency"`
	RC6 struct {
		Value float64 `json:"value"`
	} `json:"rc6"`
	Power struct {
		GPU     float64 `json:"GPU"`
		Package float64 `json:"Package"`
	} `json:"power"`
	Engines map[string]struct {
		Busy float64 `json:"busy"`
	} `json:"engines"`
	Clients map[string]struct {
		Name    string `json:"name"`
		Engines map[string]struct {
			Busy float64 `json:"busy"`
		} `json:"engines"`
	} `json:"clients"`
}

// igpuStream is a process-wide cache of the latest intel_gpu_top sample,
// maintained by a background goroutine. It never blocks the UI: callers read the
// last sample under a short mutex and move on.
var igpuStream struct {
	start  sync.Once
	mu     sync.Mutex
	sample igpuSample
	have   bool
	note   string
}

// startIGPU ensures the streaming goroutine is running (exactly once).
func startIGPU() {
	igpuStream.start.Do(func() {
		go igpuLoop()
	})
}

// igpuLoop spawns intel_gpu_top, decodes the concatenated JSON stream from its
// stdout pipe sample-by-sample into the cache, and respawns the process (with a
// 1s backoff) whenever it exits. stderr is captured to classify permission
// errors as the "needs root" degradation.
func igpuLoop() {
	backoff := time.Second
	for {
		cmd := exec.Command("intel_gpu_top", "-J", "-s", "300", "-d", igpuDevice)
		var errBuf bytes.Buffer
		cmd.Stderr = &errBuf
		stdout, err := cmd.StdoutPipe()
		if err == nil {
			err = cmd.Start()
		}
		if err != nil {
			if note := classifySpawnError(err); note != "" {
				setIgpuNote(note)
			}
			time.Sleep(backoff)
			continue
		}

		dec := json.NewDecoder(stdout)
		for {
			var s igpuSample
			if derr := dec.Decode(&s); derr != nil {
				break
			}
			setIgpuSample(s)
		}
		_ = cmd.Wait()

		if strings.Contains(strings.ToLower(errBuf.String()), "permission denied") {
			setIgpuNote("engine busy: needs root — run with sudo")
		}
		time.Sleep(backoff)
	}
}

// classifySpawnError maps an exec/start failure to a degradation hint.
func classifySpawnError(err error) string {
	if err == nil {
		return ""
	}
	lower := strings.ToLower(err.Error())
	switch {
	case strings.Contains(lower, "executable file not found"),
		strings.Contains(lower, "no such file"):
		return "needs intel-gpu-tools"
	case strings.Contains(lower, "permission denied"):
		return "engine busy: needs root — run with sudo"
	default:
		return ""
	}
}

func setIgpuSample(s igpuSample) {
	igpuStream.mu.Lock()
	igpuStream.sample = s
	igpuStream.have = true
	igpuStream.note = ""
	igpuStream.mu.Unlock()
}

func setIgpuNote(note string) {
	igpuStream.mu.Lock()
	igpuStream.note = note
	igpuStream.mu.Unlock()
}

func latestIgpu() (igpuSample, bool) {
	igpuStream.mu.Lock()
	defer igpuStream.mu.Unlock()
	return igpuStream.sample, igpuStream.have
}

// igpuNote returns the persistent degradation note, if any.
func igpuNote() string {
	igpuStream.mu.Lock()
	defer igpuStream.mu.Unlock()
	return igpuStream.note
}

func (c *Collector) collectGPU(ctx context.Context, d *Data) {
	g := GPU{Label: "Iris Xe (iGPU)", OK: true}

	if cur, maxv, ok := readIGPUFreq(); ok {
		g.FreqCur = cur
		g.FreqMax = maxv
		g.HasFreq = true
	}

	startIGPU()
	if note := igpuNote(); note != "" {
		g.OK = false
		g.Err = note
		d.GPUs = []GPU{g}
		return
	}

	s, have := latestIgpu()
	if !have {
		g.EngineNote = "warming up…"
		d.GPUs = []GPU{g}
		return
	}

	g.RenderBusy = enginePct(s, "Render/3D")
	g.VideoBusy = enginePct(s, "Video")
	if ve := enginePct(s, "VideoEnhance"); ve > g.VideoBusy {
		g.VideoBusy = ve
	}
	g.RC6Pct = s.RC6.Value
	if s.Power.GPU > 0 || s.Power.Package > 0 {
		g.HasPower = true
		g.GPUPowerW = s.Power.GPU
		g.PkgPowerW = s.Power.Package
	}
	if name, busy, ok := busiestClient(s); ok {
		g.Client = name
		g.ClientBusy = busy
		g.HasClients = true
	}
	d.GPUs = []GPU{g}
}

// enginePct returns a clamped whole-percent for the named engine, defensively.
func enginePct(s igpuSample, name string) int {
	if e, ok := s.Engines[name]; ok {
		return clampPct(e.Busy)
	}
	return 0
}

// busiestClient returns the client with the busiest engine (best-effort).
func busiestClient(s igpuSample) (string, int, bool) {
	bestName, bestBusy := "", -1
	for _, cl := range s.Clients {
		for _, e := range cl.Engines {
			pct := clampPct(e.Busy)
			if pct > bestBusy {
				bestName = cl.Name
				bestBusy = pct
			}
		}
	}
	if bestBusy < 0 {
		return "", 0, false
	}
	return bestName, bestBusy, true
}

func clampPct(v float64) int {
	if v < 0 {
		v = 0
	}
	if v > 100 {
		v = 100
	}
	return int(v)
}

// readIGPUFreq reads the iGPU's current/max request frequencies from sysfs. The
// gt/gt0/rps_* path is preferred, falling back to gt_cur_freq_mhz etc.
func readIGPUFreq() (cur, maxv int, ok bool) {
	cur, curOK := readIntFile("/sys/class/drm/card1/gt/gt0/rps_cur_freq_mhz")
	if !curOK {
		cur, curOK = readIntFile("/sys/class/drm/card1/gt_cur_freq_mhz")
	}
	maxv, maxOK := readIntFile("/sys/class/drm/card1/gt/gt0/rps_max_freq_mhz")
	if !maxOK {
		maxv, maxOK = readIntFile("/sys/class/drm/card1/gt_max_freq_mhz")
	}
	if !curOK || !maxOK {
		return 0, 0, false
	}
	return cur, maxv, true
}

func readIntFile(path string) (int, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	v, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return 0, false
	}
	return v, true
}

// gpuLine formats the engine summary as a single display line. Kept here so the
// JSON parsing and its line are testable in the collect package.
func gpuLine() string {
	s, have := latestIgpu()
	if !have {
		return ""
	}
	var parts []string
	parts = append(parts, fmt.Sprintf("render %d%%", enginePct(s, "Render/3D")))
	video := enginePct(s, "Video")
	if ve := enginePct(s, "VideoEnhance"); ve > video {
		video = ve
	}
	parts = append(parts, fmt.Sprintf("video %d%%", video))
	parts = append(parts, fmt.Sprintf("rc6 %.0f%%", s.RC6.Value))
	if name, busy, ok := busiestClient(s); ok {
		parts = append(parts, fmt.Sprintf("%s %d%%", name, busy))
	}
	return strings.Join(parts, " · ")
}
