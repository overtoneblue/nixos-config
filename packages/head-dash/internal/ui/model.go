package ui

import (
	"context"
	"time"

	"head-dash/internal/collect"

	"github.com/charmbracelet/bubbletea"
)

// Collection budget bounds every tick so a slow data source can never hang
// the UI; individual collectors keep their own (tighter) timeouts.
const collectBudget = 6 * time.Second

const (
	minInterval = 250 * time.Millisecond
	maxInterval = 30 * time.Second
)

// Model is the Bubble Tea dashboard state.
type Model struct {
	col      *collect.Collector
	theme    *Theme
	interval time.Duration

	data   collect.Data
	width  int
	height int

	paused bool
	busy   bool // a collect is in flight
	tick   int
}

type tickMsg struct{}

type gotDataMsg struct {
	data collect.Data
}

// NewModel returns a dashboard model. The collector must already be warmed up
// (see collect.Collector.Warmup) so the first frame has CPU deltas.
func NewModel(col *collect.Collector, noColor bool, interval time.Duration) Model {
	if interval < minInterval {
		interval = minInterval
	}
	return Model{
		col:      col,
		theme:    NewTheme(noColor),
		interval: interval,
		width:    120,
		height:   36,
	}
}

func (m Model) Init() tea.Cmd {
	return func() tea.Msg { return tickMsg{} }
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "p":
			m.paused = !m.paused
			if m.paused {
				return m, nil
			}
			return m, m.nextTick()
		case "r":
			if m.paused || m.busy {
				return m, nil
			}
			m.busy = true
			return m, m.collectCmd()
		case "+", "=":
			m.interval = clampDur(m.interval*2, minInterval, maxInterval)
			return m, nil
		case "-", "_":
			m.interval = clampDur(m.interval/2, minInterval, maxInterval)
			return m, nil
		}

	case tickMsg:
		if m.paused || m.busy {
			return m, nil
		}
		m.busy = true
		return m, m.collectCmd()

	case gotDataMsg:
		m.data = msg.data
		m.busy = false
		m.tick++
		return m, m.nextTick()
	}
	return m, nil
}

func (m Model) nextTick() tea.Cmd {
	return tea.Tick(m.interval, func(time.Time) tea.Msg { return tickMsg{} })
}

// collectCmd runs the async snapshot and delivers it back to the UI loop.
func (m Model) collectCmd() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), collectBudget)
		defer cancel()
		return gotDataMsg{data: m.col.Collect(ctx)}
	}
}

func (m Model) View() string {
	return renderFrame(m.theme, m.width, m.height, m.data, m.interval, m.paused)
}

func clampDur(d, lo, hi time.Duration) time.Duration {
	if d < lo {
		return lo
	}
	if d > hi {
		return hi
	}
	return d
}
