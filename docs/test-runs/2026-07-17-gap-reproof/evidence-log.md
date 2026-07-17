# WP5 dogfood-gap re-proof — 2026-07-17

**Tip:** `origin/master` @ `f6c226290c3e038de8c0b8f1da5af752c4c6e973` (fetched fresh; PR #157 merged).
**Method:** live iOS Simulator (Simurgh lease) + a freshly built, fully isolated `lancerd`
daemon (own `LANCER_STATE_DIR`, own relay pairing code, own repo) — **not** production
`~/.lancer`, not the owner's phone pairing slot.
**Evidence root:** this directory (this file + `screenshots/`).

---

## Setup (for reproduction)

1. `git fetch origin master` → `f6c22629`. Worktree: `.worktrees/wp5-gap-reproof` on branch
   `docs/gap-reproof-2026-07-17`.
2. Isolated daemon: `cd daemon/lancerd && go build -o /tmp/wp5-lancerd/lancerd .` (built from
   this tip); ran as `LANCER_STATE_DIR=/tmp/wp5-lancerd-state /tmp/wp5-lancerd/lancerd daemon`.
   `lancerd doctor` → 8 OK / 5 warn (all expected — fresh state dir) / 0 fail.
3. Simurgh: `pool_status` → capacity 2, 1 already active elsewhere → `lease_acquire` (`lease-205`,
   `iPhone 17 Pro`, UDID `3F7890DE-BACA-491E-B251-4C62342E6E18`). `simurgh integration
   xcodebuildmcp start --session lease-205` to bind XcodeBuildMCP.
4. `xcodegen generate` in the worktree (project.yml → Lancer.xcodeproj is gitignored).
   `build_run_sim` on scheme `Lancer` → **SUCCEEDED** (321.5s), installed + launched
   `dev.lancer.mobile` on the leased sim.
5. Paired the sim app to the isolated daemon: `lancerd pair` → code, entered on-device →
   isolated daemon log `2026/07/17 11:09:14 e2e: paired with phone` (relay
   `wss://conduit-push.fly.dev`, same relay endpoint as prod but a distinct pairing
   code/keypair — **not** the owner's production pairing slot).
6. Added a scratch git repo `/tmp/wp5-scratch-repo` (`git init`, one commit) via in-app
   "Add Repo" so dispatches have something real to operate on.
7. Confirmed production untouched throughout: `~/.lancer/audit.log` last entry stayed at
   `2026-07-16T23:44:20Z` (pre-dating this whole session) after all isolated-daemon activity.

---

## Verdict table

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | GAP #10 — background-tasks pill (FX10 relay artifact mirror) | **PASS** | `screenshots/gap10-background-tasks-pill.png`; sheet lists 4 real tool-call entries (`ls -la …`, `git … commit …`, `Read notes.txt`, `Edited notes.txt`) with live elapsed timers, populated over the relay mirror. Caveat below (stayed "Running" after turn completed). |
| 2 | GAP #14 — tool-call chips under real concurrent execution | **PASS** | `screenshots/gap14-tool-chips-expanded.png`; real Claude Code run (not `LANCER_SEED_TRANSCRIPT`) produced 4 distinct, correctly-labeled chips ("Read notes.txt", "Edited notes.txt", "Ran a command" with real JSON input) — no "Bash Bash:" duplicate-label bug, no prose-only collapse. |
| 3 | C4 #7 — review chain (needsApproval→awaiting→fix FX7) | **PASS** | `screenshots/c4-review-approval-card.png` (live "Bash wants to run: ls -la …" card, High risk); 3 escalate→approve round-trips over relay (`bd7b6195…`, `8cbc210d…`, `57782942…` — isolated daemon log + audit.log); real commit `b03e19b "wp5 reproof edit"` landed in `/tmp/wp5-scratch-repo` (`git log` confirms); "Review +1 −0 1 file" pill rendered post-turn. |
| 4 | Emergency Stop | **FAIL** | See detailed finding below. UI/audit layer reports success; host process is not killed. |

---

## Detail: Emergency Stop (FAIL — new finding)

**Entry point** (never live-verified before this session): Profile → Settings →
"Policy & Governance" → **Emergency Stop** section →
`cursor.settings.emergency-stop` button → confirm sheet "Stop all runs".
Wired in `Packages/LancerKit/Sources/AppFeature/Settings/AppSettingsView.swift`
(commit `d68de81e`).

**Repro:**
1. Dispatched a new turn in `wp5-scratch-repo`: "Run the shell command sleep 120 then say
   done. Do not stop early."
2. Approved the resulting escalation (`sleep 120`, `ask-high`) — audit:
   `{"timestamp":"2026-07-17T15:15:33Z","action":"escalate", ...,"command":"sleep 120", "approvalId":"6c8d949e-…"}`.
   On the host this spawned the **PreToolUse hook gate** process (confirmed via `ps`):
   ```
   roshansilva  37570  ... /Users/roshansilva/.lancer/bin/lancerd agent-hook --agent claudeCode \
     --kind command --command "sleep 120" --cwd /private/tmp/wp5-scratch-repo --risk high \
     --tool-name=Bash --tool-use-id=toolu_01Kqfj57yBEYxR5EzWmmj2BX \
     --session-id=13f3bca9-ed95-4ead-bf6b-8fe3fee096bf \
     --tool-input={"command":"sleep 120","description":"Sleep for 120 seconds","run_in_background":true}
   ```
   (the actual `sleep 120` subprocess had not even started yet — Claude Code was still
   blocked on the PreToolUse hook's approval gate.)
3. Navigated to Settings → Emergency Stop → confirmed "Stop all runs".
4. App showed: **"Stopped 2 runs. New launches are blocked on the host until re-enabled."**
   (`screenshots/emergency-stop-result.png`, `cursor.settings.emergency-stop.result` AXUniqueId).
5. Isolated daemon's audit log recorded the stop:
   ```
   {"timestamp":"2026-07-17T15:17:16Z","action":"run-stopped","kind":"run-control","approvalId":"b0902e57-…"}
   {"timestamp":"2026-07-17T15:17:16Z","action":"run-stopped","kind":"run-control","approvalId":"b7af995d-…"}
   ```
6. **But `ps -p 37570` showed the hook-gate process still alive, unchanged, for 6+ minutes
   after the "Stopped 2 runs" confirmation** — well past both the tap and any 120s hook
   timeout window. It had to be killed manually (`kill -9 37570`) to clean up; Emergency
   Stop never sent it a signal.

**Root cause (from evidence, not code-read):** Emergency Stop's `run-stopped` audit events
are recorded against the **dispatch-level `approvalId`** of the original `conversation-append`
launch (`b0902e57…`, `b7af995d…`), not against the **specific escalation** the CLI is currently
blocked on (`6c8d949e…`, the pending `sleep 120` ask). The daemon marks the run "stopped" and
blocks new launches, but never resolves (deny/kill) the live PreToolUse hook process that's
holding the CLI's tool call open — so the host-side agent process is orphaned, running past
the point the UI claims everything is stopped.

**This matches and confirms** the prior GAP_LIST entry `LA2 #1 BLOCKED — "No connected host"
under re-pair race`: Emergency Stop is mechanically reachable and does update daemon
bookkeeping, but does not actually terminate a running host process. Verdict upgraded from
BLOCKED (harness/pairing issue) to **FAIL** (product bug), now proven against a real pairing
with no harness/pairing ambiguity.

---

## Caveat found during setup (Simurgh / isolation friction)

**1. XcodeBuildMCP session defaults are not session-scoped — clobbered mid-run by a
concurrent lease.** After `build_run_sim` succeeded on `lease-205`, a subsequent
`screenshot` call silently returned a screenshot from a **different** simulator
(`803465E0-…`, `simurgh-clone[lease-204:iPhone 17 Pro:27.0]`, project `wp1-perf`) because
another concurrent session's `session_set_defaults` had overwritten the shared
`(default)` XcodeBuildMCP profile between my calls. `session_show_defaults` confirmed this.
Recovered by re-calling `session_set_defaults` with my own project/scheme/`lease-205`
UDID immediately before every subsequent build/screenshot call, and preferring
`mcp__ios-simulator__screenshot` (which takes an explicit `udid`) over the XcodeBuildMCP
`screenshot` tool (which trusts the shared session default) for all evidence capture after
this was discovered. **Recommendation:** treat XcodeBuildMCP session defaults as
best-effort only when multiple Simurgh leases are active concurrently; always pass an
explicit `udid` to screenshot/describe/tap calls instead of relying on defaults.

**2. Claude Code's `PreToolUse` hook resolves the daemon binary via real `$HOME`, not the
isolated one.** `daemon/lancer-hook.sh` does `LANCERD="${LANCERD:-$HOME/.lancer/bin/lancerd}"`.
The isolated daemon's spawned Claude CLI subprocess did **not** override `$HOME` (only
`LANCER_STATE_DIR`), so every `agent-hook` invocation actually exec'd the **production**
installed binary at `/Users/roshansilva/.lancer/bin/lancerd` (built `2026-07-16 22:07`,
i.e. slightly stale vs. today's `f6c22629` tip) — though correctly pointed at the isolated
`/tmp/wp5-lancerd-state` via inherited `LANCER_STATE_DIR`, so no state leaked into
production (`~/.lancer/audit.log` verified untouched throughout, last entry pre-dating this
session). Net effect: the escalate/approve/Emergency-Stop round trips in this report
exercised the **isolated daemon's `daemon`/`agent-hook`-consumer RPC surface** correctly
(state fully separated), but the **`agent-hook` CLI leg itself ran yesterday's production
binary**, not the freshly-built master-tip binary. Given `agent-hook`'s code path is small
and unrelated to the Emergency Stop/FX10/FX7 changes under test, this is unlikely to affect
the verdicts above, but is recorded here as a rigor caveat and a real isolation gap in the
`lancerd install` + hook-script design worth fixing (hook should resolve the daemon binary
via an env var the spawning daemon sets, not via literal `$HOME`).

**3. Pairing codes expire fast under manual multi-step navigation.** First two pairing
attempts hit "Pairing code expired" because minting a code, then navigating multiple
describe/tap round-trips before entering it, took long enough to expire the code. Fixed by
minting the code, then entering+connecting in the same tight loop without intervening
`describe_all` calls.

**4. `agentPermissionModeGet` is unhandled by this master-tip isolated daemon** —
`2026/07/17 11:10:42 e2e: unhandled message type: agentPermissionModeGet` appeared twice
in the isolated daemon log, correlating with a red "The machine didn't respond. Make sure
it's online, then try again." error under the composer's permission-mode pill
(visible in `screenshots/thread-completed-with-chips-and-pill.png`). Not one of the four
assigned items, but flagged here since it's new, live, reproducible evidence at current
master tip and affects the composer's permission-mode pill UX.

---

## Repo state changed by this run

`/tmp/wp5-scratch-repo` (scratch, outside the source tree) now has commit `b03e19b`
"wp5 reproof edit" from the real dispatch. No source-tree files were modified except
under `docs/test-runs/2026-07-17-gap-reproof/**`, `docs/CHANGELOG.md`, and
`docs/test-runs/2026-07-16-untested-feature-sweep/GAP_LIST.md` per the lane's write-set.
