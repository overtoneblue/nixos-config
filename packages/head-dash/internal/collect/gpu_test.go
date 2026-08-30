package collect

import (
	"encoding/json"
	"strings"
	"testing"
)

// gpuFixture mirrors the verified intel_gpu_top -J object from the host.
const gpuFixture = `{"period":{"duration":8.76,"unit":"ms"},"frequency":{"requested":0,"actual":0,"unit":"MHz"},"interrupts":{"count":0,"unit":"irq/s"},"rc6":{"value":99.98,"unit":"%"},"power":{"GPU":0.014,"Package":3.44,"unit":"W"},"engines":{"Render/3D":{"busy":0,"sema":0,"wait":0,"unit":"%"},"Blitter":{"busy":0,"sema":0,"wait":0,"unit":"%"},"Video":{"busy":0,"sema":0,"wait":0,"unit":"%"},"VideoEnhance":{"busy":0,"sema":0,"wait":0,"unit":"%"}},"clients":{}}`

func TestParseIGPUSample(t *testing.T) {
	var s igpuSample
	if err := json.NewDecoder(strings.NewReader(gpuFixture)).Decode(&s); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
	if s.RC6.Value != 99.98 {
		t.Errorf("rc6 = %v, want 99.98", s.RC6.Value)
	}
	if s.Power.GPU != 0.014 || s.Power.Package != 3.44 {
		t.Errorf("power = gpu %v pkg %v", s.Power.GPU, s.Power.Package)
	}
	if got := enginePct(s, "Render/3D"); got != 0 {
		t.Errorf("render busy = %d, want 0", got)
	}
	if got := enginePct(s, "Video"); got != 0 {
		t.Errorf("video busy = %d, want 0", got)
	}
	if _, _, ok := busiestClient(s); ok {
		t.Error("busiestClient found a client with empty clients map")
	}
}

func TestBusiestClient(t *testing.T) {
	fixture := `{"engines":{},"clients":{"a":{"name":"ffmpeg","engines":{"Render/3D":{"busy":42.5}}},"b":{"name":"wanting","engines":{"Video":{"busy":88}}}}}`
	var s igpuSample
	if err := json.NewDecoder(strings.NewReader(fixture)).Decode(&s); err != nil {
		t.Fatalf("decode: %v", err)
	}
	name, busy, ok := busiestClient(s)
	if !ok {
		t.Fatal("expected a busiest client")
	}
	if name != "wanting" || busy != 88 {
		t.Errorf("busiest client = %q %d%%, want wanting 88%%", name, busy)
	}
}
