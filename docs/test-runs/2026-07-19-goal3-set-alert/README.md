# Goal 3 — SET-failure alert repro — 2026-07-19

**Outcome: reproduced the underlying daemon SET failure cleanly (no daemon-lifecycle chaos), but the
"Couldn't change permission mode" alert never presents. This is a real UI-lifecycle bug in
`ChatPermissionModePill`, not a test-harness limitation — evidenced by a controlled A/B pair below.**

Worktree: `/Volumes/LancerDev/worktrees/lancer/goal3-set-alert-2026-07-19` @ branch
`test/goal3-set-alert-2026-07-19` (based on PR #176 tip `4d558f5d`).

## TL;DR

- The daemon SET RPC (`agentPermissionModeSet` → `setPermissionModeAudited` →
  `policy.SetCWDOverride` → `os.WriteFile`) was made to fail deterministically by chmod'ing the
  isolated daemon's `permission-mode-overrides.yaml` read-only — **no daemon kill, no LaunchAgent
  touch, no production state touched at any point.**
- Tapping a new preset in the composer's `+` → embedded Permission submenu against this induced
  failure: the preset **correctly reverts** to the prior confirmed value (proving `apply()`'s
  catch block ran to completion, including the network round trip) — but **no alert ever
  appears**, confirmed across 3 independent attempts with immediate + delayed UI polling.
- A same-session **control test** (same tap path, override file made writable again) shows a
  *successful* SET correctly updates the pill label and persists — proving the tap→`apply()`
  invocation itself is reliable and my isolated pairing/RPC path works end-to-end. The only
  variable between the two runs is success vs. failure of the RPC, and only the failure case's
  user-facing alert is missing.
- **Root cause hypothesis (code-backed, not just inference):** `ChatPermissionModePill(embedded:
  true)` renders as its own `Menu { optionsMenuContent } … .alert(...)`, and per
  `ChatThreadChrome.swift:308-316` this Menu is embedded *inside* the composer's outer `+` Menu's
  content builder (`Menu { Button(Add context); permissionMenu() }`). Selecting a leaf preset
  button in a nested `Menu` dismisses the **entire** menu chain immediately (standard
  `UIMenu`/SwiftUI `Menu` dismiss-on-select behavior) — tearing down the `ChatPermissionModePill`
  view instance (and its `.alert` modifier's presentation surface) before the async `apply()`
  (which awaits a real network RPC) can complete and flip `isShowingErrorAlert = true`. The
  `@State` mutation still happens (which is why the preset correctly reverts on next render), but
  there's no live view left for the `.alert(isPresented:)` binding to actually present against, so
  it silently no-ops.

## Isolation — exact commands (repeatable)

Everything below uses `LANCER_STATE_DIR=/tmp/goal3-set-alert-lancerd-state`, entirely separate from
production `~/.lancer`. Verified before and after: `~/.lancer/relay-pairing.json` mtime and the
resident `dev.lancer.lancerd` LaunchAgent / `~/.lancer/bin/lancerd` process (`ps aux`) were
untouched throughout (checked via `stat` / `ps aux` / `last`/`who` — no new SSH sessions to this Mac
in the repro window, no resident-daemon audit entries in that window besides the owner's own
parallel live-test activity).

```bash
# 1. Build lancerd from this worktree
cd daemon/lancerd && go build -o /tmp/goal3-lancerd .

# 2. Generate an isolated relay pairing (writes ONLY to LANCER_STATE_DIR, never ~/.lancer)
LANCER_STATE_DIR=/tmp/goal3-set-alert-lancerd-state /tmp/goal3-lancerd pair
# -> prints a 6-digit code (this run: 368065) and persists
#    /tmp/goal3-set-alert-lancerd-state/relay-pairing.json

# 3. Start the isolated resident daemon (own socket, own queue, own policy state)
LANCER_STATE_DIR=/tmp/goal3-set-alert-lancerd-state /tmp/goal3-lancerd daemon \
  > /tmp/goal3-daemon-log.txt 2>&1 &
# -> connects to the REAL hosted relay (wss://conduit-push.fly.dev) but under a
#    brand-new pairing identity/session, isolated from the phone's production pairing

# 4. Simulator via Simurgh (never raw simctl UDID pick)
#    lease_acquire(model: "iPhone 17 Pro") -> lease-223, UDID 181F36D8-1A56-40F6-B990-FDF79DAA7A2A
xcodegen generate   # Lancer.xcodeproj isn't checked in; generate from project.yml
# XcodeBuildMCP: session_set_defaults(projectPath=this worktree's Lancer.xcodeproj,
#   scheme=Lancer, simulatorId=<lease UDID>, derivedDataPath=<lease DerivedData>) -> build_sim
#   -> install_app_sim -> launch_app_sim(env: {
#        LANCER_SKIP_CURSOR_ONBOARDING: "1",
#        LANCER_RELAY_PAIR_CODE: "368065"   # headless relay pairing, see DebugSeeder.swift
#      }, launchArgs: ["-onboardingSeen", "YES"])

# 5. Confirm the sim is on MY isolated daemon (not production): daemon log shows
#    "e2e: connected to relay as daemon" then "e2e: paired with phone" — and the
#    app's Permission pill successfully GETs a daemon-confirmed preset (see below).
```

Daemon-side pairing confirmation (`docs/test-runs/2026-07-19-goal3-set-alert/daemon-log.txt`):
```
lancerd daemon: E2E relay started
lancerd daemon listening on /tmp/goal3-set-alert-lancerd-state/lancerd.sock
2026/07/19 10:20:48 e2e: connected to relay as daemon
2026/07/19 10:28:23 e2e: paired with phone
2026/07/19 10:28:23 e2e: device registered for push (session C8F85F84-...)
relay-token registration rejected: HTTP 401   # expected: no LANCER_ACCOUNT_BACKEND_URL configured;
apns-token registration rejected: HTTP 401    # unrelated to the permission-mode RPC path, harmless
activity-token registration rejected: HTTP 401
```

**Note on repeated re-pairing:** the log shows ~100 "paired with phone" events over the session
(a reconnect roughly every couple seconds). This did not block the repro — every RPC I sent
(GET on thread-open, both control-test and failure-test SETs) completed successfully against the
isolated daemon — but it suggests the relay connection was cycling more than expected. Flagging as
a secondary observation, not chased further (out of scope for goal 3).

## Getting a thread with a real `cwd` (the local seed detour)

`LANCER_SEED_TRANSCRIPT=1` (the documented seam for exactly this — a fixed "Parity seed" thread
with `cwd: "/Users/dev/project"`) **did not persist** despite the env var reaching the process
(confirmed via `ps eww -p <pid> | grep LANCER_`) and the app rendering past the seeding gate. The
app's local GRDB database (App Group container
`.../AppGroup/EE22F6DF-773D-4857-81C9-5626900BC5F6/Lancer/db.sqlite`, group `group.dev.lancer.mobile`)
showed 0 rows in every chat table after two separate launches with the env var set. Root cause not
chased (out of scope) — worth a follow-up ticket since it's a documented, currently-broken seam.

Workaround: stopped the app and inserted a conversation directly via `sqlite3` against the App
Group DB (`chat_conversations` + one `chat_turns` row, `cwd = /private/tmp/goal3-set-alert-fake-cwd`,
a fake path — the daemon never validates `cwd` exists on disk, it's just a map key for the coarse
per-cwd override), then relaunched. This is a legitimate substitute since `ChatPermissionModePill`
only needs a non-global (`cwd != "" && cwd != "~"`) string from `thread.cwd` — see
`ThreadDetailView.swift:359`.

## Important aside: real desktop-history data surfaced (not a violation, but worth flagging)

On first launch, the Workspaces "Agents" section showed rows that looked like real production
Claude-Code session titles (e.g. a WSL-setup session, a Momentum screenshot-critique session).
Investigated before proceeding further, per the isolation constraint. Confirmed via
`RunningAgentsMapping`/`RunningAgentsSection` code + an empty local DB at the time: this section is
a **live, unpersisted "what's on the connected host's disk right now" view** (`ObservedSession`),
not something read from local storage or CloudKit. Since my isolated daemon (`/tmp/goal3-lancerd
daemon`) runs as the real `roshansilva` user on this same real Mac, it legitimately observes real
`~/.claude/projects` session history when asked — `LANCER_STATE_DIR` isolates Lancer's own
queue/policy/pairing state but does not (and structurally should not) sandbox the host's own
Claude-Code/Codex/etc. session files, which live at fixed real paths independent of Lancer.
**This does not touch `~/.lancer` or the resident production daemon** — confirmed via `ps aux`
(only my `/tmp/goal3-lancerd daemon` and the untouched resident `~/.lancer/bin/lancerd` were
running), `last`/`who` (no new SSH logins), and the resident daemon's `audit.log` (no new entries
in the repro window besides the owner's own concurrent live-test activity). I did not interact
with any of these real "Agents" rows — only my own inserted `conv-goal3-set-alert` thread.

## The repro itself

1. Opened `Goal3 SET-alert repro` thread (`cwd = /private/tmp/goal3-set-alert-fake-cwd`).
2. Tapped `+` → embedded Permission submenu. Pill showed **"Permission: Safe writes"**
   (daemon-confirmed via a successful GET — proves the RPC path was live before any failure
   injection).
3. **Control test (prove the harness/tap path itself works):** override file writable, tapped
   "Critical only". `permission-mode-overrides.yaml` correctly gained
   `/private/tmp/goal3-set-alert-fake-cwd: ask`; reopening the menu confirmed the pill label
   updated to **"Permission: Critical only"** and persisted. This proves `apply()` → RPC → daemon
   write → UI-reflects-confirmed-state all works reliably through this exact tap sequence, even
   after the enclosing Menu visually dismisses.
4. **Failure injection:** `chmod 0400` the override file (pre-created, owned by the same user, so
   `os.WriteFile`'s `O_TRUNC` open fails with `EPERM` — verified directly with a Python
   `os.open(..., O_WRONLY|O_TRUNC)` check before relying on it in the app). No daemon restart, no
   socket disruption — the daemon stays fully alive and connected throughout.
5. Tapped "Always ask" (attempt 1): menu closed, **no alert**. Reopened menu: label still read
   **"Permission: Critical only"** (correct revert-on-error behavor) and the override file was
   byte-for-byte unchanged (confirms the write was attempted and failed, not silently skipped).
6. Retried with a different target preset, "Always ask" (attempt 2) and then "Auto-approve reads"
   (attempt 3), including immediate post-tap `ui_describe_all` polls and a second poll after
   reopening the menu each time. Same result all three times: correct silent revert, zero alert,
   confirmed via the accessibility tree (no `AXAlert`-role element ever appeared) and a full
   screenshot (`01-no-alert-after-failed-set.jpg`).

Evidence in this directory:
- `00-repo-thread-view.jpg` — the seeded thread, pre-failure-injection.
- `01-no-alert-after-failed-set.jpg` — post 3rd failed SET attempt: back on the base thread view,
  no alert, no inline error indicator anywhere (the inline caption only exists on the
  non-embedded pill variant per `ChatPermissionModePill.swift:120-125`).
- `daemon-log.txt` — full isolated-daemon log (pairing, repeated reconnects, no crashes).
- `permission-mode-overrides-final.yaml` — final state: `ask` (from the successful control-test
  write), never overwritten by any of the 3 failed attempts.

## Fix-forward pointer (not implemented this session — out of scope for a repro task)

The alert needs to be anchored to a view whose identity outlives the menu-dismiss transition —
e.g. move the `.alert` modifier (and its `isShowingErrorAlert`/`applyErrorMessage` state) up to
`LiveThreadView`/`ThreadDetailView` itself (which persists across the composer menu opening and
closing), with `ChatPermissionModePill` reporting failures via a callback/binding instead of owning
its own alert presentation when `embedded: true`. `ChatPermissionModePill.swift:79-90`.

## Cleanup performed

- `stop_app_sim` on lease-223.
- Killed the isolated daemon (`pkill -f '/tmp/goal3-lancerd daemon'`) — this is **my own isolated
  process**, not the resident production `~/.lancer/bin/lancerd` (verified distinct PIDs
  throughout: mine was `/tmp/goal3-lancerd`, production stayed at
  `/Users/roshansilva/.lancer/bin/lancerd`, untouched).
- `lease_release` on lease-223.
- Left `/tmp/goal3-set-alert-lancerd-state` and `/tmp/goal3-lancerd` on disk (harmless scratch
  state, not under `~/.lancer`) in case anyone wants to re-inspect without rebuilding.
- **Noted, not fully repaired:** while setting simulator screenshot defaults, an XcodeBuildMCP
  `session_set_defaults` call landed on a shared `device-build-phone` profile (created by another
  concurrent session/worktree) instead of my own, stamping my simulator UDID onto its
  `simulatorId`/`simulatorName` fields. That profile's `deviceId` (the field actually used for
  physical-device builds) was untouched. I immediately created and switched to a dedicated
  `goal3-set-alert` profile for the rest of the session to stop further collisions. Flagging this
  for whoever owns the `device-build` worktree — XcodeBuildMCP session-defaults appear to be
  shared/global across concurrent MCP client sessions, not process-isolated, which is a real hazard
  for concurrent agent work on this repo.
