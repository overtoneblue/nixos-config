package collect

import "testing"

func TestMergeModels(t *testing.T) {
	got := mergeModels([]UsageModel{
		{
			Name:      "DeepSeek-V4-Flash",
			Provider:  "deepseek",
			APICalls:  318,
			InTokens:  1200,
			OutTokens: 300,
			CacheRead: 40,
			Reasoning: 20,
			Cost:      1.25,
		},
		{
			Name:      "deepseek-v4-flash",
			Provider:  "deepseek",
			APICalls:  148,
			InTokens:  800,
			OutTokens: 200,
			CacheRead: 60,
			Reasoning: 30,
			Cost:      2.5,
			RateNA:    true,
		},
		{
			Name:      "DeepSeek-V4-Flash",
			Provider:  "other",
			APICalls:  7,
			InTokens:  11,
			OutTokens: 13,
			CacheRead: 17,
			Reasoning: 19,
			Cost:      23.5,
		},
	})

	want := []UsageModel{
		{
			Name:      "DeepSeek-V4-Flash",
			Provider:  "deepseek",
			APICalls:  466,
			InTokens:  2000,
			OutTokens: 500,
			CacheRead: 100,
			Reasoning: 50,
			Cost:      3.75,
			RateNA:    true,
		},
		{
			Name:      "DeepSeek-V4-Flash",
			Provider:  "other",
			APICalls:  7,
			InTokens:  11,
			OutTokens: 13,
			CacheRead: 17,
			Reasoning: 19,
			Cost:      23.5,
		},
	}
	if len(got) != len(want) {
		t.Fatalf("mergeModels() returned %d models, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("mergeModels()[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
}
