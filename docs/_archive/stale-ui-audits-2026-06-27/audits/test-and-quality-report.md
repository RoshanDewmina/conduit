# Phase 8 — Test & Quality Report

> Every result below was **actually run this audit** (2026-06-23), not inferred from docs.
> Live relay/APNs E2E **not run** (owner: done with those). No fixes applied (audit-only).

## What ran

| Gate | Command | Result | Evidence |
|---|---|---|---|
| LancerKit build (macOS) | `swift build` (Packages/LancerKit) | ✅ exit 0 | bg job brix50qvk |
| App-target build (iOS sim) | XcodeBuildMCP `build_run_sim` (Lancer scheme, iPhone 17 Pro) | ✅ **SUCCEEDED** 20.8 s, 0 warn / 0 err | build_run_sim result |
| LancerKit tests (macOS) | `swift test` (Packages/LancerKit) | ✅ 13/13 in 2 suites | **only platform-agnostic tests** — iOS-gated targets excluded on macOS |
| **LancerKit tests (iOS sim)** | `xcodebuild test -scheme LancerKitTests` | 🟥 **464 tests / 74 suites — 1 FAILED, 463 passed** | log `ioskittests.log:1714` |
| lancerd (Go) | `go test ./...` | ✅ ok (22.8 s) + policy cached | bg job bs05l6n4s |
| push-backend (Go) | `go test ./...` | ✅ ok (0.6 s) | same |
| agent-runner (Go) | `go test ./...` | ✅ ok | same |

## 🟥 The one failing test (real, not flaky)

- **Test:** `LiveActivityContentStateTests.swift:151` — *"lastUpdate encodes as a JSON number (Unix fractional seconds) — ActivityKit push contract."*
- **Assertion:** `abs(asDouble - 1_700_000_000.0) < 0.001` — expects the encoded `lastUpdate` to be a Unix-epoch number.
- **Why it fails (root cause):** the test encodes a `Date` with a **default `JSONEncoder`**, which encodes `Date` as `timeIntervalSinceReferenceDate` (**seconds since 2001-01-01**), not Unix epoch (1970). So a date pinned to Unix `1_700_000_000` encodes as ~`721_692_800`, not `1_700_000_000`. Uses a `fixedDate` → deterministic, **reproducible**, not time-dependent.
- **Significance:** this is a **push-contract test for Live Activity lock-screen updates** (the app-closed approval surface, recently verified C2). Either (a) the Swift `ContentState` Date encoding does not match what `push-backend`/ActivityKit expect (a real interop bug in lock-screen timestamps), or (b) the test's assumption about the default encoder is wrong. **Must be triaged before relying on Live Activity timestamps.** Not fixed here (audit-only).
- **Doc conflict:** KNOWN_ISSUES/CHECKLIST claim "385 tests green." Actual current iOS suite is **464 tests with 1 failure**. The "385 green" figure is stale and was likely never the full iOS-sim run.

## Tooling note (process integrity)
A first attempt to capture the iOS suite piped `xcodebuild` into `grep`; the shell's `grep` is aliased to `ugrep` (via `rtk`), which errored on a `** TEST` regex and silently discarded output. Re-run wrote a full log and parsed with Python. **Lesson:** don't trust a piped-`grep` summary in this environment for pass/fail; capture the raw log.

## Coverage vs the prompt's test list

| Requested | Done? | Note |
|---|---|---|
| Clean build | ✅ | swift build + app-target build |
| Unit tests | ✅ | iOS sim suite (464) + Go (3 modules) |
| Integration tests | ◑ | covered by Go + Swift suites; no separate harness |
| UI tests | ⚠️ not run | `LancerUITests` exist; 4 `TapInjectionProofTests` are XCTSkip'd (assert old tab bar — IA debt). Not executed this run. |
| Static analysis / lint | ◑ | build is 0-warn; Semgrep is a session hook (not re-run here) |
| Runtime smoke / navigation | ✅ | app launched; 53 gallery routes rendered; live boot → Home |
| E2E critical workflows | ⚠️ | dispatch/approve/continue verified in **prior** owner runs (incl. device C2); **not re-run** (relay E2E skipped per owner) |
| Error/recovery, offline/reconnect, permission-denial, empty-data, session-persistence, bg/fg, relaunch | ⚠️ not tested | No automated coverage (KNOWN_ISSUES C4 open). Recommended as a test-debt item, not a redesign blocker. |

## Per-critical-feature

| Workflow | Test type | Result | Runtime verified | Gap | Evidence |
|---|---|---|---|---|---|
| Dispatch agent | unit + prior live | pass (unit) | prior-run | not re-run live | feature-matrix A |
| Approval (in-app) | unit | pass | prior + C2 device | — | inbox-typed.png |
| Approval via **Live Activity** push | unit | 🟥 **FAIL** | C2 passed on device 2026-06-23 | timestamp encoding contract red | this report |
| Continue/follow-up | unit + prior live | pass | prior-run | per-vendor re-verify pending | feature-matrix A |
| Policy engine | Go unit | pass (124) | prior-run | — | go test lancerd |
| Quota guard | unit | pass | prior-run | — | feature-matrix B |
| Relay transport | — | not run | prior-run | skipped per owner | — |

## Verdict
Builds are green; Go backend is green; the iOS suite is **463/464 with one real ActivityKit push-contract failure** that should be triaged (it touches the app-closed approval path). UI tests, reconnect/offline/permission flows, and live E2E remain untested this run (known debt, not redesign blockers).
