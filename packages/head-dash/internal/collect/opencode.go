package collect

import (
	"context"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// OpenCode reports the OpenCode persistent backend status as UP / RUNNING /
// DOWN / UNKNOWN. DOWN when the unit is inactive or the local HTTP gate cannot
// be reached; RUNNING while the state database is fresh (within a quiet-hold
// window); UP when the HTTP gate answers any status (401 is the auth gate, so
// it still counts as alive). If the database is unreadable, RUNNING detection
// is skipped and the UI notes "activity n/a".
type OpenCode struct {
	Status        string // up | down | unknown
	HTTPStatus    int
	Latency       time.Duration
	HasLatency    bool
	ServiceActive bool
	Err           string
	DBUnread      bool
}

// opencodeState carries the RUNNING→UP hysteresis across samples.
type opencodeState struct {
	quietSince time.Time
	lastAct    time.Time
}

const (
	opencodeActivityWindow = 10 * time.Second
	opencodeHoldFromDown   = 15 * time.Second
)

const opencodeDBPath = "/mnt/cache/appdata/opencode/data/opencode/opencode-stable.db"

func (c *Collector) collectOpenCode(ctx context.Context, d *Data) {
	oc := OpenCode{Status: "unknown"}

	serviceActive := false
	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "is-active", "opencode.service"); err == nil {
		serviceActive = strings.TrimSpace(out) == "active"
		oc.ServiceActive = serviceActive
	}

	client := &http.Client{Timeout: 2 * time.Second}
	start := time.Now()
	resp, err := client.Get("http://127.0.0.1:4096/")
	latency := time.Since(start)
	httpOK := err == nil
	if httpOK {
		oc.HasLatency = true
		oc.Latency = latency
		oc.HTTPStatus = resp.StatusCode
		_, _ = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	} else {
		oc.Err = err.Error()
	}

	dbOK, dbFresh := false, false
	if fi, err := os.Stat(opencodeDBPath); err == nil {
		dbOK = true
		dbFresh = time.Since(fi.ModTime()) < opencodeActivityWindow
	} else {
		oc.DBUnread = true
	}

	st := &c.ocSt
	now := time.Now()
	switch {
	case !serviceActive:
		oc.Status = "down"
	case !httpOK:
		oc.Status = "down"
	case !dbOK:
		oc.Status = "up"
	case dbFresh:
		st.lastAct = now
		st.quietSince = time.Time{}
		oc.Status = "running"
	default:
		if st.lastAct.IsZero() {
			oc.Status = "up"
		} else {
			if st.quietSince.IsZero() {
				st.quietSince = now
			}
			if now.Sub(st.quietSince) < opencodeHoldFromDown {
				oc.Status = "running"
			} else {
				oc.Status = "up"
			}
		}
	}

	d.OpenCode = oc
}
