package collect

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// GPU describes one DRM card. On head: card0 is the discrete Intel DG1
// (primary, drives Jellyfin hardware transcoding), card1 is the iGPU. The
// hardware exposes temp + power via hwmon but NO gpu_busy_percent / gt*/freq
// sysfs, so engine utilisation is scraped best-effort from intel_gpu_top.
type GPU struct {
	Card        string
	Label       string
	TempC       float64
	HasTemp     bool
	PowerW      float64
	HasPower    bool
	EngineBusy  string // e.g. "Render 0% · Video 1%"
	EngineNote  string // hint, e.g. "engine busy: needs root"
	OK          bool
	Err         string
}

func (c *Collector) collectGPU(ctx context.Context, d *Data) {
	gpus := make([]GPU, 0, 2)
	present := false

	for _, card := range []string{"card0", "card1"} {
		g := c.readCardHWMon(ctx, card)
		if g.OK {
			present = true
		}
		gpus = append(gpus, g)
	}

	// Engine busy via intel_gpu_top (single scrape, attached to the primary
	// card). Root is required to open the DRM device; degrade to a hint.
	if busy, note, ok := c.scrapeGPUEngines(ctx); ok {
		for i := range gpus {
			if gpus[i].Card == "card0" {
				gpus[i].EngineBusy = busy
			}
		}
	} else if note != "" {
		for i := range gpus {
			if gpus[i].Card == "card0" {
				gpus[i].EngineNote = note
			}
		}
	}

	if !present {
		for i := range gpus {
			gpus[i].OK = false
			if gpus[i].Err == "" {
				gpus[i].Err = "no /sys/class/drm/i915 card exposed"
			}
		}
	}
	d.GPUs = gpus
}

func (c *Collector) readCardHWMon(ctx context.Context, card string) GPU {
	g := GPU{Card: card}
	switch card {
	case "card0":
		g.Label = "DG1 (discrete)"
	case "card1":
		g.Label = "iGPU"
	default:
		g.Label = card
	}

	base := fmt.Sprintf("/sys/class/drm/%s/device", card)
	stat, err := os.Stat(base)
	if err != nil {
		g.OK = false
		g.Err = "card missing"
		return g
	}
	if !stat.IsDir() {
		g.OK = false
		g.Err = "card path not a directory"
		return g
	}

	// Find a hwmon node exposing temperature.
	matches, _ := filepath.Glob(base + "/hwmon/hwmon*")
	for _, m := range matches {
		tmp, ferr := readFirstUint(m + "/temp1_input")
		if ferr == nil {
			g.TempC = float64(tmp) / 1000.0
			g.HasTemp = true
		}
		// power1_average is in microwatts; absent on this hardware.
		if pw, werr := readFirstUint(m + "/power1_average"); werr == nil {
			g.PowerW = float64(pw) / 1e6
			g.HasPower = true
		}
	}
	if !g.HasTemp {
		g.TempC = 0
		g.PowerW = 0
	}

	g.OK = true
	if !g.HasTemp && !g.HasPower {
		g.Err = "no hwmon temp/power exposed"
	}
	return g
}

// scrapeGPUEngines runs `timeout 2 intel_gpu_top -s 1000 -o -` and returns a
// summary of engine utilisation from the last emitted data row. The tool emits
// a header + periodic table rows even when stdout is not a terminal (verified
// with `-o -`), so parsing must not require a TTY. ok=false means no usable
// engine data; the returned note explains why (root required, tool missing, ...).
func (c *Collector) scrapeGPUEngines(ctx context.Context) (summary, note string, ok bool) {
	out, err := runCmd(ctx, 2*time.Second, "timeout", "2", "intel_gpu_top", "-s", "1000", "-o", "-")
	// The command exits non-zero when `timeout` kills it after 2s even though
	// it already printed usable rows, so prefer parsing the output over err.
	if s, found := parseGPUEngines(out); found {
		return s, "", true
	}
	if err != nil {
		lower := strings.ToLower(err.Error() + " " + out)
		switch {
		case strings.Contains(lower, "permission denied"):
			return "", "engine busy: needs root", false
		case ctx.Err() != nil:
			return "", "engine busy: scrape timed out", false
		case strings.Contains(lower, "no such file") ||
			strings.Contains(lower, "not found") ||
			strings.Contains(lower, "127"):
			return "", "engine busy: needs intel-gpu-tools", false
		default:
			return "", "engine busy: unavailable", false
		}
	}
	return "", "engine busy: no engine data", false
}

// parseGPUEngines extracts engine utilisation from intel_gpu_top's non-TTY
// table output. Each periodic row has 16 numeric fields:
//
//	freq-req freq-act irq/s rc6% | RCS busy se wa | BCS busy se wa | VCS busy se wa | VECS busy se wa
//
// RCS is render, VCS is video decode, VECS is video encode; RC6 is the
// deep-sleep idle state. Only the last complete data row is used.
func parseGPUEngines(out string) (string, bool) {
	var last []string
	for _, line := range strings.Split(out, "\n") {
		f := strings.Fields(line)
		if len(f) < 16 {
			continue
		}
		allNumeric := true
		for _, tok := range f[:16] {
			if _, err := strconv.ParseFloat(tok, 64); err != nil {
				allNumeric = false
				break
			}
		}
		if allNumeric {
			last = f
		}
	}
	if len(last) < 16 {
		return "", false
	}
	return fmt.Sprintf("render %d%% · decode %d%% · encode %d%% · rc6 %d%%",
		gpuPct(last[4]), gpuPct(last[10]), gpuPct(last[13]), gpuPct(last[3])), true
}

// gpuPct parses a percentage field, clamped to a whole percent.
func gpuPct(field string) int {
	v, err := strconv.ParseFloat(field, 64)
	if err != nil {
		return 0
	}
	if v < 0 {
		v = 0
	}
	if v > 100 {
		v = 100
	}
	return int(v)
}
