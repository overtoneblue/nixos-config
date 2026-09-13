package ui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"head-dash/internal/collect"
)

func fixtureData() collect.Data {
	timestamp := time.Date(2026, 9, 12, 21, 34, 56, 0, time.Local)
	models24h := []collect.UsageModel{
		{Name: "deepseek-v4-flash", Provider: "deepseek", APICalls: 41, InTokens: 2_850_000, CacheRead: 410_000, OutTokens: 360_000, Reasoning: 55_000, Cost: 0.62},
		{Name: "claude-sonnet-4", Provider: "anthropic", APICalls: 17, InTokens: 650_000, CacheRead: 100_000, OutTokens: 130_000, Reasoning: 15_000, Cost: 2.18},
		{Name: "gpt-5.6-terra", Provider: "openai", APICalls: 8, InTokens: 310_000, CacheRead: 80_000, OutTokens: 80_000, Reasoning: 20_000, Cost: 1.75},
		{Name: "qwen3-coder-480b", Provider: "openrouter", APICalls: 27, InTokens: 1_210_000, CacheRead: 190_000, OutTokens: 260_000, Cost: 0.89},
		{Name: "deepseek-ai/DeepSeek-V4-Flash", Provider: "opencode", APICalls: 63, InTokens: 3_900_000, CacheRead: 1_100_000, OutTokens: 420_000, Reasoning: 42_000, Cost: 0.78},
	}
	modelsMonth := []collect.UsageModel{
		{Name: "deepseek-v4-flash", Provider: "deepseek", APICalls: 125, InTokens: 8_400_000, CacheRead: 1_400_000, OutTokens: 1_100_000, Reasoning: 190_000, Cost: 1.84},
		{Name: "claude-sonnet-4", Provider: "anthropic", APICalls: 53, InTokens: 2_200_000, CacheRead: 350_000, OutTokens: 430_000, Reasoning: 52_000, Cost: 6.42},
		{Name: "gpt-5.6-terra", Provider: "openai", APICalls: 21, InTokens: 1_100_000, CacheRead: 250_000, OutTokens: 300_000, Reasoning: 67_000, Cost: 5.19},
		{Name: "qwen3-coder-480b", Provider: "openrouter", APICalls: 86, InTokens: 4_900_000, CacheRead: 780_000, OutTokens: 1_100_000, Reasoning: 75_000, Cost: 3.02},
		{Name: "deepseek-ai/DeepSeek-V4-Flash", Provider: "opencode", APICalls: 187, InTokens: 14_600_000, CacheRead: 3_500_000, OutTokens: 1_800_000, Reasoning: 260_000, Cost: 3.24},
	}

	return collect.Data{
		Timestamp: timestamp,
		Header: collect.Header{
			Hostname: "head",
			Uptime:   20*24*time.Hour + 23*time.Hour,
			Kernel:   "6.18.43",
			NumCPU:   8,
			OK:       true,
		},
		CPU: collect.CPU{
			OK:     true,
			Total:  37.4,
			NumCPU: 8,
			Cores: []collect.Core{
				{ID: 0, Pct: 31}, {ID: 1, Pct: 22}, {ID: 2, Pct: 58}, {ID: 3, Pct: 41},
				{ID: 4, Pct: 14}, {ID: 5, Pct: 46}, {ID: 6, Pct: 28}, {ID: 7, Pct: 61},
			},
			Top: []collect.Proc{
				{PID: 4128, Comm: "jellyfin", State: 'S', CPUPct: 28.4},
				{PID: 9652, Comm: "opencode", State: 'R', CPUPct: 16.7},
				{PID: 782, Comm: "hermes-agent", State: 'S', CPUPct: 8.2},
			},
		},
		Load: []float64{0.78, 0.64, 0.51},
		Mem:  collect.Mem{Total: 32 << 30, Used: 13 << 30, Available: 19 << 30, UsedPct: 40.625, OK: true},
		Swap: collect.Mem{Total: 8 << 30, Used: 1 << 30, Available: 7 << 30, UsedPct: 12.5, OK: true},
		GPUs: []collect.GPU{{
			Label: "Iris Xe (iGPU)", FreqCur: 1200, FreqMax: 1300, HasFreq: true,
			RenderBusy: 34, VideoBusy: 7, RC6Pct: 82, HasPower: true, GPUPowerW: 1.23,
			PkgPowerW: 7.81, Client: "jellyfin", ClientBusy: 21, HasClients: true, OK: true,
		}},
		Docker: collect.Docker{OK: true, Containers: []collect.Container{
			{Name: "jellyfin", Image: "jellyfin/jellyfin:unstable", State: "running", Status: "Up 20 days", CPU: 12.8, MemPct: 18.4, MemUsed: 1_580 << 20, MemLimit: 8 << 30, HasStats: true},
			{Name: "opencode", Image: "ghcr.io/anomalyco/opencode", State: "running", Status: "Up 6 days", CPU: 7.3, MemPct: 9.7, MemUsed: 796 << 20, MemLimit: 8 << 30, HasStats: true},
		}},
		Services: collect.Services{OK: true, List: []collect.Service{
			{Name: "hermes-agent", ActiveState: "active", SubState: "running"},
			{Name: "opencode", ActiveState: "active", SubState: "running"},
			{Name: "docker", ActiveState: "active", SubState: "running"},
			{Name: "docker-jellyfin", ActiveState: "active", SubState: "running"},
			{Name: "nginx", ActiveState: "active", SubState: "running"},
		}, FailedUnits: []string{}},
		Hermes:   collect.Hermes{Badge: "RUNNING", ActiveState: "active", SubState: "running", LastAct: time.Now(), HasAct: true},
		OpenCode: collect.OpenCode{Status: "up", HTTPStatus: 200, Latency: 18 * time.Millisecond, HasLatency: true, ServiceActive: true},
		Storage: []collect.Storage{
			{Label: "user", Path: "/mnt/user", Total: 12 << 40, Used: 8 << 40, Avail: 4 << 40, UsedPct: 66.7, Mounted: true},
			{Label: "cache", Path: "/mnt/cache", Total: 2 << 40, Used: 810 << 30, Avail: 1_238 << 30, UsedPct: 39.6, Mounted: true},
			{Label: "disk1", Path: "/mnt/disk1", Total: 8 << 40, Used: 5 << 40, Avail: 3 << 40, UsedPct: 62.5, Mounted: true},
			{Label: "disk2", Path: "/mnt/disk2", Total: 8 << 40, Used: 6 << 40, Avail: 2 << 40, UsedPct: 75, Mounted: true},
			{Label: "disk3", Path: "/mnt/disk3", Total: 8 << 40, Used: 7 << 40, Avail: 1 << 40, UsedPct: 87.5, Mounted: true},
		},
		Usage: collect.Usage{
			Fresh: timestamp,
			W24h: collect.UsageWindow{
				InTokens: 8_920_000, CacheRead: 1_880_000, OutTokens: 1_250_000, Reasoning: 132_000, APICalls: 156, Cost: 6.22,
				HermesCost: 5.44, OpenCodeCost: 0.78, HermesTokens: 5_850_000, OpenCodeTokens: 4_320_000,
				Models: models24h, HermesModels: models24h[:4], OpenCodeModels: models24h[4:],
				Bots: []collect.UsageBot{
					{Name: "main", OK: true, APICalls: 60, InTokens: 3_300_000, OutTokens: 620_000, Cost: 3.75, TopModels: []collect.UsageModel{models24h[0], models24h[1]}},
					{Name: "debbie", OK: true, APICalls: 33, InTokens: 1_720_000, OutTokens: 210_000, Cost: 1.69, TopModels: []collect.UsageModel{models24h[3], models24h[2]}},
				},
			},
			Month: collect.UsageWindow{
				InTokens: 31_200_000, CacheRead: 6_280_000, OutTokens: 4_730_000, Reasoning: 644_000, APICalls: 472, Cost: 19.71,
				HermesCost: 16.47, OpenCodeCost: 3.24, HermesTokens: 19_530_000, OpenCodeTokens: 16_400_000,
				Models: modelsMonth, HermesModels: modelsMonth[:4], OpenCodeModels: modelsMonth[4:],
				Bots: []collect.UsageBot{
					{Name: "main", OK: true, APICalls: 175, InTokens: 10_800_000, OutTokens: 1_900_000, Cost: 10.30, TopModels: []collect.UsageModel{modelsMonth[1], modelsMonth[0]}},
					{Name: "debbie", OK: true, APICalls: 110, InTokens: 5_800_000, OutTokens: 1_030_000, Cost: 6.17, TopModels: []collect.UsageModel{modelsMonth[3], modelsMonth[2]}},
				},
			},
			Daily: []collect.UsageDay{
				{Day: time.Date(2026, 9, 1, 0, 0, 0, 0, time.Local), In: 2_400_000, Out: 310_000, Cost: 1.42},
				{Day: time.Date(2026, 9, 4, 0, 0, 0, 0, time.Local), In: 5_100_000, Out: 780_000, Cost: 3.18},
				{Day: time.Date(2026, 9, 8, 0, 0, 0, 0, time.Local), In: 8_900_000, Out: 1_430_000, Cost: 5.66},
				{Day: time.Date(2026, 9, 12, 0, 0, 0, 0, time.Local), In: 14_800_000, Out: 2_210_000, Cost: 9.45},
			},
		},
	}
}

func TestRenderSystemGolden(t *testing.T) {
	got := renderFrame(NewTheme(true), 140, 50, fixtureData(), time.Second, false, pageSystem, win24h)
	assertGolden(t, "system.golden", got)
}

func TestRenderUsageGolden(t *testing.T) {
	for _, tc := range []struct {
		name   string
		window int
		golden string
	}{
		{name: "24h", window: win24h, golden: "usage-24h.golden"},
		{name: "month", window: winMonth, golden: "usage-month.golden"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := renderFrame(NewTheme(true), 140, 50, fixtureData(), time.Second, false, pageUsage, tc.window)
			for _, want := range []string{"by provider", "(fresh ", "+ cached ", "opencode"} {
				if !strings.Contains(got, want) {
					t.Fatalf("usage frame missing %q", want)
				}
			}
			assertGolden(t, tc.golden, got)
		})
	}
}

func assertGolden(t *testing.T, name, got string) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if os.Getenv("UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(want) != got {
		t.Fatalf("%s does not match golden; regenerate via UPDATE_GOLDEN=1 go test ./internal/ui -run TestRender AFTER reviewing the diff", path)
	}
}
