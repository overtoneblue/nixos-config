package ui

import (
	"time"

	"head-dash/internal/collect"

	"github.com/charmbracelet/bubbletea"
)

// Collection budget bounds every collect so a slow data source can never hang
// the UI; individual collectors keep their own (tighter) timeouts.
const collectBudget = 6 * time.Second

// intervalLadder is the discrete set of refresh intervals the +/- keys step
// through.
var intervalLadder = []time.Duration{
	50 * time.Millisecond,
	100 * time.Millisecond,
	200 * time.Millisecond,
	500 * time.Millisecond,
	time.Second,
	2 * time.Second,
	5 * time.Second,
}

// minInterval rejects anything below the fastest usable refresh (~20fps).
const minInterval = 50 * time.Millisecond

// Model is the Bubble Tea dashboard state. Data comes from the shared
// collector cache; each tick just snapshots it and re-schedules.
type Model struct {
	col      *collect.Collector
	theme    *Theme
	interval time.Duration

	data collect.Data
	width int
	height int
	rendered string

	paused bool
	tick   int

	// page: 0 = system, 1 = usage (ui.pageSystem / ui.pageUsage)
	page    int
	// usageWin: 0 = 24h rolling, 1 = calendar month (ui.win24h / ui.winMonth)
	usageWin int
}

type tickMsg struct{}

// NewModel returns a dashboard model. The collector must already be warmed up
// (see collect.Collector.Warmup) and started (see collect.Collector.Start) so
// the shared cache is being refreshed by the background streams.
func NewModel(col *collect.Collector, noColor bool, interval time.Duration, page int, usageWin int) Model {
	interval = clampDur(interval, minInterval, intervalLadder[len(intervalLadder)-1])
	col.SetFastCadence(interval)
	m := Model{
		col:      col,
		theme:    NewTheme(noColor),
		interval: interval,
		width:    120,
		height:   36,
		page:     page,
		usageWin: usageWin,
	}
	m.rebuildView()
	return m
}

func (m Model) Init() tea.Cmd {
	return func() tea.Msg { return tickMsg{} }
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.rebuildView()
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "p":
			m.paused = !m.paused
			m.rebuildView()
			return m, m.nextTick()
		case "r":
			if m.paused {
				return m, nil
			}
			m.refresh()
			return m, m.nextTick()
		case "+", "=":
			m.setInterval(stepInterval(m.interval, true))
			return m, nil
		case "-", "_":
			m.setInterval(stepInterval(m.interval, false))
			return m, nil
		case "tab":
			m.page = (m.page + 1) % pageCount
			m.rebuildView()
			return m, nil
		case "shift+tab":
			m.page = (m.page - 1 + pageCount) % pageCount
			m.rebuildView()
			return m, nil
		case "1":
			m.page = pageSystem
			m.rebuildView()
			return m, nil
		case "2":
			m.page = pageUsage
			m.rebuildView()
			return m, nil
		case "a":
			if m.page == pageUsage {
				m.usageWin = win24h
				m.rebuildView()
			}
			return m, nil
		case "m":
			if m.page == pageUsage {
				m.usageWin = winMonth
				m.rebuildView()
			}
			return m, nil
		case "u":
			if m.page == pageUsage {
				m.refresh()
			}
			return m, nil
		}

	case tickMsg:
		if m.paused {
			return m, nil
		}
		m.refresh()
		return m, m.nextTick()
	}
	return m, nil
}

// refresh snapshots the collector cache into m.data. It has a pointer receiver
// so the mutation survives the value-model copy that Update passes around.
func (m *Model) refresh() {
	m.data = m.col.Snapshot()
	m.tick++
	m.rebuildView()
}

func (m *Model) setInterval(d time.Duration) {
	m.interval = d
	m.col.SetFastCadence(d)
	m.rebuildView()
}

// rebuildView runs on state changes, never from View. This keeps Bubble Tea's
// high-frequency render calls allocation- and I/O-free at the 50ms cadence.
func (m *Model) rebuildView() {
	m.rendered = renderFrame(m.theme, m.width, m.height, m.data, m.interval, m.paused, m.page, m.usageWin)
}

func (m Model) nextTick() tea.Cmd {
	return tea.Tick(m.interval, func(time.Time) tea.Msg { return tickMsg{} })
}

func (m Model) View() string {
	return m.rendered
}

func stepInterval(d time.Duration, up bool) time.Duration {
	i := nearestIndex(d)
	if up {
		if i < len(intervalLadder)-1 {
			return intervalLadder[i+1]
		}
		return intervalLadder[i]
	}
	if i > 0 {
		return intervalLadder[i-1]
	}
	return intervalLadder[i]
}

func nearestIndex(d time.Duration) int {
	best := 0
	for i, v := range intervalLadder {
		if v == d {
			return i
		}
		if absDur(v-d) < absDur(intervalLadder[best]-d) {
			best = i
		}
	}
	return best
}

func absDur(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
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
