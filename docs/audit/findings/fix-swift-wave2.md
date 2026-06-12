# Fix — Swift Wave 2 (Governed Approvals v1) — reliability majors

Branch: `feat/governed-approvals` · Worktree: `governed-approvals-audit`
Scope: Swift sources only. `daemon/**`, `project.yml`, and `fix-swift-wave1.md` untouched.
Builds on wave-1 (B1/B2/B3/B4 + warnings + B13 BiometricGate already done).

NOTE: a prior wave-2 worker had already implemented several majors in source
(AppRoot/ApprovalRelay/SessionViewModel/AppDatabase) without ticking the boxes.
This pass verified those and completed the genuinely-missing ones.

Status legend: [ ] todo · [x] done · [~] partial/blocked

## Reliability majors
- [x] M4 re-arm approval ingest (DaemonChannel/ApprovalIngest) after SSH reconnect — already implemented; verified.
- [x] M5 dead/non-writable channel falls back to relay (respond throws on nil writer) — core done in wave-1; closed residual global-inbox path.
- [x] M6 buffer/replay cold-launch banner approval (ConduitApp ↔ AppRoot) — implemented this pass.
- [x] M7 persist + rehydrate blastRadius/question/choices/answeredChoice — migration pre-existed; wired encode/decode this pass.
- [x] M8 unify device-id source (sessionID == relay sessionId) — implemented this pass.
- [x] M9 exactly-once decision delivery across relay POST + SSH drain — already implemented; verified + tested.
- [x] M10 TUI escalation guard `.submitted`-only — already implemented; verified.
- [x] M11 gate startup/agent-resume on unifiedIntegrationReady via awaitUnifiedShellReady() — already implemented; verified.
- [x] M12 nil unifiedShell on reconnect so shell rebuilds — already implemented; verified.
- [x] M14 LiveActivityManager.updatePendingApprovals preserve pendingApprovalID — implemented this pass.
- [x] M15 persist watch decisions to local DB — already implemented; verified.

## Verification (run once at end)
- [x] `swift build` (no new warnings from our code) — see results below.
- [x] `swift test` — see results below.

---

## Change log (filled as items complete)

- **M4** (verified) `SessionViewModel.attemptReconnect` now `closeUnifiedShell()` + `openUnifiedShell()` + `onReconnected?()`; `reconnect()` also calls `onReconnected?()`. `AppRoot.startSession` wires `vm.onReconnected` to stop the old `DaemonChannel`/`ApprovalIngest`, build fresh ones, `FleetStore.rearm(slotID:channel:ingest:)`, `channel.start()`, re-`registerDevice`, `ApprovalRelay.setChannel`, `ingest.start()`. Approvals keep flowing post-reconnect. No change needed.
- **M5** `SSHTransport/DaemonChannel.respond`/`registerDevice` already throw `DaemonChannelError.notRunning` on a nil writer (wave-1), and `ApprovalRelay.forwardDecisionOnly` catches the throw and falls back to the backend relay + SSH-drain queue. Closed the one residual silent-drop: `AppFeature/AppRoot.swift` `configureGlobalInbox` global-inbox `onDecision` previously did `try? channel.respond` (swallow) and only relayed when `channel == nil`. Now it tries the owning slot's channel and, on a thrown/dead channel, falls through to `ApprovalRelay.shared.forwardDecisionOnly` (relay fallback) instead of dropping the decision.
- **M6** `NotificationsKit/Notifications.swift`: added `PendingApprovalAction` + `ApprovalActionBuffer` (thread-safe, `@unchecked Sendable`). `Conduit/ConduitApp.swift` `ConduitNotificationDelegate.didReceive` now `ApprovalActionBuffer.shared.record(...)` for approve/reject *before* the (cold-launch-racy) `NotificationCenter.post`. `AppFeature/AppRoot.swift`: new `drainPendingApprovalActions(env:)` applies buffered actions durably via `ApprovalRelay.shared.enqueue` (persist + forward, first-decision-wins idempotent); drained at launch in `readyRoot`'s `.task` (after `configureCloudServices`) and again on each `.conduitApprovalAction` receipt so the buffer never accumulates. A killed-app banner Approve/Reject is no longer dropped.
- **M7** Migration `v8` (blast_radius/question/choices/answered_choice columns) pre-existed in `AppDatabase`. Wired the missing model round-trip in `PersistenceKit/ApprovalRepository.swift`: `Approval.encode(to:)` now writes `blast_radius` (JSON `ApprovalBlastRadius`), `question`, `choices` (JSON `[String]`), `answered_choice`; `Approval.init(row:)` decodes them (nil/malformed → nil, no row failure). The governance banner / ask-question UI now survives the `observe()` DB re-read.
- **M8** New `ConduitCore/DeviceIdentity.swift`: one persisted-once session id (`DeviceIdentity.sessionID(defaults:)`), no `identifierForVendor` boot-window divergence. Replaced all three divergent `identifierForVendor ?? UUID()` sites: `AppRoot.configureCloudServices` (relay configureBackend), `AppRoot.startSession` (`deviceSessionID` → registerDevice + relay), and `ConduitApp.didRegisterForRemoteNotificationsWithDeviceToken` (APNs register). The relay decision POST `sessionId` is now guaranteed == the `registerDevice` `sessionID` (B2 backend token-lookup key).
- **M9** (verified + tested) `ApprovalRelay.forwardDecisionOnly` is the single forwarding chokepoint: tries the live channel; on throw posts to the backend relay; only queues for SSH drain when `postDecisionToBackend` returns `false` (non-2xx / missing token). `enqueue`/inbox/watch fire forwarding only when `repository.decide` returned `changed == true` (first-decision-wins), so a decision is applied/forwarded exactly once across both transports. Added tests for the first-decision-wins gate + wire-value stability + relay body sessionId.
- **M10** (verified) `SessionViewModel.onBlockBytes` escalation guard is `block.state == .submitted` only (no `.promptEditing` disjunct). No change needed.
- **M11** (verified) `awaitUnifiedShellReady()` + `unifiedIntegrationReady` exist; `runStartupCommandIfAny`/`attemptAgentResume` `await awaitUnifiedShellReady()` before sending; readiness is marked on first OSC 133 prompt and after the bootstrap+clear injection, with a 3 s timeout backstop. No change needed.
- **M12** (verified) `attemptReconnect` calls `closeUnifiedShell()` (which nils `unifiedShell`/`unifiedBridge`/`unifiedBlockID` and re-gates readiness) before `openUnifiedShell()`, so reconnect rebuilds the shell. No change needed.
- **M14** `SessionFeature/LiveActivityManager.updatePendingApprovals` now carries `pendingApprovalID` (`count > 0 ? base.pendingApprovalID : nil`) so the Live Activity / Dynamic Island Approve/Reject buttons are not stripped when an approval is pending.
- **M15** (verified) `AppRoot.startSession` watch `onDecision` calls `approvalRepo.decide(id:)` first (first-decision-wins), clears the delivered banner, audits, and `forwardDecisionOnly` — only when the row actually changed. Watch decisions are now durable + idempotent. No change needed.

## Tests added
- `Tests/ConduitKitTests/ApprovalReliabilityWave2Tests.swift`:
  - M7: governance-context round-trip (blastRadius/question/choices/answeredChoice) + nil-when-absent.
  - M8: `DeviceIdentity.sessionID` stability + honors pre-seeded value.
  - M9: first-decision-wins gate; decision wire-value stability; (iOS-only) relay body sessionId == register id.
