package collect

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	// Embed tzdata so time.LoadLocation works regardless of the runtime
	// environment's zoneinfo (usage day-buckets pin to head's local time).
	_ "time/tzdata"
)

// Usage aggregates token spend across the Hermes profiles (main agent + bot
// profiles) and the OpenCode delegation backend, for the two dashboard
// windows: a rolling 24h window and the current calendar month. Both windows
// are computed in every collect pass so switching between them in the UI is
// instant. All queries shell out to the sqlite3 CLI in -readonly -json mode —
// deliberately no Go SQLite driver dependency (see README).
type Usage struct {
	Fresh time.Time
	Errs  []string // per-source degradation notes; empty when everything read

	// OpenCodeErr is set when the opencode DB was unreadable this pass; the
	// UI renders it in the opencode sections instead of fake zero rows.
	OpenCodeErr string

	W24h  UsageWindow
	Month UsageWindow
	Daily []UsageDay // per-day points for the current month, head-local time
}

// UsageWindow is one aggregated view (24h rolling or calendar month).
type UsageWindow struct {
	InTokens   int64
	OutTokens  int64
	CacheRead  int64
	Reasoning  int64
	APICalls  int64
	Cost       float64 // recorded actuals + hermes estimates + computed opencode costs
	CostRateNA bool    // some opencode tokens had no published rate; their cost is omitted

	HermesCost     float64
	OpenCodeCost   float64
	HermesTokens   int64
	OpenCodeTokens int64

	Bots   []UsageBot
	Models []UsageModel // combined hermes + opencode

	HermesModels   []UsageModel
	OpenCodeModels []UsageModel
}

// UsageBot is one Hermes profile's spend in a window.
type UsageBot struct {
	Name     string
	OK       bool
	Err      string
	APICalls int64
	InTokens int64
	OutTokens int64
	Cost     float64
	TopModels []UsageModel // top models by in+out volume, for a compact mix line
}

// UsageModel is one model×provider aggregation.
type UsageModel struct {
	Name       string
	Provider   string
	APICalls   int64
	InTokens   int64
	OutTokens  int64
	CacheRead  int64
	Reasoning  int64
	Cost       float64
	RateNA     bool
}

// UsageDay is one head-local calendar day of the current month.
type UsageDay struct {
	Day  time.Time
	In   int64
	Out  int64
	Cost float64
}

// hermesDBRoot is where the Hermes agent keeps its per-profile databases.
const hermesDBRoot = "/mnt/cache/appdata/hermes-agent/.hermes"

// opencodePricePerM maps opencode model IDs to official-docs snapshot rates
// (USD per 1M tokens): [input, output, cache-read]. Sources mirror the Hermes
// agent's own usage_pricing snapshot (deepseek-pricing-2026-07,
// openai-gpt-5.6-2026-07), so both surfaces deduct with the same constants.
// Models without a published rate (e.g. custom NVFP4 endpoints) are absent —
// their tokens stay exact while their cost is reported as rate-n/a.
var opencodePricePerM = map[string][3]float64{
	"deepseek-v4-flash": {0.14, 0.28, 0.0028},
	"deepseek-v4-pro":   {0.435, 0.87, 0.003625},
	"gpt-5.6-terra":     {2.50, 15.00, 0.25},
	"gpt-5.6-sol":       {5.00, 30.00, 0.50},
	"gpt-5.6-luna":      {1.00, 6.00, 0.10},
}

// opencodeMatchRate finds the snapshot entry matching an opencode modelID
// ("deepseek-ai/DeepSeek-V4-Flash" → deepseek-v4-flash rates).
func opencodeMatchRate(modelID string) ([3]float64, bool) {
	l := strings.ToLower(modelID)
	for frag, rates := range opencodePricePerM {
		if strings.Contains(l, frag) {
			return rates, true
		}
	}
	return [3]float64{}, false
}

// collectUsage gathers both windows and the month's daily buckets. It
// populates d.Usage and is safe at any cadence.
func (c *Collector) collectUsage(ctx context.Context, d *Data) {
	u := Usage{Fresh: time.Now()}

	loc := headLocation()
	now := time.Now().In(loc)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	dayStart := now.Add(-24 * time.Hour)

	// Hermes profiles: main DB + one per bot profile, auto-discovered.
	dbs := []struct{ name, path string }{
		{"main", filepath.Join(hermesDBRoot, "state.db")},
	}
	profiles, _ := filepath.Glob(filepath.Join(hermesDBRoot, "profiles", "*", "state.db"))
	for _, p := range profiles {
		dbs = append(dbs, struct{ name, path string }{filepath.Base(filepath.Dir(p)), p})
	}

	for _, db := range dbs {
		collectHermesUsage(ctx, db.name, db.path, &u, loc, now, monthStart, dayStart)
	}
	collectOpenCodeUsage(ctx, &u, loc, now, monthStart, dayStart)

	// Merge same-day entries (hermes appends per-day aggregates, opencode
	// per-message) so each calendar day is exactly one sparkline point.
	byDay := map[string]UsageDay{}
	for _, e := range u.Daily {
		k := e.Day.Format("2006-01-02")
		agg := byDay[k]
		if agg.Day.IsZero() {
			agg.Day = e.Day
		}
		agg.In += e.In
		agg.Out += e.Out
		agg.Cost += e.Cost
		byDay[k] = agg
	}
	u.Daily = u.Daily[:0]
	for _, e := range byDay {
		u.Daily = append(u.Daily, e)
	}

	sort.Slice(u.W24h.Models, func(i, j int) bool { return u.W24h.Models[i].Cost > u.W24h.Models[j].Cost })
	sort.Slice(u.Month.Models, func(i, j int) bool { return u.Month.Models[i].Cost > u.Month.Models[j].Cost })
	sort.Slice(u.W24h.HermesModels, func(i, j int) bool { return u.W24h.HermesModels[i].Cost > u.W24h.HermesModels[j].Cost })
	sort.Slice(u.Month.HermesModels, func(i, j int) bool { return u.Month.HermesModels[i].Cost > u.Month.HermesModels[j].Cost })
	sort.Slice(u.W24h.OpenCodeModels, func(i, j int) bool { return u.W24h.OpenCodeModels[i].Cost > u.W24h.OpenCodeModels[j].Cost })
	sort.Slice(u.Month.OpenCodeModels, func(i, j int) bool { return u.Month.OpenCodeModels[i].Cost > u.Month.OpenCodeModels[j].Cost })
	for i := range u.W24h.Bots {
		sortBotsModels(u.W24h.Bots[i].TopModels)
	}
	for i := range u.Month.Bots {
		sortBotsModels(u.Month.Bots[i].TopModels)
	}
	sort.Slice(u.Daily, func(i, j int) bool { return u.Daily[i].Day.Before(u.Daily[j].Day) })

	d.Usage = u
}

func sortBotsModels(ms []UsageModel) {
	sort.Slice(ms, func(i, j int) bool { return ms[i].InTokens+ms[i].OutTokens > ms[j].InTokens+ms[j].OutTokens })
}

// collectHermesUsage reads one Hermes state.db. Unreadable databases
// degrade: the bot row appears with OK=false and a note is appended.
func collectHermesUsage(ctx context.Context, name, path string, u *Usage, loc *time.Location, now, monthStart, dayStart time.Time) {
	fail := func(err string) {
		u.Errs = append(u.Errs, name+": "+err)
		u.W24h.Bots = append(u.W24h.Bots, UsageBot{Name: name, Err: err})
		u.Month.Bots = append(u.Month.Bots, UsageBot{Name: name, Err: err})
	}

	rows, err := queryJSON(ctx, path, `SELECT session_id, model, billing_provider, api_call_count, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, estimated_cost_usd, actual_cost_usd, first_seen, last_seen FROM session_model_usage`)
	if err != nil {
		fail("db unreadable (" + shortErr(err) + ")")
		return
	}

	// Per-session message timestamps weight multi-day sessions onto days and
	// window fractions. One extra query per DB; a few thousand rows max.
	msgRows, _ := queryJSON(ctx, path, `SELECT session_id, timestamp FROM messages`)
	msgTimes := map[string][]float64{}
	for _, m := range msgRows {
		sid, _ := m["session_id"].(string)
		if ts, ok := num(m["timestamp"]); ok {
			msgTimes[sid] = append(msgTimes[sid], ts)
		}
	}

	bot24 := UsageBot{Name: name, OK: true}
	botM := UsageBot{Name: name, OK: true}
	models24 := map[string]*UsageModel{}
	modelsM := map[string]*UsageModel{}
	daily := map[string]*UsageDay{}

	addModel := func(set map[string]*UsageModel, model, prov string, frac float64, r usageRow) {
		key := strings.ToLower(model) + "\x00" + prov
		m := set[key]
		if m == nil {
			m = &UsageModel{Name: model, Provider: prov}
			set[key] = m
		}
		m.APICalls += int64(float64(r.APICalls) * frac)
		m.InTokens += int64(float64(r.InTokens) * frac)
		m.OutTokens += int64(float64(r.OutTokens) * frac)
		m.CacheRead += int64(float64(r.CacheRead) * frac)
		m.Reasoning += int64(float64(r.Reasoning) * frac)
		cost := r.EstCost
		if r.ActCost > 0 {
			cost = r.ActCost
		}
		m.Cost += cost * frac
	}

	for _, row := range rows {
		r, ok := parseUsageRow(row)
		if !ok {
			continue
		}

		times := msgTimes[r.SessionID]
		// Window fractions: share of the session's messages inside each
		// window. Sessions without messages fall back to a time-overlap
		// heuristic on first_seen..last_seen.
		f24, fM := windowFractions(times, r.FirstSeen, r.LastSeen, float64(dayStart.Unix()), float64(monthStart.Unix()), float64(now.Unix()))

		for _, f := range []struct {
			frac float64
			w    *UsageWindow
			bot  *UsageBot
			set  map[string]*UsageModel
		}{
			{f24, &u.W24h, &bot24, models24},
			{fM, &u.Month, &botM, modelsM},
		} {
			if f.frac <= 0 {
				continue
			}
			f.w.InTokens += int64(float64(r.InTokens) * f.frac)
			f.w.OutTokens += int64(float64(r.OutTokens) * f.frac)
			f.w.CacheRead += int64(float64(r.CacheRead) * f.frac)
			f.w.Reasoning += int64(float64(r.Reasoning) * f.frac)
			f.w.APICalls += int64(float64(r.APICalls) * f.frac)
			cost := r.EstCost
			if r.ActCost > 0 {
				cost = r.ActCost
			}
			f.w.Cost += cost * f.frac
			f.w.HermesCost += cost * f.frac
			f.w.HermesTokens += int64(float64(r.InTokens+r.OutTokens) * f.frac)

			f.bot.APICalls += int64(float64(r.APICalls) * f.frac)
			f.bot.InTokens += int64(float64(r.InTokens) * f.frac)
			f.bot.OutTokens += int64(float64(r.OutTokens) * f.frac)
			f.bot.Cost += cost * f.frac

			addModel(f.set, r.Model, r.Provider, f.frac, r)
		}

		// Daily buckets for the month sparkline: same per-day message shares.
		dayShares := dayFractions(times, r.FirstSeen, r.LastSeen, float64(monthStart.Unix()), float64(now.Unix()), loc)
		for dayKey, share := range dayShares {
			if share <= 0 {
				continue
			}
			pd := daily[dayKey]
			if pd == nil {
				t, _ := time.ParseInLocation("2006-01-02", dayKey, loc)
				pd = &UsageDay{Day: t}
				daily[dayKey] = pd
			}
			pd.In += int64(float64(r.InTokens) * share)
			pd.Out += int64(float64(r.OutTokens) * share)
			cost := r.EstCost
			if r.ActCost > 0 {
				cost = r.ActCost
			}
			pd.Cost += cost * share
		}
	}

	for _, pair := range []struct {
		bot  *UsageBot
		set  map[string]*UsageModel
		w    *UsageWindow
	}{{&bot24, models24, &u.W24h}, {&botM, modelsM, &u.Month}} {
		for _, m := range pair.set {
			pair.w.Models = append(pair.w.Models, *m)
			pair.w.HermesModels = append(pair.w.HermesModels, *m)
			pair.bot.TopModels = append(pair.bot.TopModels, *m)
		}
		pair.w.Bots = append(pair.w.Bots, *pair.bot)
	}

	for _, pd := range daily {
		u.Daily = append(u.Daily, *pd)
	}
}

// collectOpenCodeUsage reads the OpenCode backend's per-message token JSON.
// The data dir is owner-only by design; hermes-user runs degrade honestly.
func collectOpenCodeUsage(ctx context.Context, u *Usage, loc *time.Location, now, monthStart, dayStart time.Time) {
	rows, err := queryJSON(ctx, opencodeDBPath,
		`SELECT json_extract(data,'$.modelID') AS model, json_extract(data,'$.tokens.input') AS tin, json_extract(data,'$.tokens.output') AS tout, json_extract(data,'$.tokens.reasoning') AS treason, json_extract(data,'$.tokens.cache.read') AS tread, json_extract(data,'$.cost') AS cost, time_created FROM message WHERE json_extract(data,'$.role')='assistant'`)
	if err != nil {
		note := "opencode db unreadable (" + shortErr(err) + ")"
		u.Errs = append(u.Errs, note+" — hermes runs see this by design")
		u.OpenCodeErr = note
		u.W24h.CostRateNA = true
		u.Month.CostRateNA = true
		return
	}

	models24 := map[string]*UsageModel{}
	modelsM := map[string]*UsageModel{}

	for _, row := range rows {
		model, _ := row["model"].(string)
		if model == "" {
			model = "unknown"
		}
		tin, _ := num(row["tin"])
		tout, _ := num(row["tout"])
		treason, _ := num(row["treason"])
		tread, _ := num(row["tread"])
		cost, _ := num(row["cost"])
		tms, ok := num(row["time_created"])
		if !ok {
			continue
		}
		ts := tms / 1000 // opencode stores ms

		rate, hasRate := opencodeMatchRate(model)
		msgCost := cost // recorded actual wins
		if !(cost > 0) && hasRate {
			msgCost = (tin/1e6)*rate[0] + (tout/1e6)*rate[1] + (tread/1e6)*rate[2]
		}
		computableCost := msgCost
		if !(cost > 0) && !hasRate {
			computableCost = 0
			// tokens stay counted; cost flagged as rate n/a below.
		}

		for _, f := range []struct {
			in    bool
			w     *UsageWindow
			set   map[string]*UsageModel
		}{
			{ts >= float64(dayStart.Unix()), &u.W24h, models24},
			{ts >= float64(monthStart.Unix()), &u.Month, modelsM},
		} {
			if !f.in {
				continue
			}
			f.w.InTokens += int64(tin)
			f.w.OutTokens += int64(tout)
			f.w.CacheRead += int64(tread)
			f.w.Reasoning += int64(treason)
			f.w.APICalls++
			f.w.Cost += computableCost
			f.w.OpenCodeCost += computableCost
			f.w.OpenCodeTokens += int64(tin + tout)
			if !(cost > 0) && !hasRate {
				f.w.CostRateNA = true
			}

			key := strings.ToLower(model) + "\x00opencode"
			m := f.set[key]
			if m == nil {
				m = &UsageModel{Name: model, Provider: "opencode"}
				f.set[key] = m
			}
			m.APICalls++
			m.InTokens += int64(tin)
			m.OutTokens += int64(tout)
			m.CacheRead += int64(tread)
			m.Reasoning += int64(treason)
			m.Cost += computableCost
			if !(cost > 0) && !hasRate {
				m.RateNA = true
			}
		}

		// Month daily bucket (exact per-message, unlike hermes weighting).
		// Same-day entries are merged by collectUsage's byDay pass.
		if ts >= float64(monthStart.Unix()) {
			day := time.Unix(int64(ts), 0).In(loc)
			u.Daily = append(u.Daily, UsageDay{Day: day, In: int64(tin), Out: int64(tout), Cost: computableCost})
		}
	}

	for _, pair := range []struct {
		set map[string]*UsageModel
		w   *UsageWindow
	}{{models24, &u.W24h}, {modelsM, &u.Month}} {
		for _, m := range pair.set {
			pair.w.Models = append(pair.w.Models, *m)
			pair.w.OpenCodeModels = append(pair.w.OpenCodeModels, *m)
		}
	}
}

// windowFractions returns the fraction of a session's activity falling in the
// 24h and calendar-month windows. Prefer per-message timestamps; fall back to
// first/last_seen span overlap when a session has no message rows.
func windowFractions(times []float64, first, last float64, dayStart, monthStart, now float64) (f24, fMonth float64) {
	if len(times) == 0 {
		// Span heuristic.
		if first <= 0 || last <= 0 {
			return 0, 0
		}
		f24 = overlapFraction(first, last, dayStart, now)
		fMonth = overlapFraction(first, last, monthStart, now)
		return f24, fMonth
	}
	var c24, cM int
	for _, t := range times {
		if t >= dayStart && t <= now {
			c24++
		}
		if t >= monthStart && t <= now {
			cM++
		}
	}
	n := float64(len(times))
	return float64(c24) / n, float64(cM) / n
}

// dayFractions distributes a session across head-local calendar days of the
// month by per-message day counts (span-heuristic fallback).
func dayFractions(times []float64, first, last float64, monthStart, now float64, loc *time.Location) map[string]float64 {
	out := map[string]float64{}
	if len(times) == 0 {
		if first <= 0 || last <= 0 {
			return out
		}
		// Linear split across spanned days inside the month.
		start := max64f(first, monthStart)
		end := min64f(last, now)
		if end <= start {
			// Entire session outside/at edge — attribute to last day inside.
			if last >= monthStart && last <= now {
				out[time.Unix(int64(last), 0).In(loc).Format("2006-01-02")] = 1
			}
			return out
		}
		total := end - start
		if total <= 0 {
			total = 1
		}
		for d := time.Unix(int64(start), 0).In(loc); !d.After(time.Unix(int64(end), 0).In(loc)); d = d.AddDate(0, 0, 1) {
			dayStartF := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, loc).Unix()
			dayEndF := dayStartF + 86400
			share := overlapFraction(start, end, float64(dayStartF), float64(dayEndF))
			if share > 0 {
				out[d.Format("2006-01-02")] = share
			}
		}
		return out
	}
	counts := map[string]int{}
	for _, t := range times {
		if t >= monthStart && t <= now {
			counts[time.Unix(int64(t), 0).In(loc).Format("2006-01-02")]++
		}
	}
	n := len(times)
	for k, c := range counts {
		out[k] = float64(c) / float64(n)
	}
	return out
}

func overlapFraction(aStart, aEnd, bStart, bEnd float64) float64 {
	lo := max64f(aStart, bStart)
	hi := min64f(aEnd, bEnd)
	if hi <= lo {
		return 0
	}
	span := aEnd - aStart
	if span <= 0 {
		return 1
	}
	return (hi - lo) / span
}

func max64f(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func min64f(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// usageRow is one parsed session_model_usage row.
type usageRow struct {
	SessionID string
	Model     string
	Provider  string
	APICalls  int64
	InTokens  int64
	OutTokens int64
	CacheRead int64
	Reasoning int64
	EstCost   float64
	ActCost   float64
	FirstSeen float64
	LastSeen  float64
}

func parseUsageRow(row map[string]any) (usageRow, bool) {
	r := usageRow{}
	r.SessionID, _ = row["session_id"].(string)
	r.Model, _ = row["model"].(string)
	r.Provider, _ = row["billing_provider"].(string)
	if r.SessionID == "" && r.Model == "" {
		return r, false
	}
	if v, ok := num(row["api_call_count"]); ok {
		r.APICalls = int64(v)
	}
	if v, ok := num(row["input_tokens"]); ok {
		r.InTokens = int64(v)
	}
	if v, ok := num(row["output_tokens"]); ok {
		r.OutTokens = int64(v)
	}
	if v, ok := num(row["cache_read_tokens"]); ok {
		r.CacheRead = int64(v)
	}
	if v, ok := num(row["reasoning_tokens"]); ok {
		r.Reasoning = int64(v)
	}
	if v, ok := num(row["estimated_cost_usd"]); ok {
		r.EstCost = v
	}
	if v, ok := num(row["actual_cost_usd"]); ok {
		r.ActCost = v
	}
	if v, ok := num(row["first_seen"]); ok {
		r.FirstSeen = v
	}
	if v, ok := num(row["last_seen"]); ok {
		r.LastSeen = v
	}
	return r, true
}

// queryJSON runs one sqlite3 -readonly -json query and decodes rows.
func queryJSON(ctx context.Context, db, sql string) ([]map[string]any, error) {
	out, err := runCmd(ctx, 8*time.Second, "sqlite3", "-readonly", "-json", db, sql)
	if err != nil {
		if strings.Contains(err.Error(), "not found in $PATH") || strings.Contains(err.Error(), "executable file not found") {
			return nil, fmt.Errorf("sqlite3 not on PATH")
		}
		return nil, err
	}
	s := strings.TrimSpace(out)
	if s == "" {
		return nil, nil
	}
	var rows []map[string]any
	if err := json.Unmarshal([]byte(s), &rows); err != nil {
		// sqlite3 -json can emit non-array JSON errors; surface row parse as
		// note rather than hard failure.
		return nil, fmt.Errorf("bad json (%v)", shortErr(err))
	}
	return rows, nil
}

func shortErr(err error) string {
	s := strings.TrimSpace(err.Error())
	s = strings.SplitN(s, "\n", 2)[0]
	if len(s) > 60 {
		s = s[:57] + "…"
	}
	return s
}

// num coerces json numbers (float64) and nil to float64.
func num(v any) (float64, bool) {
	switch t := v.(type) {
	case float64:
		return t, true
	case int64:
		return float64(t), true
	case int:
		return float64(t), true
	default:
		return 0, false
	}
}

var (
	headLocOnce sync.Once
	headLocVal  *time.Location
)

// headLocation pins day-bucketing to head's own timezone (read from
// /etc/localtime), independent of whatever TZ an SSH client forwards. Falls
// back to the process local zone when the symlink is unreadable.
func headLocation() *time.Location {
	headLocOnce.Do(func() {
		headLocVal = loadLocationFrom("/etc/localtime")
		if headLocVal == nil {
			headLocVal = time.Local
		}
	})
	return headLocVal
}

func loadLocationFrom(localtimePath string) *time.Location {
	dst, err := os.Readlink(localtimePath)
	if err != nil {
		return nil
	}
	// e.g. /etc/zoneinfo/America/Los_Angeles or .../zoneinfo/<Region>/<City>
	idx := strings.Index(dst, "zoneinfo/")
	if idx < 0 {
		return nil
	}
	name := dst[idx+len("zoneinfo/"):]
	if name == "" {
		return nil
	}
	loc, err := time.LoadLocation(name)
	if err != nil {
		return nil
	}
	return loc
}
