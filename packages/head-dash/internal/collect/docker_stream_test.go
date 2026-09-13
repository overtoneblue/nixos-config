package collect

import (
	"context"
	"sync"
	"testing"
)

func TestDockerStreamStoreRead(t *testing.T) {
	c := &Collector{}
	c.dockerStream.stats = make(map[string]containerStats)
	c.dockerStream.have = make(map[string]bool)
	c.dockerStream.streams = map[string]context.CancelFunc{
		"present":   func() {},
		"cancelled": func() {},
	}

	sample := containerStats{cpu: 12.5, memPct: 34.2, memUsed: 512, memLimit: 2_048}
	c.storeContainerStats(context.Background(), "present", sample)
	if got, ok := c.latestContainerStats("present"); !ok || got != sample {
		t.Fatalf("latest present = (%+v, %v), want (%+v, true)", got, ok, sample)
	}

	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	c.storeContainerStats(cancelled, "cancelled", sample)
	if got, ok := c.latestContainerStats("cancelled"); ok {
		t.Fatalf("latest cancelled = (%+v, %v), want no sample", got, ok)
	}

	c.storeContainerStats(context.Background(), "absent", sample)
	if got, ok := c.latestContainerStats("absent"); ok {
		t.Fatalf("latest absent = (%+v, %v), want no sample", got, ok)
	}
}

func TestDockerStreamConcurrent(t *testing.T) {
	c := &Collector{}
	c.dockerStream.stats = make(map[string]containerStats)
	c.dockerStream.have = make(map[string]bool)
	ids := []string{"one", "two", "three", "four"}
	c.dockerStream.streams = make(map[string]context.CancelFunc, len(ids))
	for _, id := range ids {
		c.dockerStream.streams[id] = func() {}
	}

	const (
		workers    = 10
		iterations = 500
	)
	var wg sync.WaitGroup
	for worker := 0; worker < workers; worker++ {
		wg.Add(1)
		go func(worker int) {
			defer wg.Done()
			for i := 0; i < iterations; i++ {
				id := ids[(worker+i)%len(ids)]
				c.storeContainerStats(context.Background(), id, containerStats{
					cpu: float64(worker*iterations + i), memPct: float64(i % 100), memUsed: uint64(i), memLimit: 1_024,
				})
				_, _ = c.latestContainerStats(ids[(worker+i+1)%len(ids)])
			}
		}(worker)
	}
	wg.Wait()

	for _, id := range ids {
		if _, ok := c.latestContainerStats(id); !ok {
			t.Fatalf("latest %q has no stored sample", id)
		}
	}
}
