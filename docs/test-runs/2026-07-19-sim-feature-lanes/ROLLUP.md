# 2026-07-19 feature-sweep rollup — serial re-run addendum

**Synthesized:** 2026-07-19 ~18:05 local  
**Serial worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-serial-lanes` · branch `sim/serial-lanes-2026-07-19`  
**Baseline tip:** `origin/master` @ `7c4b1eca` (+ cherry-picked #187 widget commits for L5)  
**Lease:** single Simurgh `lease-242` (iPhone 17 Pro `798BEDDF-…`) for L4→L6→L1→L5; renewed; **released** (`lease-release.json`)  
**Prod pairing:** **intact** (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26:47 throughout)

Status legend: **PASS** / **PARTIAL** / **FAIL** / **MISSING** (unchanged meaning from fan-out rollup).

---

## Serial re-run summary (priority lanes)

| Track | Prior (PR #189) | Serial re-run | Evidence |
|---|---|---|---|
| **L4 Governance** | PARTIAL | **PASS** | [`L4/REPORT.md`](L4/REPORT.md) — Go E2E + Swift 38 + `SweepLaneC4Tests` **TEST SUCCEEDED**; screenshots Policy/Audit/E-stop |
| **L6 Siri** | FAIL (missing xcodeproj) | **PASS** | [`L6/REPORT.md`](L6/REPORT.md) — `xcodegen` first; IntentsKit tests; AppShortcuts discovered; Approve **not** in `autoShortcuts` |
| **L1 Core loop** | MISSING | **PARTIAL** | [`L1/REPORT.md`](L1/REPORT.md) — isolated pair + dispatch-to-thread PASS; reply FAIL (connect race + push-backend 401) |
| **L5 Widgets/LA** | MISSING | **PARTIAL** | [`L5/REPORT.md`](L5/REPORT.md) — #187 cherry-pick; stale TTL + Agents/LA writers PASS; PendingApprovals arrive/resolve FAIL on sim; HS widget chrome skipped |

### Unchanged from fan-out inventory (not re-run this session)

| Track | Status | Notes |
|---|---|---|
| L2 Chat | PARTIAL | Disk-budget hygiene; not in serial priority order |
| L3 Chrome | MISSING | Parked |
| L7 Review | MISSING | Parked |
| L8 Accounts | FAIL | Compile/`PermissionModeSetResult` — parked |
| Vendor free-model smoke | MISSING | Parked |
| Cursor CLI adapter | PARTIAL | PR #190 — needs sensitive-path review |
| Plan matrix | PASS | PR #188 |

---

## Serial method notes

1. Forced-release of orphan fan-out leases (`lease-230`/`lease-231`, dead PIDs) then acquired **one** lease for the whole run.
2. Never bare `lancerd pair` on `~/.lancer` — all pairing under `LANCER_STATE_DIR=/tmp/sweep-C4` (and probes under `/tmp/serial-l4-gov-state`).
3. L6 prior FAIL fixed by `xcodegen generate` before any `xcodebuild`.
4. L5 used tip + cherry-picked #187 widget commits (stale approvals / Agents widget / LA sync).

---

## Ranked next actions (updated)

1. **Owner B1 device re-proof (P0)** — unchanged; sim cannot substitute.  
2. **L1 reply recovery** — pair-first with longer settle; dismiss notification privacy before `liveThread`; or use SweepLaneC4-style UITest with `TEST_RUNNER_*` without terminate/relaunch.  
3. **L5 PendingApprovals writer** — investigate `WidgetSnapshotWriterTests.writerTracksArriveAndResolveSequence` zero-count on iOS sim after #187 cherry-pick; device confirm #185/#187 widgets.
EOF