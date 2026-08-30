package collect

import (
	"context"
	"encoding/json"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
)

// Docker reports on running containers via the Docker Engine API (the Go SDK,
// never the CLI).
type Docker struct {
	OK         bool
	Err        string
	Containers []Container
}

// Container is one engine container with live usage stats.
type Container struct {
	Name     string
	Image    string
	State    string
	Status   string
	CPU      float64
	MemPct   float64
	MemUsed  uint64
	MemLimit uint64
	HasStats bool
}

// dockerHolder lazily builds a single API client per process.
type dockerHolder struct {
	once    sync.Once
	cli     *client.Client
	initErr error
}

func (c *Collector) dockerClient() (*client.Client, error) {
	c.docker.once.Do(func() {
		c.docker.cli, c.docker.initErr = client.NewClientWithOpts(
			client.FromEnv,
			client.WithAPIVersionNegotiation(),
		)
	})
	return c.docker.cli, c.docker.initErr
}

func (c *Collector) collectDocker(ctx context.Context, d *Data) {
	select {
	case <-ctx.Done():
		d.Docker = Docker{OK: false, Err: "collect budget exceeded"}
		return
	default:
	}

	cli, err := c.dockerClient()
	if err != nil {
		d.Docker = Docker{OK: false, Err: "docker socket not accessible"}
		return
	}

	pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	if _, err := cli.Ping(pingCtx); err != nil {
		cancel()
		d.Docker = Docker{OK: false, Err: dockerErr(err)}
		return
	}
	cancel()

	listCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	containers, err := cli.ContainerList(listCtx, container.ListOptions{})
	cancel()
	if err != nil {
		d.Docker = Docker{OK: false, Err: dockerErr(err)}
		return
	}

	out := Docker{OK: true, Containers: []Container{}}
	for _, ctr := range containers {
		name := ""
		if len(ctr.Names) > 0 {
			// The engine reports names with a leading "/" (e.g. "/jellyfin").
			name = strings.TrimPrefix(ctr.Names[0], "/")
		}
		row := Container{
			Name:   name,
			Image:  ctr.Image,
			State:  ctr.State,
			Status: ctr.Status,
		}
		statsCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		if s, ok := readContainerStats(statsCtx, cli, ctr.ID); ok {
			row.CPU = s.cpu
			row.MemPct = s.memPct
			row.MemUsed = s.memUsed
			row.MemLimit = s.memLimit
			row.HasStats = true
		}
		cancel()
		out.Containers = append(out.Containers, row)
	}
	d.Docker = out
}

func dockerErr(err error) string {
	if err != nil && strings.Contains(strings.ToLower(err.Error()), "permission denied") {
		return "docker socket not accessible"
	}
	return "docker daemon unreachable"
}

type containerStats struct {
	cpu      float64
	memPct   float64
	memUsed  uint64
	memLimit uint64
}

// readContainerStats grabs a single stats snapshot for a container. The
// non-streaming endpoint returns a snapshot whose PreCPUStats carry the
// previous sample, so a proper CPU% delta is computable.
func readContainerStats(ctx context.Context, cli *client.Client, id string) (containerStats, bool) {
	resp, err := cli.ContainerStats(ctx, id, false)
	if err != nil {
		return containerStats{}, false
	}
	defer resp.Body.Close()

	var s container.StatsResponse
	dec := json.NewDecoder(resp.Body)
	if err := dec.Decode(&s); err != nil {
		return containerStats{}, false
	}

	out := containerStats{}
	cpuDelta := float64(0)
	if s.CPUStats.CPUUsage.TotalUsage >= s.PreCPUStats.CPUUsage.TotalUsage {
		cpuDelta = float64(s.CPUStats.CPUUsage.TotalUsage - s.PreCPUStats.CPUUsage.TotalUsage)
	}
	sysDelta := float64(0)
	if s.CPUStats.SystemUsage >= s.PreCPUStats.SystemUsage {
		sysDelta = float64(s.CPUStats.SystemUsage - s.PreCPUStats.SystemUsage)
	}
	cpus := s.CPUStats.OnlineCPUs
	if cpus == 0 {
		cpus = uint32(runtime.NumCPU())
	}
	if sysDelta > 0 && cpuDelta >= 0 {
		out.cpu = cpuDelta / sysDelta * float64(cpus) * 100
	}
	if s.MemoryStats.Limit > 0 {
		out.memPct = float64(s.MemoryStats.Usage) / float64(s.MemoryStats.Limit) * 100
		out.memUsed = s.MemoryStats.Usage
		out.memLimit = s.MemoryStats.Limit
	}
	return out, true
}
