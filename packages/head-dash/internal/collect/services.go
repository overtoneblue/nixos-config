package collect

import (
	"context"
	"strings"
	"time"
)

// Services reports the curated systemd units plus a failed-units section.
type Services struct {
	OK          bool
	Err         string
	List        []Service
	FailedUnits []string
}

// Service is the ActiveState/SubState pair of one systemd unit.
type Service struct {
	Name        string
	ActiveState string
	SubState    string
	Err         string
}

// curatedServices is the set of units the dashboard tracks. docker-jellyfin
// is the OCI container unit that NixOS generates for the Jellyfin call on the
// head host.
var curatedServices = []string{"hermes-agent", "opencode", "docker", "docker-jellyfin", "nginx"}

func (c *Collector) collectServices(ctx context.Context, d *Data) {
	svcs := Services{OK: true, List: []Service{}}

	for _, name := range curatedServices {
		st := Service{Name: name}
		out, err := runCmd(ctx, 2*time.Second, "systemctl", "show", "-p", "ActiveState", "-p", "SubState", "--no-pager", name)
		if err == nil {
			vals := parseKV(out)
			st.ActiveState = vals["ActiveState"]
			st.SubState = vals["SubState"]
			if st.ActiveState == "" {
				st.Err = "no unit state returned"
			}
		} else {
			st.Err = "unavailable (systemctl failed)"
		}
		svcs.List = append(svcs.List, st)
	}

	if out, err := runCmd(ctx, 2*time.Second, "systemctl", "--failed", "--no-legend", "--no-pager", "--plain"); err == nil {
		for _, line := range strings.Split(out, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			if name := strings.Fields(line); len(name) > 0 {
				svcs.FailedUnits = append(svcs.FailedUnits, name[0])
			}
		}
	}

	d.Services = svcs
}

// parseKV converts "Key=Value" newline-separated output into a map.
func parseKV(out string) map[string]string {
	m := map[string]string{}
	for _, line := range strings.Split(out, "\n") {
		if i := strings.IndexByte(line, '='); i > 0 {
			m[line[:i]] = line[i+1:]
		}
	}
	return m
}
