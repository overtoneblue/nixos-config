// head-dash is a terminal dashboard for the head NixOS server, built on the
// charmbracelet stack (bubbletea + lipgloss). It shows CPU, memory, Intel GPUs
// (DG1 + iGPU), Docker containers, key systemd services, the Hermes agent and
// OpenCode backend status, and storage.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"head-dash/internal/collect"
	"head-dash/internal/ui"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	interval := flag.Duration("interval", time.Second, "refresh interval (e.g. 500ms, 1s; minimum 50ms)")
	once := flag.Bool("once", false, "render exactly one frame and exit 0 (CI/verification; works without a TTY)")
	noColor := flag.Bool("no-color", false, "disable colors")
	page := flag.String("page", "system", "start page: system | usage")
	usageWin := flag.String("usage-window", "24h", "usage page window: 24h | month")
	flag.Parse()

	if *interval < 50*time.Millisecond {
		fmt.Fprintf(os.Stderr, "head-dash: --interval too small (%v); minimum is 50ms\n", *interval)
		os.Exit(1)
	}

	pageIdx, winIdx := parsePageArg(*page), parseUsageWinArg(*usageWin)

	col := collect.NewCollector(0)

	if *once {
		// Warm up baselines, then take two samples a few hundred ms apart so
		// the single rendered frame carries real CPU/process/docker deltas
		// (the process's own activity between the two samples shows up as a
		// non-zero top-process CPU% instead of all-zero values).
		col.Warmup(context.Background())

		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		col.Collect(ctx) // first sample (baseline for deltas)
		time.Sleep(350 * time.Millisecond)
		d := col.Collect(ctx) // second sample: deltas vs the first

		fmt.Println(ui.RenderOnce(d, 120, 36, *noColor, *interval, false, pageIdx, winIdx))
		return
	}

	col.Warmup(context.Background())
	col.Start(context.Background())
	m := ui.NewModel(col, *noColor, *interval, pageIdx, winIdx)
	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "head-dash:", err)
		os.Exit(1)
	}
}

// parsePageArg maps the --page flag; unknown values default to system.
func parsePageArg(p string) int {
	switch strings.ToLower(strings.TrimSpace(p)) {
	case "usage", "2":
		return 1 // pageUsage
	default:
		return 0 // pageSystem
	}
}

// parseUsageWinArg maps the --usage-window flag; unknown values default to 24h.
func parseUsageWinArg(w string) int {
	switch strings.ToLower(strings.TrimSpace(w)) {
	case "month", "m":
		return 1 // winMonth
	default:
		return 0 // win24h
	}
}
