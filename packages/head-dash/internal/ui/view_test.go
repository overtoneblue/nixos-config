package ui

import (
	"strings"
	"testing"
	"time"

	"head-dash/internal/collect"
)

// sampleData returns a fully-populated snapshot with both healthy and
// degraded states so the renderer is exercised across all branches.
func sampleData() collect.Data {
	return collect.Data{
		Timestamp: time.Now(),
		Header:    collect.Header{Hostname: "head", Uptime: 6*24*time.Hour + 22*time.Hour, Kernel: "6.18.43", NumCPU: 8, OK: true},
		CPU: collect.CPU{
			OK: true, Total: 42, NumCPU: 8,
			Cores: []collect.Core{{ID: 0, Pct: 10}, {ID: 1, Pct: 20}, {ID: 2, Pct: 60}, {ID: 3, Pct: 90}, {ID: 4, Pct: 5}},
			Load:  [3]float64{0.5, 0.4, 0.3},
			Top: []collect.Proc{
				{PID: 1234, Comm: "jellyfin", State: 'S', CPUPct: 33.3},
				{PID: 5678, Comm: "opencode", State: 'S', CPUPct: 12.1},
			},
		},
		Load:   []float64{0.5, 0.4, 0.3},
		Mem:    collect.Mem{Total: 16 << 30, Used: 6 << 30, Available: 10 << 30, UsedPct: 37.5, OK: true},
		Swap:   collect.Mem{Total: 0, OK: false, Err: "no swap configured"},
		GPUs: []collect.GPU{
			{Card: "card0", Label: "DG1 (discrete)", TempC: 63, HasTemp: true, PowerW: 12, HasPower: true, EngineBusy: "Render 0% · Video 1%", OK: true},
			{Card: "card1", Label: "iGPU", OK: true, Err: "no hwmon temp/power exposed"},
		},
		Docker: collect.Docker{OK: true, Containers: []collect.Container{
			{Name: "jellyfin", Image: "jellyfin/jellyfin:unstable", State: "running", Status: "Up 3 days", CPU: 12.5, MemPct: 34.2, HasStats: true},
		}},
		Services: collect.Services{OK: true, List: []collect.Service{
			{Name: "hermes-agent", ActiveState: "active", SubState: "running"},
			{Name: "opencode", ActiveState: "active", SubState: "running"},
			{Name: "nginx", ActiveState: "failed", SubState: "failed"},
		}, FailedUnits: []string{"nginx.service"}},
		Hermes:   collect.Hermes{Badge: "ACTIVE", ActiveState: "active", HasAge: true, ActivityAge: 3 * time.Second, JournalLines: 2},
		OpenCode: collect.OpenCode{Status: "up", HTTPStatus: 401, Latency: 3 * time.Millisecond, HasLatency: true, ServiceActive: true},
		Storage: []collect.Storage{
			{Label: "user", Path: "/mnt/user", Total: 12 << 40, Used: 3 << 40, Avail: 9 << 40, UsedPct: 25, Mounted: true},
			{Label: "disk3", Path: "/mnt/disk3", Err: "not mounted"},
		},
	}
}

func TestRenderOnceSizes(t *testing.T) {
	d := sampleData()
	for _, dim := range [][2]int{{40, 20}, {66, 22}, {80, 30}, {120, 36}} {
		w, h := dim[0], dim[1]
		for _, nc := range []bool{false, true} {
			got := RenderOnce(d, w, h, nc, time.Second, false)
			if got == "" {
				t.Fatalf("RenderOnce(%d,%d,t=%v) returned empty output", w, h, nc)
			}
			if strings.Count(got, "\n")+1 > h {
				t.Errorf("RenderOnce(%d,%d,t=%v) exceeded requested height", w, h, nc)
			}
		}
	}
}

func TestBarNeverPanics(t *testing.T) {
	tm := NewTheme(false)
	for _, w := range []int{0, 1, 4, 40} {
		_ = tm.bar(-5, w)
		_ = tm.bar(37.5, w)
		_ = tm.bar(200, w)
	}
	tm = NewTheme(true)
	_ = tm.bar(50, 10)
}
