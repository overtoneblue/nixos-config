package ui

import (
	"strings"
	"testing"
	"time"

	"head-dash/internal/collect"

	"github.com/charmbracelet/lipgloss"
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
			{Label: "Iris Xe (iGPU)", FreqCur: 1250, FreqMax: 1300, HasFreq: true, RenderBusy: 42, VideoBusy: 1, RC6Pct: 99.5, HasPower: true, GPUPowerW: 0.014, PkgPowerW: 3.44, Client: "ffmpeg", ClientBusy: 12, HasClients: true, OK: true},
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

func TestDockerHeaderLabel(t *testing.T) {
	tm := NewTheme(false)
	d := sampleData()
	got := renderDocker(tm, 60, d)
	if !strings.Contains(got, "cpu% (per-core)") {
		t.Fatalf("docker header missing; got %q", got)
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

// TestTruncateIsDisplayWidthAware guards the interactive-TTY regression where
// styled (ANSI) content was measured by rune count instead of display width and
// got chopped to a few characters (" total ░", "● jellyfin  c…", a single
// sparkline block) while the panel borders still spanned the full width.
func TestTruncateIsDisplayWidthAware(t *testing.T) {
	tm := NewTheme(false)

	// A fully-styled full-width cpu bar line: many visible cells, far more
	// runes than cells once 24-bit color codes are inline.
	inner := 62
	labelS := tm.bright().Render(truncate("total", 6))
	rightS := tm.dimText().Render("6%")
	barW := inner - lipgloss.Width(labelS) - lipgloss.Width(rightS) - 2
	line := labelS + " " + tm.bar(42, barW) + " " + rightS

	if w := lipgloss.Width(line); w != inner {
		t.Fatalf("test setup: bar line display width = %d, want %d", w, inner)
	}
	if got := truncate(line, inner); got != line {
		t.Fatalf("truncate chopped a line that already fits: got width=%d want %d", lipgloss.Width(got), inner)
	}
	// It must cut the over-wide bar line to exactly inner cells, not to a
	// handful of runes, and must keep the ANSI sequences intact.
	cut := truncate(line, 20)
	if w := lipgloss.Width(cut); w != 20 {
		t.Fatalf("truncate to 20 gave width %d, want 20", w)
	}

	// Docker-style row: "● <name>  cpu x.x% mem y.y%" must survive untouched at
	// panel width, and a genuinely-narrow panel must trim to the panel.
	dot := tm.ok().Render("●")
	row := dot + " " + tm.bright().Render("jellyfin") + "  " + "cpu 12.5% mem 34.2%"
	if got := truncate(row, 62); got != row {
		t.Fatalf("docker row chopped though it fits: width=%d", lipgloss.Width(got))
	}
	narrow := truncate(row, 16)
	if w := lipgloss.Width(narrow); w > 16 {
		t.Fatalf("narrow truncate exceeded width: %d", w)
	}
}

// TestTruncatePlainStillWorks ensures the no-color/plain path keeps the
// previous semantics (trim by columns, ellipsis on overflow).
func TestTruncatePlainStillWorks(t *testing.T) {
	if got := truncate("jellyfin", 5); got != "jell…" {
		t.Fatalf("truncate plain: got %q", got)
	}
	if got := truncate("short", 100); got != "short" {
		t.Fatalf("truncate short no-op: got %q", got)
	}
	if got := truncate("x", 0); got != "" {
		t.Fatalf("truncate width 0: got %q", got)
	}
}
