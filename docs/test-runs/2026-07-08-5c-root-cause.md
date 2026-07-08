# Checkpoint 5c root cause + fix (2026-07-08)

Fixes the failure documented in `docs/test-runs/2026-07-08-tier0-device-proof-results.md`
(steps 6b/7: force-quit + lock-screen Approve/Reject never reached `lancerd`).
Branch: `fix/5c-lockscreen-decision`.

## Root cause

`LancerNotificationDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`
(`Lancer/LancerApp.swift`, previously lines 202–261) never delivered the decision
itself. On `approval.approve` / `approval.reject` it only:

1. Recorded the action into `ApprovalActionBuffer` (an in-memory, `NSLock`-protected
   array — not persisted to disk).
2. Posted `.lancerApprovalAction` to `NotificationCenter`.
3. Called `completionHandler()` immediately.

Actual delivery — `ApprovalRelay.enqueue` → Keychain credential hydration →
`postDecisionToBackend` — only happened in `AppRoot.swift`, gated behind:

- `relayEventModifiers`'s `.onReceive(.lancerApprovalAction)` (`AppRoot.swift:381`),
  which requires a *live subscriber already existing* when the notification posts
  (a SwiftUI view's `.onReceive` only fires for subscribers registered before the
  post — this is exactly the race the code's own "MAJOR-6" comment describes), and
- the cold-launch drain in `AppRoot`'s startup `.task` (`AppRoot.swift:768`,
  `drainPendingApprovalActions`), which requires `AppRoot`'s view body to actually
  run and reach `environment == .ready`.

Both paths depend on `AppRoot`'s `WindowGroup` scene being connected. When the
`approval` category's actions are declared without `.foreground`
(`NotificationsKit/Notifications.swift:329-345`, intentionally — so lock-screen
Approve/Reject doesn't force-launch the UI), and the app process was previously
force-quit, iOS invokes `UNUserNotificationCenterDelegate.didReceive` by relaunching
the process **in the background, without connecting a `WindowGroup` scene**. SwiftUI
apps only build/evaluate `some Scene` bodies for a scene the system actually
connects; a background-only notification-action relaunch never does that here. So:

- `AppRoot`'s `body`, its `.onReceive` modifiers, and its startup `.task` never run.
- `ApprovalActionBuffer.shared.record(...)` still executes (it's a plain static
  call, no scene needed) — but nothing ever calls `.drain()`.
- `completionHandler()` fires immediately, satisfying iOS with no further work
  queued, and the process is free to suspend.
- The buffered decision is lost with the process (in-memory only). `lancerd`'s
  `audit.log` never sees `approve`/`deny`, only the original `escalate`, exactly as
  observed for `f8e24db0` (16:18:46Z, PASS on the phone side / FAIL on the host
  side) and `98e45e0e` (16:54:23Z, same failure for Reject).

This is **not** the 2026-07-04 risk-tier-floor / biometric-decision-gate hardening
blocking the decision on purpose: the test used `--risk medium` (standard tier,
the intended lock-screen-approvable tier per the risk-tier design), the phone-side
long-press → Approve/Reject UI completed normally (`.authenticationRequired` only
requires the device be unlocked, which it already effectively is once you can act
on a lock-screen notification — this is unrelated to the removed in-app
`BiometricGate`/Face ID prompt and was left untouched), and there is no gate in
`LiveActivityPresentation.swift` or elsewhere that intentionally suppresses
delivery for this risk tier. This is a genuine delivery-path bug, not an
intentional block.

## Fix

`LancerNotificationDelegate.didReceive` (`Lancer/LancerApp.swift`) now performs the
decision delivery itself, inline, instead of only buffering it for a scene that may
never connect:

- Kept the `ApprovalActionBuffer.record` + `NotificationCenter` post (still needed
  for the warm/foregrounded-app case, where they drive the live Inbox view model).
- Added a new private `deliverDecision(approvalID:decision:)` that opens its own
  `AppDatabase` (`AppDatabase.openShared()` — GRDB `DatabasePool` supports multiple
  pool instances against the same WAL-mode SQLite file within one process) and
  calls `ApprovalRelay.shared.enqueue(approvalID:decision:db:hostID:"")` — the exact
  same cold-launch-safe path (Keychain credential hydration, SSH-channel-then-
  backend-relay fallback, on-disk redelivery queue) the Live Activity intent path
  already relies on. This path requires no `AppRoot`/`AppEnvironment` and therefore
  no connected scene.
- Wrapped the call in `UIApplication.shared.beginBackgroundTask`/`endBackgroundTask`
  so the process gets extra run time to finish the network POST before `didReceive`
  returns, and only calls `completionHandler()` after `deliverDecision` completes.
- `completionHandler` (a non-`Sendable` closure) is wrapped in a small
  `CompletionHandlerBox: @unchecked Sendable` so it can cross into the
  `Task { @MainActor in ... }` under Swift 6 strict concurrency without a
  region-isolation error — it is invoked exactly once, from wherever the box ends
  up running.

Both the buffered/`NotificationCenter` path (warm app) and the new direct path
(any app state) ultimately call the same `ApprovalRelay.enqueue`, whose DB write is
first-decision-wins (`ApprovalRepository.decide`'s `WHERE decision IS NULL` guard),
so a decision can be applied twice (once via each path, if the app happens to be
foregrounded when the notification action fires) with no double-effect. Fail-closed
behavior is unchanged: `enqueue`/`postDecisionToBackend` never fabricate an approve;
if the credentials aren't hydrated, no channel is attached, and the backend POST
fails, the decision is queued for the next SSH/relay reconnect, and `lancerd`'s
existing 120s auto-deny timeout remains the backstop. No Face ID/biometric gating
or Siri approve intent was added or reintroduced; the risk-tier floor logic is
untouched.

## Files changed

- `Lancer/LancerApp.swift` — `LancerNotificationDelegate.didReceive` now delivers
  approve/reject directly; new `CompletionHandlerBox` helper and
  `deliverDecision(approvalID:decision:)`. Added `import PersistenceKit`.
- `Packages/LancerKit/Tests/LancerKitTests/LockScreenDecisionDeliveryTests.swift`
  (new) — regression test for the engine-level half of the fix.

## Tests

New test: `LockScreenDecisionDeliveryTests.enqueueWithoutLocalRowPostsDecision` —
constructs a fresh `ApprovalRelay` with Keychain-persisted credentials (simulating
a prior warm session, exactly as `ApprovalRelay.persistCredentials` does in
production) and an in-memory `AppDatabase` with **no local row** for the approval
(the force-quit / push-only case: the phone never had a chance to persist the
approval before the decision arrives). Calls `enqueue` directly — the same call
`deliverDecision` now makes — and asserts the decision POST reaches the backend
relay with the correct `approvalId`/`decision`/`sessionId`. This is the exact
scenario that failed on-device for `f8e24db0`/`98e45e0e`.

A second planned test (already-resolved local approval → no re-forward) was
dropped: that branch of `ApprovalRelay.enqueue` calls
`Notifications.shared.clearDeliveredApproval`, which calls
`UNUserNotificationCenter.current()` — this crashes the bare `LancerKitTests`
xctest bundle (`bundleProxyForCurrentProcess is nil`, no host app bundle),
independent of this fix. The row-less path the new test covers is the one that
matters for checkpoint 5c and never reaches that branch.

`LancerApp.swift` is part of the `Lancer` app target (Xcode/XcodeGen), not the
`LancerKit` SwiftPM package, so it has no direct unit-test coverage; the fix's
production code path is exercised through the app-target build succeeding
(the delegate method type-checks and compiles under Swift 6 strict concurrency)
and through `LockScreenDecisionDeliveryTests` covering the exact engine call it
makes.

## Verification (commands run, real output)

### 1. `cd Packages/LancerKit && swift build`

```
Building for debugging...
[Computing dependencies]
[Using on-disk description]
[1 / 4]
[1 / 6] Citadel
[1 / 3] CCryptoBoringSSL
[1 / 4] SessionFeature
Build complete! (1.75 secs.)
```

(Runs on macOS host; `ApprovalRelay.swift` and the new test file are gated
`#if os(iOS)` and compile to effectively nothing here — this only proves no
macOS-host regression. The load-bearing verification is #3 below.)

### 2. Daemon (`daemon/lancerd`)

Not touched — this is a pure iOS-client fix (the decision-delivery hop from
notification action to the daemon, not the daemon itself). No `go test` run
required by the gate; confirmed via `git status`/`git diff` that
`daemon/lancerd/**` has no changes on this branch.

### 3. App-target build — XcodeBuildMCP (`Lancer` scheme, iPhone 17 simulator)

First attempt failed under Swift 6 strict concurrency (`sending 'completionHandler'
risks causing data races`); fixed via the `CompletionHandlerBox` wrapper and
`Task { @MainActor in ... }` restructuring documented above. Final result:

```
{"summary":{"status":"SUCCEEDED","durationMs":126794,"target":"simulator"},
 "diagnostics":{"warnings":[...pre-existing DSChip/ChatTranscriptView type-check-time warnings, unrelated...],"errors":[]}}
```

### 4. `LancerKitTests` — new regression test, isolated

```
-only-testing:LancerKitTests/LockScreenDecisionDeliveryTests
{"summary":{"status":"SUCCEEDED","durationMs":94989,"counts":{"passed":1,"failed":0,"skipped":0}},
 "testCases":[{"test":"enqueue on a cold-launch, row-less approval still posts the decision to the backend","status":"passed","durationMs":129}]}
```

Reproduced green 3 times across the session (54ms / 56ms / 129ms).

### 5. Full `LancerKitTests` suite — pre-existing flakiness, NOT a regression

Running the *entire* `LancerKitTests` scheme (no `-only-testing` filter) is
unreliable in this environment independent of this change. Three consecutive runs
on a clean `git stash` (i.e. **without** any of this fix's changes) gave three
different results:

```
Run A (baseline, stashed): 86 failed / 612 passed
Run B (baseline, stashed): 609 failed / 89 passed   (after popping the stash's
                                                       test file back out — LancerApp.swift
                                                       change still present but irrelevant,
                                                       since it's a different Xcode target)
Run C (same state as B):   618 failed / 80 passed
```

Nearly all of the swing is `Crash: xctest at specialized static
Runner._applyScopingTraits(for:testCase:_:)` — a cascading collateral failure mode
where one test's crash (confirmed independently to include, e.g.,
`Notifications.shared.clearDeliveredApproval` → `UNUserNotificationCenter.current()`
crashing this bare test bundle) takes down the shared xctest process mid-run and
the runner marks every not-yet-executed test in that run as "Crash" too. The
codebase already documents this exact class of problem for another suite
(`LiveActivityContentStateTests.swift:151`: "Swift Testing runs a suite's tests
concurrently by default, which raced these against each other... Serializing
matches how this shared, unswappable state is actually used at runtime"). This is
a pre-existing test-infrastructure limitation of the full suite's concurrent
execution against shared global state (`UserDefaults.standard`, a shared Keychain
migration static, global `URLProtocol` registration, `URLSession.shared`), not
something this branch introduced — confirmed by reproducing wildly different
fail/pass counts with **none** of this fix's changes present.

The correct, actionable verification for this change is #4 (the new test run in
isolation, deterministic and green across repeats) plus #3 (the app target
compiles clean under strict concurrency). A pre-existing, separate problem — the
full `LancerKitTests` suite is not safely parallelizable as currently written — is
real and worth fixing, but out of scope for this checkpoint-5c fix.

## Follow-on (evening 2026-07-08) — content-hash echo + race

#52 closed the "decision never left the phone" gap. Evening re-test then hit
`approvalStore.resolve` **content hash mismatch**: force-quit has no local DB row,
APNs originally omitted `contentHash`, and a warm drain POST could overwrite a
hash-bearing decision. Fix + host-proven PASS (Approve `79137ae4…`, Reject
`461bc3e0…`) documented in
[`2026-07-08-tier0-5c-retest-results.md`](2026-07-08-tier0-5c-retest-results.md).
**D0.2 / checkpoint 5c: PASS.**

## Still open (separate)

- **Full `LancerKitTests` suite flakiness** (see above) is a pre-existing,
  separate problem worth a dedicated fix (likely: run the whole scheme
  `.serialized`, or replace the global-`URLProtocol` test pattern with per-test
  injected `URLSessionConfiguration`s) — flagged here, not fixed in this branch.
- **Push delivery reliability itself** (the `BadDeviceToken` on `api.push.apple.com`
  / sandbox-fallback path noted in the 2026-07-08 device-proof doc, step 6a) is a
  separate, already-known issue from this one; this fix only closes the
  "notification action arrived but the decision never reached the daemon" gap once
  a push has been delivered and its action tapped.
