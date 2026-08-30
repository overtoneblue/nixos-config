// Package collect gathers host telemetry for the head dashboard. Collectors run
// on their own cadences in background goroutines and publish into a mutex
// guarded cache that the UI reads on every render; a synchronous all-at-once
// Collect path is retained for --once / CI verification.
package collect

import (
	"context"
	"os"
	"sync"
	"time"
)

// fastCadenceMin bounds how quickly the cheap /proc-backed collectors
// (cpu/mem/gpu) refresh. It matches the minimum allowed UI interval.
const fastCadenceMin = 50 * time.Millisecond

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
// lazily-created Docker client, agent hysteresis) and a shared cache that
// background streams keep fresh. Snapshot() returns the latest frame.
type Collector struct {
	budget   time.Duration
	docker   dockerHolder
	prevCPU  cpuPrev
	hermesSt hermesState
	ocSt     opencodeState

	cache    cache
	fast     time.Duration
	fastLock sync.RWMutex
	started  sync.Once
}

// cache is the mutex-guarded store shared between background collectors and
// the UI's snapshot reads.
type cache struct {
	mu sync.RWMutex
	d  Data
}

// NewCollector returns a Collector with the given collect budget. A non-positive
// budget falls back to 6s — generous enough for the slowest collector (Docker
// stats of many containers) while still bounding the tick.
func NewCollector(budget time.Duration) *Collector {
	if budget <= 0 {
		budget = 6 * time.Second
	}
	return &Collector{budget: budget, fast: 200 * time.Millisecond}
}

// Warmup establishes baselines (CPU/proc deltas, Docker client + ping) so the
// very first rendered frame already carries meaningful deltas. It is safe and
// cheap; call once before the first Collect or Start.
func (c *Collector) Warmup(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, c.budget)
	defer cancel()
	_ = c.Collect(ctx)
}

// Collect returns a fresh host snapshot via a single synchronous read of every
// source. It is kept for --once / verification and doubles as the baseline
// pass for the streaming path. Collect is not safe for concurrent use.
func (c *Collector) Collect(parent context.Context) Data {
	var d Data
	c.collectAll(parent, &d)
	return d
}

// Snapshot returns the latest cached frame. It never blocks on any collector;
// only a short cache lock separates the caller from the background streams.
func (c *Collector) Snapshot() Data {
	c.cache.mu.RLock()
	d := c.cache.d
	d.Timestamp = time.Now()
	c.cache.mu.RUnlock()
	return d
}

// SetFastCadence updates how often the cheap /proc-backed collectors
// (cpu/mem/gpu) run. The UI drives this so those panels stay in lock-step with
// the render tick.
func (c *Collector) SetFastCadence(d time.Duration) {
	if d < fastCadenceMin {
		d = fastCadenceMin
	}
	c.fastLock.Lock()
	c.fast = d
	c.fastLock.Unlock()
}

func (c *Collector) fastCadence() time.Duration {
	c.fastLock.RLock()
	defer c.fastLock.RUnlock()
	d := c.fast
	if d < fastCadenceMin {
		return fastCadenceMin
	}
	return d
}

// Start launches the per-source background streams and primes the cache with
// one full synchronous snapshot so the first rendered frame is already
// populated. Cadences: cpu/mem/gpu follow the UI tick; docker + agents every
// 1s; storage every 2s. The GPU itself is already a background stream.
func (c *Collector) Start(ctx context.Context) {
	c.started.Do(func() {
		c.cache.mu.Lock()
		c.collectAll(ctx, &c.cache.d)
		c.cache.mu.Unlock()

		c.spawn(ctx, c.fastCadence, func(ctx context.Context) {
			c.cache.mu.Lock()
			defer c.cache.mu.Unlock()
			ctx2, cancel := context.WithTimeout(ctx, c.budget)
			defer cancel()
			dc := &c.cache.d
			c.collectCPU(ctx2, dc)
			c.collectMem(ctx2, dc)
			c.collectGPU(ctx2, dc)
		})
		c.spawn(ctx, func() time.Duration { return time.Second }, func(ctx context.Context) {
			c.cache.mu.Lock()
			defer c.cache.mu.Unlock()
			ctx2, cancel := context.WithTimeout(ctx, c.budget)
			defer cancel()
			c.collectDocker(ctx2, &c.cache.d)
		})
		c.spawn(ctx, func() time.Duration { return time.Second }, func(ctx context.Context) {
			c.cache.mu.Lock()
			defer c.cache.mu.Unlock()
			ctx2, cancel := context.WithTimeout(ctx, c.budget)
			defer cancel()
			dc := &c.cache.d
			c.collectHermes(ctx2, dc)
			c.collectOpenCode(ctx2, dc)
		})
		c.spawn(ctx, func() time.Duration { return 2 * time.Second }, func(ctx context.Context) {
			c.cache.mu.Lock()
			defer c.cache.mu.Unlock()
			ctx2, cancel := context.WithTimeout(ctx, c.budget)
			defer cancel()
			c.collectStorage(ctx2, &c.cache.d)
		})
	})
}

// spawn runs fn every cadence() in its own goroutine until ctx is done.
func (c *Collector) spawn(ctx context.Context, cadence func() time.Duration, fn func(context.Context)) {
	go func() {
		for {
			d := cadence()
			select {
			case <-ctx.Done():
				return
			case <-time.After(d):
				fn(ctx)
			}
		}
	}()
}

// collectAll is the synchronous full snapshot on which Collect and the
// streaming prime pass are built.
func (c *Collector) collectAll(parent context.Context, d *Data) {
	d.Timestamp = time.Now()
	d.Header = collectHeader()

	ctx, cancel := context.WithTimeout(parent, c.budget)
	defer cancel()

	var wg sync.WaitGroup
	wg.Add(8)
	go func() { defer wg.Done(); c.collectCPU(ctx, d) }()
	go func() { defer wg.Done(); c.collectMem(ctx, d) }()
	go func() { defer wg.Done(); c.collectGPU(ctx, d) }()
	go func() { defer wg.Done(); c.collectDocker(ctx, d) }()
	go func() { defer wg.Done(); c.collectServices(ctx, d) }()
	go func() { defer wg.Done(); c.collectHermes(ctx, d) }()
	go func() { defer wg.Done(); c.collectOpenCode(ctx, d) }()
	go func() { defer wg.Done(); c.collectStorage(ctx, d) }()
	wg.Wait()
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
