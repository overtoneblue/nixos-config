// Package collect gathers host telemetry for the head dashboard. Every
// collector is bounded by the budget context passed to Collect, runs
// concurrently, and reports availability through OK/Err fields so the UI can
// degrade to a clear "unavailable" state instead of crashing or hanging.
package collect

import (
	"context"
	"os"
	"sync"
	"time"
)

// Data is a full host snapshot for one dashboard frame. Subsystems carry an
// OK flag; when a source is unreadable the UI renders that panel's
// "unavailable" state.
type Data struct {
	Timestamp time.Time
	Header    Header
	CPU       CPU
	Load      []float64
	Mem       Mem
	Swap      Mem
	GPUs      []GPU
	Docker    Docker
	Services  Services
	Hermes    Hermes
	OpenCode  OpenCode
	Storage   []Storage
}

// Header holds system identity trivia shown at the top of the dashboard.
type Header struct {
	Hostname string
	Uptime   time.Duration
	Kernel   string
	NumCPU   int
	OK       bool
	Err      string
}

// Collector owns cross-tick state (previous /proc/stat + per-process baselines,
// lazily-created Docker client) and produces Data snapshots.
type Collector struct {
	budget  time.Duration
	docker  dockerHolder
	prevCPU cpuPrev
}

// NewCollector returns a Collector with the given collect budget. A non-positive
// budget falls back to 6s — generous enough for the slowest collector (Docker
// stats of many containers) while still bounding the tick.
func NewCollector(budget time.Duration) *Collector {
	if budget <= 0 {
		budget = 6 * time.Second
	}
	return &Collector{budget: budget}
}

// Warmup establishes baselines (CPU/proc deltas, Docker client + ping) so the
// very first rendered frame already carries meaningful deltas. It is safe and
// cheap; call once before the first Collect.
func (c *Collector) Warmup(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, c.budget)
	defer cancel()
	_ = c.Collect(ctx)
}

// Collect returns a fresh host snapshot. The combined deadline is bounded by
// c.budget; individual collectors keep their own tighter timeouts so one slow
// source cannot stall the whole tick. Collect is not safe for concurrent use.
func (c *Collector) Collect(parent context.Context) Data {
	var (
		d  Data
		wg sync.WaitGroup
	)
	d.Timestamp = time.Now()
	d.Header = collectHeader()

	ctx, cancel := context.WithTimeout(parent, c.budget)
	defer cancel()

	wg.Add(8)
	go func() { defer wg.Done(); c.collectCPU(ctx, &d) }()
	go func() { defer wg.Done(); c.collectMem(ctx, &d) }()
	go func() { defer wg.Done(); c.collectGPU(ctx, &d) }()
	go func() { defer wg.Done(); c.collectDocker(ctx, &d) }()
	go func() { defer wg.Done(); c.collectServices(ctx, &d) }()
	go func() { defer wg.Done(); c.collectHermes(ctx, &d) }()
	go func() { defer wg.Done(); c.collectOpenCode(ctx, &d) }()
	go func() { defer wg.Done(); c.collectStorage(ctx, &d) }()
	wg.Wait()

	return d
}

// collectHeader reads quickly-derivable system identity. Failures here are
// non-fatal: fields become empty strings.
func collectHeader() Header {
	h := Header{OK: true, NumCPU: runtimeNumCPU()}
	if host, err := os.Hostname(); err == nil {
		h.Hostname = host
	}
	if up, err := readUptime(); err == nil {
		h.Uptime = up
	}
	if kern, err := readString("/proc/sys/kernel/osrelease"); err == nil {
		h.Kernel = kern
	}
	if h.Hostname == "" {
		h.OK = false
		h.Err = "unable to read hostname"
	}
	return h
}
