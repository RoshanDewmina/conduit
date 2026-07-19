# L1 — Core loop — PASS (reply-path fix re-run)

**When:** 2026-07-19 ~18:12–18:25 local  
**Worktree:** `/Volumes/LancerDev/lancer/.worktrees/widget-stale-approvals` @ `fix/l1-reply-path`  
**Lease:** `lease-244` (iPhone 17 Pro `8DED1B25-…`)  
**Isolated daemon:** `LANCER_STATE_DIR=/tmp/l1-reply-fix-state` · pair code `790149`  
**Prod pairing:** **intact** — `~/.lancer/relay-pairing.json` mtime still `2026-07-19 10:26:47`

Prior serial result (PR #192): **PARTIAL** — see git history on `sim/serial-lanes-2026-07-19` for the fail pack (`L1-06`…`L1-10`, notification sheet + “No connected machine”).

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Isolated pair (sim ↔ daemon via relay) | **PASS** | `L1-fix-paired.png` / Trusted Machines “Relay host … connected”; daemon `e2e: paired with phone` |
| Dispatch prompt into live thread | **PASS** | `L1-fix-reply-pong.png` — thread titled with prompt, user bubble present, cwd `target-repo` |
| Agent reply / round-trip | **PASS** | axe label **`PONG`** + “Worked 4s. Proof available in menu.” (`axe-reply-pass.txt`, `L1-fix-reply-pong.png`) |
| Screenshots | **PASS** | `screenshots/L1-fix-*.png` |
| Notification sheet | **PASS** | Absent — `LANCER_SKIP_NOTIFICATION_PROMPT=1` (wired in `AppRoot`) |
| push-backend `/run-start` | **BLOCKED (env-only)** | `push-backend /run-start rejected: HTTP 401` in `isolated-daemon-fix.log` — does **not** block local relay reply |

## Root causes (prior PARTIAL)

1. **Notification permission alert** — `AppRoot.readyRoot` always called `Notifications.shared.requestAuthorization()` (`AppRoot.swift`), which presented the system sheet and blocked HID. UITests already set `LANCER_SKIP_NOTIFICATION_PROMPT=1` but nothing honored it.
2. **Connect race** — three stacked bugs:
   - `DebugSeeder.autoPairRelayIfRequested` ran **after** `markHydrated` + 8s wait (`AppRoot.swift`), while `ShellLiveBridge.waitForConnectedMachine` **fail-fasted** on an empty fleet before auto-pair could add a machine (`ShellLiveBridge.swift`).
   - `LANCER_DESTINATION=liveThread` opened the thread immediately without waiting for a connected machine (`WorkspacesView.swift`) — unlike `terminal`.
   - Harness: `lancerd daemon` started **before** `relay-pairing.json` existed and the pair-watcher did not attach; stale/expired pair codes + relaunch with auto-pair minting a **second** machine ID churned the fleet.
3. **push-backend HTTP 401** — isolated daemon identity is not registered with hosted push-backend secrets. APNs/Live Activity registration and `/run-start` reject with 401; **local E2E relay still delivers the agent reply** (proven this run).

## Fixes landed (`fix/l1-reply-path`)

- Honor `LANCER_SKIP_NOTIFICATION_PROMPT` in DEBUG `AppRoot`.
- Run auto-pair **before** `markHydrated`; skip auto-pair when already connected.
- `waitForConnectedMachine` waits the full timeout when `LANCER_RELAY_PAIR_CODE` is set even if the fleet is empty.
- `liveThread` destination waits up to 45s for a connected machine before presenting.
- Sweep / reconnect / LA dispatch UITests set `LANCER_SKIP_NOTIFICATION_PROMPT=1`.

## Harness notes (sim)

1. `LANCER_STATE_DIR=<isolated>` → `lancerd pair` → **then** `lancerd daemon` (so E2E relay starts with the pairing file present).
2. Launch sim promptly with fresh code: `SIMCTL_CHILD_LANCER_RELAY_PAIR_CODE`, `LANCER_SKIP_NOTIFICATION_PROMPT=1`, `LANCER_DESTINATION=liveThread`, `LANCER_LIVETHREAD_CWD`.
3. Do not treat push-backend 401 as a reply failure on sim.

## Status: **PASS**
