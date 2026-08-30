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

// renderBody renders the multi-panel dashboard body that must fit in exactly
// `h` lines (the space between the header and footer). The agents panel and the
// footer are the last, must-fit items, so the body always reserves room for the
// full agents panel (two rows + borders) and compresses the column panels until
// the remaining space is enough. See renderPCB for the compression priority.
func renderBody(t *Theme, w, h int, d collect.Data) string {
	agents := renderAgents(t, w, d)
	agentsLines := countLines(agents)
	colH := h - agentsLines
	if colH < 1 {
		colH = 1
	}

	var mid string
	if w < 80 {
		mid = renderSingleColumn(t, w, colH, d)
	} else {
		mid = renderColumns(t, w, colH, d)
	}

	// Trim columns only (never agents) if even full compression cannot fit;
	// the top panels are preserved and the low-priority tail is dropped.
	if midLines := countLines(mid); midLines > colH {
		parts := strings.Split(mid, "\n")
		mid = strings.Join(parts[:colH], "\n")
	}

	return mid + "\n" + agents
}

// renderColumns lays out the two-column body (w >= 80). The right column (docker,
// services, failed units) is not compressible; the left column holds the GPU,
// CPU and memory panels, which are compressed up front until they fit `colH`.
func renderColumns(t *Theme, w, colH int, d collect.Data) string {
	leftW := w / 2
	rightW := w - leftW

	right := strings.Join(compact([]string{
		renderDocker(t, rightW, d),
		renderServices(t, rightW, d),
		renderFailed(t, rightW, d),
	}), "\n")

	left := ""
	for lvl := 0; lvl <= memLevel; lvl++ {
		left = renderLeftColumn(t, leftW, d, lvl)
		if countLines(left) <= colH {
			break
		}
	}

	return lipgloss.JoinHorizontal(lipgloss.Top, left, right)
}

// renderSingleColumn lays out the stacked single-column body (w < 80),
// compressing the GPU/CPU/memory panels until the whole column fits `colH`.
func renderSingleColumn(t *Theme, w, colH int, d collect.Data) string {
	for lvl := 0; lvl <= memLevel; lvl++ {
		mergeCPU, top := cpuOpts(lvl)
		ps := compact([]string{
			renderCPU(t, w, d, mergeCPU, top),
			renderMem(t, w, d, lvl >= memLevel),
			renderGPU(t, w, d, lvl >= gpuLevel),
			renderStorage(t, w, d),
			renderDocker(t, w, d),
			renderServices(t, w, d),
			renderFailed(t, w, d),
		})
		col := strings.Join(ps, "\n")
		if countLines(col) <= colH {
			return col
		}
	}
	// Unreachable in practice: the loop always terminates at the fully
	// compressed level and the caller trims any residual overflow.
	mergeCPU, top := cpuOpts(memLevel)
	return strings.Join(compact([]string{
		renderCPU(t, w, d, mergeCPU, top),
		renderMem(t, w, d, true),
		renderGPU(t, w, d, true),
		renderStorage(t, w, d),
		renderDocker(t, w, d),
		renderServices(t, w, d),
		renderFailed(t, w, d),
	}), "\n")
}

// Compression levels, in the priority order the spec mandates: GPU collapses to
// a single row first, then the CPU panel (cores merged onto the total line, then
// top-5 trimmed to 4 and then to 3), and only if still overflowing does the
// memory "avail" line merge into the "swap" line.
const (
	gpuLevel = 1
	cpuMerge = 2
	cpuTop4  = 3
	cpuTop3  = 4
	memLevel = 5
)

// cpuOpts maps a compression level to the CPU panel options.
func cpuOpts(level int) (mergeCores bool, top int) {
	mergeCores = level >= cpuMerge
	top = 5
	if level >= cpuTop4 {
		top = 4
	}
	if level >= cpuTop3 {
		top = 3
	}
	return mergeCores, top
}

// renderLeftColumn renders the left column (cpu, memory, gpu, storage) with the
// compression selected by `level`.
func renderLeftColumn(t *Theme, w int, d collect.Data, level int) string {
	mergeCPU, top := cpuOpts(level)
	return strings.Join(compact([]string{
		renderCPU(t, w, d, mergeCPU, top),
		renderMem(t, w, d, level >= memLevel),
		renderGPU(t, w, d, level >= gpuLevel),
		renderStorage(t, w, d),
	}), "\n")
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

func countLines(s string) int {
	if s == "" {
		return 0
	}
	return strings.Count(s, "\n") + 1
}

func renderCPU(t *Theme, width int, d collect.Data, mergeCores bool, maxTop int) string {
	inner := maxint(width-4, 0)
	if !d.CPU.OK {
		return panel(t, "cpu", width, unavailable(t, d.CPU.Err))
	}
	var b strings.Builder
	b.WriteString(barLine(t, inner, "total", d.CPU.Total, fmt.Sprintf("%.0f%%", d.CPU.Total)))
	b.WriteString("\n")

	if mergeCores && len(d.CPU.Cores) > 0 {
		// Compact: fold the per-core sparkline onto the total line so the
		// panel drops a row.
		b.WriteString(cpuTotalMerged(t, inner, d.CPU.Total, coresSpark(t, d.CPU.Cores)))
		b.WriteString("\n")
	} else {
		n := len(d.CPU.Cores)
		if n > 0 {
			label := t.dimText().Render("cores")
			spark := coresSpark(t, d.CPU.Cores)
			avail := inner - lipgloss.Width(label) - 1
			b.WriteString(label + " " + truncate(spark, maxint(avail, 0)))
			b.WriteString("\n")
		}
	}

	b.WriteString(t.dimText().Render(fmt.Sprintf("top %d (per-core %%)", maxTop)))
	b.WriteString("\n")
	if len(d.CPU.Top) == 0 {
		b.WriteString("  " + t.dimText().Render("sampling…"))
	} else {
		for i, p := range d.CPU.Top {
			if i >= maxTop {
				break
			}
			line := fmt.Sprintf("  %-6d %-16s %5.1f", p.PID, truncate(p.Comm, 16), p.CPUPct)
			b.WriteString(line)
			b.WriteString("\n")
		}
	}
	body := strings.TrimSuffix(b.String(), "\n")
	return panel(t, "cpu", width, body)
}

// cpuTotalMerged renders the compact "total <bar> pct  cores <spark>" line,
// sizing the bar around everything else so it all stays on one row.
func cpuTotalMerged(t *Theme, inner int, total float64, spark string) string {
	labelS := t.bright().Render(truncate("total", 6))
	right := fmt.Sprintf("%.0f%%", total)
	cores := t.dimText().Render("cores") + " " + spark
	barW := inner - lipgloss.Width(labelS) - lipgloss.Width(right) - lipgloss.Width(cores) - 2
	if barW < 1 {
		barW = 1
	}
	line := labelS + " " + t.bar(total, barW) + " " + right + "  " + cores
	return truncate(line, inner)
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

func renderMem(t *Theme, width int, d collect.Data, mergeAvail bool) string {
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
	b.WriteString(memSwapLine(t, inner, d, mergeAvail))
	if !mergeAvail {
		b.WriteString("\n")
		b.WriteString(t.dimText().Render(fmt.Sprintf("avail %s", humanBytes(m.Available))))
	}
	return panel(t, "memory", width, strings.TrimSuffix(b.String(), "\n"))
}

// memSwapLine renders the swap row; when mergeAvail is set the "avail" line is
// folded onto the swap row ("swap none · avail 12.4GB", or appended to the swap
// bar's right-hand column) so the panel drops a row.
func memSwapLine(t *Theme, inner int, d collect.Data, mergeAvail bool) string {
	if d.Swap.OK {
		right := fmt.Sprintf("%s/%s %.0f%%", humanBytes(d.Swap.Used), humanBytes(d.Swap.Total), d.Swap.UsedPct)
		if mergeAvail {
			right += " · avail " + humanBytes(d.Mem.Available)
		}
		return barLine(t, inner, "swap", d.Swap.UsedPct, right)
	}
	base := "swap  unavailable"
	if d.Swap.Err == "no swap configured" {
		base = "swap  none"
	}
	if mergeAvail {
		return t.dimText().Render(base) + " · " + t.dimText().Render("avail "+humanBytes(d.Mem.Available))
	}
	return t.dimText().Render(base)
}

func renderGPU(t *Theme, width int, d collect.Data, compact bool) string {
	if len(d.GPUs) == 0 {
		return panel(t, "gpu", width, unavailable(t, "no iGPU discovered"))
	}
	g := d.GPUs[0]
	var b strings.Builder
	b.WriteString(t.bright().Render(truncate(g.Label, 14)))

	// Degradation (missing/failed probe): title + a status line only, no data.
	if !g.OK {
		err := g.Err
		if err == "" {
			err = "unavailable"
		}
		b.WriteString("\n  " + t.warn().Render(err))
		return panel(t, "gpu", width, b.String())
	}

	// Before the first JSON sample arrives: show "warming up…" as the status and
	// never fake zeroed engine numbers. Compact collapses to a single row.
	if g.EngineNote == "warming up…" {
		b.WriteString("\n  " + t.dimText().Render("warming up…"))
		return panel(t, "gpu", width, b.String())
	}

	data := engineLine(g)
	if compact {
		// Tight height: title + one merged row (data, plus any status suffix).
		if note := g.EngineNote; note != "" {
			data += " · " + note
		}
		b.WriteString("\n  " + data)
		return panel(t, "gpu", width, b.String())
	}

	// Uncompressed: title + data row, then a second line ONLY for status.
	b.WriteString("\n  " + data)
	if note := g.EngineNote; note != "" {
		b.WriteString("\n  " + t.dimText().Render(note))
	}
	return panel(t, "gpu", width, b.String())
}

// engineLine formats the GPU data row (freq · render · video · rc6, plus power
// and the busiest client when present). It returns only the real numbers; any
// status ("warming up…" / degradation) is rendered separately by renderGPU.
func engineLine(g collect.GPU) string {
	var parts []string
	if g.HasFreq {
		parts = append(parts, fmt.Sprintf("freq %d/%dMHz", g.FreqCur, g.FreqMax))
	}
	parts = append(parts, fmt.Sprintf("render %d%%", g.RenderBusy))
	parts = append(parts, fmt.Sprintf("video %d%%", g.VideoBusy))
	parts = append(parts, fmt.Sprintf("rc6 %.0f%%", g.RC6Pct))
	line := strings.Join(parts, " · ")
	if g.HasPower {
		line += fmt.Sprintf(" · gpu %.2fW pkg %.2fW", g.GPUPowerW, g.PkgPowerW)
	}
	if g.HasClients {
		line += fmt.Sprintf(" · %s %d%%", g.Client, g.ClientBusy)
	}
	return line
}

func renderStorage(t *Theme, width int, d collect.Data) string {
	if len(d.Storage) == 0 {
		return panel(t, "storage", width, unavailable(t, "no mounts sampled"))
	}
	inner := maxint(width-4, 0)
	track, showFree := storageLayout(inner)
	var lines []string
	for _, s := range d.Storage {
		labelS := t.bright().Render(fmt.Sprintf("%-6s", truncate(s.Label, 6)))
		if !s.Mounted {
			lines = append(lines, labelS+"  "+t.dimText().Render(s.Err))
			continue
		}
		// Adaptive row: label(6) + 1 + track + 1 + used/total(16) + 1 + pct(5),
		// then "· free" only when it fits the available inner width. Every
		// visible column stays fixed-width so all rows align exactly.
		bar := t.levelBar(s.UsedPct, track, t.storageLevel(s.UsedPct))
		usedTotal := padLeft(fmt.Sprintf("%s/%s", humanBytes(s.Used), humanBytes(s.Total)), 16)
		pctS := padLeft(fmt.Sprintf("%.0f%%", s.UsedPct), 5)
		if s.UsedPct >= 95 {
			pctS = t.danger().Render(pctS)
		}
		line := labelS + " " + bar + " " + usedTotal + " " + pctS
		if showFree {
			line += " " + t.dimText().Render("· "+humanBytes(s.Avail)+" free")
		}
		lines = append(lines, line)
	}
	return panel(t, "storage", width, strings.Join(lines, "\n"))
}

// storageLayout picks a track width and whether the trailing "· free" column
// is shown, so that no visible column is ever ellipsis-truncated when the row
// can be made to fit. The full row needs 6+1+track+1+16+1+5 (+1+~14 for free).
// "· free" is dropped first, then the track shrinks from 24 toward 20 cells and
// further only to keep the pct column fully visible.
func storageLayout(inner int) (track int, showFree bool) {
	const (
		label    = 6
		pad      = 1
		usedPad  = 16
		pctPad   = 5
		freeLen  = 14
		baseOver = label + 2*pad + usedPad + pad + pctPad // chars either side of the bar
	)
	withFree24 := label + pad + 24 + pad + usedPad + pad + pctPad + pad + freeLen
	if withFree24 <= inner {
		return 24, true
	}
	noFree24 := label + pad + 24 + pad + usedPad + pad + pctPad
	if noFree24 <= inner {
		return 24, false
	}
	noFree20 := label + pad + 20 + pad + usedPad + pad + pctPad
	if noFree20 <= inner {
		return 20, false
	}
	track = inner - baseOver
	if track < 8 {
		track = 8
	}
	return track, false
}

// padLeft left-pads s with spaces to at least width display columns.
func padLeft(s string, width int) string {
	if n := width - lipgloss.Width(s); n > 0 {
		return strings.Repeat(" ", n) + s
	}
	return s
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
	lines = append(lines, t.dimText().Render("cpu% (per-core)  mem%"))
	for _, c := range d.Docker.Containers {
		dot := t.ok().Render("●")
		switch c.State {
		case "exited", "dead":
			dot = t.dimText().Render("○")
		case "paused":
			dot = t.warn().Render("◐")
		}
		var stats string
		if c.HasStats {
			stats = fmt.Sprintf("cpu %.1f%% mem %.1f%%", c.CPU, c.MemPct)
		} else {
			stats = "stats n/a"
		}
		// Fixed chrome: status dot (1 col), a space after it, two spaces
		// before the stats. Give everything else to the name and only
		// truncate that, so the full "cpu x.x% mem y.y%" row shows whenever
		// it fits; the panel-level truncate handles genuinely narrow widths.
		fixed := 4
		nameW := maxint(inner-fixed-lipgloss.Width(stats), 4)
		line := dot + " " + t.bright().Render(truncate(c.Name, nameW)) + "  "
		if c.HasStats {
			line += stats
		} else {
			line += t.dimText().Render(stats)
		}
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

func renderAgents(t *Theme, width int, d collect.Data) string {
	inner := maxint(width-4, 0)
	h := d.Hermes
	oc := d.OpenCode

	hermes := hermesRow(t, inner, h)
	opencode := opencodeRow(t, inner, oc)
	return panel(t, "agents", width, hermes+"\n"+opencode)
}

// statusWord colors the agent status word: UP green, RUNNING amber, DOWN red,
// anything else (unknown) dim.
func statusWord(t *Theme, s string) string {
	switch strings.ToUpper(s) {
	case "UP":
		return t.ok().Render("UP")
	case "RUNNING":
		return t.warn().Render("RUNNING")
	case "DOWN":
		return t.danger().Render("DOWN")
	default:
		return t.dimText().Render("UNKNOWN")
	}
}

func hermesRow(t *Theme, inner int, h collect.Hermes) string {
	name := t.bright().Render("hermes")
	line := name + "  " + statusWord(t, h.Badge)

	var sub string
	switch {
	case h.Badge == "UNKNOWN":
		sub = "activity unknown"
	case h.Badge == "DOWN":
		if h.HasAct {
			sub = "idle " + humanDuration(time.Since(h.LastAct))
		} else {
			sub = "unit inactive"
		}
	case h.Badge == "RUNNING":
		sub = fmt.Sprintf("last act %s ago", humanDuration(time.Since(h.LastAct)))
	case h.HasAct:
		sub = "idle " + humanDuration(time.Since(h.LastAct))
	}
	if sub != "" {
		line += "  " + t.bright().Render(sub)
	}
	return truncate(line, inner)
}

func opencodeRow(t *Theme, inner int, oc collect.OpenCode) string {
	name := t.bright().Render("opencode")
	line := name + "  " + statusWord(t, oc.Status)

	if oc.HasLatency {
		line += "  " + t.bright().Render(fmt.Sprintf("http %d · %s", oc.HTTPStatus, fmtDuration(oc.Latency)))
	}
	switch strings.ToUpper(oc.Status) {
	case "RUNNING":
		line += "  " + t.bright().Render("busy")
	case "UP":
		line += "  " + t.bright().Render("idle")
	case "DOWN":
		line += "  " + t.bright().Render("offline")
	}
	if oc.DBUnread {
		line += "  " + t.bright().Render("activity n/a")
	}
	return truncate(line, inner)
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
