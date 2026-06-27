# Chat Artifacts and Inline Approvals V1

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`. This plan depends on durable chat tables and repository APIs.

**Goal:** Make chat feel like a real coding-agent workspace by showing durable, actionable artifacts inside the thread: tool cards, diffs, touched files, test results, previews, and blocking approvals.

## Dependencies

Requires `2026-06-18-chat-history-search-continuation-v1.md` through at least:

- `ChatConversation`
- `ChatTurn`
- `ChatArtifact`
- `ChatConversationRepository`
- run output/status/tool event persistence

This plan can start with repository/API additions once the base repository exists, but SwiftUI rendering should wait until saved artifacts round-trip in tests.

## Current Reality

- `NewChatTabView` renders live `InlineChatToolCard` from `RunOutputStore.ToolBlock`.
- Tool cards disappear after app restart because `RunOutputStore` is in-memory.
- Approval events persist through `ApprovalRepository` and render in Inbox.
- Chat currently surfaces `needsApproval` as an error message telling the user to check Inbox.
- `PatchPersistenceTests` and approval persistence tests already cover related persistence patterns.

## Artifact Types

Use `ChatArtifact.Kind` from the durable chat plan:

- `tool`
  - source: `agent.tool.start`
  - title: tool name
  - payload: tool input JSON
  - status: running/done/failed if known
- `diff`
  - source: approval patch, patch repository, or future daemon artifact
  - title: changed file summary
  - payload: unified diff or patch ID
- `file`
  - source: tool input path, patch file paths, future daemon artifact
  - title: path
  - payload: path plus optional preview metadata
- `test`
  - source: recognizable test command/tool output for V1, future structured daemon event later
  - title: test command or suite
  - payload: command, status, excerpt
- `preview`
  - source: detected dev server/preview metadata where available
  - title: URL/port
  - payload: URL, host, source run
- `approval`
  - source: `ApprovalRepository`/approval pending event
  - title: command/patch/action
  - payload: approval ID, kind, risk, command, patch pointer

## Implementation Tasks

- [ ] **Task 1: Extend repository artifact API if needed**
  - File: `Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift`
  - Add helpers:
    - `artifacts(turnID:)`
    - `artifacts(runID:)`
    - `updateArtifactStatus(id:status:)`
    - `associateApproval(approvalID:runID:)`
  - Keep FTS artifact text updated.

- [ ] **Task 2: Persist tool artifacts**
  - Files: `Packages/LancerKit/Sources/AppFeature/ApprovalIngest.swift`, chat run persistence sink from the durable chat plan.
  - On `ToolStartParams`, upsert a `tool` artifact keyed by `toolId`.
  - When tool completion is available, update status. If only live `markToolDone` exists, leave persisted status as running until a terminal run status marks unresolved tool artifacts done/unknown.

- [ ] **Task 3: Persist approval artifacts**
  - Files: `Packages/LancerKit/Sources/AppFeature/ApprovalIngest.swift`, `Packages/LancerKit/Sources/InboxFeature/InboxViewModel+Live.swift`, repository.
  - Associate approvals to a chat turn using the best available key:
    - exact `runId` if present in event metadata later;
    - `agentSessionID`/tool use ID if available;
    - fallback to active conversation for same agent/cwd/session while run is active.
  - If no safe association exists, do not guess. Keep it Inbox-only.

- [ ] **Task 4: Add artifact card components**
  - File: `Packages/LancerKit/Sources/AppFeature/ChatArtifactCards.swift`
  - Components:
    - `ChatToolArtifactCard`
    - `ChatDiffArtifactCard`
    - `ChatFileArtifactCard`
    - `ChatTestArtifactCard`
    - `ChatPreviewArtifactCard`
    - `ChatApprovalArtifactCard`
  - Use existing design tokens.
  - Keep cards compact and tappable on phone.

- [ ] **Task 5: Add artifact detail panels**
  - File: `Packages/LancerKit/Sources/AppFeature/ChatArtifactDetailView.swift`
  - Diff: unified diff single-column view.
  - Files: path list and lightweight preview/excerpt.
  - Tests: command, status, output excerpt.
  - Approval: command/patch summary and decision controls only if payload is complete.
  - Tool: raw structured JSON behind disclosure, not shown by default.

- [ ] **Task 6: Render artifacts in `NewChatTabView`**
  - File: `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
  - Saved turns should show saved artifacts.
  - Live turns should merge live `RunOutputStore` tool blocks with persisted artifacts without duplicates.
  - Tapping an artifact opens the detail panel.

- [ ] **Task 7: Inline approval actions**
  - Reuse the same decision path as Inbox:
    - `LiveInboxViewModel.decide`
    - repository persistence
    - daemon channel decision call
  - If the chat approval card lacks complete command/patch data, render "Open in Inbox" instead of inline approve/deny.
  - Decisions must update both Inbox and the chat artifact state.

- [ ] **Task 8: Search integration**
  - Artifact title/summary should be searchable through `chat_fts`.
  - Diff bodies can be too large; index file paths and short summaries first.

## Tests

- [ ] Repository tests for artifact upsert, update, lookup by turn/run, and FTS search.
- [ ] Approval association tests for:
  - exact association;
  - ambiguous association does not attach to the wrong thread;
  - decision updates artifact status.
- [ ] Swift package tests for any extracted artifact mapping helper.
- [ ] App-target simulator build.
- [ ] Manual UI check:
  - live tool card appears;
  - app restart still shows saved artifact;
  - approval card opens Inbox or decides inline;
  - diff/file/test detail panels render in light and dark.

## Acceptance Criteria

- Chat turns show durable artifacts after app restart.
- Tool artifacts no longer depend only on `RunOutputStore`.
- Approval context appears in the related chat when association is safe.
- Inbox remains the source of truth for approval decisions.
- Search can find a thread by artifact title/path/summary.
- Ambiguous approvals are not attached to the wrong chat.

## Non-Goals

- Do not invent daemon protocol changes unless absolutely required.
- Do not store huge diff/test bodies in FTS.
- Do not replace Inbox.
- Do not build a full file browser here.
