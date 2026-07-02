# 09 — Recommended roadmap

> Organized by phase, referencing the ranked items in `08-feature-opportunity-ranking.md`. Each
> item includes a user story, technical approach, likely-affected files, dependencies, acceptance
> criteria, required tests, and a relative complexity estimate (S/M/L/XL).

## Immediate fixes

These are cheap, unblock later work, or fix something currently silently broken. Do these before
anything else in this roadmap.

### Resolve the iOS 26.0 vs. 27.0 deployment-target drift (#16)
- **User story:** as a developer relying on `docs/agent-contract.md`'s claim that iOS 27-only APIs
  need no `#available` gating, I need that claim to actually be true.
- **Technical approach:** decide — raise `IPHONEOS_DEPLOYMENT_TARGET` in `project.yml` and
  `.iOS(.v27)` in `Package.swift` to match the docs, or correct the docs to say 26.0. This audit
  recommends raising the target, since it unblocks #8 (AppIntentsTesting) and #12 (semantic
  search) at effectively zero migration cost (Xcode 27/iOS 27 SDK is already the local toolchain).
- **Files:** `project.yml` (7 deployment-target lines), `Packages/LancerKit/Package.swift:19`,
  `docs/agent-contract.md:28` (if the docs-correction path is chosen instead).
- **Dependencies:** none.
- **Acceptance criteria:** `project.yml` and `Package.swift` deployment targets match what
  `docs/agent-contract.md`/`ARCHITECTURE.md` claim; app-target Xcode build stays green.
- **Tests:** existing test suite must stay green; no new tests needed for the target bump itself.
- **Complexity:** S.

### Fix deep-link routing for auth/billing callbacks (#20)
- **User story:** as a user completing an account sign-in or billing purchase via a browser
  redirect, I need the app to actually receive and act on the resulting deep link.
- **Technical approach:** fix `onOpenURL`'s path-rejection logic in `Lancer/LancerApp.swift:69` to
  accept the exact non-empty paths `AccountClient.swift:316` and `daemon/push-backend/billing.go:304`
  emit (`lancer://auth/callback`, `lancer://billing/complete`).
- **Files:** `Lancer/LancerApp.swift`.
- **Dependencies:** none.
- **Acceptance criteria:** a real auth/billing deep link opens and completes the flow, verified via
  `AccountSessionTests.swift` (extend the existing URL-generation/completion test to also assert
  app-side routing, per `02`'s confirmed test gap).
- **Tests:** extend `AccountSessionTests.swift`.
- **Complexity:** S.

## Phase 1 — foundational platform work (trust boundary + Live Activity correctness)

The plan's own framing is correct: the strongest first move is hardening the approval trust
boundary, not adding Siri surface area. These items should land before any Phase 2 user-facing
feature.

### Approval content-hash binding (#1)
- **User story:** as a user, when I approve a request, I need certainty that what I approve is
  exactly what executes — not a stale or substituted command.
- **Technical approach:** daemon computes `approvalHash = SHA-256(canonicalize(command || args ||
  cwd || diffContent || toolInputJSON))` at pending-approval creation; phone renders and echoes it
  back in the decision message; daemon re-verifies before executing, refusing on mismatch. HMAC
  with the existing E2E session key for defense in depth.
- **Files:** `daemon/lancerd/approval.go`, `daemon/lancerd/dispatch.go`,
  `Packages/LancerKit/Sources/LancerCore/Approval.swift`,
  `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift`, `daemon/push-backend/decisions.go`.
- **Dependencies:** none.
- **Acceptance criteria:** a decision with a mismatched/stale hash is refused and re-requests
  approval instead of executing; a matching hash executes normally with no added latency.
- **Tests:** new daemon Go test asserting hash mismatch → refusal; new Swift test asserting the
  decision payload always carries a hash matching the currently-displayed approval.
- **Complexity:** M.

### Risk-tiered fail-closed no-client policy (#2)
- **User story:** as a user, if my phone is unreachable, I need destructive actions to wait for me,
  not auto-approve.
- **Technical approach:** reuse the existing blast-radius/policy-preset classification; only
  low-risk/reversible kinds keep the 8-second grace-then-auto-approve; high/critical kinds fail
  closed (hold/deny) on no-client.
- **Files:** `daemon/lancerd/server.go` (`handleHookWithNotify`, the `noClientGrace` path),
  `daemon/lancerd/policy/evaluate.go`.
- **Dependencies:** none.
- **Acceptance criteria:** a no-client scenario with a high-risk pending action holds/denies, not
  auto-approves; a no-client scenario with a low-risk action still auto-approves after the grace
  period (preserving existing UX for the genuinely-safe case).
- **Tests:** extend the existing `TestApprovalNeverAutoDeniesReachableClient`-style test coverage
  with a new no-client, high-risk-kind test asserting it does NOT auto-approve.
- **Complexity:** M.

### E2E relay replay resistance (#3)
- **User story:** as a user, I need a captured/replayed encrypted frame to be unable to re-trigger
  a dispatch or run-control action.
- **Technical approach:** monotonic sequence number inside the encrypted envelope (not
  relay-visible), small in-memory replay cache per session+generation on the daemon side, reject
  non-strictly-increasing sequences. Bind the sequence into the same HMAC as the content hash
  from the item above.
- **Files:** `daemon/lancerd/e2e_crypto.go`, `daemon/lancerd/e2e_router.go`,
  `Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift` (extends the existing
  `connectGeneration` counter pattern).
- **Dependencies:** none, but naturally sequenced after the content-hash item since both touch the
  same envelope.
- **Acceptance criteria:** a duplicated/replayed encrypted frame is silently dropped, not
  processed twice; a legitimate reconnect (new generation) is unaffected.
- **Tests:** new daemon Go test replaying a captured frame and asserting it's rejected; extend
  existing `E2ERelayClient` connect-generation tests.
- **Complexity:** M.

### Fix Live Activity lifecycle + relay-only token registration + push-to-start (#4, #5, #6)
- **User story:** as a user with the app fully closed, I need my Live Activity to keep updating via
  push, matching what `ARCHITECTURE.md` already claims.
- **Technical approach:** remove the `.end()`-on-background call in `AppRoot.swift:338`; keep the
  `Activity` reference and register its push token over the relay path (not just the APNs device
  token); add a `push-backend` sender for `event: "start"` payloads following the (medium-confidence,
  verify-before-shipping) payload shape in `04-live-activities-and-dynamic-island.md`.
- **Files:** `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`,
  `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`,
  `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift`,
  `daemon/push-backend/liveactivity.go`, `daemon/push-backend/main.go`.
- **Dependencies:** none for the `.end()` fix; token registration and push-to-start naturally
  follow it (no point registering a token for a lifecycle that immediately ends the activity).
- **Acceptance criteria:** backgrounding the app during an active relay-dispatched run does NOT end
  the Live Activity; a push update while backgrounded correctly updates the Lock Screen/Dynamic
  Island; a cold push-to-start correctly begins a new Live Activity with the app fully closed.
  **Must be verified on a physical device**, per `05-device-hub-testing-plan.md` — this is exactly
  the kind of claim that's previously been "code-verified" but not "visually confirmed."
- **Tests:** app-target build green; physical-device pass per `05`'s backgrounding/relaunching
  test row; no automated test can substitute for the device verification here.
- **Complexity:** L (spans app, widget extension, and backend).

### Risk level in Live Activity content state (#7)
- **User story:** as a user, I need to visually distinguish a routine approval from a
  high/critical-risk one at a glance on my Lock Screen.
- **Technical approach:** add `riskLevel` to the content-state schema; redact/summarize full
  command/diff content above a configurable threshold per HIG privacy guidance
  (`04-live-activities-and-dynamic-island.md`).
- **Files:** `LancerLiveActivityWidget/LancerLiveActivityWidget.swift`, the shared
  `ActivityAttributes.ContentState` type, `LiveActivityManager.swift`.
- **Dependencies:** should land alongside #4 (same content-state schema surface).
- **Acceptance criteria:** a high/critical approval's Live Activity visually differs (redacted
  detail, distinct styling) from a routine one; `RenderPreview` states updated to cover both.
- **Tests:** extend the existing 7 `#Preview` states with risk-tiered variants; visual
  confirmation via `RenderPreview` and a physical-device pass.
- **Complexity:** M.

## Phase 2 — high-value user features

### AppIntentsTesting adoption (#8)
- **User story:** as a developer, I need the exact bug class that shipped twice in production
  (registration gap, runtime crash) to be caught by CI, not live testing.
- **Technical approach:** compiled-metadata assertion test (autoShortcuts contains exactly the 5
  intended entries) + real runtime-execution test for each of the 5 Siri-only intents, run through
  the real `AppIntentsTesting` stack.
- **Files:** new test target/file under `LancerUITests` or a new `AppIntentsTests` bundle.
- **Dependencies:** iOS 27 deployment target (Immediate fix above) — the framework itself is
  27.0-gated.
- **Acceptance criteria:** the test suite fails if `AppShortcutsProvider` is ever moved back to a
  shared library, or if an intent is compiled into two binaries again.
- **Tests:** this item IS the test work.
- **Complexity:** M.

### `AppEntity` model for runs/approvals/machines/conversations (#9, #10)
- **User story:** as a user, I need Siri to correctly disambiguate "pause the run" or "deny that
  approval" when I have multiple active runs or paired machines.
- **Technical approach:** `RunEntity`/`ApprovalEntity` as `EntityStringQuery` (volatile, resolved
  fresh each time — matches their short-lived nature); `MachineEntity`/`ConversationEntity` as
  `IndexedEntity` (durable, low-churn, indexable). Fix `DenyLatestApprovalIntent` to take a proper
  `ApprovalEntity` parameter instead of "always newest," fixing the empty-`hostID` audit bug too.
- **Files:** new entity types in `Lancer/` (app target, per the confirmed multi-target constraint
  from `03`), `Lancer/DenyLatestApprovalIntent.swift`, `Lancer/RunControlIntents.swift`,
  `Packages/LancerKit/Sources/SessionFeature/ActiveRunRegistry.swift`.
- **Dependencies:** none for the entity model itself (works at the current deployment target);
  `IndexedEntity` for durable entities is iOS 18+, already satisfied.
- **Acceptance criteria:** with 2 concurrent runs, "pause my Codex run" correctly resolves to the
  right one; `DenyLatestApprovalIntent` audit records carry a correct `hostId`.
- **Tests:** `AppIntentsTesting` runtime-execution tests covering multi-run/multi-machine
  disambiguation.
- **Complexity:** L.

### Device Hub regression matrix formalization (#14)
- **User story:** as a developer, I need the multi-config test matrix in `05` to run as a standing
  process, not be rediscovered live each time (as multi-machine name collision and the
  backgrounding lifecycle bug both were).
- **Technical approach:** turn `05-device-hub-testing-plan.md`'s matrix into a checklist run before
  any release touching Live Activity lifecycle, relay pairing/machine identity, Siri intents, or
  accessibility-affecting design-system primitives — per that file's own "Regression process"
  section.
- **Files:** none (process work); optionally a new `docs/` checklist file if the owner wants it
  tracked as a durable artifact.
- **Dependencies:** none.
- **Acceptance criteria:** the matrix is actually run (not just documented) before the next release
  touching any of the four trigger areas above.
- **Tests:** N/A — this item defines the test process itself.
- **Complexity:** S (formalization) but ongoing (recurring execution cost).

### App Attest for device-binding flows (#15)
- **User story:** as the platform operator, I need device-binding to have a hardware-attested
  identity signal, not just a QR-secret exchange.
- **Technical approach:** adopt `DCAppAttestService` scoped narrowly to account/device-binding
  registration — not per-approval (App Attest proves the app/device is genuine, not that a
  specific approval matches specific content; that's the content-hash item's job).
- **Files:** `daemon/push-backend/device_bindings.go`, a new iOS-side App Attest client.
- **Dependencies:** physical-device-only testing (App Attest doesn't work in Simulator).
- **Acceptance criteria:** device binding includes a verified App Attest assertion; binding fails
  closed if attestation fails.
- **Tests:** integration test on physical device only (documented limitation, not a gap to fix).
- **Complexity:** M.

### Widget snapshot freshness for relay chat (#21)
- **User story:** as a user with the Home Screen widget added, I need it to reflect my actual
  active relay session, not stale legacy-SSH state.
- **Technical approach:** wire the relay-dispatch path (`NewChatTabView.swift`) to update the same
  app-group snapshot the widget reads, alongside the existing SSH-path writer.
- **Files:** `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`,
  `LancerWidget/LancerStatusWidget.swift`.
- **Dependencies:** none.
- **Acceptance criteria:** a relay-dispatched run updates the widget within one timeline reload.
- **Tests:** new WidgetKit provider test asserting a relay-sourced snapshot renders correctly.
- **Complexity:** M.

## Phase 3 — experimental differentiation

### Approval Copilot, evidence-retrieval-first (#13)
- **User story:** as a user reviewing a pending approval, I want a plain-language explanation and
  risk flag before I decide, without that explanation ever being able to decide for me.
- **Technical approach:** start with the most production-ready piece per `06` — `Tool`-based local
  evidence retrieval (`PastPolicyDecisionTool`, `HostRiskHistoryTool`, `DiffContextTool` over the
  existing GRDB store) plus `@Generable`-typed `RiskVerdict` output, on-device
  `SystemLanguageModel` only for the first prototype (defer PCC escalation and image/screenshot
  input to a second iteration once latency is measured on-device).
- **Files:** new `SessionFeature` module for the Copilot session/tools; UI card alongside (never
  replacing) `DSApprovalBanner`/`InboxApprovalCard`.
- **Dependencies:** none for the on-device-only first cut; PCC escalation and `Attachment`
  (screenshot) support need iOS 27 (already true after the Immediate-fix target raise).
- **Acceptance criteria:** a `RiskVerdict` renders next to every pending approval; the Copilot's
  output has zero code path that can set an approval's outcome; failure (model unavailable, timeout)
  degrades to "no Copilot opinion," never blocks the human decision.
- **Tests:** build a small eval corpus from the daemon's existing hash-chained audit log (real
  historical approve/deny decisions); grade the Copilot's verdict against the human's actual
  decision before shipping any prompt/schema change.
- **Complexity:** L.

### App Schemas + semantic search prototype (#12)
- **User story:** as a user, I want to find "that run where the tests failed last week" via system
  Spotlight, not just in-app search.
- **Technical approach:** `IndexedEntityQuery`/`CSSearchableIndexDescription`/`SearchableItemAttribute`
  over the `MachineEntity`/`ConversationEntity` durable-entity model from Phase 2.
- **Files:** extends the Phase 2 entity types with indexing conformance.
- **Dependencies:** iOS 27 deployment target (Immediate fix); Phase 2's entity model.
- **Acceptance criteria:** a system Spotlight search for a machine/conversation name surfaces the
  Lancer result.
- **Tests:** `AppIntentsTesting`'s `spotlightQuery` assertion.
- **Complexity:** M-L.

### View Annotations for on-screen run/approval disambiguation (#18)
- **User story:** as a user looking at a list of pending approvals, I want to say "deny that one"
  and have Siri resolve which row I mean.
- **Technical approach:** `.appEntityIdentifier()` on approval/run list rows.
- **Files:** `InboxApprovalCard.swift`, `FleetView.swift`.
- **Dependencies:** Phase 2's entity model; the SwiftUI modifier's exact minimum OS needs direct
  verification before committing (flagged medium-confidence in `03`).
- **Acceptance criteria:** on-screen disambiguation resolves correctly in a live test.
- **Tests:** `AppIntentsTesting`'s `viewAnnotations()` assertion.
- **Complexity:** M.

## Phase 3 (later) — deferred until Phase 1/2 risk-gating groundwork lands

### Watch Smart Stack presence (#19)
Deferred until #4/#7 (Live Activity lifecycle + risk-gating) land — no point adding an ungated
approve surface on a third device before the first two are correct. Complexity: M.

## Deferred / rejected work

Per `08-feature-opportunity-ranking.md`: SwiftData migration (#23), Core AI/MLX custom classifier
before the simpler approach is evaluated (#22), third-party cloud model routing before conforming
packages ship (#24), broad voice-approve expansion (#25), App Schemas domain adoption absent a
confirmed fit (#11), and `IntentAuthenticationPolicy`/Face-ID gating for approvals (#17) —
**rejected for V1 by explicit owner decision, 2026-07-02**, not merely deferred. No source changes
were needed for this rejection; `BiometricGate.swift` remains unchanged, still serving the
unrelated (V2-scope, currently unwired) legacy SSH key-unlock path.
