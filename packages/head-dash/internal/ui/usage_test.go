package ui

import (
	"reflect"
	"testing"

	"head-dash/internal/collect"
)

func TestProviderTotalsGroupsAndSortsByCost(t *testing.T) {
	got := providerTotals([]collect.UsageModel{
		{Provider: "anthropic", APICalls: 2, InTokens: 100, CacheRead: 20, OutTokens: 30, Cost: 1.25},
		{Provider: "openai", APICalls: 7, InTokens: 400, CacheRead: 50, OutTokens: 60, Cost: 4},
		{Provider: "anthropic", APICalls: 3, InTokens: 200, CacheRead: 40, OutTokens: 50, Cost: 0.75},
	})
	want := []providerTotal{
		{Provider: "openai", APICalls: 7, InTokens: 400, CacheRead: 50, OutTokens: 60, Cost: 4},
		{Provider: "anthropic", APICalls: 5, InTokens: 300, CacheRead: 60, OutTokens: 80, Cost: 2},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("providerTotals() = %#v, want %#v", got, want)
	}
}
