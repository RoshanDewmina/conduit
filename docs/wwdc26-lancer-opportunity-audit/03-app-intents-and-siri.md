# 03 — App Intents and Siri

> Research method: apple-docs MCP WWDC index confirmed empty for 2026, skipped per prior
> verification. Grepped the shipped iOS 27.0 SDK's `AppIntents.swiftinterface` (16,759 lines,
> `Copyright © 2026 Apple Inc.` headers confirming genuine iOS 27/WWDC26 SDK content) and
> `CoreSpotlight`/`AppIntentsTesting` swiftinterface files for ground-truth `@available`
> signatures, cross-checked against WebFetch of the actual `wwdc2026/240,343,345,295` session
> pages. SDK grep is the strongest evidence in this file; treat anything sourced only from a
> WebFetch session summary as secondary.

## Important correction to carry into the rest of this report

**App Schemas is not a new WWDC26 primitive.** `AppSchema` (and its `AppSchemaIntent`/
`AppSchemaEntity`/`AppSchemaEnum` marker protocols) are `@available(iOS 18.0, macOS 15.0...)` in
the shipped SDK — WWDC24/iOS 18-era, itself the rename target of the even older
`AssistantSchema`/`AssistantSchemas` (`iOS 16.0`/`iOS 18.0`, now `@available(*, deprecated,
renamed: "AppSchema")`). WWDC26 session 240 ("Build intelligent Siri experiences with App
Schemas") is a deep re-framed walkthrough of this **existing** mechanism combined with genuinely
new-in-27 semantic search (`IndexedEntityQuery`, `CSSearchableIndexDescription`), not an
introduction of a new `AppSchema` type. This matters for Lancer's roadmap: adopting App Schemas
is not gated on iOS 27 the way `IndexedEntityQuery`/Core Spotlight semantic indexing is — it's
available at the app's *current* iOS 26.0 deployment target already (see `02-current-codebase-state.md`'s
deployment-drift finding).

## Execution Targets — the direct answer to the multi-binary AppIntent question

**Execution Targets solves the runtime-dispatch-ambiguity half of the bug class Lancer already
hit. It does NOT cover `AppShortcutsProvider`.** The prior session's confirmed finding —
`AppShortcutsProvider` must physically live in the app target's own compiled binary — is
untouched by this API.

New type (SDK `AppIntents.swiftinterface:1768`):
```swift
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public struct IntentExecutionTargets : OptionSet, Sendable, Hashable, Equatable {
    public static var `default`: IntentExecutionTargets { get }
    public static var main: IntentExecutionTargets { get }
    public static var appIntentsExtension: IntentExecutionTargets { get }
    public static var widgetKitExtension: IntentExecutionTargets { get }
}
```

Hook point on `AppIntent` (SDK `AppIntents.swiftinterface:1309,1349`):
```swift
@available(iOS 27.0, ...) static var allowedExecutionTargets: IntentExecutionTargets { get }
```
Also exposed on `EntityQuery` (SDK `:2422`) — entity resolution can independently pin its own
execution process.

**Confirmed absent from `AppShortcutsProvider`** (SDK `:9079-9230`) — zero hits for
`ExecutionTargets` anywhere near that protocol block; it only exposes `appShortcuts`,
`shortcutTileColor`, `negativePhrases`, `updateAppShortcutParameters()`. No WWDC26 session (240,
343, or 345) mentions `AppShortcutsProvider` placement or a fix for its multi-target behavior.

**What it's actually for**, per WWDC26 session 345's transcript: *"When your intents, entities,
and queries live in a shared package like this — linked by your app and extensions — the system
has to decide which process runs each intent when a request comes in… ExecutionTargets lets you
tell the system exactly which process should run your intent."*

```swift
struct UpdateFavoriteIntent: AppIntent {
    static var allowedExecutionTargets: ExecutionTargets { .main }
}
struct GetLandmarkStatusIntent: AppIntent {
    static var allowedExecutionTargets: ExecutionTargets { .widgetKitExtension }
}
```

**Interpretation for Lancer's confirmed bug (§14/§15 of the 2026-07-02 session report):** the
intent type is still compiled into every binary that links it — no new "single shared instance
across processes" mechanism exists. What's new is that the system dispatcher, which previously
used undocumented heuristics when the same `AppIntent` type was reachable from multiple linked
targets, now has an explicit developer-declared answer. **Recommendation:** for any future
`AppIntent` (not `AppShortcutsProvider`) shared between the app target and
`LancerLiveActivityWidget`, add `allowedExecutionTargets` to pin it explicitly rather than relying
on system heuristics — this directly targets the "Unable to run App Shortcut" / ambiguous-target
failure class already hit once. The `AppShortcutsProvider`-in-shared-package problem still needs
the existing workaround (compile it directly in the app target) — this API doesn't change that.

## API / capability table

| API/Framework | Min OS + Xcode | New in WWDC26? | Entitlements | Restrictions | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|---|
| `IntentExecutionTargets`/`AppIntent.allowedExecutionTargets` | iOS 27.0 | **Y** | None found | `.default`/`.main`/`.appIntentsExtension`/`.widgetKitExtension` only — no per-Live-Activity or per-watch granularity | Main app / App Intents Extension / WidgetKit extension | SDK `:1309,1768`; WWDC26 s345 | High |
| `EntityQuery.allowedExecutionTargets` | iOS 27.0 | **Y** | Same | Same OptionSet | Entity resolution, same 3 targets | SDK `:2420-2440` | High |
| `AppShortcutsProvider` | iOS 16.0 baseline, unchanged in 27 | **N** — no execution-target hook added | N/A | Must be discoverable at build time in the **app target** that hosts it (confirmed constraint, unchanged) | Main app target only — does not merge from linked SPM libraries | SDK `:9079-9095` (absence confirmed by grep) | High |
| `LongRunningIntent` (+`CancellableIntent`, `performBackgroundTask`, `LongRunningTaskOptions`) | iOS 27.0 | **Y** | None found; standard background-task infra implied | Must also be `ProgressReportingIntent`; `.requiresGPU` option for GPU tasks | Removes the standard **30-second** intent execution ceiling; requires progress reporting, which auto-renders as a Live Activity | SDK `:1799-1820`; WWDC26 s345 | High (API) / Medium (entitlement claims unverified) |
| `SyncableEntity`/`SyncableEntityIdentifier<LocalID,StableID>` | iOS 27.0 | **Y** | None found; relies on app's own sync layer for a stable ID | `id` must be stable across the user's devices, or pair local+stable IDs | Cross-device Siri conversation continuation | SDK `:851-877`; WWDC26 s345 | High |
| `EntityCollection<Entity>` | iOS 27.0 | **Y** | None | Stores only entity identifiers, not resolved entities — avoids full-resolution cost for large sets | Any `@Parameter` on an `AppIntent`; purpose-built for large entity-set parameters | SDK `:8600-8636`; WWDC26 s345 | High |
| `AppUnionValue`/`@UnionValue` macro | Protocol iOS 27.0; macro itself iOS 18.0, **gained input-parameter support in 27** | **Partially Y** | None | Enum cases each wrap a distinct `_IntentValue`-conforming type | Works in Shortcuts, widgets, any `AppIntent` parameter — "not limited to Widgets" per s345 | SDK `:1914-1960,3362`; WWDC26 s345 | High |
| `IntentValueRepresentation`/`ValueRepresentation` (cross-app transfer) | Base type iOS 16.0; new `exporting`/`importing` initializers **iOS 26.4** | **Partially Y** — shipped just before 27, framed as new in s345 | Conforms to `Transferable` — standard UTType plumbing | `IntentValue: _IntentValue & Sendable` | Cross-app content transfer (share sheet, drag-drop, intents) | SDK `:830-849`; WWDC26 s345 | Medium |
| `RelevantEntities` (new struct) | iOS 27.0 | **Y** | None found | Operates via `AppEntityContext` (incl. new `.audio(_:)`) | Surfaces entities "**without requiring Spotlight indexing or interaction donation**" per s345 — a lighter-weight relevance channel than `CSSearchableIndex` | SDK `:3029-3040`; WWDC26 s345 | High |
| `RelevantIntentManager`/`RelevantIntent` (older, distinct API) | iOS 17.0 | **N** — pre-existing | N/A | Requires `IntentType: WidgetConfigurationIntent`; tvOS unavailable | Widget relevance only | SDK `:3044-3057` | High |
| `IndexedEntity` (protocol) | **iOS 18.0** — not new in 27 | **N** | Requires `attributeSet: CSSearchableItemAttributeSet` | Some adjacent APIs tvOS/watchOS-unavailable | Main app; works with `IndexedEntityQuery` | SDK `:807-816`; WWDC26 s240 | High |
| `IndexedEntityQuery` (`reindexEntities`, `reindexAllEntities`) | **iOS 27.0** (tvOS/watchOS unavailable) | **Y** — the query-side reindex protocol is new, layered on iOS-18 `IndexedEntity` | Takes `CSSearchableIndexDescription` | tvOS/watchOS unavailable | Main app (indexing is generally app-target work) | SDK `:2467-2470` | High |
| `CSSearchableIndexDescription` (Core Spotlight) | **iOS 27.0** (tvOS/watchOS unavailable) | **Y** | `NSFileProtectionType` as `protectionClass` — file-protection-class-aware indexing | tvOS/watchOS unavailable | Main app; consumed by `IndexedEntityQuery.reindexEntities` | SDK `CSSearchableIndexDescription.h:12-16` | High |
| `SearchableItemAttribute` (Swift-native, type-safe replacement for ObjC string keys) | **iOS 27.0** (tvOS/watchOS unavailable) | **Y** | None | tvOS/watchOS unavailable | Main app indexing surface (~180 static attribute keys, e.g. `.displayName`, `.textContent`, `.rankingHint`) | SDK `CoreSpotlight.swiftinterface:9-16` | High |
| `AppEntityAnnotatable`/`appEntityIdentifier` (View Annotations) | Protocol iOS 18.2; SwiftUI modifier's exact `@available` unconfirmed (lives in an un-grepped cross-import overlay) | **Partially Y** — protocol predates 27; s240/343 newly emphasize it for on-screen awareness | None found | Use "when multiple meaningful items are visible at once, like messages in a conversation or items in a list" per s240 — implies list/collection UI, not single always-visible item | SwiftUI views in the main app | SDK `:8646-8681`; WWDC26 s240/343 | Medium — modifier's OS gate unverified against a direct swiftinterface |
| `AppIntentsTesting` framework | **iOS 27.0**, whole module gated | **Y** — brand-new framework | None found; standard XCUITest bundle | `spotlightQuery`/`viewAnnotations` unavailable tvOS/watchOS | Runs as a **separate XCUITest bundle process** driving the real app process — "no mocks, stubs, or app-code imports... Full App Intents stack execution matching production code paths" per s295 | SDK `AppIntentsTesting.swiftinterface` (full read); WWDC26 s295 | High |
| `ViewAnnotation` (testing struct) + `AppEntityDefinition.viewAnnotations()` | iOS 27.0 | **Y** | N/A (test-only) | N/A | Test target only — validates production `.appEntityIdentifier` annotations | `AppIntentsTesting.swiftinterface`; WWDC26 s295 code sample | High |

## Entity model (recommended)

Per `02-current-codebase-state.md`, Lancer has **zero** production `AppEntity`/`IndexedEntity`
usage today — this is the largest addressable App Intents gap. Recommended entities:

| Entity | Kind | Rationale |
|---|---|---|
| `MachineEntity` | `IndexedEntity` (durable, low-churn) | Machines are long-lived, few in number (≤3-slot fleet), stable identity — ideal for indexing |
| `ConversationEntity` | `IndexedEntity` | Chat threads persist in GRDB already; natural Spotlight surface for "find my conversation about X" |
| `ApprovalEntity` | `EntityStringQuery` (volatile) | Pending approvals are short-lived and change fast — don't index, resolve fresh each time |
| `RunEntity` | `EntityStringQuery` (volatile) | Active runs are ephemeral — same reasoning as approvals; directly fixes the confirmed gap where `ActiveRunRegistry.swift:4` stores run IDs only with no entity, causing the multi-run Siri disambiguation failure in `RunControlIntents` |
| `WorkspaceEntity` (if the `docs/design/projects-workspaces-concept.md` design ships) | `IndexedEntity`, `SyncableEntity` | Would pair naturally with the design doc's already-decided GRDB storage layer |

## Safety classification (unchanged from what's already correct — verify, don't relitigate)

- **Read-only:** status query, pending-approvals query, find-a-run, find-a-conversation — safe for
  full Siri/Spotlight exposure with `.default` execution target.
- **Safe reversible:** pause a run — already implemented conservatively.
- **Sensitive, requires confirmation:** stop a run, deny-latest-approval — already implemented;
  `DenyLatestApprovalIntent`'s ambiguity bug (no entity/machine disambiguation, empty `hostID`,
  per `02-current-codebase-state.md`) should be fixed by giving it a proper `ApprovalEntity`
  parameter instead of "always pick newest," not by adding more voice restriction.
- **Must open Lancer + require Face ID:** approve — correctly never exposed to Siri today (see
  `07-security-and-trust.md` for the `IntentAuthenticationPolicy` mechanism that could formalize
  this at the widget/Live-Activity layer too, with the owner-decision caveat noted there).
- **Never voice-only:** approve/reject of any kind — this existing policy is correct and this
  report does not recommend changing it.

## AppIntentsTesting adoption plan

This framework runs as a separate XCUITest bundle process driving the real, compiled app — not
mocks — and is exactly the tool that would have caught both of the confirmed production bugs from
the 2026-07-02 session (`AppShortcutsProvider` never registering because it lived in the wrong
target; the 5 Shortcuts-only intents crashing at runtime because they were compiled into two
binaries). Recommended first tests, in priority order:

1. **Compiled-metadata assertion:** confirm exactly the 5 intended Siri shortcuts appear in
   `autoShortcuts` and `ApprovalActionIntent` does not — regression-guards the §14 fix.
2. **Runtime execution proof:** actually invoke each of the 5 Siri-only intents through the real
   `AppIntentsTesting` stack (not a UI tap) and assert success — regression-guards the §15 fix,
   the more serious of the two bugs (silent runtime crash despite correct static registration).
3. **`DenyLatestApprovalIntent` disambiguation:** once fixed per the entity-model recommendation
   above, test that it correctly resolves a specific approval by ID rather than "always newest."
4. **`ViewAnnotation` test** (`AppEntityDefinition.viewAnnotations()`) — only relevant if the View
   Annotations recommendation below is adopted.

## Spotlight / semantic search behavior

`IndexedEntityQuery` + `CSSearchableIndexDescription` + `SearchableItemAttribute` are all
genuinely new in iOS 27 (not carried over from 18's `IndexedEntity`), and together are the
mechanism for exposing Lancer's existing in-app SQLite FTS search (`AppDatabase.swift:302`,
`ChatConversationRepository.swift:278`) to system-level Spotlight/Siri semantic search. This is
correctly scoped as a **Prototype**, not **Build now**, per the plan's ranking — it requires the
iOS 27 deployment-target question (`02-current-codebase-state.md`) to be resolved first, since
`IndexedEntityQuery`/`CSSearchableIndexDescription` are hard-gated to iOS 27.0, unlike `AppSchema`
adoption which works at the current 26.0 target.

## View Annotations / onscreen awareness — tentative recommendation

`AppEntityAnnotatable`/`.appEntityIdentifier()` is well-suited to Lancer's approval-list and
run-list UI ("pause *this* run," "deny *that* approval" resolved from visible UI, per s240's own
framing: "when multiple meaningful items are visible at once, like messages in a conversation or
items in a list"). This is a plausible **Prototype**-tier addition alongside the entity model
above, but the SwiftUI-side modifier's exact minimum OS could not be pinned to a direct SDK
citation this pass (it lives in an un-shipped cross-import overlay module) — verify against Xcode
autocomplete/documentation directly before committing to a specific deployment-target requirement
in the roadmap.

## Testing plan summary

No `AppIntentsTesting`, deep-link routing tests, Spotlight/entity tests, or multi-machine Siri
run-control tests exist today (`02-current-codebase-state.md`). The adoption plan above should be
the first App Intents work item regardless of what else ships — it's cheap, it directly targets
two already-proven production bug classes, and it doesn't require the iOS 27 deployment-target
decision to be resolved first (the framework itself and basic intent-execution tests work at the
current target; only the Spotlight/semantic-indexing tests need iOS 27).

## Sourcing caveats

- Entitlements and App Review implications are the weakest-evidence column throughout — nothing
  in the grepped SDK files declares an Info.plist key or entitlement string for any WWDC26-new App
  Intents API, and WWDC26 transcripts (via WebFetch summarization) didn't surface explicit App
  Review guidance either. Treat every "None found" as "not found in available evidence," not
  "confirmed absent" — a follow-up direct documentation-page read is worth doing before the
  roadmap commits engineering time based on an assumed-absent entitlement requirement.
- Session numbers/titles confirmed live via WebFetch: 240 = "Build intelligent Siri experiences
  with App Schemas"; 343 = "Explore advanced App Intents features for Siri and Apple
  Intelligence"; 345 = "Discover new capabilities in the App Intents framework" (explicitly framed
  by its own speaker as covering "2027 releases" — i.e., forward-looking even within WWDC26); 295
  = "Validate your App Intents adoption with AppIntentsTesting."
