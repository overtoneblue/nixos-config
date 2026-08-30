package collect

import (
	"context"
	"io"
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
	hermesActivityWindow = 10 * time.Second
	hermesHoldFromDown   = 15 * time.Second
	hermesLogTailSize    = 16 * 1024
)

const (
	hermesLogPath = "/mnt/cache/appdata/hermes-agent/.hermes/logs/agent.log"
)

func (c *Collector) collectHermes(ctx context.Context, d *Data) {
	h := Hermes{}

	active := false
	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "is-active", "hermes-agent"); err == nil {
		active = strings.TrimSpace(out) == "active"
	}

	now := time.Now()
	lastLogAct, logOK := readHermesLogActivity(hermesLogPath)
	freshLog := logOK && !lastLogAct.IsZero() && now.Sub(lastLogAct) < hermesActivityWindow
	freshJournal, journalOK := false, false
	if out, err := runCmd(ctx, 3*time.Second, "journalctl", "-u", "hermes-agent", "--since=-10s", "--no-pager"); err == nil {
		journalOK = true
		for _, line := range strings.Split(out, "\n") {
			if line != "" && !hermesHousekeeping(line) {
				freshJournal = true
				h.JournalLines++
			}
		}
	}

	st := &c.hermesSt
	if !lastLogAct.IsZero() && lastLogAct.After(st.lastAct) {
		st.lastAct = lastLogAct
	}
	switch {
	case !active:
		h.Badge = "DOWN"
		h.HasAct = !st.lastAct.IsZero()
		h.LastAct = st.lastAct
	case !(logOK || journalOK):
		h.Badge = "UNKNOWN"
		h.HasAct = !st.lastAct.IsZero()
		h.LastAct = st.lastAct
	case freshLog || freshJournal:
		if freshJournal && now.After(st.lastAct) {
			st.lastAct = now
		}
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

// readHermesLogActivity reads only the end of the log, where the most recent
// meaningful event is expected. mtime is deliberately ignored: gateway memory
// trims update it even while the agent is idle.
func readHermesLogActivity(path string) (time.Time, bool) {
	f, err := os.Open(path)
	if err != nil {
		return time.Time{}, false
	}
	defer f.Close()

	if fi, err := f.Stat(); err == nil && fi.Size() > hermesLogTailSize {
		if _, err := f.Seek(-hermesLogTailSize, io.SeekEnd); err != nil {
			return time.Time{}, false
		}
	}
	b, err := io.ReadAll(f)
	if err != nil {
		return time.Time{}, false
	}
	return newestHermesActivity(string(b)), true
}

func newestHermesActivity(log string) time.Time {
	var newest time.Time
	for _, line := range strings.Split(log, "\n") {
		if hermesHousekeeping(line) || len(line) < len("2006-01-02 15:04:05,000") {
			continue
		}
		at, err := time.ParseInLocation("2006-01-02 15:04:05,000", line[:23], time.Local)
		if err == nil && at.After(newest) {
			newest = at
		}
	}
	return newest
}

func hermesHousekeeping(line string) bool {
	return strings.Contains(line, "mem_trim") || strings.Contains(line, "housekeeping") ||
		strings.Contains(line, "pam_unix") || strings.Contains(line, "sudo[") || strings.Contains(line, " COMMAND=")
}
