package collect

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// userHz is the fixed user-space clock tick rate Linux uses for task times in
// /proc/*/stat. It is 100 on virtually all kernels regardless of CONFIG_HZ.
const userHz = 100

// CPU reports aggregate + per-core utilisation and the top CPU consumers.
type CPU struct {
	OK     bool
	Err    string
	Total  float64
	Cores  []Core
	Load   [3]float64
	NumCPU int
	Top    []Proc
}

// Core is the utilisation of one logical CPU.
type Core struct {
	ID  int
	Pct float64
}

// Proc is one process' CPU usage (percentage of one core, top-style).
type Proc struct {
	PID    int
	Comm   string
	State  byte
	CPUPct float64
}

type coreSlice struct {
	total uint64
	idle  uint64
}

type procInfo struct {
	comm  string
	state byte
	ticks uint64
}

// cpuPrev is the previous /proc/stat + /proc/*/stat snapshot used for deltas.
type cpuPrev struct {
	have  bool
	at    time.Time
	total uint64
	idle  uint64
	cores []coreSlice
	proc  map[int]procInfo
}

type cpuSnapshot struct {
	at     time.Time
	total  uint64
	idle   uint64
	cores  []coreSlice
	proc   map[int]procInfo
}

func (c *Collector) collectCPU(ctx context.Context, d *Data) {
	select {
	case <-ctx.Done():
		d.CPU = CPU{OK: false, Err: "collect budget exceeded", NumCPU: runtimeNumCPU()}
		return
	default:
	}

	cur, err := readCPU(ctx)
	if err != nil {
		d.CPU = CPU{OK: false, Err: fmt.Sprintf("read /proc/stat: %v", err), NumCPU: runtimeNumCPU()}
		return
	}

	cpu := CPU{OK: true, NumCPU: len(cur.cores), Top: []Proc{}}
	if cpu.NumCPU == 0 {
		cpu.NumCPU = runtimeNumCPU()
	}

	if prev := c.prevCPU; prev.have {
		elapsed := cur.at.Sub(prev.at).Seconds()
		dTotal := cur.total - prev.total
		dIdle := cur.idle - prev.idle
		if dTotal > 0 {
			cpu.Total = float64(dTotal-dIdle) / float64(dTotal) * 100
		}
		n := min(len(cur.cores), len(prev.cores))
		for i := 0; i < n; i++ {
			dt := cur.cores[i].total - prev.cores[i].total
			di := cur.cores[i].idle - prev.cores[i].idle
			pct := 0.0
			if dt > 0 {
				pct = float64(dt-di) / float64(dt) * 100
			}
			cpu.Cores = append(cpu.Cores, Core{ID: i, Pct: pct})
		}

		// Top processes by per-core CPU% between ticks.
		if elapsed > 0 {
			for pid, pc := range cur.proc {
				pp, ok := prev.proc[pid]
				if !ok {
					continue
				}
				delta := pc.ticks - pp.ticks
				pct := float64(delta) / (userHz * elapsed) * 100
				cpu.Top = append(cpu.Top, Proc{PID: pid, Comm: pc.comm, State: pc.state, CPUPct: pct})
			}
			sort.Slice(cpu.Top, func(i, j int) bool {
				if cpu.Top[i].CPUPct == cpu.Top[j].CPUPct {
					return cpu.Top[i].Comm < cpu.Top[j].Comm
				}
				return cpu.Top[i].CPUPct > cpu.Top[j].CPUPct
			})
			if len(cpu.Top) > 5 {
				cpu.Top = cpu.Top[:5]
			}
		}
	}

	load, err := readLoadavg()
	if err != nil {
		cpu.OK = false
		cpu.Err = fmt.Sprintf("read /proc/loadavg: %v", err)
		cpu.Load = [3]float64{}
	} else {
		cpu.Load = load
	}

	d.CPU = cpu
	d.Load = cpu.Load[:]
	c.prevCPU = cpuPrev{have: true, at: cur.at, total: cur.total, idle: cur.idle, cores: cur.cores, proc: cur.proc}
}

func readCPU(ctx context.Context) (cpuSnapshot, error) {
	out := cpuSnapshot{at: time.Now(), proc: map[int]procInfo{}}

	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return out, err
	}
	var agg coreSlice
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.HasPrefix(line, "cpu") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}
		t := parseUintFields(fields[1:])
		total := t[0] + t[1] + t[2] + t[3] + t[4]
		if len(t) > 7 {
			total += t[5] + t[6] + t[7]
		}
		idle := t[3] + t[4]
		if fields[0] == "cpu" {
			agg = coreSlice{total: total, idle: idle}
		} else {
			out.cores = append(out.cores, coreSlice{total: total, idle: idle})
		}
	}
	out.total = agg.total
	out.idle = agg.idle

	// Per-process ticks, best-effort (processes vanish as we scan).
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return out, nil
	}
	for _, e := range entries {
		select {
		case <-ctx.Done():
			return out, ctx.Err()
		default:
		}
		if !e.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		if info, ok := readProcStat(pid); ok {
			out.proc[pid] = info
		}
	}
	return out, nil
}

func readProcStat(pid int) (procInfo, bool) {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return procInfo{}, false
	}
	line := string(b)
	// comm may contain spaces/parens; tokenise from the last ')'.
	last := strings.LastIndexByte(line, ')')
	if last < 0 || last+2 > len(line) {
		return procInfo{}, false
	}
	comm := ""
	if open := strings.IndexByte(line, '('); open >= 0 {
		comm = line[open+1 : last]
	}
	fields := strings.Fields(line[last+2:])
	if len(fields) < 13 {
		return procInfo{}, false
	}
	utime, err1 := strconv.ParseUint(fields[11], 10, 64)
	stime, err2 := strconv.ParseUint(fields[12], 10, 64)
	if err1 != nil || err2 != nil {
		return procInfo{}, false
	}
	return procInfo{comm: comm, state: fields[0][0], ticks: utime + stime}, true
}

// parseUintFields converts a slice of numeric strings to uint64 values.
func parseUintFields(fields []string) []uint64 {
	out := make([]uint64, len(fields))
	for i, f := range fields {
		v, err := strconv.ParseUint(f, 10, 64)
		if err != nil {
			v = 0
		}
		out[i] = v
	}
	return out
}

func readLoadavg() ([3]float64, error) {
	s, err := readString("/proc/loadavg")
	if err != nil {
		return [3]float64{}, err
	}
	fields := strings.Fields(s)
	if len(fields) < 3 {
		return [3]float64{}, os.ErrNotExist
	}
	var out [3]float64
	for i := 0; i < 3; i++ {
		v, err := strconv.ParseFloat(fields[i], 64)
		if err != nil {
			return [3]float64{}, err
		}
		out[i] = v
	}
	return out, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
