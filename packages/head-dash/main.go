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
	"time"

	"head-dash/internal/collect"
	"head-dash/internal/ui"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	interval := flag.Duration("interval", time.Second, "refresh interval (e.g. 500ms, 1s)")
	once := flag.Bool("once", false, "render exactly one frame and exit 0 (CI/verification; works without a TTY)")
	noColor := flag.Bool("no-color", false, "disable colors")
	flag.Parse()

	col := collect.NewCollector(0)

	if *once {
		// Warm up baselines, then let a tick elapse so the frame carries real
		// CPU/process deltas rather than all-zero values.
		col.Warmup(context.Background())
		time.Sleep(time.Second)

		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		d := col.Collect(ctx)
		cancel()

		fmt.Println(ui.RenderOnce(d, 120, 36, *noColor, *interval, false))
		return
	}

	col.Warmup(context.Background())
	m := ui.NewModel(col, *noColor, *interval)
	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "head-dash:", err)
		os.Exit(1)
	}
}
