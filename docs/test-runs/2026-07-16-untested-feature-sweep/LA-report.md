# Lane A — Governance & Settings (candidates 1, 2, 3, 21, 24)

Date: 2026-07-16. Sim: Simurgh lease-180, `iPhone 17 Pro`, udid `BF6E4883-B03E-4ABA-A23D-3097E8EA186E` (released at end). Daemon: isolated `/tmp/sweep-A` (`/tmp/lancerd-sweep`). App: `/tmp/dd-untested-sweep/Build/Products/Debug-iphonesimulator/Lancer.app` (bundle `dev.lancer.mobile`).

## Environment incident (read first — high priority)

**A build I did not start finished mid-setup, and a mistake on my part briefly broke the owner's real production `lancerd`.** Sequence:

1. The "fixed artifact" app bundle named in the common brief was still an in-progress `xcodebuild` (PID 21241, started 07:55, another session's process) when I first tried `install_app_sim` — it failed with "Missing bundle ID" because `Lancer.app/` only had a `Frameworks/` dir. I waited for that PID to exit (~3 min) rather than rebuild; it then had a valid `Info.plist`/executable.
2. My own mistake: I ran `nohup /tmp/lancerd-sweep daemon > /tmp/sweep-A/daemon.log 2>&1 &` **without** `LANCER_STATE_DIR` exported in that same shell invocation (I only exported it for the subsequent `pair` call). The daemon process defaulted to `~/.lancer` — the owner's real state dir — and its bind to `~/.lancer/lancerd.sock` evicted the launchd-managed resident `lancerd` (PID 81742, `dev.lancer.lancerd`) from that socket for **~11 minutes** (08:01–08:12). `lancerd doctor` on the real state dir showed `WARN resident daemon: socket present but dial failed: connection refused`.
3. Recovery: killed my two errant `~/.lancer`-bound daemon processes, then `launchctl kickstart -k gui/501/dev.lancer.lancerd` to force the real service to rebind. `lancerd doctor` confirmed `OK resident daemon reachable` afterward. No other `~/.lancer` files were touched (checked `ls -la ~/.lancer`; only `lancerd.sock` mtime moved).
4. **Root cause for next time:** always put `export LANCER_STATE_DIR=...` and the `nohup ... daemon &` in the *same* `Bash` call, not split across calls with other work in between — that's what let a shell without the export slip through.

**Second, separate incident: XcodeBuildMCP session-defaults are a single global shared across lanes.** `session_show_defaults` showed one `currentProfile` field shared by the whole MCP server process — lane-b activating its own profile flipped my active profile mid-task multiple times, and one `launch_app_sim` call of mine landed on lane-b's leased simulator (lease-181) with my pairing code before I caught it (`stop_app_sim`'d immediately after). Mitigated by re-calling `session_use_defaults_profile("lane-a")` immediately before each XcodeBuildMCP UI call, and by switching to `xcrun simctl`/`ios-simulator` MCP tools (which take an explicit `udid`) for install/launch/screenshot wherever possible — those don't share the race.

## Critical environment blocker: no touch/HID input reaches the app on this sim

Confirmed via **five independent mechanisms**, on **three different screens**, across **multiple app relaunches**: `mcp__ios-simulator__ui_tap` (x2, different durations), raw `idb ui tap` CLI, `mcp__XcodeBuildMCP__tap` with AXe-based elementRef (after installing AXe via `brew tap cameroncooke/axe && brew install axe`, since it wasn't preinstalled), `mcp__ios-simulator__ui_swipe`, and even `mcp__XcodeBuildMCP__button(home)` (hardware Home button) — **all report "success" but produce zero observable UI change** (screenHash unchanged / screenshot identical). This matches a previously-documented limitation (headless Xcode-beta/iOS simulator not delivering HID taps to SwiftUI gesture recognizers) rather than something new. `open_sim` also failed ("Unable to find application named 'Simulator'") confirming this is a fully headless environment with no window to give input focus.

**Practical effect:** anything reachable purely by DEBUG deep-link (`LANCER_DESTINATION=...`) could be verified by view/a11y-tree. Anything requiring a tap/type/confirm inside the app (composer send, Policy edit+Save, Emergency Stop confirm, opening Audit feed rows, opening an Agents thread) could not be driven and is marked BLOCKED, not FAIL — the UI renders correctly where I could reach it.

## Setup completed

- `git init` target repo at `/tmp/sweep-A/target-repo` (README.md, 1 commit) — never used, since composer dispatch requires taps.
- Isolated daemon at `/tmp/sweep-A`, paired successfully after fix (`lancerd doctor` → `relay pairing: paired ... (confirmed)`).
- Could **not** dispatch the planned haiku run from the composer (send button unreachable by touch). The "Agents" section instead surfaced a real, pre-existing Claude Code session from this very sweep session (`Test untested Lancer features against live simulator stack · Claude Code · command-center`) — not something I dispatched, but a real live session nonetheless, useful for candidate #24.

## Candidate verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 21 | Profile usage placeholder removal | **PASS** | Deep-linked `LANCER_DESTINATION=profile`. `snapshot_ui` a11y tree (seq4, 90 elements) lists: Profile, Lancer, "Paired with Relay host", Connections/Trusted Machines(1), More/Settings/Help, "LANCER 1.0.0 (2)" — **no** "Usage" text/element and no "Not available yet" string anywhere in the tree. Screenshot: `screenshots/LA-01-profile.png`. |
| 2 | Policy editor (Settings → Policy) | **BLOCKED** | Deep-linked `LANCER_DESTINATION=settings`; screen renders "Policy" row ("View rules and edit host policy YAML", a11y id `cursor.settings.row.policy`) correctly wired. Tapped it via AXe elementRef `e91` — tool reported `SUCCEEDED` but the returned snapshot tree was byte-identical to before the tap (same targets/text, no Policy editor sheet appeared). Cannot load/edit/Save/round-trip. `lancerd doctor` on the isolated state dir shows `policy.yaml absent (default-ask only)` — no policy file was ever created, consistent with never reaching the editor. Screenshot: `screenshots/LA-02-settings.png`. |
| 3 | Audit feed (Settings → Audit) | **BLOCKED** | Same Settings screen shows "Audit feed" row ("Recent host audit entries", a11y id `cursor.settings.row.audit`) correctly wired, but tapping it (same input blocker) never opens it. Daemon-side confirmation: `lancerd doctor` shows `audit.log absent (created on first event)` for `/tmp/sweep-A` — no audit events exist yet in this isolated session anyway (never dispatched a governed run), so even a working tap wouldn't have shown non-trivial rows without also fixing the dispatch blocker. |
| 1 | Emergency Stop | **BLOCKED** | Settings screen shows the "Emergency Stop" section and red button ("Stops all runs and blocks new launches until re-enabled. Requires a connected host (SSH or relay)."), fully wired/styled correctly (a11y id `cursor.settings.emergency-stop`). Could not tap it (input blocker), and could not first start the required long-running haiku turn (composer unreachable) to have something to stop. Re-enable-after-stop behavior unobserved. |
| 24 | Agents section reliability | **PARTIAL / mixed, but with new signal** | On Workspaces home, "Agents" briefly showed "Machine unreachable — no successful update yet" immediately post-pair, then within ~1 min corrected to "1 running" with a real row: "Test untested Lancer features against live simulator stack · Claude Code · command-center · Running · N mins ago" (real session data, not a fixture — this is this actual sweep's own Claude Code session on this machine, auto-discovered). That's a **partial PASS** on "lists real sessions, not stuck Checking/unreachable" (G7). However, tapping the row (tried 3x across AXe tap, raw idb, ios-simulator tap, at different elementRef generations) never opened a thread — **but this is confounded by the sim-wide input blocker**, so I cannot attribute the non-navigation to a real app bug vs. the environment; call it BLOCKED on the "tap opens continuable thread" half of the PASS bar, not a confirmed FAIL. |

## Top surprises

1. The app build I was told was a fixed, already-built artifact was still mid-compile when I started (another session's `xcodebuild`, PID 21241) — good thing was to wait for it rather than trust the brief blindly.
2. My own env-var-in-wrong-shell-call mistake actually knocked the owner's real production `lancerd` daemon offline for ~11 minutes. Recovered via `launchctl kickstart -k`, but this is exactly the class of incident the "protects the owner's phone pairing" hard rule warns about — the rule needs a stronger operational note: **export the state dir and start the daemon in the same command**, never split across calls.
3. XcodeBuildMCP's session-defaults `currentProfile` is a single value shared across concurrent lane sessions on the same MCP server — a structural collision risk for any future parallel-lane sim work via this MCP, independent of Simurgh itself.
4. Total, simulator-wide HID input failure (confirmed 5 ways including the hardware Home button) blocked essentially all interactive verification beyond what DEBUG deep-links + a11y-tree reads could reach. AXe had to be installed fresh (`brew tap cameroncooke/axe && brew install axe`, required trusting an untrusted tap) — worth pre-installing on the sweep host for future runs, though it didn't ultimately fix the tap-delivery problem here.

## Simurgh feedback (2 items)

1. **Lease TTL (30 min) was too short relative to setup overhead.** Between waiting for another session's in-flight Xcode build (~3 min) and diagnosing the daemon/profile incidents above, a large fraction of the 30-minute lease was consumed by non-Simurgh-related setup before any candidate testing began. Not a Simurgh bug per se, but worth a documented "renew immediately after acquire if doing multi-step setup" pattern in the CLI help.
2. **No friction directly attributable to the `simurgh` CLI itself** — `acquire --json` and `release` both worked cleanly and returned exactly the fields needed (`udid`, `leaseId`). The env/xcodebuildFlags block in the acquire response was unused by me (I used raw `simctl`/`ios-simulator` MCP with the explicit udid instead) but looked well-formed.

## Files

- Screenshots: `docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/LA-01-profile.png`, `LA-02-settings.png`, `LA-03-agents-noop.png`
- This report: `docs/test-runs/2026-07-16-untested-feature-sweep/LA-report.md`
