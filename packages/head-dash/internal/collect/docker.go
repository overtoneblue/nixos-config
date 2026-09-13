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

const dockerStatsWorkers = 4

const (
	dockerStreamRefresh = 10 * time.Second
	dockerStreamBackoff = 1500 * time.Millisecond
)

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

// dockerStatsStream caches each running container's latest streaming sample.
// The manager owns stream lifetimes; readers only take a short read lock.
type dockerStatsStream struct {
	start   sync.Once
	mu      sync.RWMutex
	stats   map[string]containerStats
	have    map[string]bool
	streams map[string]context.CancelFunc
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

// startDockerStream starts the per-container stats stream manager once. Its
// initial refresh runs immediately so new dashboard sessions do not wait for
// the regular container-list interval before receiving stats.
func (c *Collector) startDockerStream(ctx context.Context) {
	c.dockerStream.start.Do(func() {
		c.dockerStream.mu.Lock()
		c.dockerStream.stats = make(map[string]containerStats)
		c.dockerStream.have = make(map[string]bool)
		c.dockerStream.streams = make(map[string]context.CancelFunc)
		c.dockerStream.mu.Unlock()

		go c.dockerStreamLoop(ctx)
	})
}

func (c *Collector) dockerStreamLoop(ctx context.Context) {
	ticker := time.NewTicker(dockerStreamRefresh)
	defer ticker.Stop()

	for {
		c.syncDockerStreams(ctx)
		select {
		case <-ctx.Done():
			c.stopDockerStreams()
			return
		case <-ticker.C:
		}
	}
}

// syncDockerStreams keeps exactly one stats stream for every container in the
// latest running-container list. Failed lists leave existing streams alone so
// they can reconnect when the daemon comes back.
func (c *Collector) syncDockerStreams(ctx context.Context) {
	cli, err := c.dockerClient()
	if err != nil {
		return
	}

	listCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	containers, err := cli.ContainerList(listCtx, container.ListOptions{})
	cancel()
	if err != nil {
		return
	}

	present := make(map[string]struct{}, len(containers))
	for _, ctr := range containers {
		present[ctr.ID] = struct{}{}
	}

	type pendingStream struct {
		id  string
		ctx context.Context
	}
	var starts []pendingStream
	var stops []context.CancelFunc

	c.dockerStream.mu.Lock()
	for id, stop := range c.dockerStream.streams {
		if _, ok := present[id]; ok {
			continue
		}
		delete(c.dockerStream.streams, id)
		delete(c.dockerStream.stats, id)
		delete(c.dockerStream.have, id)
		stops = append(stops, stop)
	}
	for id := range present {
		if _, ok := c.dockerStream.streams[id]; ok {
			continue
		}
		streamCtx, stop := context.WithCancel(ctx)
		c.dockerStream.streams[id] = stop
		starts = append(starts, pendingStream{id: id, ctx: streamCtx})
	}
	c.dockerStream.mu.Unlock()

	for _, stop := range stops {
		stop()
	}
	for _, stream := range starts {
		go c.streamContainerStats(stream.ctx, cli, stream.id)
	}
}

func (c *Collector) stopDockerStreams() {
	var stops []context.CancelFunc
	c.dockerStream.mu.Lock()
	for id, stop := range c.dockerStream.streams {
		delete(c.dockerStream.streams, id)
		delete(c.dockerStream.stats, id)
		delete(c.dockerStream.have, id)
		stops = append(stops, stop)
	}
	c.dockerStream.mu.Unlock()

	for _, stop := range stops {
		stop()
	}
}

// streamContainerStats reconnects a Docker streaming stats endpoint whenever
// it closes. The child context is canceled by the manager when the container
// leaves the running list.
func (c *Collector) streamContainerStats(ctx context.Context, cli *client.Client, id string) {
	for {
		if ctx.Err() != nil {
			return
		}

		resp, err := cli.ContainerStats(ctx, id, true)
		if err == nil {
			dec := json.NewDecoder(resp.Body)
			for {
				var sample container.StatsResponse
				if err := dec.Decode(&sample); err != nil {
					break
				}
				c.storeContainerStats(ctx, id, computeContainerStats(sample))
			}
			_ = resp.Body.Close()
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(dockerStreamBackoff):
		}
	}
}

func (c *Collector) storeContainerStats(ctx context.Context, id string, stats containerStats) {
	if ctx.Err() != nil {
		return
	}
	c.dockerStream.mu.Lock()
	defer c.dockerStream.mu.Unlock()
	if ctx.Err() != nil {
		return
	}
	if _, ok := c.dockerStream.streams[id]; !ok {
		return
	}
	c.dockerStream.stats[id] = stats
	c.dockerStream.have[id] = true
}

// latestContainerStats returns the last decoded stream sample without waiting
// on the Docker daemon or a stats stream.
func (c *Collector) latestContainerStats(id string) (containerStats, bool) {
	c.dockerStream.mu.RLock()
	defer c.dockerStream.mu.RUnlock()
	stats, ok := c.dockerStream.stats[id]
	return stats, ok && c.dockerStream.have[id]
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

	out := Docker{OK: true, Containers: make([]Container, len(containers))}
	for i, ctr := range containers {
		name := ""
		if len(ctr.Names) > 0 {
			// The engine reports names with a leading "/" (e.g. "/jellyfin").
			name = strings.TrimPrefix(ctr.Names[0], "/")
		}
		out.Containers[i] = Container{
			Name:   name,
			Image:  ctr.Image,
			State:  ctr.State,
			Status: ctr.Status,
		}
	}

	statsNeeded := make([]int, 0, len(containers))
	for i, ctr := range containers {
		if s, ok := c.latestContainerStats(ctr.ID); ok {
			out.Containers[i].CPU = s.cpu
			out.Containers[i].MemPct = s.memPct
			out.Containers[i].MemUsed = s.memUsed
			out.Containers[i].MemLimit = s.memLimit
			out.Containers[i].HasStats = true
		} else if !c.dockerStreaming {
			statsNeeded = append(statsNeeded, i)
		}
	}

	workers := len(statsNeeded)
	if workers > dockerStatsWorkers {
		workers = dockerStatsWorkers
	}
	jobs := make(chan int)
	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				statsCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
				if s, ok := fetchContainerStats(statsCtx, cli, containers[i].ID); ok {
					out.Containers[i].CPU = s.cpu
					out.Containers[i].MemPct = s.memPct
					out.Containers[i].MemUsed = s.memUsed
					out.Containers[i].MemLimit = s.memLimit
					out.Containers[i].HasStats = true
				}
				cancel()
			}
		}()
	}
	for _, i := range statsNeeded {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
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

// fetchContainerStats grabs a single stats snapshot for a container. The
// non-streaming endpoint returns a snapshot whose PreCPUStats carry the
// previous sample, so a proper CPU% delta is computable.
func fetchContainerStats(ctx context.Context, cli *client.Client, id string) (containerStats, bool) {
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
	return computeContainerStats(s), true
}

// computeContainerStats converts Docker's cumulative counters into one display
// sample. It is shared by one-shot verification reads and persistent streams.
func computeContainerStats(s container.StatsResponse) containerStats {
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
	return out
}
