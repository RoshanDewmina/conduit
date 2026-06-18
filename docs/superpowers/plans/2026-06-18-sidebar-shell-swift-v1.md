# Sidebar Shell Swift V1

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`. This is a Swift UI implementation plan, not a product ideation brief.

**Goal:** Replace Conduit's tab-first root with a chat-first sidebar shell on all device classes, using the prototype direction in `docs/conduit-ui-prototype/app/interactive/page.tsx` as the interaction reference.

## Dependencies

This plan should run after, or alongside the final stages of, `2026-06-18-chat-history-search-continuation-v1.md`.

Do not ship a sidebar whose Recent Threads and Search are only mock data. If the chat repository is not ready, land only the shell scaffolding behind a debug flag.

## Current Reality

- `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`
  - `Tab.rootTabs` is `Inbox / Fleet / New Chat / Settings`.
  - compact width uses a bottom `DSTabBar`.
  - regular width uses `NavigationSplitView` with a simple `List` of tabs.
  - `NewChatTabView` is one root tab, not the default app shell.
- `docs/conduit-ui-prototype/app/interactive/page.tsx`
  - already demonstrates three sidebar variants.
  - current recommendation is Chat-first.
  - sidebar contains New Chat, Search, Recent Threads, Needs Attention, Fleet, Settings.

## Product Decision

Implement the Chat-first variant for Swift V1.

- First app surface: chat detail.
- Sidebar applies everywhere:
  - iPhone: drawer opened by toolbar button; auto-closes after selection.
  - iPad: persistent sidebar using `NavigationSplitView`.
- Do not keep a bottom tab bar.
- Do not reintroduce Activity as a root item.
- Fleet remains in the sidebar.
- Inbox/Needs Attention remains visible, but approvals resolve in Inbox and can be opened from chat context.

## Proposed Types

Add UI-only routing types in `AppFeature`:

- `SidebarDestination`
  - `.newChat`
  - `.thread(String)`
  - `.needsAttention`
  - `.fleet`
  - `.settings`
- `SidebarSection`
  - static sections for actions and settings
  - dynamic sections for recent threads, attention count, and fleet agents
- `SidebarShellState`
  - selected destination
  - sidebar open state for compact width
  - search query
  - filtered thread IDs

Keep the data models from `ConduitCore`/`PersistenceKit`; do not duplicate persisted chat entities in UI state.

## Implementation Tasks

- [ ] **Task 1: Add a sidebar destination model**
  - File: `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift` or a new small `SidebarShell.swift` if `AppRoot.swift` becomes too large.
  - Add the destination enum and selection state.
  - Preserve existing `CONDUIT_TAB` debug launch behavior by mapping `newchat` to the chat destination, `inbox` to needs-attention, `fleet` to fleet, and `settings` to settings.

- [ ] **Task 2: Build `ConduitSidebarView`**
  - File: `Packages/ConduitKit/Sources/AppFeature/ConduitSidebarView.swift`
  - Sections:
    - New Chat action.
    - Search field.
    - Recent Threads.
    - Needs Attention.
    - Fleet.
    - Settings.
  - Use existing `DesignSystem` tokens and `conduitGlassChrome`.
  - Use icons for primary actions.
  - Keep text compact and phone-readable.

- [ ] **Task 3: Replace compact bottom tabs with drawer shell**
  - File: `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`
  - Replace `compactRoot` and `tabContent` with a chat detail plus drawer overlay.
  - Detail should default to `NewChatTabView`.
  - A toolbar/sidebar button opens the drawer.
  - Selecting a sidebar item closes the drawer on compact width.

- [ ] **Task 4: Replace regular split list with persistent sidebar**
  - File: `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`
  - Use `NavigationSplitView` with `ConduitSidebarView` as the sidebar.
  - Detail renders `SidebarDestination`.
  - Keep `SessionView` full-screen cover behavior intact.

- [ ] **Task 5: Wire destinations to existing surfaces**
  - `.newChat` and `.thread(id)` route to `NewChatTabView` in the appropriate mode.
  - `.needsAttention` routes to `InboxView` or a narrowed pending-only wrapper.
  - `.fleet` routes to `FleetView`.
  - `.settings` routes to `SettingsRoot`.
  - Keep `RunDetailView` and session covers reachable.

- [ ] **Task 6: Connect sidebar data**
  - Recent Threads: from `ChatConversationRepository.recent`.
  - Search: from `ChatConversationRepository.search`.
  - Needs Attention: pending approvals from `activeInboxViewModel`.
  - Fleet: current `fleetStore.slots`.
  - Avoid polling loops; load on appear and refresh after relevant state changes.

- [ ] **Task 7: Preserve deep links and notification routes**
  - Approval notification action must still route to the related approval.
  - Run-complete action must still open the related live session/thread.
  - Existing `.conduitApprovalAction` and `.conduitRunCompleteAction` observers must keep working.

- [ ] **Task 8: Remove dead tab UI after shell is stable**
  - Remove or stop using `DSTabBar` from the root shell if no longer needed.
  - Do not delete `DSTabBar` globally if gallery or other debug surfaces still use it.

## Testing

- [ ] Run `swift test --package-path Packages/ConduitKit`.
- [ ] Run app-target simulator build with XcodeBuildMCP.
- [ ] Launch compact iPhone simulator:
  - app opens to chat;
  - sidebar button opens drawer;
  - drawer closes after selecting thread/fleet/settings;
  - search filters recent threads;
  - no bottom tab bar remains.
- [ ] Launch iPad/regular-width simulator:
  - persistent sidebar appears;
  - detail defaults to chat;
  - selecting sidebar items updates detail without losing environment state.
- [ ] Verify light and dark appearances.
- [ ] Verify VoiceOver labels for sidebar toggle, New Chat, Search, and Fleet rows.

## Acceptance Criteria

- First-view app experience is chat.
- Sidebar exists on iPhone and iPad.
- Bottom tabs are no longer the primary root navigation.
- Recent Threads, Needs Attention, Fleet, and Settings are reachable from the sidebar.
- Selecting a Fleet item can open Fleet detail in this plan; related chat routing is completed in `2026-06-18-fleet-thread-routing-v1.md`.
- No regression to notification approval handling.
- No new Swift concurrency warnings in the app-target build.

## Non-Goals

- Do not build durable chat persistence here.
- Do not redesign individual Inbox/Fleet/Settings screens beyond fitting them into the shell.
- Do not add cloud sync.
- Do not solve physical-device APNs validation here.
