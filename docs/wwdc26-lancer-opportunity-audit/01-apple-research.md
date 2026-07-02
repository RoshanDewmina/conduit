# 01 — Apple research (WWDC26 / iOS 27 source matrix)

> Synthesized from five parallel research passes covering App Intents/Siri/Spotlight, Live
> Activities/ActivityKit/WidgetKit, Foundation Models/Core AI, App Attest/security, and
> MetricKit/StateReporting/SwiftData/Xcode-27-tooling. Full detail with per-question analysis
> lives in `03`, `04`, `06`, `07`. This file is the flat, citable matrix across all five domains.
>
> **Method note, applies to every row below:** the `apple-docs` MCP's WWDC session index only
> covers through 2025 (confirmed independently by two separate research passes) and its general
> doc search returned zero hits for several pre-2026 API names during one pass (appears
> stale/unreliable for this query set) — every 2026-specific claim below comes from either (a)
> direct grep of the shipped iOS 27.0 SDK on this machine (Xcode 27.0 build `27A5194q`,
> `iPhoneOS27.0.sdk`, `Copyright © 2026 Apple Inc.` headers confirming genuine content — the
> **highest-confidence source in this report**), or (b) WebFetch/WebSearch of live
> developer.apple.com pages. Apple's own doc pages for ActivityKit push notifications and the
> Live Activities HIG returned only a page title via WebFetch (client-side rendered) — those
> specific claims are corroborated by independent secondary sources instead and are flagged
> medium confidence, not read directly from Apple's primary text.

## Correction to the audit's own premise (important — read first)

**App Schemas is not a new WWDC26 API.** `AppSchema` and its marker protocols are
`@available(iOS 18.0, macOS 15.0...)` in the shipped SDK — the rename target of the even-older
`AssistantSchema` (`iOS 16.0`). WWDC26 session 240 is a deep re-explainer of this existing
mechanism combined with genuinely-new-in-27 semantic search (`IndexedEntityQuery`,
`CSSearchableIndexDescription`). This means App Schemas adoption is **not** gated on Lancer
resolving its iOS 26.0-vs-27.0 deployment-target drift (`02-current-codebase-state.md`) — it works
today at the current target. Semantic indexing is the part that's actually iOS-27-gated. See
`03-app-intents-and-siri.md` for full detail.

## Matrix — App Intents, Siri, Spotlight

| API/Framework | Min OS + Xcode | New in WWDC26? | Entitlements | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|
| `IntentExecutionTargets`/`allowedExecutionTargets` | iOS 27.0 | Y | None found | Main app / App Intents Extension / WidgetKit extension | SDK `AppIntents.swiftinterface:1309,1768`; WWDC26 s345 | High |
| `AppShortcutsProvider` | iOS 16.0, unchanged | N | N/A | Main app target only — confirmed does not merge from linked SPM libraries | SDK `:9079-9095` | High |
| `LongRunningIntent`/`CancellableIntent` | iOS 27.0 | Y | None found | Removes the standard 30s intent execution ceiling; auto-renders progress as a Live Activity | SDK `:1799-1820`; WWDC26 s345 | High (API) / Med (entitlements) |
| `SyncableEntity`/`SyncableEntityIdentifier` | iOS 27.0 | Y | None found | Cross-device Siri conversation continuation | SDK `:851-877`; WWDC26 s345 | High |
| `EntityCollection<Entity>` | iOS 27.0 | Y | None | Large entity-set parameters without full resolution | SDK `:8600-8636`; WWDC26 s345 | High |
| `RelevantEntities` (new struct) | iOS 27.0 | Y | None found | Surfaces entities "without requiring Spotlight indexing or interaction donation" | SDK `:3029-3040`; WWDC26 s345 | High |
| `IndexedEntity` (protocol) | **iOS 18.0** | N | Requires `CSSearchableItemAttributeSet` | Main app; not new this cycle | SDK `:807-816`; WWDC26 s240 | High |
| `IndexedEntityQuery` (reindex) | **iOS 27.0** | Y | Takes `CSSearchableIndexDescription` | Main app indexing | SDK `:2467-2470` | High |
| `CSSearchableIndexDescription`, `SearchableItemAttribute` | **iOS 27.0** (tvOS/watchOS unavailable) | Y | File-protection-class-aware | Main app semantic indexing | SDK `CoreSpotlight.swiftinterface` | High |
| `AppEntityAnnotatable`/View Annotations | Protocol iOS 18.2; SwiftUI modifier OS gate unconfirmed | Partially Y (re-emphasized) | None found | On-screen "this/that" resolution for lists | SDK `:8646-8681`; WWDC26 s240/343 | Medium |
| `AppIntentsTesting` framework | **iOS 27.0**, whole module gated | Y — brand new | None found | Separate XCUITest bundle, real execution, no mocks | SDK `AppIntentsTesting.swiftinterface`; WWDC26 s295 | High |

## Matrix — Live Activities, Dynamic Island, WidgetKit

| API/capability | Min OS + Xcode | New in WWDC26? | Entitlements | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|
| `Activity.end()` (one-way, terminal) | iOS 16.2+ | N | — | No "pause" state exists — relevant to Lancer's background-`.end()` bug | SDK `ActivityKit.swiftinterface:174-191` | High |
| Push-to-start (`pushToStartTokenUpdates`) | iOS 17.2+, unchanged | N | Push Notifications + `NSSupportsLiveActivities*` | Wakes app, grants background runtime with no running process required | SDK `:132,539` | High |
| ActivityKit push payload shape (`event`, `content-state`, etc.) | n/a | N | `apns-topic: <bundle>.push-type.liveactivity` | 4KB max payload | 2 independent 3rd-party writeups + SDK field names — **Apple's own doc page didn't render via WebFetch** | Medium |
| `EnvironmentValues.isDynamicIslandLimitedInWidth` | **iOS 27.0** | Y | — | Already in use in Lancer's landscape fix; confirmed lives in **WidgetKit**, not ActivityKit | SDK `WidgetKit.swiftinterface:605-611` | High — SDK-verified twice independently |
| `WidgetFamily.systemExtraLargePortrait` | **iOS 27.0/macOS 27.0** | Y | — | The other genuinely-new width/orientation API this cycle | SDK `:951-955` | High |
| `supplementalActivityFamilies([.small])` | iOS 18.0+, unchanged | N | — | Apple Watch Smart Stack + CarPlay Dashboard both use Small Activity Family | SDK `:750-817`; WWDC26 s223 | High (SDK) / Med (Watch-vs-CarPlay disambiguation) |
| Lock Screen / StandBy | iOS 16.1+/17+ | N | — | StandBy reuses the Lock Screen view scaled to 200% — no separate view builder | WWDC26 s223 direct quote | High |
| `LiveActivityIntent` protocol | iOS 16.1+, unchanged | N | — | Executes **inside the widget-extension process**; no host-app round-trip before `perform()` | SDK `AppIntents.swiftinterface:257`; WWDC26 s223 | High |

## Matrix — Foundation Models / Core AI

| API/capability | Min OS + Xcode | New in WWDC26? | Entitlements | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|
| `SystemLanguageModel` | iOS 26.0 baseline | N | None found | On-device engine, default/offline mode | SDK `:43-88` | High |
| `SystemLanguageModel.Availability`/`UnavailableReason` | iOS 26.0 | N | — | Exact cases: `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady` | SDK `:264-283` | High |
| `PrivateCloudComputeLanguageModel` | iOS 27.0 emphasis | N (shipped) | None to call, Apple-side quota | 32K context, `.light`/`.deep` reasoning, **quota-limited** — real capacity risk for a review-gate feature | SDK `:45-138`; WWDC26 s241 | Med-High |
| Third-party model routing (`LanguageModel` protocol) | iOS 27.0 protocol; conformers **not shipped** | **Y — treat as unavailable today** | 3rd-party auth, App Attest recommended | Apple requires naming the provider + disclosure if personal data leaves device | WWDC26 s339 | Medium |
| `@Generable`/`@Guide` macros | iOS 26.0 baseline | N | — | **The mechanism for a machine-readable risk verdict** | SDK `:889-909,1722-1784` | High |
| `Tool` protocol | iOS 26.0 baseline, tool-calling quality improved in 27 | Partially Y | — | **The mechanism for evidence retrieval** — fully general, app-process-local | SDK `:2503-2511` | High |
| `Attachment<ImageAttachmentContent>` | **iOS 27.0 new** | Y | — | Genuinely new — screenshot review now possible; PCC image support **unconfirmed** | SDK `:2297-2321`; WWDC26 s241 | High (existence) / Med (PCC scope) |
| `LanguageModelSession.DynamicProfile` | **iOS 27.0 new** | Y | — | Mode-switching within one session, preserves transcript — fits a tiered on-device→PCC design | SDK `:590-705` | High |
| Fine-tuned adapter (`SystemLanguageModel(adapter:guardrails:)`) | **`@available(iOS, obsoleted: 27.0)`** | N — **removed** | — | **Trap: this path is dead** — don't propose custom adapter fine-tuning on `SystemLanguageModel` | SDK `:296-303` | High — concrete finding |
| Core AI / MLX conformers | New WWDC26 | Y | Not SDK-verified | Custom on-device classifier route, if ever needed | WebSearch only — **not found in the grepped SDK** | Low-Med |
| Evaluations framework | New WWDC26 | Y | — | Regression-test Copilot verdict quality | WWDC26 s241 — **no standalone framework found in the SDK** | Low-Med |

## Matrix — Security (App Attest, DeviceCheck, LocalAuthentication)

| API/capability | Min OS + Xcode | New in WWDC26? | Entitlements | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|
| `DCAppAttestService` | iOS 14.0+, unchanged | N (API) | `com.apple.developer.devicecheck.appattest-environment` | **Does not work in Simulator**; main app only, needs Secure Enclave | `DCAppAttestService.h:14`; WWDC26 s201 | High |
| App Attest iOS 27 authenticator-data extensions | iOS 27.0 | **Y** | Same | Adds TestFlight-vs-App-Store launch forensic signal | WWDC26 s201 transcript | High |
| App Attest fraud metric | iOS 14+ infra | N | — | **Advisory signal only, never a hard block** — explicit Apple guidance | WWDC26 s201 | High |
| `DCDevice`/DeviceCheck | iOS 11.0+ | N — zero iOS-27 additions found | `com.apple.developer.devicecheck` | Weaker than App Attest, no Secure Enclave binding | `DeviceCheck.h` (grepped) | Medium-high |
| `IntentAuthenticationPolicy` | Pre-existing App Intents enum, reinforced framing in WWDC26 | Partially Y | None beyond App Intents adoption | **System-owned** Face ID/passcode prompt before `perform()` runs — sidesteps the extension-process auth limitation | WWDC26 s347 transcript; AppIntents docs | Medium-high |
| `LAContext` inside a widget extension | N/A | N/A | N/A | **No direct Apple statement found** — inference by analogy to `LAErrorNotInteractive` in Network Extension | Forums thread 129480 | **Low-medium, explicitly flagged** |
| `.onToolCall` (Foundation Models) | iOS 27.0 | **Y** | None extra | Synchronous confirm-or-throw gate before tool execution, main app only | WWDC26 s347 | High |

## Matrix — MetricKit, StateReporting, SwiftData, Xcode 27 tooling

| API/capability | Min OS + Xcode | New in WWDC26? | Applicability | Source | Confidence |
|---|---|---|---|---|---|
| `MetricManager` (Swift-first, replaces `MXMetricManager`) | iOS 27.0 (tvOS/watchOS unavailable) | **Y** | Foreground, long-lived-object pattern — **no background-daemon support found**; only the iOS app target could adopt it, not `lancerd` | SDK `MetricKit.swiftinterface:1181-1202`; WWDC26 s222 | High |
| `StateReporter<Stable,Volatile>` | iOS/macOS/watchOS/tvOS/visionOS **27.0** | **Y** | Transition-based state tagging, one active state per domain; **no cross-process/shared-domain API** — cannot tag `lancerd` (a separate Go process) | SDK `StateReporting.swiftinterface:57-68`; WWDC26 s222 | High |
| `HitchTimeMetric`/`HangTimeMetric` | iOS 27.0 | Partially Y | Aggregated ~daily, not live profiling — relevant to auditing terminal-block UI hitches over time | SDK `:356-395,884-893` | High |
| Instruments "Swift executors" instrument | Xcode 27 | Y | Diagnoses actor-hop contention — directly relevant to Lancer's async relay decrypt/dispatch path | WWDC26 s268 | Medium (web-sourced) |
| Swift Testing — interop modes | Xcode 27 | Y | `complete` is now default for **new** projects; existing XCTest suites unaffected, no forced migration | WWDC26 s267; InfoQ | Medium |
| `AppIntentsTesting` (cross-referenced from `03`) | iOS/Xcode 27 | Y | Real execution against the running app, not mocks | WWDC26 s295 | Medium-High |
| SwiftData (sectioned queries, composite predicates, `ResultsObserver`) | iOS 27 / WWDC26 s274 | Y | **Incremental — does not change the calculus** for Lancer's GRDB choice (no cross-process story for a shared Go+Swift store) | WWDC26 s274 | Medium |
| Xcode 27 MCP host / Agent Client Protocol (ACP) | Xcode 27 | Y | Mac-local dev tooling, meta-relevant only, not a Lancer app dependency | Multiple secondary blogs — **no primary Apple source fetched** | Low-Medium |

## Overall confidence summary

- **Highest confidence, cite freely:** anything with a direct SDK `file:line` citation — this is
  the actual shipped iOS 27.0 SDK on this machine, stronger evidence than any documentation page.
- **Medium confidence:** WWDC26 session transcript quotes (fetched live from developer.apple.com)
  and multi-source-corroborated web claims.
- **Low-medium confidence, flagged throughout the per-domain files:** anything sourced from a
  single secondary blog/forum post, or inference by analogy rather than a direct Apple statement.
  Do not present these as settled fact in the roadmap without a follow-up verification pass.
- **Known evidence gaps worth a follow-up pass before final sign-off:** Apple's own ActivityKit
  push-notification doc page and Live Activities HIG page (client-rendered, didn't return body
  text via WebFetch — try a direct browser fetch); Xcode 27's MCP/ACP tooling claims (no primary
  Apple source found); Core AI/MLX conformer specifics (not found in the local SDK, WebSearch
  only); the Evaluations framework's actual packaging (not found as a standalone SDK framework).
