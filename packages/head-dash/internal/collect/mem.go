package collect

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Mem describes physical or swap memory usage in bytes.
type Mem struct {
	Total     uint64
	Used      uint64
	Available uint64
	UsedPct   float64
	OK        bool
	Err       string
}

func (c *Collector) collectMem(ctx context.Context, d *Data) {
	select {
	case <-ctx.Done():
		d.Mem = Mem{OK: false, Err: "collect budget exceeded"}
		d.Swap = Mem{OK: false, Err: "collect budget exceeded"}
		return
	default:
	}
	mem, swap, err := readMeminfo(ctx)
	if err != nil {
		d.Mem = Mem{OK: false, Err: fmt.Sprintf("read /proc/meminfo: %v", err)}
		d.Swap = Mem{OK: false, Err: fmt.Sprintf("read /proc/meminfo: %v", err)}
		return
	}
	d.Mem = mem
	d.Swap = swap
}

func readMeminfo(ctx context.Context) (Mem, Mem, error) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return Mem{}, Mem{}, err
	}
	vals := map[string]uint64{}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		key := strings.TrimSuffix(fields[0], ":")
		if v, err := strconv.ParseUint(fields[1], 10, 64); err == nil {
			// Values are reported in kibibytes.
			vals[key] = v * 1024
		}
	}

	mem := Mem{}
	if total, ok := vals["MemTotal"]; ok {
		mem.Total = total
	}
	if avail, ok := vals["MemAvailable"]; ok {
		mem.Available = avail
	} else {
		mem.Available = vals["MemFree"] + vals["Buffers"] + vals["Cached"]
	}
	if mem.Total > 0 && mem.Available <= mem.Total {
		mem.Used = mem.Total - mem.Available
		mem.UsedPct = float64(mem.Used) / float64(mem.Total) * 100
	}
	mem.OK = mem.Total > 0

	swap := Mem{}
	if total, ok := vals["SwapTotal"]; ok {
		swap.Total = total
	}
	if free, ok := vals["SwapFree"]; ok {
		swap.Used = swap.Total - minU64(free, swap.Total)
	}
	if swap.Total > 0 {
		swap.UsedPct = float64(swap.Used) / float64(swap.Total) * 100
		swap.Available = swap.Total - swap.Used
		swap.OK = true
	} else {
		swap.OK = false
		swap.Err = "no swap configured"
	}
	return mem, swap, nil
}

func minU64(a, b uint64) uint64 {
	if a < b {
		return a
	}
	return b
}
