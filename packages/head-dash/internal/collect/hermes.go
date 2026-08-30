package collect

import (
	"context"
	"io/fs"
	"path/filepath"
	"time"
)

// Hermes reports the hermes-agent badge: DOWN / ACTIVE / IDLE, based on the
// systemd unit state, recent journal output, or (when journal access is
// denied) the freshness of log/session files under the appdata dirs.
type Hermes struct {
	Badge        string
	ActiveState  string
	SubState     string
	ActivityAge  time.Duration
	HasAge       bool
	JournalLines int
	Note         string
}

// hermesLogDirs are the appdata paths whose newest mtime approximates the
// last agent activity when journalctl is unavailable.
var hermesLogDirs = []string{
	"/mnt/cache/appdata/hermes-agent/.hermes/logs",
	"/mnt/cache/appdata/hermes-agent/.hermes/sessions",
}

const hermesRecentWindow = 60 * time.Second

func (c *Collector) collectHermes(ctx context.Context, d *Data) {
	h := Hermes{}

	active := false
	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "show", "-p", "ActiveState", "-p", "SubState", "--no-pager", "hermes-agent"); err == nil {
		vals := parseKV(out)
		h.ActiveState = vals["ActiveState"]
		h.SubState = vals["SubState"]
		active = h.ActiveState == "active"
	}

	journalOK := false
	if out, err := runCmd(ctx, 3*time.Second, "journalctl", "-u", "hermes-agent", "--since=-60s", "--no-pager"); err == nil {
		journalOK = true
		h.JournalLines = countLines(out)
		if h.JournalLines > 0 {
			h.Badge = "ACTIVE"
			h.HasAge = true
			h.ActivityAge = 0
		}
	}

	// Journal access can be denied (e.g. non-root without the right policy);
	// fall back to the newest log/session mtime under the appdata dirs.
	newest, ok := newestMtime(ctx, hermesLogDirs)
	if ok && !h.HasAge {
		age := time.Since(newest)
		h.ActivityAge = age
		h.HasAge = true
		if age <= hermesRecentWindow {
			h.Badge = "ACTIVE"
		}
	}
	if !ok && !journalOK && h.Badge == "" {
		h.Note = "journal access denied and log dirs unreadable"
	}

	switch {
	case !active:
		h.Badge = "DOWN"
	case h.Badge == "ACTIVE":
		// already set
	default:
		if h.HasAge {
			h.Badge = "IDLE"
		} else {
			h.Badge = "activity unknown"
		}
	}

	d.Hermes = h
}

// newestMtime returns the newest modification time across all files under the
// given directories (best-effort; unreadable directories are skipped, and the
// walk is capped to bound the cost of a large session tree).
func newestMtime(ctx context.Context, dirs []string) (time.Time, bool) {
	var newest time.Time
	found := false
	visits := 0
	for _, dir := range dirs {
		_ = filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
			visits++
			if visits > 5000 {
				return fs.SkipAll
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}
			if err != nil {
				return nil // skip unreadable subtree
			}
			if info, e := entry.Info(); e == nil && info.ModTime().After(newest) {
				newest = info.ModTime()
				found = true
			}
			return nil
		})
	}
	return newest, found
}
