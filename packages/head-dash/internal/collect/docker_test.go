package collect

import (
	"math"
	"testing"

	"github.com/docker/docker/api/types/container"
)

func TestComputeContainerStats(t *testing.T) {
	t.Run("sample", func(t *testing.T) {
		var sample container.StatsResponse
		sample.CPUStats.CPUUsage.TotalUsage = 1_300
		sample.PreCPUStats.CPUUsage.TotalUsage = 1_000
		sample.CPUStats.SystemUsage = 12_000
		sample.PreCPUStats.SystemUsage = 10_000
		sample.CPUStats.OnlineCPUs = 4
		sample.MemoryStats.Usage = 512
		sample.MemoryStats.Limit = 2_048

		got := computeContainerStats(sample)
		if math.Abs(got.cpu-60) > 1e-9 {
			t.Errorf("cpu = %v, want 60", got.cpu)
		}
		if got.memUsed != 512 || got.memLimit != 2_048 {
			t.Errorf("memory = %d/%d, want 512/2048", got.memUsed, got.memLimit)
		}
		if math.Abs(got.memPct-25) > 1e-9 {
			t.Errorf("memory percent = %v, want 25", got.memPct)
		}
	})

	t.Run("zero deltas", func(t *testing.T) {
		var sample container.StatsResponse
		sample.CPUStats.CPUUsage.TotalUsage = 1_000
		sample.PreCPUStats.CPUUsage.TotalUsage = 1_000
		sample.CPUStats.SystemUsage = 10_000
		sample.PreCPUStats.SystemUsage = 10_000
		sample.CPUStats.OnlineCPUs = 4

		got := computeContainerStats(sample)
		if got.cpu != 0 {
			t.Errorf("cpu = %v, want 0", got.cpu)
		}
		if got.memPct != 0 || got.memUsed != 0 || got.memLimit != 0 {
			t.Errorf("memory = %+v, want zero values", got)
		}
	})
}
