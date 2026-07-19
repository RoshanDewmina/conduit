# 2026-07-19 feature-sweep rollup — serial re-run addendum

**Synthesized:** 2026-07-19 ~18:05 local (serial) · **L1 reply fix ~18:25** · **L5 writer fix ~18:37**  
**Serial worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-serial-lanes` · branch `sim/serial-lanes-2026-07-19`  
**L1 fix worktree:** `/Volumes/LancerDev/lancer/.worktrees/widget-stale-approvals` · branch `fix/l1-reply-path`  
**L5 fix worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-l5-widgets` · branch `fix/l5-pending-approvals-writer-test`  
**Baseline tip:** `origin/master` @ `7c4b1eca` (+ #187 widget commits + #193 L1 cherry-pick on L5 branch)  
**Leases:** serial `lease-242` (released); L1 fix `lease-244`; L5 fix `lease-246`  
**Prod pairing:** **intact** (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26:47 throughout)

Status legend: **PASS** / **PARTIAL** / **FAIL** / **MISSING** (unchanged meaning from fan-out rollup).

---

## Serial re-run summary (priority lanes)

| Track | Prior (PR #189) | Serial re-run | After L1 fix | After L5 fix | Evidence |
|---|---|---|---|---|---|
| **L4 Governance** | PARTIAL | **PASS** | **PASS** | **PASS** | [`L4/REPORT.md`](L4/REPORT.md) — Go E2E + Swift 38 + `SweepLaneC4Tests` **TEST SUCCEEDED**; screenshots Policy/Audit/E-stop |
| **L6 Siri** | FAIL (missing xcodeproj) | **PASS** | **PASS** | **PASS** | [`L6/REPORT.md`](L6/REPORT.md) — `xcodegen` first; IntentsKit tests; AppShortcuts discovered; Approve **not** in `autoShortcuts` |
| **L1 Core loop** | MISSING | **PARTIAL** | **PASS** | **PASS** | [`L1/REPORT.md`](L1/REPORT.md) — assistant **PONG** via isolated relay; push-backend 401 env-only BLOCKED |
| **L5 Widgets/LA** | MISSING | **PARTIAL** | **PARTIAL** | **PASS** | [`L5/REPORT.md`](L5/REPORT.md) — arrive/resolve was stale epoch fixtures vs 10m TTL; fixed; iOS 12/12 + macOS 14 + app build PASS |

### Unchanged from fan-out inventory (not re-run this session)

| Track | Status | Notes |
|---|---|---|
| L2 Chat | PARTIAL | Disk-budget hygiene; not in serial priority order |
| L3 Chrome | MISSING | Parked |
| L7 Review | MISSING | Parked |
| L8 Accounts | FAIL | Compile/`PermissionModeSetResult` — parked |
| Vendor free-model smoke | MISSING | Parked (separate branch has smoke evidence) |
| Cursor CLI adapter | PARTIAL | PR #190 — needs sensitive-path review |
| Plan matrix | PASS | PR #188 |

---

## Serial method notes

1. Forced-release of orphan fan-out leases (`lease-230`/`lease-231`, dead PIDs) then acquired **one** lease for the whole run.
2. Never bare `lancerd pair` on `~/.lancer` — all pairing under isolated `LANCER_STATE_DIR`.
3. L6 prior FAIL fixed by `xcodegen generate` before any `xcodebuild`.
4. L5 used tip + cherry-picked #187 widget commits (stale approvals / Agents widget / LA sync).
5. **L1 reply fix:** honor `LANCER_SKIP_NOTIFICATION_PROMPT`; auto-pair before hydrate mark; wait for connected on `liveThread`; harness order `pair` → `daemon` → fresh-code launch. Local relay reply works despite push-backend 401.
6. **L5 PendingApprovals writer:** test used 1970 `createdAt`; `writeApprovalWidgetSnapshot` → `expireStalePending` (10m TTL) zeroed the count. Fixtures now use wall-clock ages inside TTL.

---

## Ranked next actions (updated)

1. **Owner B1 device re-proof (P0)** — unchanged; sim cannot substitute.  
2. **Owner push-backend secrets (optional)** — isolated-daemon 401 on `/run-start` / token registration is env-only; needed only for APNs/Live Activity push proof, not core reply.  
3. **Device visual confirm** — Home Screen / Island widget chrome still device-oriented (#185/#187).
