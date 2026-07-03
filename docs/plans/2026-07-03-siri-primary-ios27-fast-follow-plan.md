# Siri-Primary Lancer: iOS 26 Launch Lane and iOS 27 Fast Follow

Date: 2026-07-03
Status: Phase 1 implemented (iOS 26 launch-safe foundation); Phase 2 deferred until iOS 27 target/toolchain decision
Owner goal: ship Lancer on iOS 26 now, then be ready to ship an iOS 27 Siri-first update quickly after the iOS 27 target/toolchain decision.

## Implementation status (2026-07-03)

### Phase 1 — done in `cursor/siri-primary-ios26-foundation-bc7c`

- **`IntentEntityCatalog`** (`Packages/LancerKit/Sources/PersistenceKit/IntentEntityCatalog.swift`): testable GRDB-backed snapshots for machines, runs, approvals, conversations, workspaces. Relay machines and active run IDs are injected from the app target.
- **App Entities + queries** (`Lancer/AppEntities.swift`): `MachineEntity`, `RunEntity`, `ApprovalEntity`, `ConversationEntity`, `WorkspaceEntity` with `EntityQuery` + `EntityStringQuery` disambiguation.
- **Refactored run control** (`Lancer/RunControlIntents.swift`): `PauseRunIntent` / `StopRunIntent` accept optional `RunEntity`; fall back to sole-active-run only when unambiguous.
- **Entity-aware deny** (`Lancer/DenyLatestApprovalIntent.swift`): `DenyApprovalIntent(approval:)` plus `DenyLatestApprovalIntent` only when exactly one approval is pending.
- **Navigation intents** (`Lancer/NavigationIntents.swift`): `SearchLancerIntent`, `OpenConversationIntent`, `OpenMachineIntent`, `OpenApprovalIntent`, `ContinueConversationIntent` (opens thread; does not send to agent).
- **Siri navigation bridge** (`NotificationsKit/SiriNavigation.swift`, `AppRoot.handleSiriNavigation`): intents post `lancerSiriNavigation`; app routes to sidebar search, thread, machines, or approval review.
- **Shortcuts** (`Lancer/LancerAppShortcuts.swift`): 11 Siri phrases registered (status, pending approvals, search, open/continue conversation, open machine, open/deny approval, pause/stop run, deny latest). Approve remains never Siri-triggered.
- **Tests** (`Packages/LancerKit/Tests/LancerKitTests/IntentEntityCatalogTests.swift`): catalog loading, FTS search, matcher behavior, multi-approval ambiguity guard.

### Phase 2 — not started (requires iOS 27 SDK/target)

- `IndexedEntity` / `IndexedEntityQuery` / Core Spotlight semantic indexing
- `RelevantEntities`, view annotations, `LongRunningIntent`
- `AppIntentsTesting` XCUITest bundle
- Deployment target bump in `project.yml` / `Package.swift`

### Verification note

Cloud agent environment has no Xcode/Swift toolchain. Owner should run locally:

- `cd Packages/LancerKit && swift build && swift test --no-parallel`
- `xcodebuild build -project Lancer.xcodeproj -scheme Lancer -configuration Debug -destination 'platform=iOS Simulator,name=<available iPhone>,OS=latest'`

Inspect build log for App Intents metadata extraction / training phrases.

## Ground Truth

Current repo state:

- The app still targets iOS 26: `project.yml`, `Packages/LancerKit/Package.swift`, and `Lancer.xcodeproj/project.pbxproj`.
- Lancer already has five basic App Shortcuts in `Lancer/LancerAppShortcuts.swift`: status, pending approvals, pause, stop, and deny latest approval.
- Current run control Siri intents are intentionally narrow: `PauseRunIntent` and `StopRunIntent` only work when there is exactly one active run.
- `DenyLatestApprovalIntent` denies the newest pending approval only. It does not resolve a specific approval entity.
- In-app chat search already exists through SQLite FTS in `ChatConversationRepository` and UI wiring in `LancerSidebarView`.
- No production AppEntity, IndexedEntity, EntityQuery, IndexedEntityQuery, Core Spotlight, or AppIntentsTesting adoption is present yet.

Apple docs reviewed:

- WWDC 2026: Build intelligent Siri experiences with App Schemas - https://developer.apple.com/videos/play/wwdc2026/240/
- WWDC 2026: Explore advanced App Intents features for Siri and Apple Intelligence - https://developer.apple.com/videos/play/wwdc2026/343/
- WWDC 2026: Validate your App Intents adoption with AppIntentsTesting - https://developer.apple.com/videos/play/wwdc2026/295/
- WWDC 2026: Discover new capabilities in the App Intents framework - https://developer.apple.com/videos/play/wwdc2026/345/
- App Store featuring guidance - https://developer.apple.com/app-store/getting-featured/

Key Apple takeaways:

- Siri and Apple Intelligence use App Intents as the foundation. The quality of entities, queries, disambiguation, and dialogs matters as much as the raw action count.
- App Schemas should be preferred where Lancer actions map to system-understood domains. Custom intents/entities remain appropriate for Lancer-specific domains like machines, agent runs, approvals, and conversations.
- Searchable content should be modeled as App Entities, then exposed through IndexedEntity/Core Spotlight when the iOS 27 lane is opened.
- AppIntentsTesting validates the real App Intents stack from XCUITest, including intent execution, Spotlight indexing, and view annotations.
- LongRunningIntent is the right shape for tasks that may run longer than the normal App Intent execution window.
- RelevantEntities and view annotations are the path to contextual Siri behavior: "pause this run", "open that conversation", "deny this approval".
- App Store featuring nominations need a polished story and should be submitted in App Store Connect at least two weeks before the desired featuring window, with up to three months preferred.

## Product Positioning

Headline:

> Lancer is a Siri-first command center for AI coding agents. Ask Siri to find work, open conversations, check pending approvals, continue an agent run, pause or stop work, and safely review decisions across your own machines.

Important boundary:

- "Full Siri control" should not mean silent unsafe execution.
- Read-only, navigation, search, pause, and stop can be voice-first.
- Deny can be voice-first if the target approval is resolved clearly.
- Approve should require explicit confirmation and local authentication, or open the approval surface for review. Do not implement blind voice-only approval for command execution.

## Phase 1: iOS 26 Launch-Safe Siri Foundation

Goal: improve Siri usefulness now without raising the deployment target or introducing iOS 27-only symbols that would break Xcode 26 fallback builds.

Implement:

1. Add stable Lancer App Entities:
   - `MachineEntity`
   - `RunEntity`
   - `ApprovalEntity`
   - `ConversationEntity`
   - `WorkspaceEntity` only if the current persistence model has stable enough workspace IDs for Siri resolution.

2. Add queries and disambiguation:
   - Entity queries should use existing GRDB repositories and in-memory stores, not duplicate persistence.
   - Match by stable ID first, then title/name/host/workspace recency.
   - Handle ambiguous matches with system disambiguation rather than "open Lancer" fallbacks.

3. Refactor existing intents:
   - `PauseRunIntent(run:)`
   - `StopRunIntent(run:)`
   - `DenyApprovalIntent(approval:)`
   - Keep "deny latest approval" only as a shortcut phrase backed by the entity-aware implementation or remove it if it creates ambiguity.

4. Add launch-safe navigation/search intents:
   - `SearchLancerIntent(query:)`: opens Lancer to current in-app search results using the existing FTS path.
   - `OpenConversationIntent(conversation:)`
   - `OpenMachineIntent(machine:)`
   - `OpenApprovalIntent(approval:)`
   - `ContinueConversationIntent(conversation:)`: should open the conversation/composer or ask for explicit confirmation before sending work to an agent.

5. Add strong Siri dialogs:
   - Confirmation summaries must include machine, workspace/conversation, run/approval title, risk level, and whether the host is online.
   - Failure dialogs should distinguish no paired machines, offline host, multiple matches, no pending approvals, and auth required.

6. Add tests:
   - Unit tests for each entity query and intent routing path.
   - App-target build verification so metadata extraction catches broken App Shortcuts.
   - Do not require AppIntentsTesting in this lane unless it compiles cleanly with the current supported CI/toolchain matrix.

## Phase 2: iOS 27 Fast-Follow Lane

Start this only after the project explicitly commits to the iOS 27 SDK/target/toolchain lane. Do not land iOS 27-only symbols in the iOS 26 release branch if CI or contributor machines still need Xcode 26 compatibility.

Implement:

1. Raise target intentionally:
   - Update `project.yml`.
   - Regenerate `Lancer.xcodeproj`.
   - Update `Packages/LancerKit/Package.swift`.
   - Verify all app, widget, watch, and test targets.

2. Adopt iOS 27 Siri/search primitives:
   - `IndexedEntity` and `IndexedEntityQuery` for conversations and, where useful, machines/workspaces/runs.
   - Core Spotlight descriptions for conversation titles, agent/vendor, machine, workspace, recent turns, and status.
   - `SyncableEntity` for stable cross-device IDs where the same entity must resolve across phone, iPad, Mac, and future devices.
   - `RelevantEntities` for pending approvals, active runs, online machines, and recently used conversations.
   - `IntentValueQuery` or the current iOS 27 equivalent for structured in-app search backed by the existing FTS index.

3. Add onscreen awareness:
   - Annotate conversation rows, run cards, approval cards, and machine rows with app entity identifiers.
   - Target utterances like "pause this run", "deny that approval", "open this conversation", and "continue here".

4. Add long-running flows:
   - Use `LongRunningIntent` for start/continue agent work that may exceed the normal intent window.
   - Bridge progress to Live Activities and existing run state.
   - Support cancellation and host-offline recovery.

5. Add AppIntentsTesting:
   - Metadata validation for all App Shortcuts and App Schemas.
   - Entity query tests for exact match, fuzzy match, ambiguity, unavailable host, and deleted entity.
   - Intent execution tests for status, search, open, pause, stop, deny, and continue.
   - Spotlight indexing tests for conversations.
   - View annotation tests for onscreen awareness.

## App Store Featuring Work

Build a feature packet before nomination:

- Product story: "Siri-first command center for AI coding agents on your own machines."
- Demo script:
  - Ask Siri for agent status.
  - Ask Siri for pending approvals.
  - Ask Siri to search a past conversation.
  - Ask Siri to open a conversation and continue work.
  - Ask Siri to pause/stop a run.
  - Ask Siri to deny a clearly identified approval.
- Screenshots/app previews should show Siri/Spotlight, the approval safety model, Live Activity progress, and the local-first/private-host architecture.
- Nominate in App Store Connect at least two weeks before the desired feature window; earlier is better.

## Claude Code Implementation Prompt

Use this prompt for a Claude Code build session:

```text
You are working in /Users/roshansilva/Documents/command-center on Lancer. Read AGENTS.md, CLAUDE.md, ARCHITECTURE.md sections 0.1 and 4.1, docs/agent-contract.md, docs/KNOWN_ISSUES.md, docs/PUBLISH_READINESS_CHECKLIST.md, docs/wwdc26-lancer-opportunity-audit/02-current-codebase-state.md, docs/wwdc26-lancer-opportunity-audit/03-app-intents-and-siri.md, and docs/plans/2026-07-03-siri-primary-ios27-fast-follow-plan.md before editing.

Goal: implement the iOS 26 launch-safe Siri foundation for Lancer, while preparing a clean iOS 27 fast-follow plan. Do not raise the deployment target in this task. Do not add iOS 27-only APIs unless they are isolated in a separate plan/prototype file that is not compiled by the iOS 26 release lane. Current target must remain iOS 26.

Build Phase 1:
1. Inventory existing App Intents in Lancer/LancerAppShortcuts.swift, Lancer/RunControlIntents.swift, and Lancer/DenyLatestApprovalIntent.swift.
2. Add stable AppEntity types and EntityQuery implementations for Machine, Run, Approval, and Conversation using existing LancerKit repositories/stores. Add Workspace only if there are stable IDs and a clear repository path.
3. Refactor pause/stop/deny intents to accept resolved entity parameters and use system disambiguation. Keep the existing safety boundary: no blind voice-only approve path.
4. Add new launch-safe intents and shortcuts:
   - Search Lancer for <query>
   - Open conversation <conversation>
   - Open machine <machine>
   - Open approval <approval>
   - Continue conversation <conversation>, opening the composer or requiring explicit confirmation before sending anything to an agent
5. Dialogs must be specific and safe: mention machine, workspace/conversation, risk level where relevant, online/offline state, and why an action cannot run.
6. Add tests for entity query resolution, ambiguity, offline/no-data behavior, and each new/refactored intent. Prefer normal Swift/XCTest/Swift Testing tests that work with the current iOS 26 lane. If AppIntentsTesting is available and compiles without raising the target or breaking CI, add a small gated test; otherwise document it as Phase 2.
7. Update docs/wwdc26-lancer-opportunity-audit/03-app-intents-and-siri.md and docs/plans/2026-07-03-siri-primary-ios27-fast-follow-plan.md with what was implemented and what remains for the iOS 27 lane.

Verification required before claiming done:
- cd Packages/LancerKit && swift build
- cd Packages/LancerKit && swift test --no-parallel
- xcodebuild build -project Lancer.xcodeproj -scheme Lancer -configuration Debug -destination "platform=iOS Simulator,name=$(first available iPhone simulator),OS=latest"
- If you touch CI, make simulator destination dynamic. Do not hard-code a simulator name.
- If you touch daemon/lancerd, run go test ./... from daemon/lancerd.
- Inspect the app-target build output for AppIntents metadata extraction/training lines and note the shortcut phrases.

Deliverable:
- Code and tests for Phase 1.
- A short summary of exact files changed.
- Verification command results.
- A residual-risk section, especially any Siri behavior that still needs physical-device testing.
```

## Residual Risks

- Siri/App Intents behavior must still be validated on a physical device. Simulator builds prove compilation and metadata extraction, not the full Siri UX.
- Multi-machine entity routing needs careful testing. Current observed-session import code often assumes the active/first connected channel, which is acceptable for single-machine testing but not a final model for entity-backed Siri commands.
- Approve-by-voice remains a security/product decision. The recommended implementation is explicit confirmation plus local authentication or opening the approval UI, not silent execution.
