package ui

import (
	"fmt"
	"strings"
	"time"

	"head-dash/internal/collect"

	"github.com/charmbracelet/lipgloss"
)

// RenderOnce renders a single frame at a fixed size and returns it. It is the
// non-interactive path used by --once / CI and works without a TTY.
func RenderOnce(d collect.Data, w, h int, noColor bool, interval time.Duration, paused bool) string {
	if w <= 0 {
		w = 120
	}
	if h <= 0 {
		h = 36
	}
	return renderFrame(NewTheme(noColor), w, h, d, interval, paused)
}

func renderFrame(t *Theme, w, h int, d collect.Data, interval time.Duration, paused bool) string {
	if h < 3 {
		h = 3
	}
	header := renderHeader(t, w, d)
	footer := renderFooter(t, w, interval, paused)

	avail := h - 2 // header + footer
	body := renderBody(t, w, avail, d)
	bLines := strings.Split(body, "\n")
	if len(bLines) > avail {
		bLines = bLines[:avail]
	}

	lines := append(strings.Split(header, "\n"), bLines...)
	lines = append(lines, strings.Split(footer, "\n")...)
	return strings.Join(lines, "\n")
}

// ── Header ───────────────────────────────────────────────────────────────

func renderHeader(t *Theme, w int, d collect.Data) string {
	h := d.Header
	host := h.Hostname
	if host == "" {
		host = "head"
	}
	var b strings.Builder
	b.WriteString(t.accentBold().Render(" " + host + " "))
	b.WriteString(t.dimText().Render("▸"))

	segs := []string{}
	if h.OK {
		segs = append(segs, seg(t, "up", humanDuration(h.Uptime)))
	}
	if len(d.Load) == 3 {
		segs = append(segs, seg(t, "load", fmt.Sprintf("%.2f %.2f %.2f", d.Load[0], d.Load[1], d.Load[2])))
	}
	if h.Kernel != "" {
		segs = append(segs, seg(t, "kernel", h.Kernel))
	}
	segs = append(segs, seg(t, "cpu", fmt.Sprintf("%d", maxint(d.CPU.NumCPU, h.NumCPU))))
	segs = append(segs, seg(t, "now", d.Timestamp.Local().Format("15:04:05")))

	for i, s := range segs {
		b.WriteString("  ")
		b.WriteString(s)
		if i != len(segs)-1 {
			b.WriteString(t.dimText().Render("│"))
		}
	}
	return truncate(b.String(), w)
}

func seg(t *Theme, label, value string) string {
	var b strings.Builder
	b.WriteString(t.dimText().Render(label + " "))
	b.WriteString(t.bright().Render(value))
	return b.String()
}

// ── Footer ───────────────────────────────────────────────────────────────

func renderFooter(t *Theme, w int, interval time.Duration, paused bool) string {
	state := ""
	if paused {
		state += t.warn().Render(" PAUSED")
	} else {
		state += t.ok().Render(" live")
	}
	state += t.dimText().Render(fmt.Sprintf("  interval %v", interval.Round(time.Millisecond)))

	keys := t.dimText().Render(" q quit · p pause · r refresh · +/- interval · ctrl+c quit ")
	return truncate(keys+state, w)
}

// ── Body layout ──────────────────────────────────────────────────────────

func renderBody(t *Theme, w, h int, d collect.Data) string {
	if w < 80 {
		ps := compact([]string{
			renderCPU(t, w, d),
			renderMem(t, w, d),
			renderGPU(t, w, d),
			renderStorage(t, w, d),
			renderDocker(t, w, d),
			renderServices(t, w, d),
			renderFailed(t, w, d),
			renderHermes(t, w, d),
			renderOpenCode(t, w, d),
		})
		return strings.Join(ps, "\n")
	}

	leftW := w / 2
	rightW := w - leftW

	left := strings.Join(compact([]string{
		renderCPU(t, leftW, d),
		renderMem(t, leftW, d),
		renderGPU(t, leftW, d),
		renderStorage(t, leftW, d),
	}), "\n")

	right := strings.Join(compact([]string{
		renderDocker(t, rightW, d),
		renderServices(t, rightW, d),
		renderFailed(t, rightW, d),
	}), "\n")

	mid := lipgloss.JoinHorizontal(lipgloss.Top, left, right)

	strip := lipgloss.JoinHorizontal(lipgloss.Top,
		renderHermes(t, w/2, d),
		renderOpenCode(t, w-w/2, d),
	)
	return mid + "\n" + strip
}

func compact(ss []string) []string {
	out := ss[:0]
	for _, s := range ss {
		if s != "" {
			out = append(out, s)
		}
	}
	return out
}

// ── Panels ───────────────────────────────────────────────────────────────

// panel draws a titled, bordered box of the requested total width. lipgloss
// Width(n) sizes the inner block (padding included) with the 2-column rounded
// border added on top, so Width(n-2) yields a total width of n; the visible
// text area is therefore n-4.
func panel(t *Theme, title string, width int, body string) string {
	if width < 6 {
		width = 6
	}
	content := t.accentBold().Render(title)
	if body != "" {
		for _, line := range strings.Split(strings.TrimSuffix(body, "\n"), "\n") {
			content += "\n" + truncate(line, maxint(width-4, 0))
		}
	}
	style := lipgloss.NewStyle().
		Width(maxint(width-2, 0)).
		Border(lipgloss.RoundedBorder()).
		Padding(0, 1).
		BorderForeground(t.border)
	if !t.noColor {
		style = style.Background(t.bg)
	}
	return style.Render(content)
}

// barLine renders `label <gradient bar> right` within an inner width.
func barLine(t *Theme, innerW int, label string, pct float64, right string) string {
	labelS := t.bright().Render(truncate(label, 6))
	rightS := t.dimText().Render(right)
	barW := innerW - lipgloss.Width(labelS) - lipgloss.Width(rightS) - 2
	if barW < 1 {
		barW = 1
	}
	return labelS + " " + t.bar(pct, barW) + " " + rightS
}

func unavailable(t *Theme, err string) string {
	if err == "" {
		err = "unavailable"
	}
	return t.dimText().Render("— " + err)
}

func renderCPU(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	if !d.CPU.OK {
		return panel(t, "cpu", width, unavailable(t, d.CPU.Err))
	}
	var b strings.Builder
	b.WriteString(barLine(t, inner, "total", d.CPU.Total, fmt.Sprintf("%.0f%%", d.CPU.Total)))
	b.WriteString("\n")

	// Compact per-core ruler.
	n := len(d.CPU.Cores)
	if n > 0 {
		label := t.dimText().Render("cores")
		spark := coresSpark(t, d.CPU.Cores)
		avail := inner - lipgloss.Width(label) - 1
		b.WriteString(label + " " + truncate(spark, maxint(avail, 0)))
		b.WriteString("\n")
	}

	b.WriteString(t.dimText().Render("top 5 (per-core %)\n"))
	if len(d.CPU.Top) == 0 {
		b.WriteString("  " + t.dimText().Render("sampling…"))
	} else {
		for _, p := range d.CPU.Top {
			line := fmt.Sprintf("  %-6d %-16s %5.1f", p.PID, truncate(p.Comm, 16), p.CPUPct)
			b.WriteString(line)
			b.WriteString("\n")
		}
	}
	body := strings.TrimSuffix(b.String(), "\n")
	return panel(t, "cpu", width, body)
}

func coresSpark(t *Theme, cores []collect.Core) string {
	chars := []string{"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
	parts := make([]string, 0, len(cores))
	for _, c := range cores {
		idx := int(clampf(c.Pct, 0, 100) / 100 * float64(len(chars)-1))
		if t.noColor {
			parts = append(parts, chars[idx])
			continue
		}
		col := t.levelColor(c.Pct)
		parts = append(parts, t.fg(col).Render(chars[idx]))
	}
	return strings.Join(parts, "")
}

func renderMem(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	m := d.Mem
	if !m.OK {
		return panel(t, "memory", width, unavailable(t, m.Err))
	}
	var b strings.Builder
	b.WriteString(barLine(t, inner, "mem",
		m.UsedPct,
		fmt.Sprintf("%s/%s %.0f%%", humanBytes(m.Used), humanBytes(m.Total), m.UsedPct)))
	b.WriteString("\n")

	swap := d.Swap
	if swap.OK {
		b.WriteString(barLine(t, inner, "swap",
			swap.UsedPct,
			fmt.Sprintf("%s/%s %.0f%%", humanBytes(swap.Used), humanBytes(swap.Total), swap.UsedPct)))
	} else if swap.Err == "no swap configured" {
		b.WriteString(t.dimText().Render("swap  none"))
	} else {
		b.WriteString(t.dimText().Render("swap  unavailable"))
	}
	b.WriteString("\n")
	b.WriteString(t.dimText().Render(fmt.Sprintf("avail %s", humanBytes(m.Available))))
	return panel(t, "memory", width, strings.TrimSuffix(b.String(), "\n"))
}

func renderGPU(t *Theme, width int, d collect.Data) string {
	if len(d.GPUs) == 0 {
		return panel(t, "gpu", width, unavailable(t, "no cards discovered"))
	}
	var lines []string
	for _, g := range d.GPUs {
		var b strings.Builder
		label := t.bright().Render(g.Card) + "  " + t.dimText().Render(truncate(g.Label, 14))
		b.WriteString(label)
		if g.OK {
			if g.HasTemp {
				b.WriteString(t.dimText().Render("  " + fmt.Sprintf("%.0f°C", g.TempC)))
			} else {
				b.WriteString(t.dimText().Render("  temp n/a"))
			}
			if g.HasPower {
				b.WriteString(t.dimText().Render(fmt.Sprintf("  %.0fW", g.PowerW)))
			}
			if g.EngineBusy != "" {
				b.WriteString("\n    " + t.dimText().Render("engine: ") + t.warn().Render(g.EngineBusy))
			}
			if g.EngineNote != "" {
				b.WriteString("\n    " + t.dimText().Render(g.EngineNote))
			}
		} else {
			b.WriteString(t.dimText().Render("  " + g.Err))
		}
		lines = append(lines, b.String())
	}
	return panel(t, "gpu", width, strings.Join(lines, "\n"))
}

func renderStorage(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	if len(d.Storage) == 0 {
		return panel(t, "storage", width, unavailable(t, "no mounts sampled"))
	}
	var lines []string
	for _, s := range d.Storage {
		if !s.Mounted {
			lines = append(lines, t.bright().Render(truncate(s.Label, 6))+"  "+t.dimText().Render(s.Err))
			continue
		}
		labelS := t.bright().Render(truncate(s.Label, 6))
		rightS := t.dimText().Render(fmt.Sprintf("%s/%s %.0f%% · %s free",
			humanBytes(s.Used), humanBytes(s.Total), s.UsedPct, humanBytes(s.Avail)))
		barW := inner - lipgloss.Width(labelS) - lipgloss.Width(rightS) - 2
		if barW < 1 {
			barW = 1
		}
		bar := t.levelBar(s.UsedPct, barW, t.storageLevel(s.UsedPct))
		lines = append(lines, labelS+" "+bar+" "+rightS)
	}
	return panel(t, "storage", width, strings.Join(lines, "\n"))
}

func renderDocker(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	if !d.Docker.OK {
		return panel(t, "docker", width, unavailable(t, d.Docker.Err))
	}
	if len(d.Docker.Containers) == 0 {
		return panel(t, "docker", width, t.dimText().Render("no running containers"))
	}
	var lines []string
	for _, c := range d.Docker.Containers {
		name := truncate(c.Name, 18)
		dot := t.ok().Render("●")
		switch c.State {
		case "exited", "dead":
			dot = t.dimText().Render("○")
		case "paused":
			dot = t.warn().Render("◐")
		}
		stats := ""
		if c.HasStats {
			stats = fmt.Sprintf("cpu %.1f%% mem %.1f%%", c.CPU, c.MemPct)
		} else {
			stats = t.dimText().Render("stats n/a")
		}
		line := fmt.Sprintf("%s %s  %s", dot, t.bright().Render(name), truncate(stats, maxint(inner-24, 0)))
		lines = append(lines, line)
	}
	return panel(t, "docker", width, strings.Join(lines, "\n"))
}

func renderServices(t *Theme, width int, d collect.Data) string {
	if !d.Services.OK {
		return panel(t, "services", width, unavailable(t, d.Services.Err))
	}
	var lines []string
	for _, s := range d.Services.List {
		name := truncate(s.Name, maxint(width-4-4, 1))
		var badge string
		if s.Err != "" {
			badge = t.dimText().Render(s.Err)
		} else {
			switch s.ActiveState {
			case "active":
				badge = t.ok().Render("● " + s.SubState)
			case "failed":
				badge = t.danger().Render("✘ failed")
			default:
				badge = t.warn().Render("◐ " + s.ActiveState + "/" + s.SubState)
			}
		}
		lines = append(lines, t.bright().Render(name)+"  "+badge)
	}
	return panel(t, "services", width, strings.Join(lines, "\n"))
}

func renderFailed(t *Theme, width int, d collect.Data) string {
	if !d.Services.OK || len(d.Services.FailedUnits) == 0 {
		return ""
	}
	var lines []string
	for _, u := range d.Services.FailedUnits {
		lines = append(lines, t.danger().Render("✘ "+truncate(u, maxint(width-4-2, 1))))
	}
	return panel(t, "failed units", width, strings.Join(lines, "\n"))
}

func renderHermes(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	h := d.Hermes
	var badge string
	switch h.Badge {
	case "ACTIVE":
		badge = t.ok().Render(h.Badge)
	case "DOWN":
		badge = t.danger().Render(h.Badge)
	case "IDLE":
		badge = t.warn().Render(h.Badge)
	default:
		badge = t.dimText().Render(h.Badge)
	}

	var b strings.Builder
	b.WriteString(t.accentBold().Render("hermes"))
	b.WriteString("  " + badge)
	if h.HasAge {
		b.WriteString(t.dimText().Render("  last act " + humanDuration(h.ActivityAge)))
	}
	if h.JournalLines > 0 {
		b.WriteString(t.dimText().Render(fmt.Sprintf("  journal %d/60s", h.JournalLines)))
	}
	if h.Note != "" {
		b.WriteString("\n  " + t.dimText().Render(h.Note))
	}
	return panel(t, "agents", width, truncate(b.String(), inner))
}

func renderOpenCode(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	oc := d.OpenCode
	var badge string
	switch oc.Status {
	case "up":
		badge = t.ok().Render("UP")
	case "down":
		badge = t.danger().Render("DOWN")
	default:
		badge = t.warn().Render("UNKNOWN")
	}
	var b strings.Builder
	b.WriteString(t.accentBold().Render("opencode"))
	b.WriteString("  " + badge)
	if oc.HasLatency {
		b.WriteString(t.dimText().Render(fmt.Sprintf("  http %d  %s", oc.HTTPStatus, fmtDuration(oc.Latency))))
	}
	if oc.ServiceActive {
		b.WriteString("  " + t.ok().Render("●"))
	} else {
		b.WriteString("  " + t.dimText().Render("○"))
	}
	if oc.Status == "down" || oc.Status == "unknown" {
		if oc.Err != "" {
			b.WriteString("\n  " + t.dimText().Render(oc.Err))
		}
	}
	return panel(t, "opencode", width, truncate(b.String(), inner))
}

// ── Formatting helpers ───────────────────────────────────────────────────

func humanBytes(n uint64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%dB", n)
	}
	div, exp := uint64(unit), 0
	for m := n / unit; m >= unit; m /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f%cB", float64(n)/float64(div), "KMGTPE"[exp])
}

func humanDuration(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	switch {
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm%ds", int(d.Minutes()), int(d.Seconds())%60)
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh%dm", int(d.Hours()), int(d.Minutes())%60)
	default:
		return fmt.Sprintf("%dd%dh", int(d.Hours()/24), int(d.Hours())%24)
	}
}

func fmtDuration(d time.Duration) string {
	switch {
	case d < time.Millisecond:
		return fmt.Sprintf("%dµs", d.Microseconds())
	case d < time.Second:
		return fmt.Sprintf("%.1fms", float64(d.Microseconds())/1000)
	default:
		return fmt.Sprintf("%.2fs", d.Seconds())
	}
}
