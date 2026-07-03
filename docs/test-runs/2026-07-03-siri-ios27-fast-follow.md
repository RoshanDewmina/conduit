# Siri iOS 27 fast-follow — verification report

Date: 2026-07-03  
Branch: `cursor/siri-primary-ios26-foundation-bc7c`  
Runner: Cursor agent (Composer)  
Scope: iOS 27 Spotlight indexing, SyncableEntity, relevance donations, LongRunningIntent start-run, execution targets, shortcut rebalance.

## Baseline (iOS 26 foundation — unchanged)

| Item | Status |
|---|---|
| Branch at PR #15 foundation (`bf550154`) | ✅ |
| 10 `AppShortcut(` entries, no `ApprovalActionIntent` | ✅ |
| 5 AppEntity types + entity queries | ✅ |
| `DenyLatestApprovalIntent` intent (not in shortcuts after rebalance) | ✅ |
| App deployment target iOS **26.0** | ✅ |

## What was added (iOS 27 fast-follow)

| Capability | Files |
|---|---|
| `IndexedEntity` + `IndexedEntityQuery` | [`Lancer/AppEntityIOS27.swift`](../../Lancer/AppEntityIOS27.swift), [`Lancer/SiriEntityIndexing.swift`](../../Lancer/SiriEntityIndexing.swift) |
| Privacy-safe index field builders | [`Packages/LancerKit/Sources/PersistenceKit/IntentEntitySpotlightSupport.swift`](../../Packages/LancerKit/Sources/PersistenceKit/IntentEntitySpotlightSupport.swift) |
| `SyncableEntity` (machine, workspace, conversation) | [`Lancer/AppEntityIOS27.swift`](../../Lancer/AppEntityIOS27.swift) |
| Intent donations + relevance coordinator | [`Lancer/SiriRelevanceCoordinator.swift`](../../Lancer/SiriRelevanceCoordinator.swift), [`Packages/LancerKit/Sources/NotificationsKit/SiriRelevanceSelection.swift`](../../Packages/LancerKit/Sources/NotificationsKit/SiriRelevanceSelection.swift) |
| Surface refresh bridge | [`Lancer/SiriSurfaceBootstrap.swift`](../../Lancer/SiriSurfaceBootstrap.swift), [`SiriNavigation.swift`](../../Packages/LancerKit/Sources/NotificationsKit/SiriNavigation.swift) |
| `LongRunningIntent` + `CancellableIntent` start-run | [`Lancer/StartAgentRunIntent.swift`](../../Lancer/StartAgentRunIntent.swift), [`Lancer/StartAgentRunSupport.swift`](../../Lancer/StartAgentRunSupport.swift) |
| `IntentExecutionTargets` hardening | [`Lancer/IntentExecutionPolicy.swift`](../../Lancer/IntentExecutionPolicy.swift) |
| Start-run shortcut (replaced deny-latest slot) | [`Lancer/LancerAppShortcuts.swift`](../../Lancer/LancerAppShortcuts.swift) |

### Shortcut inventory (post-rebalance, 10/10)

1. Agent Status  
2. Pending Approvals  
3. Search Lancer  
4. Open Conversation (includes continue phrases)  
5. Open Machine  
6. Open Approval  
7. Pause Run  
8. Stop Run  
9. Deny Approval  
10. **Start Agent Run** (replaces Deny Latest Approval shortcut)

`DenyLatestApprovalIntent` remains available in Shortcuts gallery; entity-aware `DenyApprovalIntent` is preferred for multiple approvals.

## Automated verification gates

| Gate | Command | Result |
|---|---|---|
| LancerKit build | `cd Packages/LancerKit && swift build` | ✅ PASS |
| LancerKit tests | `cd Packages/LancerKit && swift test --no-parallel` | ✅ PASS |
| Xcode project regen | `xcodegen` | ✅ PASS |
| Simulator app build | `xcodebuild build … iPhone 17 Pro` | ✅ BUILD SUCCEEDED |
| AppIntents metadata | `xcodebuild test … -only-testing:LancerAppIntentsTests` | ✅ 4 passed, 1 skipped |
| Shortcut policy | `xcodebuild test … -only-testing:LancerUITests/LancerShortcutsPolicyTests` | ✅ 2 passed |
| Physical device build | `xcodebuild build … id=557A7877-F729-5031-9606-0E04F2B67822` | ✅ BUILD SUCCEEDED (~154 s) |

### New unit tests

- `SiriEntitySpotlightSupportTests` — privacy fields, stable IDs  
- `SiriRelevanceCoordinatorTests` — donation selection, stale removal  
- `StartAgentRunIntentTests` — offline/ambiguity/progress stage order  

## API surfaces adopted

| API | Min OS | Notes |
|---|---|---|
| `IndexedEntity` | iOS 18+ | Used from iOS 27 indexing lane |
| `IndexedEntityQuery` | iOS 27+ | Reindex hooks on all entity queries |
| `CSSearchableIndex.indexAppEntities` | iOS 18+ | Donation via `SpotlightIndexBridge` |
| `SyncableEntity` | iOS 27 beta | Machine, workspace, conversation |
| `IntentDonationManager` | iOS 16+ | Proactive intent donations |
| `RelevantEntities` | iOS 27 beta | Scaffolded; `AppEntityContext` audio-only in SDK — Spotlight primary |
| `LongRunningIntent` / `CancellableIntent` / `ProgressReportingIntent` | iOS 27 beta | Start-run post-confirmation path |
| `IntentExecutionTargets` | iOS 27+ | `.main` for Siri intents; `.widgetKitExtension` for `ApprovalActionIntent` |

## Blockers / limitations

| Item | Status |
|---|---|
| `AppIntentsTesting.run()` Code=800 | Still skipped — `bundle.ui-testing` + `TEST_HOST` conflict; metadata tests pass |
| `RelevantEntities.updateEntities` | Deferred — no general `AppEntityContext` in iOS 27 beta SDK |
| `RelevantIntentManager` | Not used — requires `WidgetConfigurationIntent` only |
| Multi-parameter Siri phrases for start-run | Apple metadata rejects >1 parameter per phrase; disambiguation via separate shortcuts phrases |

## Manual Siri matrix (owner gate)

| Scenario | Status |
|---|---|
| Warm app → search/open/continue | ⚠️ Manual |
| Cold launch → buffered navigation | ⚠️ Manual |
| Locked phone (where allowed) | ⚠️ Manual |
| 1 vs N active runs → pause/stop disambiguation | ⚠️ Manual |
| 1 vs N pending approvals → deny by entity | ⚠️ Manual |
| Offline machine → start-run fails closed | ⚠️ Manual |
| Relay unavailable | ⚠️ Manual |
| Start-run per vendor (Claude/Codex/OpenCode/Kimi) | ⚠️ Manual |
| Long-running progress + cancellation (iOS 27 device) | ⚠️ Manual |
| Spotlight search hit → open conversation | ⚠️ Manual |
| No voice approve path discoverable | ✅ Policy test + source scan |

### Recommended manual pass

1. Unlock device; `devicectl device process launch --device 557A7877-F729-5031-9606-0E04F2B67822 --terminate-existing dev.lancer.mobile`  
2. **"Search Lancer"** / Spotlight search for conversation title  
3. **"Open approval …"** with pending approval  
4. **"Deny approval …"** (never approve)  
5. **"Pause the agent"** with 1 vs 2 active runs  
6. **"Start Claude in Lancer"** / **"Start a run on Mac Studio in Lancer"** — confirm confirmation, progress, fail-closed offline  
7. Verify Shortcuts app shows Start Agent Run; Deny Latest not in top-10 Siri phrases  

## Verdict

iOS 27 fast-follow layer is **build- and test-gated green** on simulator and physical device build. Live Siri/Spotlight behavior requires owner manual matrix on unlocked iPhone.
