# Chat History, Search, and Restart-Safe Continuation V1

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for implementation. Keep this file checked off task-by-task as work lands.

**Created:** 2026-06-18T14:10:46Z

## Goal

Turn the current inline New Chat surface from an active-run-only view into a durable chat workspace:

- users can see recent chat threads after app restart;
- users can search chat titles, prompts, and saved agent output;
- users can reopen an older thread and continue it when the related transport is available;
- chat can show tool/artifact/approval context without making Fleet or Inbox compete as root tabs.

This is the functional follow-up to the sidebar-first prototype pass. No additional visual redesign is required in this plan; Swift should first gain the durable model the UI needs.

## Current Reality

The app has useful live-run plumbing, but it does not yet have durable chat.

- `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
  - `ChatTurn` is local to the view and stores only `prompt` + `runId`.
  - `activeRun`, `chatTitle`, `turns`, `followUpText`, and errors are all `@State`.
  - First dispatch registers a run and replaces `turns` with one in-memory turn.
  - Follow-up calls `active.channel.continueRun(runId:prompt:)`, gets a new `runId`, appends a new in-memory turn, and creates a new `RunControlStore`.
- `Packages/LancerKit/Sources/AppFeature/RunOutputStore.swift`
  - stores streamed chunks, tool blocks, status, and exit code in memory by `runId`.
  - dedupes chunks by sequence number.
  - does not persist output, tool cards, or terminal status.
- `Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift`
  - has migrations through `v9`.
  - persists hosts, approvals, patches, snippets, searchable terminal blocks, session snapshots, audit events, loops, and sync tombstones.
  - has no chat conversation, chat turn, or chat FTS tables.
- `Packages/LancerKit/Sources/PersistenceKit/SessionSnapshotRepository.swift`
  - stores one resumability snapshot per host.
  - this is host/session resume metadata, not conversation history.
- `Packages/LancerKit/Sources/PersistenceKit/BlockRepository.swift`
  - already demonstrates the local FTS pattern through `blocks_fts`.
  - search covers terminal blocks, not chat messages or agent replies.
- `daemon/lancerd/dispatch.go`, `server.go`, and `e2e_router.go`
  - already support `continueRun` as a fresh process with a new `runId`.
  - continue reuses the original run's cwd/model, re-passes policy and budget gates, and returns structured started/blocked/error results.
  - this makes active-session continuation possible, but the iOS app cannot reconstruct thread state after restart.

## Research Baseline

The current market and framework baseline confirms this is a must-have V1 layer, not polish.

- [Claude Remote Control](https://code.claude.com/docs/en/remote-control) emphasizes continuing local sessions from phone/tablet/browser.
- [OpenAI Codex mobile](https://openai.com/index/work-with-codex-from-anywhere/) frames mobile as live work across threads, approvals, project context, screenshots, terminal output, diffs, test results, and model changes.
- [Omnara on the App Store](https://apps.apple.com/us/app/omnara-claude-codex-mobile/id6748426727) markets monitoring, steering, diff review, and approvals for Claude/Codex agents from mobile.
- [Warp Agent Mode docs](https://docs.warp.dev/terminal/input/classic-input/) separate terminal input from a dedicated agent conversation surface.
- [Termius docs](https://docs.termius.com/) show the adjacent mobile-SSH expectation: organized hosts, connection info, snippets, history, and fast reconnection.
- [AI SDK persistence docs](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot-message-persistence) state the general chatbot baseline directly: store and load messages.

## Gap Matrix

| Capability | Today | V1 Target |
| --- | --- | --- |
| Thread list/history | Missing. Active `turns` are `@State` only. | Persist and list recent conversations by last activity. |
| Search | Missing for chat. Terminal block FTS exists elsewhere. | Search conversation title, prompts, saved output, and artifact labels. |
| Continue old thread | Partial. Works only while `activeRun` and channel survive in memory. | Reopen a saved thread and continue from its latest turn when the host/relay channel is available. |
| Restart recovery | Missing. Relaunch loses chat state and output cache. | Rehydrate thread list, turns, saved output, status, and continue affordance. |
| Artifacts in chat | Partial live tool cards only. | Persist minimal artifact records for tool cards, diffs/files/tests/approvals, then render from saved state. |
| Inline approvals | Partial. Chat errors say "check Inbox"; Inbox owns decisions. | Keep Inbox as system of record, but attach blocking approval cards to the related chat turn. |
| Agent context | Present in initial composer only. | Persist host, cwd, vendor, model, budget, policy state per conversation/turn. |
| Fleet placement | Root tab today. | Fleet remains a sidebar section/secondary collection; threads are primary and include fleet/agent context. |

## Architecture Decision

Add a durable local chat model in `LancerCore` and `PersistenceKit`. Keep daemon protocol changes out of V1.

The daemon already knows how to continue a run. The missing owner is iOS-local persistence and rehydration. `RunOutputStore` should remain the live streaming cache; a new repository should own durable conversation metadata, turns, searchable text, and artifact summaries.

### Model

Add LancerCore models:

- `ChatConversation`
  - `id: String`
  - `title: String`
  - `agentID: String`
  - `vendor: String?`
  - `hostName: String`
  - `hostID: String?`
  - `cwd: String`
  - `model: String?`
  - `budgetUSD: Double?`
  - `status: Status`
  - `createdAt`, `updatedAt`, `lastActivityAt`
- `ChatTurn`
  - `id: String`
  - `conversationID: String`
  - `ordinal: Int`
  - `prompt: String`
  - `runID: String`
  - `transportKind: String` (`ssh`, `relay`)
  - `status: Status`
  - `assistantText: String`
  - `errorMessage: String?`
  - `createdAt`, `completedAt`
- `ChatArtifact`
  - `id: String`
  - `conversationID: String`
  - `turnID: String`
  - `runID: String`
  - `kind: Kind` (`tool`, `diff`, `file`, `test`, `approval`)
  - `title: String`
  - `summary: String?`
  - `payloadJSON: String`
  - `status: Status`
  - `createdAt`, `updatedAt`

Do not add typed IDs unless the implementation touches enough call sites to justify it. Existing `Loop` uses string IDs and is an acceptable pattern for this V1.

### Database

Add migration `v10` to `AppDatabase`:

- `chat_conversations`
  - primary key `id`
  - indexed `last_activity_at`, `status`, `agent_id`, `host_name`
- `chat_turns`
  - primary key `id`
  - foreign key `conversation_id` cascade delete
  - unique `(conversation_id, ordinal)`
  - indexed `run_id`
- `chat_artifacts`
  - primary key `id`
  - foreign keys `conversation_id`, `turn_id` cascade delete
  - indexed `run_id`, `kind`, `status`
- `chat_fts`
  - FTS5 table with `title`, `prompt`, `assistant_text`, and `artifact_text`

Update `wipeAll()` to clear `chat_artifacts`, `chat_turns`, `chat_conversations`, and `chat_fts` safely.

### Repository

Add `ChatConversationRepository` in `PersistenceKit`:

- `createConversation(...) -> ChatConversation`
- `appendTurn(conversationID:prompt:runID:transportKind:) -> ChatTurn`
- `updateTurnOutput(runID:assistantText:status:exitCode:errorMessage:)`
- `upsertArtifact(...)`
- `conversation(id:) -> ChatConversation?`
- `turns(conversationID:) -> [ChatTurn]`
- `artifacts(conversationID:) -> [ChatArtifact]`
- `recent(limit:offset:) -> [ChatConversation]`
- `search(_ query:limit:) -> [ChatConversationSearchResult]`
- `deleteConversation(_ id:)`

Search should update FTS rows inside the same write transaction as conversation/turn/artifact updates. Apply `Redactor.shared` when saving assistant text if `redactSavedHistory` is enabled, matching `BlockRepository`.

### Streaming Persistence

Do not make `RunOutputStore` talk directly to SQLite.

Add a small persistence coordinator owned by `AppRoot` or `ApprovalIngest`, for example `ChatRunPersistenceSink`, that receives the same typed run events:

- `runOutput`: append/dedupe in `RunOutputStore`; schedule a throttled durable text update for `runID`.
- `runStatus`: update live store and persist turn status/completion.
- `toolStart`: update live store and persist/update a `tool` artifact.
- approval pending: persist `approval` artifact when its `sessionId`/tool metadata can be associated; otherwise keep Inbox-only and add association later.

Minimum V1 can persist final text on terminal status. Better V1 persists streaming text every 500-1000 ms so a killed app still preserves recent output.

## Implementation Tasks

- [ ] **Task 1: Add LancerCore chat models**
  - Files: `Packages/LancerKit/Sources/LancerCore/ChatConversation.swift`
  - Include status enums, memberwise initializers, `Codable`, `Sendable`, `Identifiable`, and sample debug data if useful.
  - Keep the model UI-free.

- [ ] **Task 2: Add v10 chat tables and wipe support**
  - File: `Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift`
  - Add `chat_conversations`, `chat_turns`, `chat_artifacts`, and `chat_fts`.
  - Add cascade foreign keys where GRDB supports them.
  - Add the new tables to `wipeAll()`.

- [ ] **Task 3: Add `ChatConversationRepository`**
  - File: `Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift`
  - Follow the direct SQL/GRDB row decoding style used by `LoopRepository` and `SessionSnapshotRepository`.
  - Keep all writes transactional and FTS updates in sync.

- [ ] **Task 4: Add repository tests**
  - File: `Packages/LancerKit/Tests/LancerKitTests/ChatConversationRepositoryTests.swift`
  - Required tests:
    - create + fetch conversation;
    - append ordered turns;
    - update turn output/status by `runID`;
    - recent conversations sort by `last_activity_at DESC`;
    - search matches title, prompt, assistant output, and artifact text;
    - delete conversation cascades turns/artifacts;
    - `wipeAll()` removes chat data;
    - redaction setting is respected for saved assistant output.

- [ ] **Task 5: Wire repository into app environment**
  - File: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
  - Add `chatRepo` to `AppEnvironment`.
  - Instantiate it beside the other repositories.
  - Do not change root navigation yet.

- [ ] **Task 6: Persist first dispatch and follow-up turns**
  - File: `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
  - Prefer extracting a small platform-agnostic chat state helper if logic grows.
  - On successful initial dispatch:
    - create a conversation using selected agent, host/cwd, model, budget, and title;
    - append the first turn with `runId`;
    - register the run in `RunOutputStore`.
  - On successful follow-up:
    - append a turn to the existing conversation with the new `runId`;
    - update conversation `lastActivityAt`;
    - keep live `RunControlStore` behavior unchanged.

- [ ] **Task 7: Persist run output/status/artifacts**
  - Files: `Packages/LancerKit/Sources/AppFeature/ApprovalIngest.swift`, `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
  - Add a sink/coordinator that maps run events to repository updates.
  - SSH and E2E relay paths must both feed the same sink.
  - Preserve current `RunOutputStore` behavior.

- [ ] **Task 8: Add thread list/search state without redesigning shell**
  - File: `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
  - Add a minimal recent/search panel within the existing New Chat tab, behind a button or compact sidebar-like overlay.
  - Load recent conversations on appear.
  - Search calls the repository.
  - Selecting a conversation loads turns/artifacts and renders saved messages.
  - This can be replaced by the sidebar shell later.

- [ ] **Task 9: Restart-safe continuation**
  - Files: `NewChatTabView.swift`, possibly `AppRoot.swift`
  - When a saved conversation is selected, find the latest turn with a `runID`.
  - If its transport channel is active, allow Continue and call `continueRun` with that latest `runID`.
  - If transport is not active, show a clear disabled state: reconnect the host/relay to continue.
  - Do not fake continuation when the daemon cannot find the run; surface the structured error and leave the thread intact.

- [ ] **Task 10: Inline blocking context**
  - Files: repository + `NewChatTabView.swift`
  - Persist approval artifacts when they can be associated to a run/turn.
  - Render an inline approval card that deep-links to Inbox or calls the same decision path as Inbox if the command/patch payload is complete.
  - Inbox remains the source of truth for decisions.

- [ ] **Task 11: Verification**
  - Run `swift test --package-path Packages/LancerKit`.
  - Run the iOS app-target simulator build with XcodeBuildMCP, because SwiftPM can skip `#if os(iOS)` UI code.
  - Run existing daemon continue tests if daemon behavior is touched: `go test ./daemon/lancerd/...`.

## Acceptance Criteria

- Relaunching the app preserves recent chat conversations and at least final assistant output for completed turns.
- Searching from New Chat finds conversations by title, user prompt, saved assistant output, and artifact title/summary.
- Starting a new chat creates a durable conversation before or immediately after the first run starts.
- Sending a follow-up appends a durable turn with the new `runId`.
- Selecting an older thread shows its ordered turns without needing live run output in memory.
- Continue is enabled only when the associated channel is active and the latest run can be continued.
- E2E relay and SSH dispatch paths both persist turns/output through the same repository layer.
- Existing Inbox approval persistence continues to work.
- Reset app clears chat history.

## Non-Goals

- No sidebar Swift shell replacement in this pass.
- No daemon-side conversation database in this pass.
- No cloud sync for conversations in this pass.
- No local file editor or terminal reimplementation.
- No Codex continue enablement beyond the existing unsupported/structured error path.

## Suggested Follow-Up After This Lands

Once durable chat is working, replace the compact tabs with the sidebar-first shell from the prototype:

- Chat becomes the default detail view.
- Recent Threads, Needs Attention, Fleet, and Settings become sidebar sections.
- Fleet remains essential for hosts/running agents/status/spend/stop controls, but it should not compete with chat as a root-mode tab.
