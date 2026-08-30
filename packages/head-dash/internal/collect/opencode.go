package collect

import (
	"context"
	"io"
	"net/http"
	"strings"
	"time"
)

// OpenCode reports the OpenCode persistent backend status. Any HTTP response
// on 127.0.0.1:4096 (even 401, the auth gate) means the backend is up;
// connection-refused means down.
type OpenCode struct {
	Status        string // up | down | unknown
	HTTPStatus    int
	Latency       time.Duration
	HasLatency    bool
	ServiceActive bool
	Err           string
}

func (c *Collector) collectOpenCode(ctx context.Context, d *Data) {
	oc := OpenCode{}

	client := &http.Client{Timeout: 2 * time.Second}
	start := time.Now()
	resp, err := client.Get("http://127.0.0.1:4096/")
	latency := time.Since(start)
	switch {
	case err == nil:
		oc.HasLatency = true
		oc.Latency = latency
		oc.HTTPStatus = resp.StatusCode
		oc.Status = "up"
		_, _ = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	case strings.Contains(strings.ToLower(err.Error()), "connection refused"):
		oc.Status = "down"
		oc.Err = "connection refused"
	default:
		oc.Status = "unknown"
		oc.Err = err.Error()
	}

	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "is-active", "opencode.service"); err == nil {
		oc.ServiceActive = strings.TrimSpace(out) == "active"
	}

	d.OpenCode = oc
}
