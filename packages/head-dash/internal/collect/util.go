package collect

import (
	"bufio"
	"bytes"
	"context"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// readString returns the trimmed contents of a file, or an error.
func readString(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

// readFirstUint parses the first whitespace-separated token of a file as an
// unsigned integer.
func readFirstUint(path string) (uint64, error) {
	s, err := readString(path)
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return 0, os.ErrNotExist
	}
	return strconv.ParseUint(fields[0], 10, 64)
}

// readUptime reads /proc/uptime (seconds, fractional).
func readUptime() (time.Duration, error) {
	s, err := readString("/proc/uptime")
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return 0, os.ErrNotExist
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, err
	}
	return time.Duration(secs * float64(time.Second)), nil
}

func runtimeNumCPU() int {
	if n := runtime.NumCPU(); n > 0 {
		return n
	}
	return 1
}

// runCmd executes a command with a per-call timeout, returning its combined
// stdout. It is used for the handful of genuinely external reads (systemd
// state, journalctl, intel_gpu_top) that have no cheap sysfs equivalent. The
// returned error distinguishes "timed out" so callers can render the right
// hint.
func runCmd(ctx context.Context, timeout time.Duration, name string, args ...string) (string, error) {
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	prog, err := exec.LookPath(name)
	if err != nil {
		return "", err
	}
	cmd := exec.CommandContext(cmdCtx, prog, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		if cmdCtx.Err() == context.DeadlineExceeded {
			return out.String(), context.DeadlineExceeded
		}
		return out.String(), err
	}
	return out.String(), nil
}

// countLines returns the number of non-empty lines in s.
func countLines(s string) int {
	c := 0
	sc := bufio.NewScanner(strings.NewReader(s))
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) != "" {
			c++
		}
	}
	return c
}
