package collect

import (
	"context"
	"os"
	"strings"
	"time"
)

// Hermes reports the hermes-agent badge as UP / RUNNING / DOWN / UNKNOWN.
// DOWN when the systemd unit is inactive; RUNNING while a live-activity
// detector fires or within a short quiet-hold afterwards; UP otherwise. When
// every activity source is unreadable the badge is UNKNOWN.
type Hermes struct {
	Badge        string
	ActiveState  string
	SubState     string
	ActivityAge  time.Duration
	HasAge       bool
	JournalLines int
	Note         string
	LastAct      time.Time
	HasAct       bool
}

// hermesState carries the RUNNING→UP hysteresis across samples. Quiet is held
// for hermesHoldFromDown once activity stops, so a briefly-idle agent does not
// flicker back to UP immediately.
type hermesState struct {
	quietSince time.Time
	lastAct    time.Time
}

const (
	hermesActivityWindow = 5 * time.Second
	hermesHoldFromDown   = 20 * time.Second
)

const (
	hermesLogPath = "/mnt/cache/appdata/hermes-agent/.hermes/logs/agent.log"
	hermesDBPath  = "/mnt/cache/appdata/hermes-agent/.hermes/state.db"
)

func (c *Collector) collectHermes(ctx context.Context, d *Data) {
	h := Hermes{}

	active := false
	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "is-active", "hermes-agent"); err == nil {
		active = strings.TrimSpace(out) == "active"
	}

	freshLog, logOK := false, false
	if fi, err := os.Stat(hermesLogPath); err == nil {
		logOK = true
		freshLog = time.Since(fi.ModTime()) < hermesActivityWindow
	}
	freshDB, dbOK := false, false
	if fi, err := os.Stat(hermesDBPath); err == nil {
		dbOK = true
		freshDB = time.Since(fi.ModTime()) < hermesActivityWindow
	}
	freshJournal, journalOK := false, false
	if out, err := runCmd(ctx, 3*time.Second, "journalctl", "-u", "hermes-agent", "--since=-5s", "--no-pager"); err == nil {
		journalOK = true
		freshJournal = countLines(out) > 0
	}

	st := &c.hermesSt
	now := time.Now()
	switch {
	case !active:
		h.Badge = "DOWN"
		h.HasAct = !st.lastAct.IsZero()
		h.LastAct = st.lastAct
	case !(logOK || dbOK || journalOK):
		h.Badge = "UNKNOWN"
		h.HasAct = !st.lastAct.IsZero()
		h.LastAct = st.lastAct
	case freshLog || freshDB || freshJournal:
		st.lastAct = now
		st.quietSince = time.Time{}
		h.Badge = "RUNNING"
		h.HasAct = true
		h.LastAct = now
	default:
		if st.lastAct.IsZero() {
			h.Badge = "UP"
		} else {
			if st.quietSince.IsZero() {
				st.quietSince = now
			}
			if now.Sub(st.quietSince) < hermesHoldFromDown {
				h.Badge = "RUNNING"
			} else {
				h.Badge = "UP"
			}
			h.HasAct = true
			h.LastAct = st.lastAct
		}
	}

	d.Hermes = h
}
