# head-dash

A sleek terminal dashboard for the **head** NixOS server. Built in Go on the
charmbracelet stack ([Bubble Tea](https://github.com/charmbracelet/bubbletea)
+ [Lip Gloss](https://github.com/charmbracelet/lipgloss)). It reads one live
host snapshot per tick and renders a modern htop-style layout: system metrics
left, containers/services right, and an agent status strip at the bottom.

## Usage

```console
$ head-dash                     # interactive (note: it uses the alternate screen)
$ head-dash --interval 250ms    # faster refresh
$ head-dash --once              # render exactly one frame and exit 0 (CI / verification)
$ head-dash --no-color          # plain output for old terminals / logs
$ head-dash --page usage        # start on the usage page (default: system)
$ head-dash --page usage --usage-window month   # month-to-date instead of 24h
```

Interactive keys (footer always lists them):

| Key | Action |
| --- | --- |
| `tab` / `shift+tab` | cycle pages (system ↔ usage) |
| `1` / `2` | jump to page 1 / page 2 |
| `q` / `ctrl+c` | quit |
| `p` | pause / resume the ticker |
| `r` | force an immediate refresh |
| `+` / `-` | double / halve the refresh interval |

Usage page keys:

| Key | Action |
| --- | --- |
| `a` | 24h rolling window |
| `m` | month-to-date (calendar month, head-local time) |
| `u` | force a usage re-collect |

`--once` renders a single 120x36 frame without needing a TTY and exits 0, so it
can be used to verify the binary and to eyeball the data sources.

## Pages

### Page 1 — system

One live host snapshot per tick: CPU (overall + per-core + top processes),
memory/swap, Intel GPU engine stats, Docker containers, key systemd services,
Hermes + OpenCode agent status, storage.

### Page 2 — usage

Agent token & cost economics, with both windows computed every pass:

- **Window totals** — tokens in/out, cache reads, reasoning, API calls,
  estimated cost, hermes-vs-opencode spend share.
- **Spend split** — hermes profiles vs opencode delegations.
- **Models table** — top models by cost with provider, calls, in/out.
- **Hermes bots** — one row per profile (main + every bot, auto-discovered
  from `profiles/*/state.db`), top-3 model mix.
- **Month sparkline** — per-day (head-local) token volume for the current
  month with a cost-spend ribbon.

Cost basis: Hermes rows use the recorded `estimated_cost_usd`/`actual_cost_usd`
from its own pricing engine (actuals win when present). opencode rows carry
per-message token counts; cost is the recorded actual when present, else
computed from the same official-docs price snapshot constants Hermes uses
(deepseek flash 0.14/0.28, pro 0.435/0.87, gpt-5.6 terra 2.50/15.00, sol
5.00/30.00, luna 1.00/6.00). Models with no published rate (custom NVFP4
endpoints) show `rate n/a` — their tokens stay exact, cost omitted, never
silently zero.

Day attribution for multi-day hermes sessions is proportional to
per-day message counts (fallback: first/last-seen overlap when a session has
no message rows). OpenCode messages bucket exactly by timestamp.
Unreadable sources degrade to visible notes — e.g. running as `hermes`
cannot read the OpenCode data dir (owner-only by design).

## Data sources

All reads are non-blocking, wrapped in timeouts, and degrade to a clear
**unavailable** state rather than crashing or hanging the UI.

| Panel | Source |
| --- | --- |
| Usage page (page 2) | Hermes `state.db` `session_model_usage` per profile (main + `profiles/*/state.db`) and OpenCode's backend DB — read via `sqlite3 -readonly -json` subprocesses (no Go SQLite driver, per the original dependency decision) |
| CPU (overall + per-core) | `/proc/stat` deltas between ticks |
| Top 5 processes | `/proc/*/stat` utime/stime deltas across ticks (top-style per-core %) |
| Load average | `/proc/loadavg` |
| Memory / swap | `/proc/meminfo` |
| GPU | `/sys/class/drm/card<N>/device/hwmon/hwmon*/temp1_input`, `power1_average` |
| GPU engine busy | `timeout 2 intel_gpu_top -s 1000 -o -` (best-effort parse; **requires root**) |
| Docker | Docker Engine API via the Go SDK (`client.FromEnv`) — never the CLI |
| Services | `systemctl show` for `hermes-agent`, `opencode`, `docker`, `docker-jellyfin`, `nginx`; `systemctl --failed` for the failed-units section |
| Hermes agent | systemd unit state + `journalctl -u hermes-agent --since=-60s` line count; falls back to newest mtime under `/mnt/cache/appdata/hermes-agent/.hermes/{logs,sessions}` when journal access is denied |
| OpenCode | `systemctl is-active opencode.service` + HTTP GET `http://127.0.0.1:4096/` with a 2s timeout — any HTTP response (even `401`, the auth gate) means **UP**, connection refused means **DOWN**, latency is shown |
| Storage | `statfs(2)` on `/mnt/user`, `/mnt/cache`, `/mnt/disk1..3` (missing mounts read `not mounted`) |

### Notes

- **GPU engine busy needs root.** Opening the DG1 DRM device for
  `intel_gpu_top` requires privileges the interactive user does not have by
  default. Without them the dashboard still shows temperature/power and adds a
  hint (`engine busy: needs root`); never block more than ~2s per tick on GPU
  collection.
- This hardware (DG1 + iGPU) exposes **no** `gpu_busy_percent` and no
  `gt/gt0` frequency sysfs, so the dashboard does not attempt to read them.
- **Docker socket:** when `/run/docker.sock` is not accessible the panel shows a
  single `docker socket not accessible` row rather than erroring.
- OpenCode session counts via read-only SQLite are intentionally not shipped:
  it would pull a heavyweight pure-Go SQLite driver into the dependency set.
  The status is judged from the HTTP probe + unit state alone.

## Flags

```
--interval <duration>   refresh interval (default 1s; e.g. 500ms, 2s)
--once                  render exactly one frame and exit 0
--no-color              disable colours
```

## Building

From the flake root:

```console
$ nix build .#head-dash                    # outputs ./result/bin/head-dash
$ nix shell nixpkgs#go nixpkgs#gcc
$ cd packages/head-dash && go build ./...
```

The plain `go build ./...` path needs a C compiler on `PATH` (nixpkgs' `go`
sets `CGO_ENABLED=1`, and the net/`os/user` stdlib packages compile against
cgo). `go build` succeeds without gcc when invoked as
`CGO_ENABLED=0 go build ./...`; the Nix build handles all of this via its
stdenv.
```
