# Tier 0 / 5c current-tip re-proof — D0.2 lock-screen (2026-07-09)

**Purpose:** Fresh Layer 0 close on what we actually install today. Evening 2026-07-08 PASS on `732071a7` is **historical** — see [`2026-07-08-tier0-5c-retest-results.md`](2026-07-08-tier0-5c-retest-results.md). This file is the only path to declare Layer 0 **CLOSED**.

**Prior evidence (do not re-derive):**
- Checklist: [`2026-07-07-tier0-owner-checklist.md`](2026-07-07-tier0-owner-checklist.md)
- Morning FAIL: [`2026-07-08-tier0-device-proof-results.md`](2026-07-08-tier0-device-proof-results.md)
- Root cause: [`2026-07-08-5c-root-cause.md`](2026-07-08-5c-root-cause.md)
- Evening PASS: [`2026-07-08-tier0-5c-retest-results.md`](2026-07-08-tier0-5c-retest-results.md)
- Procedure: [`docs/LIVE_LOOP_RUNBOOK.md`](../LIVE_LOOP_RUNBOOK.md) Phases 1–2, 5b, **5c**

**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**Relay:** `wss://conduit-push-y4wpy6zeva-ts.a.run.app`  
**Pass bar:** host `~/.lancer/audit.log` shows `approve` / `deny` for the exact `approvalId`; hook unblocks. Never PASS from phone UX alone.

---

## Build identity (verbatim)

Recorded at Part B start (2026-07-09):

```text
git rev-parse HEAD:
  b18f519db0a37c3fd5f7bf54e3117444c8d3c147

git status --short:
 M Packages/LancerKit/Sources/AppFeature/AppRoot.swift
 M Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorAppShell.swift
 M Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorSettingsView.swift
 M Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorShellLiveBridge.swift
 M Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorTrustedMachinesView.swift
 M Packages/LancerKit/Sources/AppFeature/RelayFleetStore.swift
 M Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift
 M Packages/LancerKit/Sources/SSHTransport/RelayMachineMigration.swift
 M docs/LIVE_LOOP_RUNBOOK.md
 M docs/PUBLISH_READINESS_CHECKLIST.md
 M docs/STATUS_LEDGER.md
?? Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorShellLaunchSeam.swift
?? Packages/LancerKit/Tests/LancerKitTests/CursorShellLaunchSeamTests.swift
?? docs/test-runs/2026-07-09-slice1-sim-smoke/
?? docs/test-runs/2026-07-09-tier0-device-proof-results.md

git log -1 --oneline:
  b18f519d fix(pairing): surface Remove and stop ghost machines blocking Connect
```

**Dirty tree note:** WIP on `feat/chat-overhaul-w0a` left untouched (read-only for product code). Doc write-set + this results file are the only intentional edits for Layer 0 close.

**Host preflight (agent):**
- `dev.lancer.lancerd` launchd: **running** (pid 770)
- socket: `~/.lancer/lancerd.sock` present
- `lancerd version`: `0.1.0-dev`
- relay `/health`: **200**
- audit tail last action (pre-run): `conversation-append-launched` `hi hi` @ `2026-07-09T15:42:33Z`

**Install note:** Physical-device reinstall can wipe pairing — owner must approve before `install_app_device` / delete+reinstall. Pair once; do not rotate codes mid-run.

---

## Verdict

| Gate | Result |
|------|--------|
| Checkpoint **5c** (lock-screen Approve) | **PENDING** |
| Force-quit + lock-screen **Reject** | **PENDING** |
| **D0.2** (physical-device governed loop last gate) | **PENDING** |
| **Layer 0 CLOSED** | **NO** — Part B Done-bar not green |

---

## Trial evidence

### Approve (force-quit + lock)

| Field | Value |
|-------|-------|
| **approvalId** | |
| escalate | |
| **approve** | |
| hook | |
| notes | |

### Reject (force-quit + lock)

| Field | Value |
|-------|-------|
| **approvalId** | |
| escalate | |
| **deny** | |
| hook | |
| notes | |

---

## Session log

| Time | Step | Result | Evidence |
|------|------|--------|----------|
| | Part A doc reconciliation | DONE | checklist / runbook / ledger status lines |
| | Build identity recorded | DONE | tip `b18f519d` + dirty tree listed above |
| | Host preflight | DONE | lancerd running; relay `/health` 200 |
| ~12:09 | Accidental `lancerd pair` (meant status) | recovered | Host rotated **`527271` → `025359`**; owner re-paired |
| 12:11:38 | Phone paired on `025359` | DONE | `e2e: paired with phone (code: 025359)` |
| ~12:15 | Device build (Debug-iphoneos) | DONE | XcodeBuildMCP `build_device` SUCCEEDED (~42s) |
| ~12:16 | Install + launch `LANCER_CURSOR_SHELL_LIVE=1` | DONE | installed; pid 18395; re-pair log `12:16:41` on `025359` |
| | Step 1 — chat connect/dispatch | IN PROGRESS | Owner taps; agent watches audit/stderr |
| | Later — in-app approve → 5c | PENDING | |

### Pairing incident (agent error — do not repeat)

Agent ran `~/.lancer/bin/lancerd pair status` expecting a status subcommand; CLI treated it as `pair` and **replaced** the live relay pairing:

```text
lancerd: REPLACING existing relay pairing (code 527271 -> 025359) — phones paired to the old code are orphaned and must re-pair
Pairing code: 025359
Relay: wss://conduit-push-y4wpy6zeva-ts.a.run.app
```

Per brief: pair once; if pairing blocks the run, **STOP for owner** (no pairing-UI edits, no further code rotation).
