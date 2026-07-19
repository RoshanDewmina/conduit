# L5 — Widgets / Live Activity — PASS (PendingApprovals writer re-proof)

**When:** 2026-07-19 ~18:29–18:37 local  
**Worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-l5-widgets`  
**Branch:** `fix/l5-pending-approvals-writer-test`  
**Baseline tip:** `#187` (`fix/siri-sim-and-aesthetics` @ `960ee943`) **+ cherry-pick `#193`** (`81503814` → `66ad26ce`) **+ test fix**  
**Lease:** `lease-246` (iPhone 17 Pro `47BDCC01-…`)  
**Prod pairing:** intact (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26:47)

## Root cause (prior PARTIAL)

`WidgetSnapshotWriterTests.writerTracksArriveAndResolveSequence` used
`createdAt: Date(timeIntervalSince1970: 1_000 / 2_000)` (1970). After the
stale-approvals fix (`expireStalePending` inside `writeApprovalWidgetSnapshot`,
10m TTL), those rows were immediately marked `.expired`, so the App Group
pending count stayed `0` and `decide` returned `false` (already decided).

This was a **test bug**, not a product/sim limitation. TTL suites in the same
file already used wall-clock timestamps and were PASS on the prior serial run.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Tip includes #187 aesthetics + #193 L1 | **DONE** | branch `fix/l5-pending-approvals-writer-test` |
| Fix arrive/resolve fixtures to within TTL | **DONE** | `WidgetSnapshotWriterTests.swift` (`now -120s` / `now -60s`) |
| macOS `swift test` (stale TTL + RunningAgents mapping) | **PASS** | `swift-test-widgets.log` — 14 tests |
| App + `LancerWidgets.appex` sim build | **PASS** | `xcodebuild-build.log` → `** BUILD SUCCEEDED **` |
| iOS `LancerKit-Package` widget suites | **PASS** | `xcodebuild-kit-ios-widgets.log` — **12 tests / 4 suites**, including arrive→resolve |
| Home Screen widget chrome / Lock Screen LA visual | **SKIPPED** (sim limitation) | SpringBoard gallery + Island/Lock chrome not reliably XCUITestable; device evidence on #185/#187 |

### iOS suites that passed (this re-proof)

- `PendingApprovalsWidget snapshot writer — arrive/resolve sequence` (incl. arrive→resolve + TTL sweeps)
- `ApprovalRepository stale pending TTL`
- `AgentStatusWidget running-agents snapshot writer`
- `Live Activity → AgentStatusWidget snapshot`

## Sim limitations (unchanged, documented)

- Home Screen widget UI cannot be asserted via XCUITest the same way as in-app surfaces.
- Dynamic Island / Lock Screen Live Activity chrome requires ActivityKit + SpringBoard; unit/snapshot writer tests cover the data path; visual LA proof remains device-oriented.
- `#if os(iOS)` widget suites do **not** run under macOS `swift test` — must use `LancerKit-Package` on an iOS Simulator destination.

## Status: **PASS**
