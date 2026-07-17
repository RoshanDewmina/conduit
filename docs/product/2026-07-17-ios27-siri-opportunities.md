# iOS 27 Siri / App Intents opportunities for Lancer

**Date:** 2026-07-17
**Status:** Research + idea backlog. Not an implementation plan — feeds into
`docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md` (the live, milestone-based plan this doc
supplements rather than replaces).

**Headline finding:** Lancer is further along on iOS 27 Siri/App Intents than the daily-driver
doc's Phase framing suggests. `StartAgentRunIntent` already uses `LongRunningIntent` /
`CancellableIntent` / `ProgressReportingIntent` unconditionally (PR #167,
`docs/test-runs/2026-07-17-siri-test-workflow.md`), `IndexedEntityQuery` + `SyncableEntity` are
implemented for four entity types, and the always-excluded-on-purpose "approve by voice" gap is
intact. What's genuinely unbuilt: App Schemas domain adoption, view annotations / onscreen
awareness, interactive Live Activity snippets, Foundation Models (on-device summarization /
"approval copilot"), and any live device proof that the deep path actually behaves under Siri
(vs. Shortcuts-app invocation only).

---

## Part 1 — What Apple shipped for iOS 27 Siri / App Intents (WWDC 2026)

Distinguishing **confirmed-shipped API** (developer docs / WWDC session content, usable in
Xcode 27 today) from **announced-only / directional** claims (press recap, no doc/session
backing found).

### Confirmed-shipped (developer.apple.com session content)

**Long-running / background execution — WWDC26 #345, "Discover new capabilities in the App
Intents framework"**
- `LongRunningIntent`: extends an intent past the 30-second execution limit; framework manages a
  background task and represents it as a system Live Activity. Adopt via
  `performBackgroundTask { operation } onCancel: { reason in ... }`.
- `CancellableIntent`: `onCancel(reason:)` handler for graceful cleanup (cancel partial uploads,
  in-flight requests).
- `ProgressReportingIntent`: gives the intent a `Progress` object (`progress.totalUnitCount`,
  `progress.completedUnitCount`, `localizedAdditionalDescription`) that the system surfaces as
  Live Activity/Siri progress. `LongRunningIntent` is declared as
  `protocol LongRunningIntent: ProgressReportingIntent`, so the three usually travel together.
- `ExecutionTargets` / `allowedExecutionTargets`: override system heuristics for which process
  runs an intent (`.main`, `.appIntentsExtension`, `.widgetKitExtension`, or combinations) —
  this is the mechanism Milestone 3 of the existing roadmap needs.
- Background GPU access entitlement for on-device inference/photo processing inside a
  long-running intent.
- Entity/parameter plumbing: `ValueRepresentation` (share structured types across apps, e.g. to
  Maps), `EntityCollection<T>` (pass IDs not resolved entities — perf win for 1000+ item sets),
  `SyncableEntity`/`SyncableEntityIdentifier<Local, Stable>` (entity IDs stable across devices),
  richer native `@Parameter` types (`Duration`, `PersonNameComponents`), `@UnionValue` (one
  parameter, multiple types).

**Siri/Apple Intelligence depth — WWDC26 #343, "Explore advanced App Intents features for Siri
and Apple Intelligence"**
- `ProvidesDialog` with `IntentDialog(full:supporting:)` — separate "read this on voice-only
  devices" vs. "show this with UI" strings.
- Mid-intent clarifying questions via `$parameter.requestValue("...")` inside `perform()`.
- `ShowsSnippetView` — return a custom SwiftUI view as the intent's response (interactive
  snippet), distinct from the plain dialog/result path Lancer's intents use today.
- **Semantic Spotlight indexing**: `CSSearchableIndex.indexAppEntities()` + `IndexedEntityQuery`
  for re-indexing on system request — meaning-based search, not just keyword match. (Lancer
  already conforms four entity types to `IndexedEntityQuery` — see Part 2.)
- `IntentValueQuery` — structured search input → app returns entities, for large/server-side/
  frequently-changing corpora (an alternative to static Spotlight indexing).
- `.system.searchInApp` schema (renamed from `.system.search`) — Siri search re-runs inside the
  app's own search UI.
- **Onscreen awareness / View Annotations**: `.appEntityIdentifier(_:)` on a SwiftUI view (single
  entity), `.appEntityIdentifier(forSelectionType:_:)` on a collection (list of many), and
  `NSUserActivity.appEntityIdentifier` for a single "current" item (e.g. now-playing). Lets Siri
  resolve "pause **this** one" / "the third one" against what's literally on screen.
- **Interaction donations for personalization**: `IntentDonationManager.shared.donate(intent:result:)`
  — donating UI interactions (not just intents) so Siri learns real usage patterns.
- `OwnershipProvidingEntity` — entities declare `.shared`/`.public`/`.unknown` ownership so Siri
  auto-confirms (or doesn't) intents with side effects on shared content.
- Entity identifiers attached to existing system integrations: `UNNotificationContent.appEntityIdentifiers`,
  Now Playing `appEntityIdentifiers` array, AlarmKit `appEntityIdentifier`.

**App Schemas — WWDC26 #240, "Build intelligent Siri experiences with App Schemas"**
- Domains (mail, photos, messages, etc.) are typed contracts between an app and Siri: conforming
  an `@AppEntity` to a schema (`@AppEntity(schema: .calendar.event)`) and an intent to a schema
  intent (`@AppIntent(schema: .audio.addToPlaylist)`) tells Siri the category of content/action
  so it can reason and phrase naturally instead of pattern-matching your custom phrases.
  **No public domain exists for "AI coding agent run / approval" (confirmed by absence in the
  session's domain list: mail, photos, messages, calendar, audio) — Lancer's intents stay
  custom `AppIntent`s, not schema-conformant, until/unless Apple ships a matching domain.** This
  matches the existing roadmap's non-goal ("App Schemas domain adoption without an Apple domain
  that matches agent runs").
- **SiriKit is deprecated** in iOS 27; App Intents is now the only way a third-party app is
  reachable by Siri, with Apple describing a two-to-three-year SiriKit support window.

**Foundation Models framework — WWDC26 #241, "What's new in the Foundation Models framework"**
- Public `LanguageModel` protocol: any provider (on-device Apple model, or a cloud model) can
  conform; `LanguageModelSession` is provider-agnostic.
- **Server-side model routing** through the same Swift API — Apple's on-stage claim is that
  Claude and Gemini are reachable this way for apps that opt in to server routing. (This is the
  vendor's own announcement of third-party interop; independent verification of exact
  availability/terms was not part of this pass — treat as announced-shipped-in-beta, re-check
  before depending on it.)
- **Dynamic Profiles** — swap models/tools/instructions mid-session for multi-step agent-style
  workflows.
- The on-device model itself is rebuilt, gains **vision input** and improved tool-calling.
- Apps under the Small Business threshold (<2M first-time downloads) get free Private Cloud
  Compute access to the next-gen Apple Foundation Models.
- Apple has said the framework will open-source later in the summer (2026) — unverified beyond
  press recap, no session/doc citation found.

**Live Activities / widgets** — narrower and mostly refinement, not new APIs:
- Dynamic Island now shows in landscape too (`isDynamicIslandLimitedInWidth` environment value to
  adapt layout).
- Extra-large / full-screen widgets on Home Screen and Today View.
- No new Live Activity *interaction* API beyond what already existed (App Intent buttons via
  `LiveActivityIntent` — which Lancer's `ApprovalActionIntent` already uses); the WWDC26 #345
  long-running-intent-as-Live-Activity mechanism is the interactive-progress path, not a
  separate widget API.

**Shortcuts app — WWDC26 #310, "What's new in Shortcuts"**
- Natural-language automation authoring: describe an automation in plain English ("send my ETA
  whenever I leave home"), Apple Intelligence assembles the underlying actions —
  built directly on top of whatever App Intents/entities an app already exposes. No new intent
  API for developers; the payoff is automatic for any app with well-typed intents/parameters.
  Automation triggers (time/location/device-connection/notification-content) moved out of a
  separate "Automation" tab into general Shortcuts actions.

**Visual Intelligence** — developer guidance only (no dedicated session found in this pass):
Apple published guidance for defining entities, processing images, returning multiple result
types, and wiring visual results to direct one-tap actions/intents. Not obviously relevant to
Lancer (no image-driven content) — noted for completeness, not pursued below.

### Announced-only / lower confidence (press recap, not corroborated by a session/doc fetch)
- "Siri rebuilt on a 1.2T-parameter Google Gemini model" — third-party press claim (Lushbinary),
  not confirmed by an Apple developer source in this pass.
- Exact commercial terms of Claude/Gemini-via-Foundation-Models routing (pricing, opt-in flow,
  region availability).
- Foundation Models framework open-sourcing timeline.

---

## Part 2 — What Lancer has today (read from code, this session)

All file paths below are relative to the repo root (`/Users/roshansilva/Documents/command-center`,
this worktree at `.worktrees/ios27-ideas`).

**`Lancer/LancerAppShortcuts.swift`** — 9 registered `AppShortcut`s (Agent Status, Pending
Approvals, Pause Run, Stop Run, Deny Approval, Search, Open Conversation, Start Agent Run,
Answer Question [iOS 18+ guarded]). Explicit, load-bearing comment: `ApprovalActionIntent`
(approve/reject) is **deliberately never registered** here — approve stays a visual/Live-Activity
-tap-only action. `AppShortcutsProvider` must live in the `Lancer` app target, not a linked SPM
library, or Xcode's app-intents metadata merge silently drops it (confirmed via build log,
per the file's header comment).

**`Lancer/StartAgentRunIntent.swift` + `StartAgentRunSupport.swift`** — the one voice-dispatchable
intent that starts new work. Already conforms to `LongRunningIntent`, `CancellableIntent`, and
`ProgressReportingIntent` **unconditionally** (deployment target is iOS 27, per the file's own
comment). `performBackgroundTask` reports 5 discrete stages (resolving machine → checking
connection → creating run → dispatching agent → waiting for first state) via `progress
.completedUnitCount`/`localizedAdditionalDescription`; `onCancel` calls
`RunDispatchService.shared.cancelInFlight()`. Confirms machine/agent/workspace/prompt via
`requestConfirmation` before anything runs — the dispatch still flows through the same governed
approval loop as any other run.

**`Lancer/StatusQueryIntents.swift`** — `AgentStatusQueryIntent` (read-only status, plus
per-machine detail), `PendingApprovalsQueryIntent` (local DB read, works cold-launched),
`SearchLancerIntent` / `OpenConversationIntent` (FTS-backed, navigate via
`SiriNavigationDispatch`).

**`Lancer/RunControlIntents.swift`** — `PauseRunIntent` / `StopRunIntent`. Shared
`RunControlSupport.resolve` handles zero/one/many active runs: explicit name wins, sole active
run acts directly, multiple runs trigger the framework's own disambiguation UI/voice prompt
(`IntentParameter.requestDisambiguation`) — never a silent guess. Stop is confirmation-gated
(destructive); pause is not.

**`Lancer/DenyApprovalIntent.swift`** — the **only** Siri-reachable approval decision, and
deliberately safety-reducing only (can stop an action, never let one through). Resolves a named
`ApprovalEntity` or falls back to most-recent-pending; confirms before executing; routes through
`ApprovalRelay.shared.enqueue` (same persist-then-forward path as the Live Activity approve/deny
buttons).

**`Lancer/AnswerQuestionIntent.swift`** (iOS 18+) — voice-answers the latest unanswered
`.question` `ChatArtifact` only. Explicit, permanent doc-comment boundary: never touches
`Approval`/`ApprovalRepository` — answering a question is never conflated with approving an
action, even when a question's options read like a yes/no decision.

**`Lancer/SiriRelevanceCoordinator.swift`** — donates entity-bound intents (`DenyApprovalIntent`,
`Pause`/`StopRunIntent`, `OpenConversationIntent`, `StartAgentRunIntent`) via
`IntentDonationManager` for the current pending-approval / sole-active-run / recent-conversation
/ online-machine, and removes stale donations when that state changes. Also donates
`RelevantEntities` (Spotlight/Siri suggestion surface) for the same snapshot.

**`Lancer/SiriSurfaceBootstrap.swift`** — wires the coordinator's refresh to real
`NotificationCenter` state-change signals already firing in the app (relay connect/status, approval
received/resolved, run status, question pending, chat artifact persisted, Siri's own
open-conversation navigation) — not just app launch. On iOS 18+, also triggers
`SiriEntityIndexer.shared.refreshAll()` for Spotlight.

**`Packages/LancerKit/Sources/IntentsKit/SiriIndexedEntityQuery.swift`** — `ConversationEntityQuery`,
`RunEntityQuery`, `MachineEntityQuery`, `WorkspaceEntityQuery` all conform to iOS-27's
`IndexedEntityQuery` (system-triggered re-index), gated behind `SiriSpotlightSupport.safeEntities`
so any entity whose indexable text looks credential-like is skipped before it ever reaches
Spotlight.

**`Packages/LancerKit/Sources/IntentsKit/SiriSyncableEntities.swift`** (+
`SiriSyncableEntityTests.swift`) — Conversation and Run conform to `SyncableEntity` for
cross-device ID stability; Machine/Approval/Workspace deliberately do not (see that file's
comments).

**`Packages/LancerKit/Sources/SessionFeature/ApprovalActionIntent.swift`** — the Live-Activity-tap
approve/reject intent (`LiveActivityIntent`, not registered with Siri). `authenticationPolicy`
requires system authentication for approve when risk is unknown or ≥`.high`; reject is always
`.alwaysAllowed` (safety-reducing). Routes through the same `ApprovalRelay.enqueue`.

**Live Activity** (`Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift`, 342
lines) — one Activity per session (not per host), push-token-driven updates while backgrounded,
push-to-start token so the backend can start an Activity via APNs with the app fully closed,
`frequentPushesEnabled` observed and reported to the backend for throttling. `ContentState`
carries `pendingApprovalRisk` (0–3) so the widget can style high/critical differently. This
predates and is independent of the iOS-27 `LongRunningIntent`-as-Live-Activity mechanism from
Part 1 — the roadmap flags these as needing one coherent "who owns this Activity" story
(Milestone 4), and this session did not find evidence that reconciliation has happened yet.

**Not found in the codebase:** any `FoundationModels`/`SystemLanguageModel`/`LanguageModel`
usage (Milestone 7 "Approval Copilot" is planned, not started); any `allowedExecutionTargets` or
`.appEntityIdentifier`/`AppEntityAnnotatable` view annotation (Milestone 3, not started); any
`AppIntentsTesting` test target (Milestone 2, not started); any App Schema (`@AppEntity(schema:)`
/ `@AppIntent(schema:)`) conformance (consistent with the roadmap's explicit non-goal, since no
matching Apple domain exists).

**Existing plan already covers this ground in depth**:
`docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md` (Milestones 0–7, "Explicit non-goals"
section already rules out voice-approve, biometric approval gates, App Schema misuse, and
fine-tuned on-device adapters). `docs/test-runs/2026-07-17-siri-test-workflow.md` (today's date)
is the live device test ladder for the 9 shortcuts + the deep `StartAgentRunIntent` path, and
notes explicitly: **the deep iOS-27 path has never been proven with live Siri voice on a
physical device** — only Shortcuts-app invocation and code-level correctness are verified so far.

---

## Part 3 — How other dev-tool / productivity apps use App Intents (patterns worth borrowing)

From the WWDC26 sample apps referenced above (CosmoTunes, UnicornChat, CometCal) and general
App Intents practice surfaced in this research pass:

1. **Interactive snippet as the "what happened" surface.** Instead of only a spoken dialog,
   return a custom SwiftUI view (`ShowsSnippetView`) from a status/query intent — e.g. a
   calendar app shows the actual event card, not just "You have a meeting at 3." Lancer's status
   intents (`AgentStatusQueryIntent`, `PendingApprovalsQueryIntent`) currently return
   dialog-only.
2. **NSUserActivity for "the current thing," view annotations for "the list of things."** Media
   apps mark now-playing via `NSUserActivity.appEntityIdentifier`; list-heavy apps annotate whole
   collections (`appEntityIdentifier(forSelectionType:)`) so "pause **this one**" resolves
   against what's on screen without a spoken name.
3. **Search stays yours.** `.system.searchInApp` lets Siri's search UI hand off into the app's
   own search screen rather than trying to render results itself — useful for any app (like
   Lancer) with a richer native search/filter UX than a generic list.
4. **Donate the interaction, not just the intent.** `IntentDonationManager.donate(intent:result:)`
   after a *manual* UI action (not just a Siri-driven one) is how these apps get Siri's
   personalization to learn real usage patterns, not just synthetic donations.
5. **Ownership gates auto-confirmation.** Apps with shared/collaborative entities (calendar
   events with other attendees) implement `OwnershipProvidingEntity` so Siri knows an action
   needs confirmation because it affects other people — a pattern with an interesting analogue
   for Lancer (a run dispatched on a machine other collaborators might also use, if multi-user
   ever becomes real — not urgent today).

---

## Part 4 — Ideas, ranked by usefulness-to-effort

Ranked against the daily-driver definition
(`docs/product/2026-07-10-lancer-daily-driver-definition.md`): the JTBD is "keep agent work
moving while away from the desk, and trust what happened while I wasn't looking," and the
product principle is **governance is the substance, hands-free is the surface** — Siri/App
Intents work is core identity, not a nicety, but must never create a path around the approval
gate. Every idea below was checked against the one hard security invariant: **no
Siri-triggerable approve**.

### Tier A — small, closes gaps in what's already built

**A1. Prove the deep path live on a physical device (S, no new API).**
What: literally execute `docs/test-runs/2026-07-17-siri-test-workflow.md` Steps 3–4 end-to-end
with real voice and a real dispatched run, phone locked. Which API: none new — this validates
`LongRunningIntent`/`CancellableIntent`/`ProgressReportingIntent` that's already shipped in code.
User moment: this is the entire "wedge headline" the daily-driver doc calls out — if it doesn't
actually work live, nothing else in this doc matters. Security: none — pure verification.
**This should happen before any other idea in this list**, because every "Tier B/C" idea builds
on the assumption that the LongRunningIntent path is proven, not just compiled.

**A2. Richer spoken/visual status via `IntentDialog(full:supporting:)` and a status snippet (S).**
What: `AgentStatusQueryIntent`/`PendingApprovalsQueryIntent` currently return one plain string.
Split into `full` (what a HomePod/voice-only context reads) vs. `supporting` (what an iPhone
shows with the response), and add a `ShowsSnippetView` card for pending approvals — title, risk
color, host — so "are any approvals waiting" on the phone shows the same visual language as the
in-app approval card, not just a sentence. Which API: `ProvidesDialog(full:supporting:)`,
`ShowsSnippetView` (WWDC26 #343). Moment: this is the literal "what did my agent just finish /
what's waiting" glance the owner wants without opening the app — and it's the product's own
stated principle ("visual-first... prefer glanceable visual state... over text logs"). Security:
read-only, no new surface.

**A3. View annotations on the run list / approval list (M).**
What: annotate the Workspaces run rows and approval cards with `.appEntityIdentifier(for
SelectionType:)` so "pause this one" / "deny that one" while looking at the list resolves
against the visible item, not just spoken names or "the sole active run." Which API: View
Annotations (`appEntityIdentifier`, WWDC26 #343) — this is exactly Milestone 3 in the existing
roadmap, unstarted. Moment: closes the gap between "I'm looking at three runs" and today's
behavior (disambiguation prompt asks which one by name). Security: annotates existing
safety-reducing intents only (pause/stop/deny) — never approve.

**A4. `allowedExecutionTargets` + AppIntentsTesting regression suite (M).**
What: Milestone 2+3 from the existing roadmap — lock down which process runs which intent
(`.widgetKitExtension` for `ApprovalActionIntent`, `.main` for Siri-only intents) and add an
automated assertion that compiled App Shortcuts metadata contains exactly 9 intents and **never**
`ApprovalActionIntent`. Which API: `ExecutionTargets`/`allowedExecutionTargets`,
`AppIntentsTesting` (WWDC26 #345). Moment: not a user-facing feature — it's the regression gate
that keeps the one hard security invariant enforced by CI instead of by doc-comment discipline
alone. Security: this *is* the security control — makes "no voice-approve" machine-checked.

### Tier B — medium effort, meaningfully strengthens the core loop

**B1. Foundation Models "approval brief" — on-device summarization of what's pending (M).**
What: on opening the app (or as a Live-Activity subtitle), run a local `LanguageModelSession`
over the pending approvals + recent run diffs to produce one plain-English sentence — "Codex
wants to run `rm -rf build/` in `lancer-web`; 2 other approvals waiting, one high-risk." Purely
advisory text next to the existing approval card; **zero code path from the model's output to a
decision** — this is Milestone 7 in the existing roadmap, already scoped correctly ("UI card
beside approval — zero path to set approval outcome... never wire Copilot to auto-approve").
Which API: `LanguageModel`/`LanguageModelSession`/`@Generable` (Foundation Models framework,
WWDC26 #241), on-device only (no server routing needed here — nothing in a pending approval
should leave the device for this). Moment: directly serves "let me trust what happened while I
wasn't looking" — a fast read of *why* something is waiting, not just *that* something is
waiting. Security: must render as advisory-only; the model must never be able to submit a
decision, and Lancer's `dispatch.go`/policy content-hash chain must remain the sole audit trail
(the model output is never itself logged as the approval reason).

**B2. Interactive Live Activity via `LongRunningIntent`-as-Activity for dispatched runs (M).**
What: today `LancerLiveActivityManager` renders its own hand-rolled Activity; the iOS 27
mechanism from A1 means a `LongRunningIntent`'s progress can *also* drive a system-managed Live
Activity automatically. Reconcile per the existing roadmap's Milestone 4 note ("avoid duplicate/
conflicting activities — pick one owner story") rather than adding a second, competing Activity.
Which API: `LongRunningIntent` progress → system Live Activity (WWDC26 #345). Moment: "phone
stays in pocket while the agent works" — the exact moment named in this task's brief. Security:
none new — this is presentation-layer reconciliation of an already-approved, already-dispatched
run.

**B3. Spotlight semantic search for conversations, tuned for the actual daily-driver query shape (S/M).**
What: Lancer already indexes `ConversationEntity`/`RunEntity`/`MachineEntity`/`WorkspaceEntity`
via `IndexedEntityQuery`. The gap is `IntentValueQuery` for cases the static index doesn't cover
well (very large or frequently-changing conversation history) and confirming semantic (not just
keyword) match quality on real usage — e.g. "that thing about the auth middleware" should find a
conversation whose title doesn't contain those words. Which API: `IntentValueQuery`, semantic
Spotlight indexing (WWDC26 #343). Moment: "what did my agent do last week on the billing repo" —
a real daily-driver recall need once conversation volume grows past what a manual scroll handles.
Security: read-only.

**B4. Automation triggers via natural-language Shortcuts (arrive home → status brief) (S, mostly free).**
What: because iOS 27's Shortcuts can assemble automations from plain English over any app's
existing App Intents, Lancer doesn't need new API to enable "when I get home, tell me if
anything's waiting in Lancer" — it needs `PendingApprovalsQueryIntent`/`AgentStatusQueryIntent`
to be well-typed and discoverable (already true) and, ideally, one first-run prompt or Settings
row that surfaces this as a suggested automation (Apple doesn't script that part; Lancer would
have to prompt the user toward Shortcuts itself, or ship a bundled `.shortcut` file). Which API:
none new for Lancer — leverages iOS 27 Shortcuts NL authoring (WWDC26 #310) on top of existing
intents. Moment: closes the loop for a user who forgets to check status; matches "keep it moving
without reaching for the laptop." Security: read-only status brief only.

### Tier C — larger, more speculative, or gated on product/Apple decisions

**C1. Multi-turn conversational Siri for run steering ("tell it to also update the tests") (L).**
What: use mid-intent clarifying questions (`$parameter.requestValue`) and richer dialog to let a
single Siri conversation refine an in-flight `StartAgentRunIntent` (e.g. Siri asks a follow-up if
the prompt seems underspecified) rather than a one-shot dictation. Which API: mid-intent
`requestValue`, richer `IntentDialog` (WWDC26 #343). Moment: reduces the "open the app to fix a
vague voice prompt" tax. Effort/risk: conversational UX design work, and care that a "steer"
follow-up never becomes an implicit new dispatch without the existing confirm step. Judge: nice,
not core — the existing confirm-before-dispatch flow already covers the safety case; this is
polish on top of B/A items, do after A/B land and are dogfooded.

**C2. App Schema domain adoption — deferred, correctly, until Apple ships one that fits (—).**
What: nothing to do. Confirmed in Part 1: no public domain matches "AI coding agent run /
approval" (the closest domains — mail, calendar, audio, messages — don't fit). Re-check this
list each WWDC; adopting a schema when one exists is worth revisiting because domain-conformant
intents get materially better Siri phrasing/understanding for free. Not actionable today.

**C3. Cloud-model routing (Claude/Gemini via `LanguageModel` protocol) for anything beyond B1 (L,
defer).** What: the announced third-party model routing could, in principle, let a more capable
model draft a longer written brief than the on-device model manages. Explicitly **not**
recommended now: (a) routes potentially-sensitive command/diff content off-device for a
"nice-to-have" summary, when B1's on-device-only version already serves the actual JTBD; (b) the
commercial/terms details are unverified per Part 1's confidence note. Only reconsider if B1 in
production proves the on-device model's summaries are too shallow to be useful, and only with an
explicit data-handling review.

**C4. Visual Intelligence integration — not pursued.** No image-driven content in Lancer's model
(runs, approvals, conversations are all text/structured data); the developer guidance found in
Part 1 is about photo/image entity search, which doesn't map to Lancer's domain. Listed only to
close the loop on the brief's ask.

---

## Recommended next step

Given the daily-driver doc's own gating ("the iOS-27-gated deep layer... ships day-one at GA as
the launch story," GA ≈ Sept 14 2026) and today's finding that the deep layer is *coded* but
*unverified live*: **A1 (live device proof) first**, then **A2 + A4** (cheap polish + the
regression gate that makes the security invariant machine-enforced) before GA, with **B1
(on-device approval brief)** as the standout "why Lancer, not a remote chat window" feature to
prioritize once A-tier is solid — it's the one idea here that directly manifests the product's
own stated differentiation ("governed... surface is the deepest iOS-native integration").

---

## Sources

- [Discover new capabilities in the App Intents framework — WWDC26 #345](https://developer.apple.com/videos/play/wwdc2026/345/)
- [Explore advanced App Intents features for Siri and Apple Intelligence — WWDC26 #343](https://developer.apple.com/videos/play/wwdc2026/343/)
- [Build intelligent Siri experiences with App Schemas — WWDC26 #240](https://developer.apple.com/videos/play/wwdc2026/240/)
- [What's new in the Foundation Models framework — WWDC26 #241](https://developer.apple.com/videos/play/wwdc2026/241/)
- [What's new in Shortcuts — WWDC26 #310](https://developer.apple.com/videos/play/wwdc2026/310/)
- [Code-along: Make your app available to Siri — WWDC26 #344](https://developer.apple.com/videos/play/wwdc2026/344/)
- [Announcing Apple's next big step for Siri and iPhone — WWDC26 #121](https://developer.apple.com/videos/play/wwdc2026/121/)
- [App Intents | Apple Developer Documentation](https://developer.apple.com/documentation/appintents)
- [WWDC26 Apple Intelligence guide — Apple Developer](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [Apple aids app development with new intelligence frameworks and advanced tools — Apple Newsroom](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/)
- [App Intents are Limited to Thirty Seconds: Extend Execution as Live Activity with LongRunningIntent — Matthew Cassinelli](https://matthewcassinelli.com/app-intents-thirty-second-limit-extend-execution-live-activity-longrunningintent/)
- [WWDC26 Sessions: Discover new capabilities in the App Intents framework — Matthew Cassinelli](https://matthewcassinelli.com/wwdc26-sessions-new-capabilities-app-intents-framework/)
- [App Intents in iOS 27: Background, Sync, Spotlight — Blake Crosley](https://blakecrosley.com/blog/app-intents-ios-27-background-execution)
- [App Schemas: Make Your App Available to Siri — Blake Crosley](https://blakecrosley.com/blog/app-schemas-siri-ios-27)
- [App Intents 2.0 in iOS 26: Visual Intelligence and Snippets — Blake Crosley](https://blakecrosley.com/blog/app-intents-2-ios-26-additions)
- [Apple Retires SiriKit for App Intents in iOS 27 — SoftwareSeni](https://www.softwareseni.com/why-apple-is-retiring-sirikit-and-what-app-intents-means-for-developers/)
- [Apple Foundation Models Opens to Claude at WWDC 2026 — Vibe Coder Blog](https://blog.vibecoder.me/apple-foundation-models-claude-swift-wwdc-2026)
- [Bringing the latest Gemini models to Apple developers — Google blog](https://blog.google/innovation-and-ai/technology/developers-tools/bringing-gemini-models-to-apple-developers/)
- [Apple Foundation Models Framework: 2026 Swift Guide — Lushbinary](https://lushbinary.com/blog/apple-foundation-models-framework-swift-guide/)
- [WWDC 2026: iOS 27, New Siri & Dev Tools — Lushbinary](https://lushbinary.com/blog/wwdc-2026-announcements-ios-27-siri-developer-guide/)
- [iOS 27 App Intents and AI agents: a developer strategy — eCorpIT](https://ecorpit.com/ios-27-app-store-ai-agents-app-intents-developer-strategy-2026/)
- [Shortcuts in iOS 27 Will Build Automations From Plain English — All Things How](https://allthings.how/shortcuts-in-ios-27-will-build-automations-from-plain-english/)
- [The best iOS 27 feature is an AI update to the app nobody uses — Macworld](https://www.macworld.com/article/3175443/ios-27-shortcuts-apple-intelligence-natural-language-update.html)
- [Apple will let you build workflows using AI in its new Shortcuts app — TechCrunch](https://techcrunch.com/2026/06/08/apple-will-let-you-build-workflows-using-ai-in-its-new-shortcuts-app/)

### In-repo sources used
- `docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md`
- `docs/test-runs/2026-07-17-siri-test-workflow.md`
- `docs/product/2026-07-10-lancer-daily-driver-definition.md`
- `Lancer/LancerAppShortcuts.swift`, `Lancer/StartAgentRunIntent.swift`,
  `Lancer/StartAgentRunSupport.swift`, `Lancer/StatusQueryIntents.swift`,
  `Lancer/RunControlIntents.swift`, `Lancer/DenyApprovalIntent.swift`,
  `Lancer/AnswerQuestionIntent.swift`, `Lancer/SiriRelevanceCoordinator.swift`,
  `Lancer/SiriSurfaceBootstrap.swift`
- `Packages/LancerKit/Sources/IntentsKit/SiriIndexedEntityQuery.swift`,
  `Packages/LancerKit/Sources/IntentsKit/SiriSyncableEntities.swift`
- `Packages/LancerKit/Sources/SessionFeature/ApprovalActionIntent.swift`,
  `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift`
- `git log --oneline --all` (Siri/iOS27 commit history, e.g. `2c3187da`, `bc562ed8`,
  `fc0debdd`, `3847cba7`, `9d8d79a5`)
