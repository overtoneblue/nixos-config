// Package ui renders the head-dash frame with lipgloss. It degrades to a
// plain (no-color) terminal when Theme.noColor is set and never panics on
// narrow widths (all bars/truncations are clamped).
package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Theme bundles all styling for one render pass.
type Theme struct {
	noColor bool

	accent lipgloss.Color
	green  lipgloss.Color
	amber  lipgloss.Color
	red    lipgloss.Color
	dim    lipgloss.Color
	border lipgloss.Color
	bg     lipgloss.Color
	text   lipgloss.Color

	// ramp is the per-position gradient used for bar fills.
	ramp []lipgloss.Color
}

// NewTheme returns a Theme.
func NewTheme(noColor bool) *Theme {
	if noColor {
		return &Theme{noColor: true}
	}
	return &Theme{
		noColor: false,
		accent:  lipgloss.Color("#5ea7f0"),
		green:   lipgloss.Color("#7ee787"),
		amber:   lipgloss.Color("#e5b62f"),
		red:     lipgloss.Color("#f2553a"),
		dim:     lipgloss.Color("#4c566a"),
		border:  lipgloss.Color("#2f3340"),
		bg:      lipgloss.Color("#0f1117"),
		text:    lipgloss.Color("#c8d3e8"),
		ramp: []lipgloss.Color{
			lipgloss.Color("#3fa7ff"),
			lipgloss.Color("#3ddc97"),
			lipgloss.Color("#8fd64c"),
			lipgloss.Color("#f0c24c"),
			lipgloss.Color("#f08c3a"),
			lipgloss.Color("#f2553a"),
		},
	}
}

// fg applies a foreground color (identity when colorless).
func (t *Theme) fg(c lipgloss.Color) lipgloss.Style {
	s := lipgloss.NewStyle()
	if !t.noColor {
		s = s.Foreground(c)
	}
	return s
}

// dimText styles secondary text.
func (t *Theme) dimText() lipgloss.Style {
	return t.fg(t.dim)
}

// bright styles emphasised text.
func (t *Theme) bright() lipgloss.Style {
	if t.noColor {
		return lipgloss.NewStyle().Bold(true)
	}
	return lipgloss.NewStyle().Foreground(t.text).Bold(true)
}

// accentBold styles titles.
func (t *Theme) accentBold() lipgloss.Style {
	if t.noColor {
		return lipgloss.NewStyle().Bold(true)
	}
	return lipgloss.NewStyle().Foreground(t.accent).Bold(true)
}

// danger styles failure text.
func (t *Theme) danger() lipgloss.Style { return t.fg(t.red) }

func (t *Theme) warn() lipgloss.Style { return t.fg(t.amber) }

func (t *Theme) ok() lipgloss.Style { return t.fg(t.green) }

// rampAt returns the gradient colour at position f in [0,1].
func (t *Theme) rampAt(f float64) lipgloss.Color {
	if t.noColor || len(t.ramp) == 0 {
		return lipgloss.Color("")
	}
	clamped := clampf(f, 0, 1)
	i := int(clamped * float64(len(t.ramp)-1))
	if i >= len(t.ramp) {
		i = len(t.ramp) - 1
	}
	return t.ramp[i]
}

// levelColor maps a usage percentage onto a status colour.
func (t *Theme) levelColor(pct float64) lipgloss.Color {
	switch {
	case pct < 60:
		return t.green
	case pct < 85:
		return t.amber
	default:
		return t.red
	}
}

// badge renders a small status pill.
func (t *Theme) badge(label string, c lipgloss.Color) string {
	if t.noColor {
		if c == t.red {
			return "[" + strings.ToUpper(label) + "]"
		}
		return strings.ToUpper(label)
	}
	st := lipgloss.NewStyle().
		Background(c).
		Foreground(lipgloss.Color("#0b0d10")).
		Bold(true).
		Padding(0, 1)
	return st.Render(strings.ToUpper(label))
}

// bar renders a width-wide usage bar with a gradient fill for the used
// portion and a dim background for the free portion. pct is 0..100.
func (t *Theme) bar(pct float64, width int) string {
	if width <= 0 {
		return ""
	}
	filled := int(clampf(pct, 0, 100) / 100 * float64(width))
	if filled > width {
		filled = width
	}

	if t.noColor {
		return strings.Repeat("#", filled) + strings.Repeat("-", width-filled)
	}

	var b strings.Builder
	for i := 0; i < width; i++ {
		switch {
		case i < filled:
			col := t.rampAt(float64(i) / float64(max1(width)))
			content := lipgloss.NewStyle().Foreground(col).Render("█")
			b.WriteString(content)
		default:
			content := t.dimText().Render("░")
			b.WriteString(content)
		}
	}
	return b.String()
}

// truncate keeps s at most width runes, adding an ellipsis when trimmed.
func truncate(s string, width int) string {
	if width <= 0 {
		return ""
	}
	r := []rune(s)
	if len(r) <= width {
		return s
	}
	if width <= 1 {
		return s[:1]
	}
	return string(r[:width-1]) + "…"
}

func clampf(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func max1(v int) int {
	if v < 1 {
		return 1
	}
	return v
}

func maxint(a, b int) int {
	if a > b {
		return a
	}
	return b
}
