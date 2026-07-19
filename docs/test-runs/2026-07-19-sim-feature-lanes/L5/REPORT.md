# L5 — Widgets / Live Activity — PARTIAL (serial re-run)

**When:** 2026-07-19 ~18:00–18:06 local  
**Worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-serial-lanes`  
**Baseline:** `origin/master` @ `7c4b1eca` **+ temporary cherry-pick of #187 widget commits for this lane only** (not committed on this branch — land via PR #187). See `cherry-pick.log`.  
**Lease:** `lease-242` (shared serial)

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Cherry-pick #187 widget fixes onto tip | **DONE** | staged tree; `cherry-pick.log` |
| macOS `swift test` (stale TTL + RunningAgents mapping) | **PASS** | `swift-test-widgets.log` (14 tests) |
| App + `LancerWidgets.appex` sim build | **PASS** | `xcodebuild-build.log` → `** BUILD SUCCEEDED **` |
| `LiveActivitySimSetupUITests` | **PASS** | `xcodebuild-la-sim.log` |
| iOS `LancerKit-Package` — Agents/LA widget suites | **PASS** | `xcodebuild-kit-ios-widgets.log` — suites `Live Activity → AgentStatusWidget snapshot`, `AgentStatusWidget running-agents snapshot writer`, `ApprovalRepository stale pending TTL` |
| iOS PendingApprovals writer arrive/resolve | **FAIL** | `WidgetSnapshotWriterTests.writerTracksArriveAndResolveSequence` — pending count stayed `0` in test suite UserDefaults (`xcodebuild-kit-ios-widgets.log`) |
| Home Screen widget chrome / Lock Screen LA visual | **SKIPPED** (sim limitation) | SpringBoard widget gallery + Island/Lock LA chrome are not reliably XCUITestable; prior device evidence lives on #185/#187 |

## Sim limitations (documented)

- Home Screen widget UI cannot be asserted via XCUITest the same way as in-app surfaces.
- Dynamic Island / Lock Screen Live Activity chrome requires ActivityKit + SpringBoard; unit/snapshot writer tests cover the data path; visual LA proof remains device-oriented (see `docs/test-runs/2026-07-18-live-activity-sim/`).
- `#if os(iOS)` widget suites do **not** run under macOS `swift test` — must use `LancerKit-Package` on an iOS Simulator destination.

## Status: **PARTIAL**
