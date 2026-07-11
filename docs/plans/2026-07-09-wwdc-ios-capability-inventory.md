# WWDC iOS Capability Inventory for Lancer (iOS 27 all-in)

**Date:** 2026-07-09  
**Decision:** Owner chose **raise deployment target to iOS 27** (option C) and go all-in on WWDC26 + prior useful APIs for seamless Siri / App Intents / system integration.  
**Scope:** Agent-control / away-mode / Siri / Live Activity / Spotlight / Apple Intelligence — not every UIKit trivia.  
**Companion docs:** [`2026-07-09-siri-ios27-all-in-roadmap.md`](2026-07-09-siri-ios27-all-in-roadmap.md) · [`2026-07-09-wwdc-research-Status.md`](2026-07-09-wwdc-research-Status.md)

## How to read this inventory

| Column | Meaning |
|---|---|
| **Status** | **Shipped** = production path exists and is wired. **Partial** = real code exists but incomplete, gated, or inert until target/wiring. **Not started** = no production adoption. |
| **Priority** | **P0** = do first on the iOS-27 all-in track. **P1** = next wave for seamless Siri/away-mode. **P2** = valuable differentiator. **Defer** = later or reject for V1. |
| **Min OS** | After the target raise to 27.0, `#available` is only needed for APIs that remain *above* 27, or for shared code that must still compile against older SDKs (`#if swift(>=6.4)` pattern already used). |

### Evidence sources (confidence)

1. **Highest:** live Lancer `file:line` + local iOS 27 SDK greps from prior audit (`docs/wwdc26-lancer-opportunity-audit/`).
2. **High:** Apple Developer session pages / documentation URLs.
3. **Medium:** apple-docs MCP (indexes WWDC **2020–2025** only — **2026 year not in catalog**); filled via WebFetch of `developer.apple.com/videos/play/wwdc2026/*`.
4. **Stale audit warning:** `02-current-codebase-state.md` (2026-07-02) claimed zero `AppEntity` / Spotlight — **superseded**. Live code now has IntentsKit entities, IndexedEntity, IndexedEntityQuery, SyncableEntity, RelevantEntities, LongRunningIntent on `StartAgentRunIntent`. Re-verified 2026-07-09.

### Security standing rules (apply to every Siri row)

- **Never** expose a Siri/voice **Approve** intent.
- **Deny / Stop** stay confirmation-gated / entity-resolved.
- **High-risk** actions open the app (or Live Activity visual tap) — not voice-only.

---

## Top 10 must-use APIs (executive)

| # | API | Why Lancer | Status | Priority |
|---|---|---|---|---|
| 1 | Raise target → **iOS 27.0** | Unlocks AppIntentsTesting, removes `#if swift(>=6.4)` / dual-SDK tax | Not started (`project.yml` still `26.0`) | **P0** |
| 2 | **`AppIntentsTesting`** | Regression-guards the exact App Shortcuts registration/runtime bugs already hit twice | Not started | **P0** |
| 3 | **`IndexedEntity` + `IndexedEntityQuery` + Spotlight** | System search for conversations/machines/runs (“find that auth middleware thread”) | Partial (code exists; refresh cadence mostly launch-only) | **P0** |
| 4 | **`RelevantEntities` + donation wiring** | “Pause this run / deny that approval” without Spotlight | Partial (coordinator real; trigger mostly inert) | **P0** |
| 5 | **View annotations (`.appEntityIdentifier`)** | On-screen “this/that” resolution in lists | Not started | **P0** |
| 6 | **`LongRunningIntent` + Live Activity progress** | “Start Claude in Lancer” survives >30s; auto progress surface | Partial (`StartAgentRunIntent` conforms; progress/LA bridge incomplete) | **P0** |
| 7 | **`IntentExecutionTargets`** | Pin shared intents to `.main` vs widget — prevents multi-binary lookup failures | Not started | **P1** |
| 8 | **ActivityKit push + push-to-start (harden)** | Away-mode approvals while app closed | Partial (manager + backend exist; device dogfood still the bar) | **P1** |
| 9 | **`SyncableEntity`** | Cross-device Siri continuation for conversations/runs | Partial (Conversation + Run only) | **P1** |
| 10 | **Foundation Models (`@Generable` + `Tool`) advisory Copilot** | On-device risk explanation — never authoritative | Not started | **P2** |

---

## A. App Intents / Siri / Spotlight / App Shortcuts

| Feature / API | WWDC year + session | Min OS | What it enables for Lancer | Status | Priority | Evidence |
|---|---|---|---|---|---|---|
| `AppShortcutsProvider` + App Shortcuts phrases | WWDC23 [10102](https://developer.apple.com/videos/play/wwdc2023/10102/); re-emphasis WWDC25 [244](https://developer.apple.com/videos/play/wwdc2025/244/), [260](https://developer.apple.com/videos/play/wwdc2025/260/) | iOS 16+ | Zero-setup Siri phrases at install | **Shipped** (9 shortcuts: status, pending, pause, stop, deny, search, open conversation, start run, answer question iOS18+) | P0 keep | `Lancer/LancerAppShortcuts.swift:19-114` |
| App Shortcuts must live in **app target** (not SPM) | Forums + WWDC25 re-emphasis | iOS 16+ | Avoids “No AppShortcuts found” metadata miss | **Shipped** (documented constraint) | P0 keep | `LancerAppShortcuts.swift:11-17` |
| Interactive widgets / `Button(intent:)` | WWDC23 [10028](https://developer.apple.com/videos/play/wwdc2023/10028/) | iOS 17+ | Lock Screen / Island approve-deny taps | **Shipped** (`ApprovalActionIntent` in widget) | P1 keep | `LancerLiveActivityWidget/`; `SessionFeature/ApprovalActionIntent.swift` |
| `ProgressReportingIntent` | WWDC23 [10103](https://developer.apple.com/videos/play/wwdc2023/10103/) | iOS 17+ | Progress UI for long Shortcuts/Siri work | **Partial** (conformed with LongRunning on start-run) | P0 | `Lancer/StartAgentRunIntent.swift:162` |
| `RelevantIntent` / `RelevantIntentManager` (widget) | WWDC23 [10103](https://developer.apple.com/videos/play/wwdc2023/10103/) | iOS 17+ | Smart Stack widget relevance | **Not started** | Defer | Distinct from iOS27 `RelevantEntities` |
| Assistant Schemas → **App Schemas** (`AppSchema` / `@AppIntent(schema:)`) | WWDC24 [10133](https://developer.apple.com/videos/play/wwdc2024/10133/); WWDC26 [240](https://developer.apple.com/videos/play/wwdc2026/240/) re-explainer; WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 18+ (not 27-new) | System-trained domains (Messages/Photos/search) | **Not started** — **no domain fit** for agent runs | Defer | Audit `01`/`03` correction; Apple [app-intent-domains](https://developer.apple.com/documentation/appintents/app-intent-domains) |
| `IndexedEntity` + `CSSearchableIndex.indexAppEntities` | WWDC24 [10134](https://developer.apple.com/videos/play/wwdc2024/10134/); WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 18+ | Donate entities to Spotlight / Apple Intelligence | **Partial** (conformances + indexer; secret-screen gate) | P0 | `SiriEntityIndexing.swift:13-22,37`; `SiriSpotlightSupport.swift:26` |
| `ShowInAppSearchResultsIntent` / in-app search schema | WWDC24 [10133](https://developer.apple.com/videos/play/wwdc2024/10133/) | iOS 18+ | Siri “find X in Lancer” → in-app FTS UI | **Partial** (`SearchLancerIntent` opens search; schema not adopted) | P1 | `Lancer/StatusQueryIntents.swift:105` |
| `OpenIntent` / open-entity deep links | WWDC24/25 re-emphasis | iOS 16+ | Open conversation/machine from Spotlight hit | **Partial** (`OpenConversationIntent`) | P1 | `StatusQueryIntents.swift:139` |
| `AppEntity` + `EntityQuery` / `EntityStringQuery` | WWDC24 [10210](https://developer.apple.com/videos/play/wwdc2024/10210/) | iOS 16+ | Disambiguate runs/approvals/machines | **Shipped** | P0 keep | `IntentsKit/{Machine,Run,Approval,Conversation,Workspace}Entity.swift` |
| Entity-parameterized pause/stop/deny | — (built on AppEntity) | iOS 16+ | Multi-run / multi-approval Siri | **Shipped** | P0 keep | `RunControlIntents.swift:75+`; `DenyApprovalIntent.swift:23` |
| Interactive `SnippetIntent` / `ShowsSnippetIntent` | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/), [281](https://developer.apple.com/videos/play/wwdc2025/281/) | iOS 26+ | Confirm/act in compact Siri snippet UI | **Not started** | P2 | [SnippetIntent](https://developer.apple.com/documentation/appintents/snippetintent) |
| `IntentValueQuery` + Visual Intelligence | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 26+ | Screenshot → entity match (low Lancer fit) | **Not started** | Defer | [IntentValueQuery](https://developer.apple.com/documentation/appintents/intentvaluequery) |
| `IntentModes` / `continueInForeground` | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 26+ | Background vs foreground execution policy | **Not started** | P1 | [IntentModes](https://developer.apple.com/documentation/appintents/intentmodes) |
| `TargetContentProvidingIntent` + `onAppIntentExecution` | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 26+ | Navigation stays in SwiftUI; intents carry params | **Not started** | P1 | [TargetContentProvidingIntent](https://developer.apple.com/documentation/appintents/targetcontentprovidingintent) |
| `UndoableIntent` | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 26+ | System undo for destructive intents | **Not started** | P2 | [UndoableIntent](https://developer.apple.com/documentation/appintents/undoableintent) — useful for deny/stop, **not** approve |
| `PredictableIntent` | WWDC25 [260](https://developer.apple.com/videos/play/wwdc2025/260/) | iOS 16+ | Spotlight/Siri suggestions from usage | **Not started** | P2 | [PredictableIntent](https://developer.apple.com/documentation/appintents/predictableintent) |
| `@ComputedProperty` / `@DeferredProperty` | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/) | iOS 26+ | Lazy entity fields for Shortcuts | **Not started** | P2 | App Intents updates |
| On-screen entity annotation (`NSUserActivity` / view annotations) | WWDC25 [275](https://developer.apple.com/videos/play/wwdc2025/275/); WWDC26 [240](https://developer.apple.com/videos/play/wwdc2026/240/), [343](https://developer.apple.com/videos/play/wwdc2026/343/) | iOS 18.2+ protocol; SwiftUI modifier gate verify | “Pause **this** run” from visible list | **Not started** | **P0** | Audit `03`; [making-app-entities-available-in-spotlight](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight) |
| **`LongRunningIntent` + `CancellableIntent`** | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** | >30s Siri start-run; auto Live Activity progress | **Partial** (protocol conformance only) | **P0** | `StartAgentRunIntent.swift:162`; [LongRunningIntent](https://developer.apple.com/documentation/appintents/longrunningintent) |
| **`IntentExecutionTargets` / `allowedExecutionTargets`** | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** | Pin intent process (main vs widget) | **Not started** | **P1** | Audit `03` SDK `:1309,1768`; [IntentExecutionTargets](https://developer.apple.com/documentation/appintents/intentexecutiontargets) |
| **`SyncableEntity`** | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** | Cross-device stable entity IDs | **Partial** (Conversation + Run) | **P1** | `SiriSyncableEntities.swift:32-35`; [SyncableEntity](https://developer.apple.com/documentation/appintents/syncableentity) |
| **`RelevantEntities`** | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** | Relevance without full Spotlight | **Partial** (donate path; launch-only refresh) | **P0** | `Lancer/SiriRelevanceCoordinator.swift:38-50,133`; [RelevantEntities](https://developer.apple.com/documentation/appintents/relevantentities) |
| **`IndexedEntityQuery` + `CSSearchableIndexDescription`** | WWDC26 [240](https://developer.apple.com/videos/play/wwdc2026/240/); docs | **iOS 27+** | System-driven Spotlight reindex | **Partial** (query extensions exist) | **P0** | `SiriIndexedEntityQuery.swift:39+`; [IndexedEntityQuery](https://developer.apple.com/documentation/appintents/indexedentityquery) |
| `EntityCollection` | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** | Large entity-set params by ID | **Not started** | P2 | Audit `03` |
| `AppUnionValue` / union params | WWDC26 [345](https://developer.apple.com/videos/play/wwdc2026/345/) | **iOS 27+** (input-param support) | “Run OR conversation” pickers | **Not started** | P2 | Audit `03` |
| **`AppIntentsTesting`** | WWDC26 [295](https://developer.apple.com/videos/play/wwdc2026/295/) | **iOS 27+** | Real intent/Spotlight/view-annotation tests | **Not started** | **P0** | Session page; audit `03` |
| Intent donations (`IntentDonationManager`) | Pre-WWDC26; used with relevance | iOS 16+ | Proactive Siri suggestions | **Partial** (donates; refresh trigger thin) | P0 | `SiriRelevanceCoordinator.swift:54-79`; `SiriSurfaceBootstrap.swift:14-16` |
| Voice **Approve** App Shortcut | — | — | — | **Deliberately absent** | **Reject** | `LancerAppShortcuts.swift:4-8` |

---

## B. Live Activities / ActivityKit / WidgetKit / Controls

| Feature / API | WWDC year + session | Min OS | What it enables for Lancer | Status | Priority | Evidence |
|---|---|---|---|---|---|---|
| ActivityKit Live Activities (Lock Screen / Island) | WWDC23 [10184](https://developer.apple.com/videos/play/wwdc2023/10184/); WWDC26 [223](https://developer.apple.com/videos/play/wwdc2026/223/) | iOS 16.1+ | Away-mode agent status | **Shipped** | P0 keep | `LiveActivityManager.swift:121+` |
| Push updates (`pushType: .token`, `pushTokenUpdates`) | WWDC23 [10185](https://developer.apple.com/videos/play/wwdc2023/10185/) | iOS 16.2+ | Update while app closed | **Partial** (client + backend; device dogfood bar) | **P1** | `LiveActivityManager.swift:19-22,334`; `daemon/push-backend/liveactivity.go` |
| Push-to-start (`pushToStartTokenUpdates`, `event: "start"`) | Doc + WWDC23 push session; iOS 18+ | iOS 18+ | Start LA with app fully closed | **Partial** | **P1** | `LiveActivityManager.swift:210-213`; `liveactivity.go:230-273` |
| `staleDate` / `relevanceScore` | WWDC23 [10184](https://developer.apple.com/videos/play/wwdc2023/10184/)/[10185](https://developer.apple.com/videos/play/wwdc2023/10185/) | iOS 16.2+ | Stale when host offline; bump approvals | **Partial** (fields used; policy polish TBD) | P1 | ActivityKit docs; manager content state |
| Do **not** `.end()` on background | ActivityKit semantics | iOS 16.2+ | Keep push-driven LA alive | **Shipped** (fixed) | P0 keep | `AppRoot.swift:344-350` |
| `LiveActivityIntent` buttons | WWDC23/24; WWDC26 [223](https://developer.apple.com/videos/play/wwdc2026/223/) | iOS 16.1+/17+ | Approve/deny on Lock Screen | **Shipped** (approve stays visual, not Siri) | P0 keep | Widget + `ApprovalActionIntent` |
| Risk in LA content state | — | — | Distinguish high-risk approvals at a glance | **Partial** (`pendingApprovalRisk` / `highestRisk`) | P1 | `LiveActivityManager.swift:253-273` |
| `isDynamicIslandLimitedInWidth` | WWDC26 [223](https://developer.apple.com/videos/play/wwdc2026/223/) landscape | **iOS 27+** | Landscape Island layout | **Shipped** (gated) | P1 keep | `LancerLiveActivityWidget.swift:366-383` |
| `supplementalActivityFamilies([.small])` | WWDC24 [10068](https://developer.apple.com/videos/play/wwdc2024/10068/); WWDC25 [278](https://developer.apple.com/videos/play/wwdc2025/278/); WWDC26 [223](https://developer.apple.com/videos/play/wwdc2026/223/) | iOS 18+ | Watch Smart Stack + CarPlay small family | **Not started** | P2 | SwiftUI `supplementalActivityFamilies` |
| StandBy (reuse Lock Screen LA) | WWDC23 [10184](https://developer.apple.com/videos/play/wwdc2023/10184/) | iOS 17+ | Desk glance | **Shipped** (automatic with LA) | Defer polish | ActivityKit HIG |
| Broadcast / channel Live Activity push | WWDC24 [10069](https://developer.apple.com/videos/play/wwdc2024/10069/) | iOS 18+ | Fan-out to many devices | **Not started** | Defer | Single-user V1 |
| `ControlWidget` / Lock Screen controls | WWDC24 [10157](https://developer.apple.com/videos/play/wwdc2024/10157/) | iOS 18+ | One-tap pause/status from Control Center | **Not started** | P2 | [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system) |
| Home Screen status widget (relay-fresh) | WidgetKit | iOS 17+ | Glance active relay run | **Partial** (widget exists; relay freshness historically stale) | P1 | `LancerWidget/LancerStatusWidget.swift`; audit `02` |
| `WidgetFamily.systemExtraLargePortrait` | WWDC25 [278](https://developer.apple.com/videos/play/wwdc2025/278/) | **iOS 27+** | Tall poster widget | **Not started** | Defer | [systemExtraLargePortrait](https://developer.apple.com/documentation/WidgetKit/WidgetFamily/systemExtraLargePortrait) |
| WidgetKit push reloads | WWDC25 [278](https://developer.apple.com/videos/play/wwdc2025/278/) | iOS 18+/26+ | Server-driven widget refresh | **Not started** | P2 | WidgetKit push docs |
| RelevanceKit / `RelevanceConfiguration` (Watch) | WWDC25 [334](https://developer.apple.com/videos/play/wwdc2025/334/), [278](https://developer.apple.com/videos/play/wwdc2025/278/) | watchOS 26+ | Smart Stack ranking | **Not started** | Defer | Watch secondary |
| Frequent updates plist | WWDC23 [10185](https://developer.apple.com/videos/play/wwdc2023/10185/) | iOS 16.2+ | Higher push budget for chatty runs | **Partial** (verify Info.plist keys) | P1 | `NSSupportsLiveActivitiesFrequentUpdates` |

---

## C. Foundation Models / Apple Intelligence / Speech

| Feature / API | WWDC year + session | Min OS | What it enables for Lancer | Status | Priority | Evidence |
|---|---|---|---|---|---|---|
| `SystemLanguageModel` + `LanguageModelSession` | WWDC25 [286](https://developer.apple.com/videos/play/wwdc2025/286/), [301](https://developer.apple.com/videos/play/wwdc2025/301/); WWDC26 [241](https://developer.apple.com/videos/play/wwdc2026/241/) | iOS 26+ | On-device advisory Approval Copilot | **Not started** | **P2** | [FoundationModels](https://developer.apple.com/documentation/FoundationModels) |
| `@Generable` / `@Guide` | WWDC25 [286](https://developer.apple.com/videos/play/wwdc2025/286/) | iOS 26+ | Typed `RiskVerdict` (advisory only) | **Not started** | **P2** | Audit `06` |
| `Tool` protocol (read-only evidence) | WWDC25 [286](https://developer.apple.com/videos/play/wwdc2025/286/)/[301](https://developer.apple.com/videos/play/wwdc2025/301/) | iOS 26+ | Fetch audit/diff/policy context for Copilot | **Not started** | **P2** | Audit `06` |
| `PrivateCloudComputeLanguageModel` | WWDC26 [241](https://developer.apple.com/videos/play/wwdc2026/241/), [319](https://developer.apple.com/videos/play/wwdc2026/319/) | **iOS 27+** | Long-transcript deep review; quota-limited | **Not started** | P2 | [PCC article](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute) |
| `Attachment` / multimodal images | WWDC26 [241](https://developer.apple.com/videos/play/wwdc2026/241/) | **iOS 27+** | Screenshot/diff image review | **Not started** | P2 | FM multimodal docs |
| `LanguageModelSession.DynamicProfile` | WWDC26 docs / [241](https://developer.apple.com/videos/play/wwdc2026/241/) | **iOS 27+** | Quick triage ↔ deep PCC within one session | **Not started** | P2 | Audit `01`/`06` |
| Evaluations framework | WWDC26 docs; process in WWDC25 [248](https://developer.apple.com/videos/play/wwdc2025/248/) | **iOS 27+** | Regression-test “never says approve” | **Not started** | P2 | [Evaluations](https://developer.apple.com/documentation/Evaluations/evaluating-language-model-responses) |
| Third-party `LanguageModel` protocol | WWDC26 [241](https://developer.apple.com/videos/play/wwdc2026/241/) | **iOS 27+** | External models via same session API | **Not started** | **Defer** | Conformers immature; privacy disclosure |
| Fine-tuned `SystemLanguageModel(adapter:)` | — | **Obsoleted iOS 27** | — | **Dead API** | **Reject** | Audit `06` SDK L296-303 |
| Writing Tools / Smart Reply | WWDC24 [10168](https://developer.apple.com/videos/play/wwdc2024/10168/); WWDC25 [265](https://developer.apple.com/videos/play/wwdc2025/265/) | iOS 18+ | Polish rejection notes (not Copilot) | **Not started** | Defer | Low agent-control value |
| `SpeechAnalyzer` | WWDC25 [277](https://developer.apple.com/videos/play/wwdc2025/277/) | iOS 26+ | Voice briefing of pending approvals | **Not started** | P2 | [SpeechAnalyzer](https://developer.apple.com/documentation/Speech/SpeechAnalyzer) |

---

## D. Continuity / Spotlight / Handoff / Security tooling

| Feature / API | WWDC year + session | Min OS | What it enables for Lancer | Status | Priority | Evidence |
|---|---|---|---|---|---|---|
| Core Spotlight semantic index (via IndexedEntity) | WWDC24–26 | iOS 18+ / reindex 27+ | System find conversations | **Partial** | P0 | See §A |
| Handoff / `NSUserActivity` classic | Pre-WWDC | iOS 8+ | Continue conversation on Mac | **Not started** (prefer SyncableEntity path) | P2 | Prefer App Intents sync |
| App Attest (`DCAppAttestService`) | WWDC26 [201](https://developer.apple.com/videos/play/wwdc2026/201/) (audit) | iOS 14+ | Hardware-attested device binding | **Not started** | P1 (security track) | Audit `07`/`08` #15 |
| `IntentAuthenticationPolicy` / Face ID on intents | WWDC26 framing | varies | Biometric before intent `perform()` | **Rejected for V1** | **Reject** | Owner 2026-07-02/07; no biometric gate on approvals |
| MetricKit `MetricManager` / StateReporting | WWDC26 [222](https://developer.apple.com/videos/play/wwdc2026/222/) (audit) | **iOS 27+** | Hitch/hang telemetry for terminal UI | **Not started** | Defer | App-only; not lancerd |
| SwiftData 27 additions | WWDC26 | iOS 27 | — | **Reject** | **Reject** | GRDB is deliberate; no Go cross-process story |

---

## E. Deployment / toolchain (gate for all iOS-27-only rows)

| Item | Current | Target | Status | Priority | Evidence |
|---|---|---|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | **26.0** | **27.0** | Not started | **P0** | `project.yml:13,233,271` |
| LancerKit platforms | `.iOS(.v26)` | `.iOS(.v27)` | Not started | **P0** | `Packages/LancerKit/Package.swift:19` |
| iOS-27-only code already present | Gated `#if swift(>=6.4)` + `@available(iOS 27.0, *)` | After raise, simplify where safe | Partial | P0 | `SiriIndexedEntityQuery.swift`, `SiriSyncableEntities.swift`, `StartAgentRunIntent.swift:160-163`, widget width reader |

---

## F. Explicit non-goals / rejects (do not inventory as work)

| Item | Why |
|---|---|
| Siri/voice **Approve** | Security standing rule |
| Face ID / `IntentAuthenticationPolicy` on approvals | Owner rejected for V1 (2026-07-02/07) |
| App Schemas domain adoption | No Apple schema for “coding agent run/approval” |
| SwiftData migration | GRDB + Go daemon sharing |
| Core AI / MLX custom classifier before FM Copilot eval | Speculative; SDK evidence weak |
| Third-party cloud `LanguageModel` before mature packages | Privacy + App Review |
| Reintroducing tab-bar / Control-Activity roots | Cursor shell is IA (`ARCHITECTURE.md` §4.1) |

---

## G. Stale-doc corrections (for next implement session)

| Prior claim | Live truth (2026-07-09) |
|---|---|
| `02`: zero AppEntity / IndexedEntity / Spotlight | **False** — IntentsKit entities + IndexedEntity + indexer + IndexedEntityQuery |
| `2026-07-03` Siri plan: five shortcuts only | **False** — nine registered shortcuts including search/open/start/answer |
| `02`: LA ends on every background | **Fixed** — `AppRoot.swift:344-350` keeps activities alive |
| Deployment target is 27 | **Still 26.0** in `project.yml` / `Package.swift` — raise is the first implement gate |

---

## Canonical Apple session index (Lancer-relevant)

### WWDC 2026 (WebFetch; not in apple-docs MCP catalog)
- [240 Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [343 Explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/)
- [345 Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345/)
- [295 Validate your App Intents adoption with AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/)
- [223 Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
- [241 What’s new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [319 Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)

### WWDC 2025 (apple-docs MCP)
- [244 Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/)
- [260 Develop for Shortcuts and Spotlight with App Intents](https://developer.apple.com/videos/play/wwdc2025/260/)
- [275 Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275/)
- [281 Design interactive snippets](https://developer.apple.com/videos/play/wwdc2025/281/)
- [278 What’s new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/)
- [286 Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [301 Deep dive into Foundation Models](https://developer.apple.com/videos/play/wwdc2025/301/)
- [277 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)

### WWDC 2024
- [10133 Bring your app to Siri](https://developer.apple.com/videos/play/wwdc2024/10133/)
- [10134 What’s new in App Intents](https://developer.apple.com/videos/play/wwdc2024/10134/)
- [10157 Extend your app’s controls across the system](https://developer.apple.com/videos/play/wwdc2024/10157/)
- [10068 Bring your Live Activity to Apple Watch](https://developer.apple.com/videos/play/wwdc2024/10068/)

### WWDC 2023
- [10102 Spotlight your app with App Shortcuts](https://developer.apple.com/videos/play/wwdc2023/10102/)
- [10184 Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2023/10184/)
- [10185 Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)
- [10028 Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)
