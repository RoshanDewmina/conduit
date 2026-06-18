# Fleet to Thread Routing V1

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`. This plan assumes durable chat and the sidebar shell exist or are being merged first.

**Goal:** Make Fleet a sidebar section and operational secondary collection, where each host/agent/run opens the related chat thread instead of competing as a separate root workflow.

## Dependencies

- `2026-06-18-chat-history-search-continuation-v1.md`
- `2026-06-18-sidebar-shell-swift-v1.md`

This plan should not rewrite the root shell before the sidebar shell plan lands.

## Current Reality

- `FleetView` is a root tab and shows active fleet slots.
- `FleetStore.Slot` owns session/channel/inbox state for active host connections.
- `performDispatch` in `AppRoot.swift` starts runs through the selected fleet slot.
- Chat state is currently local to `NewChatTabView`, so Fleet cannot reliably open a related thread after restart.

## Product Decision

Fleet remains essential, but it is not the primary mode. V1 framing:

- Threads are primary.
- Fleet answers "what is running where?"
- Selecting an active agent opens its related thread when one exists.
- Fleet still exposes operational controls:
  - connection status;
  - host/cwd;
  - model/vendor;
  - spend/budget;
  - stop/pause/resume where supported;
  - reconnect/disconnect.

## Data Associations

Add or use these relationships:

- `ChatConversation.hostName` / `hostID`
- `ChatConversation.agentID`
- `ChatConversation.cwd`
- latest `ChatTurn.runID`
- `FleetStore.Slot.id`
- active daemon channel identity

For V1, a fleet row can map to a thread by:

1. explicit `conversationID` captured when dispatch starts from chat;
2. latest active turn `runID` if fleet status exposes one;
3. fallback query by host/agent/cwd and most recent active conversation.

Avoid unsafe guesses. If no related thread is found, open Fleet detail and offer "Start chat with this agent."

## Implementation Tasks

- [ ] **Task 1: Add thread association to dispatch flow**
  - Files: `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`, `NewChatTabView.swift`, repository.
  - When New Chat dispatch creates a conversation, associate the selected fleet slot/host/agent context with that conversation.
  - Preserve behavior for relay-only slots.

- [ ] **Task 2: Add Fleet row view model**
  - File: `Packages/ConduitKit/Sources/AppFeature/FleetThreadMapper.swift`
  - Pure Swift helper that maps:
    - fleet slot;
    - chat conversations;
    - active run output/status;
    - pending approvals;
    into a row model.
  - Unit test this helper outside SwiftUI.

- [ ] **Task 3: Update sidebar Fleet section**
  - File: `Packages/ConduitKit/Sources/AppFeature/ConduitSidebarView.swift`
  - Show compact fleet rows:
    - host name;
    - agent/vendor;
    - status dot plus text;
    - latest spend/budget if available;
    - attention badge if blocked.
  - Selecting row calls the shell destination `.thread(id)` when mapped, otherwise `.fleet`.

- [ ] **Task 4: Update `FleetView` for secondary role**
  - File: `Packages/ConduitKit/Sources/AppFeature/FleetView.swift`
  - Keep operational controls.
  - Add "Open thread" action for rows with a mapped conversation.
  - Add "Start chat" action for rows without a mapped conversation.
  - Do not make Fleet a duplicate chat list.

- [ ] **Task 5: Connect stop/pause/resume to thread context**
  - File: `Packages/ConduitKit/Sources/AppFeature/FleetView.swift`
  - When a fleet control affects a run, update related conversation/turn status if a mapping exists.
  - Keep daemon channel as source of operational truth.

- [ ] **Task 6: Needs-attention routing from Fleet**
  - If a fleet row has pending approvals, selecting the attention badge should open the related chat with the approval artifact selected when available.
  - If no artifact exists, open Inbox filtered to that approval/session.

## Tests

- [ ] Unit tests for `FleetThreadMapper`:
  - exact conversation ID wins;
  - latest active run ID maps to thread;
  - host/agent/cwd fallback chooses most recent active thread;
  - ambiguous fallback returns no thread;
  - offline slot row still renders.
- [ ] App-target simulator build.
- [ ] Manual UI checks:
  - sidebar Fleet row opens related chat;
  - Fleet detail "Open thread" opens related chat;
  - Fleet detail "Start chat" creates a chat with host/agent preselected;
  - stop/pause/resume still call the daemon channel;
  - blocked fleet item leads to approval context.

## Acceptance Criteria

- Fleet is reachable from the sidebar.
- Fleet rows are operational summaries, not root-mode dashboards.
- Active agents can open related chat threads.
- Starting a chat from a fleet row preselects host/agent/cwd.
- Ambiguous mappings do not open the wrong thread.
- Existing disconnect/reconnect behavior still works.

## Non-Goals

- Do not remove Fleet.
- Do not build a full metrics dashboard.
- Do not change daemon status protocol unless a hard blocker is found.
- Do not implement cloud sync.
