package collect

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
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

var engBusyRe = regexp.MustCompile(`([A-Za-z][\w/]*)\s+busy:\s*(\d+)%`)

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
// summary of the busiest engines from the last dump block. ok=false means no
// usable engine data; the returned note explains why (root required, tool
// missing, ...).
func (c *Collector) scrapeGPUEngines(ctx context.Context) (summary, note string, ok bool) {
	out, err := runCmd(ctx, 2*time.Second, "timeout", "2", "intel_gpu_top", "-s", "1000", "-o", "-")
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

	type eng struct {
		name string
		pct  int
	}
	var found []eng
	seen := map[string]bool{}
	for _, m := range engBusyRe.FindAllStringSubmatch(out, -1) {
		name := m[1]
		if seen[name] {
			continue
		}
		seen[name] = true
		if v, e := strconv.Atoi(m[2]); e == nil {
			found = append(found, eng{name: name, pct: v})
		}
	}
	if len(found) == 0 {
		return "", "engine busy: no engine data", false
	}
	sort.Slice(found, func(i, j int) bool { return found[i].pct > found[j].pct })
	parts := make([]string, 0, len(found))
	for _, e := range found {
		parts = append(parts, fmt.Sprintf("%s %d%%", e.name, e.pct))
	}
	return strings.Join(parts, " · "), "", true
}
