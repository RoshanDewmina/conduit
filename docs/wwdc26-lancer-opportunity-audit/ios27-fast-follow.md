# iOS 27 fast-follow lane — Siri / App Intents / Search

> **Launch lane stays at iOS 26.0** (`project.yml`, `Package.swift`). iOS 27 APIs are
> availability-gated in the Lancer app target.

## iOS 26 launch lane (PR #15 foundation)

- `AppEntity` + `EntityStringQuery` for machines, runs, approvals, conversations, workspaces
- Siri shortcuts for search, navigate, pause/stop, deny (never approve)
- `SiriNavigationBuffer` + `openAppWhenRun` for durable UI routing
- `IntentEntityCatalog` unit tests in LancerKit

## iOS 27 fast-follow — implemented (2026-07-03)

| Capability | Implementation | Tests |
|---|---|---|
| `IndexedEntity` + `IndexedEntityQuery` | [`Lancer/AppEntityIOS27.swift`](../../Lancer/AppEntityIOS27.swift), [`Lancer/SiriEntityIndexing.swift`](../../Lancer/SiriEntityIndexing.swift) | `SiriEntitySpotlightSupportTests` |
| Privacy-safe Spotlight fields | [`IntentEntitySpotlightSupport.swift`](../../Packages/LancerKit/Sources/PersistenceKit/IntentEntitySpotlightSupport.swift) | Same |
| `SyncableEntity` | Machine, workspace, conversation in `AppEntityIOS27.swift` | Stable ID tests |
| Intent donations | [`SiriRelevanceCoordinator.swift`](../../Lancer/SiriRelevanceCoordinator.swift) | `SiriRelevanceCoordinatorTests` |
| `RelevantEntities` | Scaffolded; blocked on audio-only `AppEntityContext` in beta SDK | Documented |
| `LongRunningIntent` start-run | [`StartAgentRunIntent.swift`](../../Lancer/StartAgentRunIntent.swift) | `StartAgentRunIntentTests` |
| `IntentExecutionTargets` | [`IntentExecutionPolicy.swift`](../../Lancer/IntentExecutionPolicy.swift) | `LancerShortcutsPolicyTests` |
| Start-run shortcut | Replaced deny-latest slot in `LancerAppShortcuts.swift` | Policy test |
| `AppIntentsTesting` metadata | `LancerAppIntentsTests` | 4 pass, 1 skip (runtime entitlement) |

Verification report: [`docs/test-runs/2026-07-03-siri-ios27-fast-follow.md`](../test-runs/2026-07-03-siri-ios27-fast-follow.md)

## Still deferred

| Capability | Blocker |
|---|---|
| `AppIntentsTesting.run()` runtime | Code=800 entitlement; `TEST_HOST` conflicts with `bundle.ui-testing` |
| `RelevantEntities.updateEntities` | No general-purpose `AppEntityContext` in iOS 27 beta SDK |
| View annotations (`appEntityIdentifier`) | Follow-up — "pause this run" on-screen awareness |
| Multi-parameter start-run Siri phrases | Apple metadata: one parameter per phrase max |

## Security invariant (all lanes)

Voice-approve remains **forbidden**. `ApprovalActionIntent` is Live Activity /
widget only (`allowedExecutionTargets: .widgetKitExtension` on iOS 27+) and must
never appear in `LancerAppShortcuts`.
