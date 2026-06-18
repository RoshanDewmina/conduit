# Conduit V1 Implementation Handoff Index

> **For agentic workers:** Start here, then open the specific plan for your assigned lane. Do not implement from this index alone.

**Created:** 2026-06-18

## Purpose

Split the remaining V1 work into handoff-ready plans that can be assigned to separate agents without them stepping on each other. The app direction is now chat-first and sidebar-first, but the implementation should land in safe dependency order.

## Source Plans

1. `docs/superpowers/plans/2026-06-18-chat-history-search-continuation-v1.md`
   - Durable local chat model, SQLite persistence, search, saved turns, restart-safe continuation.
   - This is the first product dependency. Most other UI work should not land before this exists.

2. `docs/superpowers/plans/2026-06-18-sidebar-shell-swift-v1.md`
   - Replace tab-first app shell with sidebar-first navigation on all device classes.
   - Depends on the durable chat repository for real Recent Threads and Search.

3. `docs/superpowers/plans/2026-06-18-chat-artifacts-approvals-v1.md`
   - Persist and render rich chat artifacts: tool cards, diffs, files, tests, previews, approval cards.
   - Depends on the durable chat repository.

4. `docs/superpowers/plans/2026-06-18-fleet-thread-routing-v1.md`
   - Reframe Fleet as a sidebar section and secondary collection that opens related chat threads.
   - Depends on the sidebar shell and durable chat thread association.

5. `docs/superpowers/plans/2026-06-18-v1-launch-hardening-testflight.md`
   - Verification, app-target build/archive, repeatable relay regression, APNs/TestFlight readiness, a11y sweep.
   - Can run partly in parallel, but final release verification must happen after product changes land.

## Recommended Execution Order

### Wave 1 - Data Foundation

- Implement `2026-06-18-chat-history-search-continuation-v1.md`.
- Run repository tests and app-target build.
- Do not start the sidebar Swift replacement until chat history/search are real enough to populate it.

### Wave 2 - Product Surfaces

- Implement `2026-06-18-chat-artifacts-approvals-v1.md`.
- Implement `2026-06-18-sidebar-shell-swift-v1.md`.
- These touch overlapping UI files, especially `AppRoot.swift` and `NewChatTabView.swift`; coordinate branches or sequence merges.

### Wave 3 - Fleet Integration

- Implement `2026-06-18-fleet-thread-routing-v1.md`.
- This should come after sidebar primitives exist so Fleet does not get rebuilt twice.

### Wave 4 - Launch Gate

- Implement `2026-06-18-v1-launch-hardening-testflight.md`.
- Re-run the complete verification matrix and update canonical launch docs.

## Parallelization Guidance

Safe to run in parallel:

- Chat repository/model work and launch-hardening doc/test audit.
- Chat artifact model/repository work and sidebar visual shell planning, as long as only one agent edits `AppRoot.swift`/`NewChatTabView.swift` at a time.

Avoid parallel edits:

- Two agents editing `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`.
- Two agents editing `Packages/ConduitKit/Sources/AppFeature/NewChatTabView.swift`.
- Sidebar shell and Fleet routing in the same files before the shell is merged.
- Release checklist updates before the verification commands have actually run.

## Current Product Decision

- Chat is the default first surface.
- Sidebar applies to all device classes:
  - iPhone: collapsible drawer.
  - iPad: persistent sidebar where width allows.
- Fleet is essential, but not a root-mode competitor to chat. Fleet belongs in the sidebar and opens thread detail.
- Inbox remains the system of record for approvals, but chat should show blocking approval context inline.
- Activity/history does not return as a root destination. Its useful pieces fold into Recent Threads, Needs Attention, and audit/history details.

## Definition Of Done For V1

- A new user opens the app and lands in chat.
- Recent threads survive app restart.
- Search finds prior prompts, saved assistant output, and artifacts.
- A user can continue an old thread when the related host/relay channel is available.
- Approvals appear both in Inbox and in the related chat context.
- Fleet shows hosts/agents/status/spend/stop controls and opens related threads.
- App-target simulator build is green.
- Swift package tests are green.
- Daemon tests are green if daemon behavior changes.
- Prototype and Swift app agree on the chosen IA.
- Launch docs state verified current reality, not stale assumptions.
