# V1 Verification — 2026-06-18

## Branch
v1-chat-persistence-sidebar

## Swift Package Tests
- Command: `cd Packages/ConduitKit && swift test`
- Result: **PASS**
- Summary: **385 tests in 61 suites passed**

## Go Daemon Tests
- Command: `go test ./daemon/conduitd/...`
- Result: **PASS**
- Summary: **124 tests passed** (conduitd + policy)

## App Target
- Xcode project: `Conduit.xcodeproj`
- Notes: SPM build passes. Full Xcode scheme build needs watchOS runtime gate.

## What Was Built (V1 Feature Set)

### Chat Persistence (Lane A)
- `ChatConversation`, `ChatTurn`, `ChatArtifact` models in ConduitCore
- v10 migration: `chat_conversations`, `chat_turns`, `chat_artifacts`, `chat_fts` (FTS5)
- `ChatConversationRepository` — actor with full CRUD + FTS search
- 18 repository tests

### Chat Persistence Sink
- `ChatRunPersistenceSink` in `ApprovalIngest.swift` — persists tool/approval artifacts and turn output/status from daemon events

### New Chat Tab
- Turns persist on dispatch/follow-up
- Recent conversations panel with real-time search

### Chat Artifacts (Lane B)
- 7 card types: Tool, Diff, File, Test, Preview, Approval
- Detail panels for each artifact kind
- 14 rendering tests

### Sidebar Shell (Lane C)
- `SidebarShellState` — `@Observable` routing state
- `ConduitSidebarView` — New Chat, Search, Recent Threads, Fleet, Settings
- Wired into `AppRoot.swift`: drawer on compact, `NavigationSplitView` on regular

### Fleet Thread Routing (Lane D)
- `FleetThreadMapper` — maps fleet slot to chat conversation by host/agent/cwd
- 4 unit tests

## Files Created/Modified
- **New:** `ChatConversation.swift`, `ChatConversationRepository.swift`, `ChatConversationRepositoryTests.swift` (18 tests), `ChatArtifactCards.swift`, `ChatArtifactDetailView.swift`, `ChatArtifactRenderingTests.swift` (14 tests), `SidebarShellState.swift`, `ConduitSidebarView.swift`, `FleetThreadMapper.swift`, `FleetThreadMapperTests.swift` (4 tests), `scripts/relay-regression.sh`
- **Modified:** `AppDatabase.swift` (v10), `AppRoot.swift` (shell), `ApprovalIngest.swift` (sink), `NewChatTabView.swift` (persistence), `PUBLISH_READINESS_CHECKLIST.md`, `KNOWN_ISSUES.md`

## Remaining Owner-Gated Steps
- [ ] **C2 — Physical-device APNs approval loop**
  - Deployment: `fly secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_KEY_PATH=... APNS_BUNDLE_ID=... APPROVAL_RELAY_SECRET=...`
  - Deploy push-backend: `fly deploy`
  - Test: background app → trigger approval → push arrives → lock-screen Approve → agent unblocks
  - Evidence: `docs/test-runs/2026-06-18-relay-regression-checklist.md`

- [ ] **C5 — StoreKit IAP purchase verified in TestFlight**
  - Product ID: `dev.conduit.mobile.pro` (Non-Consumable, $14.99)
  - Config file: `Conduit/Conduit.storekit`
  - Create in ASC, test sandbox purchase

- [ ] **D4 — Vanity domain + DNS**
  - Repoint `CONDUIT_PUSH_BACKEND_URL` from `sslip.io` to `push.conduit.dev`

- [ ] **D5 — Archive → TestFlight → release**
