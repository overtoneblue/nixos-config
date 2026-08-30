package collect

import (
	"testing"
	"time"
)

func TestNewestHermesActivityIgnoresHousekeeping(t *testing.T) {
	log := "2026-08-29 23:27:37,152 real request\n" +
		"2026-08-29 23:28:37,152 hermes_cli.mem_trim memory trim: reason=messaging gateway housekeeping\n"
	want := time.Date(2026, 8, 29, 23, 27, 37, 152000000, time.Local)
	if got := newestHermesActivity(log); !got.Equal(want) {
		t.Fatalf("newestHermesActivity() = %v, want %v", got, want)
	}
}

func TestHermesHousekeepingFiltersGatewayChildren(t *testing.T) {
	for _, line := range []string{"pam_unix(sudo:session)", "sudo[42]: COMMAND=/bin/true", "gateway housekeeping"} {
		if !hermesHousekeeping(line) {
			t.Errorf("hermesHousekeeping(%q) = false", line)
		}
	}
}
