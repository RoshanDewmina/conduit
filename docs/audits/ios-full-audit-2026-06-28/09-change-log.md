# 09 — Change Log (Phase B implementation)

**Status: IMPLEMENTED on `audit/ios-2026-06-28`** (owner-approved 2026-06-28). All batches below
landed; verification results are recorded honestly, including one test that could not be executed
in this environment (see B2).

Each batch is build- + test-verified before the next. Verification gate per batch:
- XcodeBuildMCP `build_sim` of the **Lancer app target** (catches `#if os(iOS)` code),
- `swift test` in `Packages/LancerKit`, `go test ./...` in `daemon/lancerd`,
- review the full `git diff`; no new warnings.

## Planned batches (proposed order)

| Batch | Findings | Files | Risk |
|---|---|---|---|
| B1 — crash fix | CONC-2 | `SSHTransport/DaemonChannel.swift` (+ test) | Low (one-line guard) |
| B2 — cold-launch reliability | SEC-2 / TEST-01 | `SessionFeature/ApprovalRelay.swift` (+ test) | Low–Med (make hydration async/awaited) |
| B3 — resume coverage | TEST-02 | `SessionFeature/RunControlStore` (+ test) | Low (test + typed error) |
| B4 — concurrency hygiene | CONC-1 | `SessionFeature/SessionViewModel.swift` | Low (store+cancel task) |
| B5 — build/CI + style | BUILD-1, CQ-1, CQ-2, CQ-3, CQ-4 | `.github/workflows/ci.yml`, `SettingsView.swift`, `DSButton.swift`, `AppRoot.swift` | Low |
| B6 — deep-link hardening | SEC-1 | `Lancer/LancerApp.swift` | Low |

Deferred (note only, not in scope): ARCH notification/DI refactors, `AppEnvironment` split, XCUITest
journey build-out, device-based performance pass, BUILD-2 self-host decision.

## Baseline (pre-change, this branch)
App-target `build_sim`: SUCCEEDED, 1 warning (`mainBody` 380ms). `swift test`: 462 / 0 fail. `go test`: pass.

## Implemented batches

### B1 — CONC-2 double-resume crash (Medium)
- **File:** `SSHTransport/DaemonChannel.swift` — `sendRPC` write-failure `catch` now guards
  `if pendingRPC.removeValue(forKey: id) != nil { cont.resume(throwing:) }`, mirroring the
  exactly-once pattern in `handleFrame`/`failPendingRPCs`.
- **Test:** none added. The type has no writer-injection seam (the existing `DaemonChannelTests`
  notes "channel wiring requires a live session"); adding a throwing-writer protocol purely to test
  one guard is a single-use abstraction the audit explicitly cautioned against. Correctness is by
  inspection — the guard makes `removeValue`-returns-non-nil the single resume token across all
  three resume sites.
- **Verify:** app-target `build_sim` SUCCEEDED (compiles `DaemonChannel`, not iOS-gated).
- **Remaining risk:** none meaningful; behaviour-preserving on the non-racing path.

### B2 — SEC-2 cold-launch hydration race (Medium) + TEST-01
- **File:** `SessionFeature/ApprovalRelay.swift` — `hydrateCredentialsIfNeeded()` is now `async`
  and `await`ed at both call sites (`enqueue`, `forwardDecisionOnly`) so the per-session
  `relayToken` is populated *before* `postDecisionToBackend`'s pre-suspension `guard`. Stale
  "this is safe" comment corrected. `init()` widened private→internal for testability.
- **Test:** `Tests/.../ApprovalRelayColdLaunchTests.swift` — seeds an in-memory Keychain, calls
  `forwardDecisionOnly` on a fresh relay, asserts the backend POST carries `Bearer <hydrated>`
  (fails on the old fire-and-forget code).
- **Verify:** **fix** compiled for iOS (app-target `build_sim` SUCCEEDED). **Test NOT EXECUTED** —
  it is `#if os(iOS)` (like the existing `ApprovalRelayBackendTests`), and the package's iOS test
  build is blocked by pre-existing macOS-only code (`HostControlKit/HostServiceClient.swift:60,69`
  uses `homeDirectoryForCurrentUser`, unavailable on iOS). See finding **TEST-INFRA**. The test is
  written to repo convention and will run once that build is unblocked / on a configured dev machine.
- **Remaining risk:** fix verified by compile + inspection; automated execution pending TEST-INFRA.

### B3 — TEST-02 resume runId validation (Medium)
- **Files:** `LancerCore/LancerDProtocol.swift` — added `DispatchResult.startedRunId` (returns the
  runId only when `status=="started"` AND non-empty). `AppFeature/NewChatTabView.swift` — the
  follow-up guard now uses `result.startedRunId`, rejecting an empty-string runId that previously
  slipped past `guard let`.
- **Test:** `Tests/.../DispatchResultStartedRunIdTests.swift` — 5 cases (valid / empty / nil /
  non-started / JSON-decode-empty).
- **Verify:** **PASS — executed.** `swift test --filter DispatchResultStartedRunId` → 5/5 pass
  (LancerCore is platform-agnostic, runs on the macOS host). Full `swift test` exit 0.

### B4 — CONC-1 orphaned timeout task (Low)
- **File:** `SessionFeature/SessionViewModel.swift` — the 3s readiness backstop `Task` is now stored
  in a dedicated `integrationReadyTimeoutTask` and cancelled in `drainIntegrationReadyWaiters`
  (the single chokepoint hit on ready / timeout / teardown). (Could not reuse the existing
  `integrationFallbackTask` — it tracks a different fallback.)
- **Verify:** app-target `build_sim` SUCCEEDED.

### B5 — BUILD-1 + style cleanups
- **`.github/workflows/ci.yml`** (BUILD-1): both Xcode-select steps now prefer `Xcode_27.0.app`
  with the existing 26.x fallback chain (`|| true` keeps CI working if the runner lacks 27).
- **`DesignSystem/Components/DSButton.swift`** (CQ-2): corrected the stale "electric blue" /
  "bg=text" comments — `.primary` and `.accent` both render accent-orange / white.
- **`SettingsFeature/SettingsView.swift`** (CQ-1): `auditRepository != nil { … auditRepository! }`
  → `if let auditRepository`.
- **`AppFeature/AppRoot.swift`** (CQ-4): removed unused `import DiffFeature` — confirmed unused
  (grep clean) and the clean app-target build proves no transitive break.
- **CQ-3 (deferred):** the silent `try?` logging was *not* done — AppRoot has no logging facility,
  and adding `os.Logger` infra to a 2374-line file for an Info-severity item is scope creep. Noted.
- **Verify:** app-target `build_sim` SUCCEEDED; `swift test` exit 0.

### B6 — SEC-1 deep-link hardening (Low)
- **File:** `Lancer/LancerApp.swift` — `onOpenURL` now rejects URLs with extra path segments
  (`guard url.path.isEmpty || url.path == "/"`) before the host switch, so a crafted
  `lancer://auth/<smuggled>` can't reach a future path-dispatched handler. Query/fragment remain
  allowed (the auth callback carries its tokens there).
- **Verify:** app-target `build_sim` SUCCEEDED.

### NOT done (deferred, by design)
- **ARCH-1** (`mainBody` 380ms type-check) — a 165-line restructure of the most critical file;
  deferred as a larger maintainability change, not bundled under the fix batches. The warning is
  pre-existing (now reported at line 313 / 428ms — line shifted by the CQ-4 import removal, ms is
  measurement variance); **no new warning was introduced.**
- ARCH notification/DI refactors, `AppEnvironment` split, XCUITest journey build-out, device perf
  pass, BUILD-2 self-host decision — all noted in 02/06, none in scope.

## Final verification (post-all-batches)
| Gate | Result |
|---|---|
| App-target `build_sim` (iPhone 17 Pro / iOS 27) | ✅ SUCCEEDED, 0 errors, 1 (pre-existing) warning |
| `swift test` (LancerKit, macOS host) | ✅ exit 0 — 462 baseline + B3 (5) all pass |
| `swift test --filter DispatchResultStartedRunId` (B3) | ✅ 5/5 |
| `go test ./...` (lancerd) | ✅ pass (unchanged; daemon untouched) |
| TEST-01 (iOS-gated) | ⚠️ written, compiles-as-pattern, **unrun** — blocked by TEST-INFRA |
| `git diff` review | ✅ 10 source files + 2 new tests; no accidental changes |

## Known limitations / follow-ups
- **TEST-INFRA (new finding):** iOS-gated package tests (`#if os(iOS)` in `LancerKitTests`) do not
  run in CI or via `swift test` (macOS host skips them) and the package's iOS test build fails on
  `HostControlKit`'s macOS-only `homeDirectoryForCurrentUser`. The existing `ApprovalRelayBackendTests`
  is already in this limbo. Fix options: guard the macOS-only HostControlKit code `#if os(macOS)`,
  or split iOS-gated tests into an iOS-buildable test target, then wire it into CI.
- SEC-2's automated regression (TEST-01) and a CONC-2 race test are pending that infra.
