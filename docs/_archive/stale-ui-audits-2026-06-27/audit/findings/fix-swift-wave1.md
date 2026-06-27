# Fix — Swift Wave 1 (Governed Approvals v1)

Branch: `feat/governed-approvals` · Worktree: `governed-approvals-audit`
Scope: Swift sources + `project.yml` + widget/watch targets. `daemon/**` untouched.

Status legend: [ ] todo · [x] done · [~] partial/blocked

## PRIORITY 1 — Blockers + submission + warnings
- [x] B4-17 project.yml: add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`
- [x] B4-18 project.yml: reconcile version (CFBundleShortVersionString ← MARKETING_VERSION, pick 1.0.0)
- [x] M16 project.yml: `ENABLE_APP_INTENTS_METADATA_EXTRACTION: YES` for App-Intent target(s)
- [x] W19/W20 DaemonChannel.swift:36,40 — await on non-async
- [x] W21 OnboardingView.swift:334 — await on non-async
- [x] W22 ShortcutBarEditor.swift:14 — body type-check >300ms; break up expression
- [x] W23 AppRoot.swift:839 — weak vs implicit-strong capture of agentStore
- [x] B1 AppRoot.startSession + SessionView — TOFU first-connect hang; present host-key prompt + `.disconnected` overlay/back
- [x] B3 ApprovalRepository.decide — isPending guard + clear delivered notifications + Live Activity
- [x] B2 (Swift) DaemonChannel + ApprovalRelay — parse/store `relayToken`; send Bearer; check HTTP response; fail-safe

## PRIORITY 2 — reliability majors
- [ ] M4 re-arm approval ingest on SSH reconnect
- [ ] M5 dead-but-attached channel falls back to relay (respond throws on nil writer)
- [ ] M6 buffer/replay cold-launch banner approval
- [ ] M7 persist + rehydrate blastRadius/question/choices
- [ ] M8 unify device-id source
- [ ] M9 exactly-once decision delivery across relay + SSH
- [ ] M10 TUI escalation guard `.submitted`-only
- [ ] M11 gate startup/agent-resume on unifiedIntegrationReady
- [ ] M12 nil unifiedShell on reconnect
- [ ] B13 BiometricGate: never silently succeed on `.biometryLockout`
- [ ] M14 LiveActivityManager.updatePendingApprovals preserve pendingApprovalID
- [ ] M15 persist watch decisions to local DB

## Verification (run once at end)
- [ ] `swift build` (no new warnings from our code)
- [ ] `swift test` (baseline 331 tests / 54 suites)
- [ ] `xcodegen generate` + `build_sim` (0 warnings / 0 errors)

---

## Change log (filled as items complete)

- **B4-17** `project.yml` Lancer `info.properties`: added `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` (dictation purpose strings) — prevents first-mic-tap crash + review rejection.
- **B4-18** `project.yml`: `MARKETING_VERSION` `0.1.0`→`1.0.0` on all 5 targets; added `CFBundleShortVersionString: $(MARKETING_VERSION)` + `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` to every target's `info.properties` so versions are no longer hardcoded `1.0`/`1` by XcodeGen.
- **M16** `project.yml` `settings.base`: `ENABLE_APP_INTENTS_METADATA_EXTRACTION` `NO`→`YES` so App-Intent (Approve/Reject) metadata bundle generates for app + iOS widget/live-activity extensions.
- **W19/W20** `SSHTransport/DaemonChannel.swift` `start()`: dropped redundant `await` on same-actor `handleFrame`/`failPendingRPCs` (Task inherits actor isolation).
- **W21** `OnboardingFeature/OnboardingView.swift:~334`: dropped `await` on `nonisolated registerCategories()`.
- **W22** `SettingsFeature/ShortcutBarEditor.swift`: split `body` into `activeSection`/`availableSection`/`resetSection` + `keyRow`/`sectionHeader` helpers to drop the >300ms type-check.
- **W23** `AppFeature/AppRoot.swift` `startSession`: replaced `[weak agentStore]` with an explicit local strong ref `agentStoreRef` (app-lifetime store, no cycle) so usage records aren't silently dropped and the implicit-strong-capture warning clears.
- **B1** TOFU first-connect hang. The host-key confirm `.sheet` lived on `readyRoot`, which cannot present over the `SessionView` fullScreenCover → permanent "Connecting…". Fix: present the prompt from INSIDE `SessionView` via a self-contained `SessionHostKeyConfirmSheet` (so SessionFeature needn't pull WorkspacesFeature into the LiveActivity widget), removed the dead sheet from `readyRoot`; added a `.disconnected` phase to `SSHConnectPhase` + handling in `SessionView.onChange(of: vm.status)` (shows a dismissible overlay only when there's no pending host-key, so reject/cancel/failed connects reveal the Back button instead of hanging). Production TOFU preserved — connect only proceeds on explicit **Trust & Connect**.
- **B3** First-decision-wins. `ApprovalRepository.decide` now `UPDATE … WHERE id=? AND decision IS NULL` and returns `Bool` (changed); added `exists(id:)`. `Notifications.clearDeliveredApproval(id:)` removes the delivered/pending banner for a resolved gate. `LiveInboxViewModel.decide` guards on `isPending`, only fires `onDecision` + clears the banner when the row actually changed (Live Activity/badge follow the `observe()` re-emit). `ApprovalRelay.enqueue` drops an already-resolved gate (exists && !changed) but still forwards when there's no local row (cold-launch).
- **B2** Relay decision auth. `DaemonChannel.registerDevice` now goes through `sendRPC`, parses + stores `result.relayToken` (back-compat with legacy `"ok"`), exposes `currentRelayToken`. `ApprovalRelay` stores the token (via `setChannel` refresh + explicit `setRelayToken`), sends `Authorization: Bearer <relayToken>` on `POST /approval/decision`, and now checks the HTTP status — returns delivered/`false` so callers only queue for SSH re-drain when the backend POST failed (fail-safe on missing token / non-2xx; supports M9 near-exactly-once). `AppRoot.startSession` wires the handshake token into the relay.
