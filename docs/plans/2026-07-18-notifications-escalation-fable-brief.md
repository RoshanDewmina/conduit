# Fable brief — APNs push + Live Activities escalation

**Prepared:** 2026-07-18, by a Sonnet 5 device-testing session, after several hours of direct
live debugging that did not reach a confirmed fix for either issue. This is an escalation, not
a first attempt — everything already tried is listed so Fable doesn't repeat it.

---

## PASTE THIS

You are Fable 5, orchestrating this session per `docs/ENGINEERING_PROCESS.md`. Read `AGENTS.md`
and `docs/agent-contract.md` first.

Repo: `/Volumes/LancerDev/lancer`. Live device-testing work has been happening in an isolated
worktree at `/Volumes/LancerDev/worktrees/lancer/device-build` (branch
`cursor/desktop-history-and-terminal-3510`, based on `origin/master` tip `69a6f490` plus three
already-merged-and-verified fixes from this same session — mid-turn message queueing, a
`resumeObservedSession` race, and a widget/database App-Group-container bug, all confirmed
working via `XcodeBuildMCP` sim/device builds). Everything below is uncommitted in that worktree.
**This brief covers ONLY the two issues below** — the other three fixes are done, tested, and
out of scope; do not re-touch them.

### Issue 1 — APNs app-closed push still does not arrive, despite a merged fix believed complete

**Original bug** (root-caused and reportedly fixed earlier this session): fired a real approval
escalation via `lancerd agent-hook` with the owner's phone locked — no APNs banner arrived in 4+
minutes; the pending approval only surfaced once the app was manually reopened and re-fetched
over the live relay connection. Root cause traced: `Lancer/LancerApp.swift`'s
`AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` captures the APNs
token and posts `.lancerAPNSTokenReceived`, but nothing forwarded it to the paired daemon —
`SessionFeature/E2ERelayBridge.swift`'s `registerDevice(apnsToken:sessionID:pushBackendURL:)`
existed specifically for this (its own doc comment says so) but had zero call sites anywhere.

**Fix built** (by a background Sonnet subagent that hit its session/quota limit mid-work but
left complete, compiling code before dying): new file
`Packages/LancerKit/Sources/AppFeature/Bridge/DevicePushRegistrationCoordinator.swift` (202
lines) — observes two triggers (a `RelayFleetStore.connectionStates` transition to `.connected`
via `ConnectionStateStore.addObserver`, and the `.lancerAPNSTokenReceived`/
`.lancerLiveActivityTokenReady` notifications) and forwards to
`E2ERelayBridge.registerDevice`/`.registerActivityToken` on every currently-connected machine.
Wired into `AppRoot.swift`'s `init()` (`_devicePushRegistration = State(initialValue:
DevicePushRegistrationCoordinator(fleetStore: fleetStore))`, `devicePushRegistration?.start()`
called in the launch task BEFORE `RelayFleetHydration.hydrate(into: relayFleetStore)`). Daemon
side `daemon/lancerd/e2e_router.go`'s `deviceRegister` handler (line ~627) was independently
read and confirmed already-correct — forwards the APNs token via `postDeviceTokenRegistration`,
no daemon change was needed or made.

**Verification done:** the coordinator compiles clean under the real iOS target (`XcodeBuildMCP
build_sim`/`build_run_device`, not just SPM `swift build` — this file is `#if os(iOS)`-gated,
plain SPM builds silently skip it entirely, a real gotcha hit multiple times this session). 8
unit tests exist in `DevicePushRegistrationCoordinatorTests.swift` covering both trigger
orderings, reconnect re-registration, and no-op cases — but these were only compile-verified,
**never confirmed passing via an actual `test_sim` run** (unlike the other two fixes from this
session, which were). This is the gap that let the fix ship un-live-tested.

**Live result: still broken.** After merging, rebuilding, and installing on the physical device
multiple times (confirmed via fresh `build_run_device` calls and daemon-side "paired with phone"
log lines showing successful relay reconnection every time), `~/.lancer/push-device.json` (the
file the daemon writes on a successful `lancer.device.register`/relay `deviceRegister` message —
see `server.go`'s `savePersistedDevice`) **still does not exist**, and
`~/.lancer/lancerd.stderr.log` contains **zero** lines matching "device registered for push" or
any `deviceRegister` activity, across multiple fresh launches. The daemon's relay pairing itself
works fine every time (approvals still get sent/re-sent correctly over the live relay
WebSocket) — only the push-registration side-channel is silent. Two real test approvals are
currently sitting unresolved in `~/.lancer/queue.json` (ids `8f9c4d76...` and `5d73db3f...`)
that never got approved because no banner ever surfaced, even locked.

**Debugging done, all inconclusive — don't repeat these:**
- Traced the coordinator's full logic by hand — no obvious logic bug found. The two-trigger
  design (cached-token-check-on-start + connection-observer + notification-observer) appears to
  correctly handle both "token arrives before pairing" and "pairing exists before token"
  orderings on paper.
- Ruled out "two separate `RelayFleetStore` instances" — confirmed via `AppRoot.swift`'s
  `init()` that `fleetStore` (passed into the coordinator) and `_relayFleetStore`'s State value
  are the exact same object.
- Confirmed `ConnectionStateStore.addObserver` is genuinely edge-triggered ("Fired only on
  actual state changes" per its own doc comment) and `apply()` fires on the very first
  nil→`.connected` transition, not just later ones — so a late-registered observer missing the
  first connection isn't obviously the failure either, given `devicePushRegistration?.start()`
  runs before `RelayFleetHydration.hydrate()`.
- **The coordinator has zero logging/diagnostic output anywhere** — completely silent, making it
  impossible to tell from device console alone whether `start()` ran, whether the connection
  observer ever fired, whether `apnsTokenHex` ever got set, or whether `sendAPNS`/
  `waitForBridgeActive` were ever reached vs. silently failing an internal guard.
- Started live device console streaming via `xcrun devicectl device process launch --device
  <udid> --console dev.lancer.mobile` — confirmed the app relaunches, but produced nothing
  useful since the coordinator prints nothing.
- Just before this escalation, added two `print("LANCER-DIAG: ...")` statements to
  `Lancer/LancerApp.swift`'s `AppDelegate` (`didRegisterForRemoteNotificationsWithDeviceToken`
  logs token length; `didFailToRegisterForRemoteNotificationsWithError` logs the error) — **this
  is uncommitted and untested, never rebuilt or run.** Reasonable starting point for Fable to
  build on (add matching diagnostics inside `DevicePushRegistrationCoordinator.swift` at every
  guard/branch point) before a fresh device console capture.
- **Untested hypothesis worth checking early:** this is a Debug build via Xcode/XcodeBuildMCP
  device install, not TestFlight/Release. Debug builds typically get APNs tokens valid only for
  Apple's **sandbox** environment; `daemon/lancerd`'s push-backend (Fly `conduit-push.fly.dev`)
  may target **production** APNs only. If so, `deviceRegister` could succeed while the push
  itself is silently rejected for an environment mismatch. Check `Lancer/Lancer.entitlements`'s
  `aps-environment` and whatever push-backend APNs client code exists
  (`daemon/push-backend/`, `server.go`'s `postDeviceTokenRegistration`) for environment match —
  but this doesn't explain the total absence of `push-device.json`/any `deviceRegister` log
  line, which points to registration never being attempted at all, not succeeding-then-failing
  at delivery. Don't let this distract from the more fundamental "is `registerDevice` ever even
  called" question.

### Issue 2 — Live Activities / Dynamic Island never trigger at all: confirmed dead code path, same bug class as the already-fixed widget bug

**Owner's live complaint:** Home Screen widgets show correct data now (separate bug, already
fixed and verified this session), but Dynamic Island / Lock Screen Live Activities showing
"processes running" never appear, ever.

**Root cause, fully traced, high confidence:** `LancerLiveActivityManager.shared.start(...)`
(`Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift:162`) — the only function
that calls `Activity<...>.request(...)` to actually create a Live Activity — has exactly ONE
call site in the entire codebase: `SessionFeature/SessionViewModel.swift:328`.
`SessionViewModel` is never constructed anywhere in production (repo-wide grep for
`SessionViewModel(` finds only its own internal factory method at `SessionViewModel.swift:277`
— never called from `AppRoot.swift`/`WorkspacesView.swift`). This is the exact same bug class
independently discovered earlier this session for the widget bug: production exclusively uses
`RelayFleetStore`/`ShellLiveBridge`/`RelayApprovalIngest`, while `SessionViewModel` and its
siblings `FleetStore`/`ApprovalIngest` (SSH-era types) are dead legacy code nobody migrated off
of when the app moved to the newer relay architecture.

**Not yet fixed.** Needs `LancerLiveActivityManager.shared.start/update/end` calls added to the
REAL production dispatch/approval path — most likely `ShellLiveBridge.swift` (agent-running
state: start on send/dispatch, update as status changes, end on terminal) and/or
`RelayApprovalIngest.swift` (pending-approval count: `updatePendingApprovals(_:highestRisk:)` at
`LiveActivityManager.swift:257` looks purpose-built for this and is currently also unreachable
in production for the same reason). Read `SessionViewModel.swift`'s existing call sites (328
start, 441 end, 595 update) as the reference for correct usage before wiring the same calls into
the real production types.

### What to do

1. **Diagnose Issue 1 first**, with real evidence, not more static reading. Extend the two
   already-added `print` statements in `LancerApp.swift`, add matching ones throughout
   `DevicePushRegistrationCoordinator.swift` at every guard/branch, rebuild via `XcodeBuildMCP
   build_run_device`, and read actual console output (`xcrun devicectl device process launch
   --device <udid> --console <bundleID>`, or an XcodeBuildMCP equivalent if one exists). Don't
   rewrite the coordinator blind — see where in its flow it's actually failing, or confirm it
   isn't even running.
2. Fix whatever the diagnostics reveal, then live-re-prove end to end: phone locked, fire a real
   escalation via `lancerd agent-hook`, confirm an APNs banner actually arrives with working
   Approve/Deny, confirm `~/.lancer/push-device.json` exists and `lancerd.stderr.log` shows a
   `deviceRegister` success line.
3. Fix Issue 2 by wiring `LancerLiveActivityManager` into the real production path, then
   live-re-prove: dispatch a real run, confirm a Live Activity actually appears in Dynamic
   Island/Lock Screen, confirm `updatePendingApprovals` reflects a real count.
4. Use the `lancer-verification-gate` skill as the acceptance bar for both — and this time
   actually run the `#if os(iOS)`-gated test suites via `XcodeBuildMCP test_sim`/`test_device`,
   not just confirm they compile (the exact gap that let Issue 1 ship un-live-tested).
5. Use the `swarm-orchestrator` skill for execution. These two issues are more tightly coupled
   (both flow through `AppRoot`'s launch sequencing and push/relay registration) than a typical
   phased brief — a focused single worktree/session per issue is probably right over heavy
   parallel fan-out; use judgment.
6. This touches `AppRoot.swift`'s launch sequencing and push/relay registration — security/
   relay-adjacent per `AGENTS.md`, full-diff review before merge, never routine auto-merge.

### Constraints

- Don't re-touch the three already-merged-and-verified fixes in the device-build worktree
  (mid-turn queueing, `resumeObservedSession` race, widget/database bug) — done, tested, out of
  scope.
- The two uncommitted `print("LANCER-DIAG: ...")` lines in `Lancer/LancerApp.swift` are a
  legitimate starting point to build on or replace — not leftover cruft to blindly revert.
- Report back with the swarm-orchestrator skill's 5-line digest (merged/in-flight/blocked/next/
  decisions-needed), backed by actual device evidence.
