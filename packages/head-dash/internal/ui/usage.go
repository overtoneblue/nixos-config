package ui

import (
	"fmt"
	"strings"

	"head-dash/internal/collect"

	"github.com/charmbracelet/lipgloss"
)

// Pages: 1 = system (the original dashboard), 2 = usage.
const (
	pageSystem = iota
	pageUsage
	pageCount
)

// Usage windows selectable in-page: d = 24h rolling, m = calendar month.
const (
	win24h = iota
	winMonth
)

// usagePageSize is the number of model-table rows kept when the terminal is
// too short to show all of them.
const usageModelRowsMax = 8

// renderUsagePage renders the usage view inside the full frame (header +
// footer are added by renderFrame).
func renderUsagePage(t *Theme, w, h int, d collect.Data, win int) string {
	innerW := maxint(w-4, 0)

	var body []string

	// ── Window totals panel ─────────────────────────────────────────────
	var uw collect.UsageWindow
	var winLabel string
	switch win {
	case win24h:
		uw = d.Usage.W24h
		winLabel = "24h rolling"
	default:
		uw = d.Usage.Month
		winLabel = "month-to-date"
	}

	naNote := ""
	if uw.CostRateNA {
		naNote = " · some opencode tokens lack a published rate (cost omitted there)"
	}

	totals := []string{
		fmt.Sprintf("tokens in %s · out %s", humanTokens(uw.InTokens), humanTokens(uw.OutTokens)),
		fmt.Sprintf("cache read %s · reasoning %s", humanTokens(uw.CacheRead), humanTokens(uw.Reasoning)),
		fmt.Sprintf("api calls %s", humanTokens(uw.APICalls)),
		fmt.Sprintf("cost %s%s", humanMoney(uw.Cost), " (est basis)" ),
	}
	totalsLine := strings.Join(totals, "  ·  ")
	body = append(body, panel(t, "usage · "+winLabel+" · head-local", w,
		totalsLine+"\n"+t.dimText().Render(fmt.Sprintf("hermes %s · %.0f%%   opencode %s · %.0f%% of spend%s",
			humanMoney(uw.HermesCost), sharePct(uw.HermesCost, uw.Cost)*100,
			humanMoney(uw.OpenCodeCost), sharePct(uw.OpenCodeCost, uw.Cost)*100,
			naNote))))

	// ── Hermes vs opencode split panel ────────────────────────────────
	splitTitle := "spend split · hermes vs opencode"
	splitBody := renderSpendSplit(t, maxint(innerW, 10), uw)
	body = append(body, panel(t, splitTitle, w, splitBody))

	// ── Per-model panel (top by cost) ──────────────────────────────────
	body = append(body, renderUsageModels(t, w, uw))

	// ── Per-bot panel ────────────────────────────────────────────────
	body = append(body, renderUsageBots(t, w, d.Usage, win))

	// ── Degradation notes, if any ────────────────────────────────────
	if len(d.Usage.Errs) > 0 {
		var lines []string
		for _, e := range d.Usage.Errs {
			lines = append(lines, t.warn().Render("— "+truncate(e, maxint(innerW-2, 1))))
		}
		body = append(body, panel(t, "usage notes", w, strings.Join(lines, "\n")))
	}

	// ── Month sparkline (both windows — it is the month detail) ───────
	body = append(body, renderMonthSpark(t, w, d.Usage))

	// Fit to available height: drop from the tail (lowest priority last
	// drawn first to go): models table rows shrink, then panels drop.
	content := strings.Join(body, "\n")
	if lines := countLines(content); lines > h {
		content = strings.Join(strings.Split(content, "\n")[:h], "\n")
	}
	return content
}

// renderSpendSplit draws a two-row share bar of hermes vs opencode spend.
func renderSpendSplit(t *Theme, inner int, uw collect.UsageWindow) string {
	if uw.Cost <= 0 {
		return t.dimText().Render("no spend recorded in this window")
	}
	hPct := sharePct(uw.HermesCost, uw.Cost)
	oPct := 1 - hPct
	hBar := t.levelBar(hPct*100, maxint(int(float64(inner)*hPct), 0), t.green)
	oBar := t.levelBar(oPct*100, maxint(int(float64(inner)*oPct), 0), t.accent)
	line1 := t.fg(t.green).Render("hermes") + "  " + hBar + "  " + t.bright().Render(fmt.Sprintf("%s (%.0f%%)", humanMoney(uw.HermesCost), hPct*100))
	line2 := t.fg(t.accent).Render("opencode") + " " + oBar + "  " + t.bright().Render(fmt.Sprintf("%s (%.0f%%)", humanMoney(uw.OpenCodeCost), oPct*100))
	return line1 + "\n" + line2
}

// renderUsageModels renders the per-model cost table.
func renderUsageModels(t *Theme, width int, uw collect.UsageWindow) string {
	if len(uw.Models) == 0 {
		return panel(t, "models", width, unavailable(t, "no usage recorded"))
	}
	var b strings.Builder
	b.WriteString(t.dimText().Render(fmt.Sprintf("%-30s %-11s %6s %10s %10s %9s",
		"model", "provider", "calls", "in", "out", "cost")))
	b.WriteString("\n")
	rows := uw.Models
	if len(rows) > usageModelRowsMax {
		rows = rows[:usageModelRowsMax]
	}
	for _, m := range rows {
		costLabel := humanMoney(m.Cost)
		if m.RateNA {
			costLabel += " (rate n/a)"
		}
		line := fmt.Sprintf("%-30s %-11s %6d %10s %10s %9s",
			truncate(m.Name, 30), truncate(providerShort(m.Provider), 11),
			m.APICalls, humanTokens(m.InTokens), humanTokens(m.OutTokens), costLabel)
		b.WriteString(line)
		b.WriteString("\n")
	}
	return panel(t, "models", width, strings.TrimSuffix(b.String(), "\n"))
}

// renderUsageBots renders one row per Hermes profile (main + bots).
func renderUsageBots(t *Theme, width int, u collect.Usage, win int) string {
	inner := maxint(width-4, 0)
	var uw collect.UsageWindow
	if win == win24h {
		uw = u.W24h
	} else {
		uw = u.Month
	}
	if len(uw.Bots) == 0 {
		return panel(t, "hermes bots", width, unavailable(t, "no bot rows"))
	}
	var b strings.Builder
	for _, bot := range uw.Bots {
		if !bot.OK {
			b.WriteString(t.bright().Render(fmt.Sprintf("%-8s", truncate(bot.Name, 8))) + " " + t.dimText().Render(truncate(bot.Err, maxint(inner-12, 1))))
			b.WriteString("\n")
			continue
		}
		name := t.bright().Render(fmt.Sprintf("%-8s", truncate(bot.Name, 8)))
		stat := fmt.Sprintf("calls %-5d in %8s out %8s cost %s",
			bot.APICalls, humanTokens(bot.InTokens), humanTokens(bot.OutTokens), humanMoney(bot.Cost))
		b.WriteString(name + " " + stat)
		b.WriteString("\n")
		if len(bot.TopModels) > 0 {
			var mix []string
			for i, m := range bot.TopModels {
				if i >= 3 {
					break
				}
				mix = append(mix, fmt.Sprintf("%s %s", truncate(modelShort(m.Name), 16), humanTokens(m.InTokens+m.OutTokens)))
			}
			b.WriteString("         " + t.dimText().Render("top: "+strings.Join(mix, " · ")))
			b.WriteString("\n")
		}
	}
	return panel(t, "hermes bots", width, strings.TrimSuffix(b.String(), "\n"))
}

// renderMonthSpark renders a compact per-day token/cost sparkline for the
// current month: one ▁-style column per day.
func renderMonthSpark(t *Theme, width int, u collect.Usage) string {
	inner := maxint(width-4, 0)
	if len(u.Daily) == 0 {
		return panel(t, "month sparkline", width, unavailable(t, "no daily data"))
	}
	maxTok := int64(1)
	for _, d := range u.Daily {
		if v := d.In + d.Out; v > maxTok {
			maxTok = v
		}
	}
	chars := []string{"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
	var b strings.Builder
	var costRow strings.Builder
	for _, d := range u.Daily {
		f := float64(d.In+d.Out) / float64(maxTok)
		idx := int(f * float64(len(chars)-1))
		if idx > len(chars)-1 {
			idx = len(chars) - 1
		}
		if !t.noColor {
			b.WriteString(t.fg(t.rampAt(f)).Render(chars[idx]))
		} else {
			b.WriteString(chars[idx])
		}
		// Cost ribbon: dim dot when the day had spend, blank otherwise.
		if d.Cost > 0 {
			costRow.WriteString(t.dimText().Render("·"))
		} else {
			costRow.WriteString(" ")
		}
	}
	// Odd days count: right-truncate to panel width.
	spark := b.String()
	if lipglossWidthSafe := lipgloss.Width(spark); lipglossWidthSafe > inner {
		spark = ansiTruncatePlain(spark, inner)
	}
	label := t.dimText().Render(fmt.Sprintf("days of %s · peak %s", u.Daily[0].Day.Format("Jan 2006"), humanTokens(maxTok)))
	return panel(t, "month sparkline", width, spark+"\n"+costRow.String()+"\n"+label)
}

// ── small formatting helpers ────────────────────────────────────────────

func humanTokens(n int64) string {
	const unit = 1000
	neg := n < 0
	if neg {
		n = -n
	}
	if n < unit {
		return fmt.Sprintf("%d", n)
	}
	div, exp := int64(unit), 0
	for m := n / unit; m >= unit; m /= unit {
		div *= unit
		exp++
	}
	s := fmt.Sprintf("%.1f%c", float64(n)/float64(div), "KMGTPE"[exp])
	if neg {
		s = "-" + s
	}
	return s
}

func humanMoney(v float64) string {
	if v > 0 && v < 0.01 {
		return fmt.Sprintf("$%.4f", v)
	}
	return fmt.Sprintf("$%.2f", v)
}

func sharePct(part, total float64) float64 {
	if total <= 0 {
		return 0
	}
	p := part / total
	if p > 1 {
		p = 1
	}
	return p
}

func providerShort(p string) string {
	switch p {
	case "":
		return "custom"
	case "custom:makora", "custom:friendliai":
		return strings.TrimPrefix(p, "custom:")
	case "openrouter", "deepseek", "openai-codex", "gemini", "openai", "fireworks", "anthropic":
		return p
	default:
		return truncate(p, 11)
	}
}

func modelShort(m string) string {
	// Strip a leading provider prefix ("deepseek-ai/").
	if i := strings.Index(m, "/"); i >= 0 {
		m = m[i+1:]
	}
	return m
}

func ansiTruncatePlain(s string, w int) string {
	for lipgloss.Width(s) > w {
		s = s[:len(s)-1]
	}
	return s
}
