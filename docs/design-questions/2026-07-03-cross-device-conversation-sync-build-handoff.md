# Cross-Device Conversation Sync Build Handoff

Prepared: 2026-07-03  
Audience: Claude Code or another implementation agent  
Source question: `docs/design-questions/2026-07-02-cross-device-sync-second-opinion.md`

## Agent Instructions

Before changing code, read:

- `AGENTS.md`
- `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md`
- `ARCHITECTURE.md` sections `0.1`, `4.1`, `11.2`, and `11.3`
- `docs/agent-contract.md`
- `docs/KNOWN_ISSUES.md`
- `docs/PUBLISH_READINESS_CHECKLIST.md`
- `docs/LIVE_LOOP_RUNBOOK.md`
- `docs/LAUNCH_AUDIT-2026-06-18.md`

If you change `daemon/lancerd/dispatch.go` or any vendor CLI resume argv behavior, use the `vendor-cli-adapter-audit` skill first. The resume flags are drift-prone and this work depends on exact session continuation.

Do not revert unrelated dirty worktree changes. Start with `git status --short`, understand what is already modified, and work around owner/other-agent changes.

## Executive Decision

Build the no-compromises solution:

**Host-owned durable conversation ledger + CloudKit private-database mirror + exact vendor-session binding.**

This is not "just extend Observed Sessions" and not "just sync the phone SQLite database through CloudKit." The host must remain authoritative for runnable agent state because the workspace, cwd, vendor CLI, policy gate, hooks, and exact resume target live on the user's machine. CloudKit should make conversation history and metadata available across Apple devices and after app reinstall, but CloudKit must not be treated as the thing that can continue an agent run by itself.

The implementation target is:

- A Lancer-created chat can be opened from any paired iPhone/iPad signed into the same iCloud account.
- The transcript is visible even if the original phone is gone.
- A follow-up resumes the exact vendor session when the host is reachable.
- If the host is offline, the user can read cached/synced history but cannot silently queue a prompt for later execution.
- Terminal-originated sessions discovered through Observed Sessions can be attached/imported into the same conversation model.

## Why This Is The Right Architecture

Current repo reality:

- `ARCHITECTURE.md` says V1 transport is phone -> blind E2E relay -> resident `lancerd`; the phone does not hold the session.
- `ChatConversationRepository` persists conversations, turns, artifacts, and FTS in the local iOS GRDB database only.
- `SyncEngine` currently syncs Hosts and Snippets only.
- `CloudSync` uses the private CloudKit database, which is the right account-level Apple-device mirror, but it is currently a small metadata sync layer.
- Observed Sessions can list/fetch/continue terminal-originated sessions using host-side provider transcript stores and exact vendor session IDs.
- Ordinary phone-created follow-up still falls back to "continue latest in cwd" when `lancerd` no longer has the run in memory.
- `push-backend` has run-log storage, but that belongs to the hosted runner/control-plane path. It is not the V1 self-host relay source of truth.

Therefore:

- **Pure host storage** is correct for continuation but insufficient for multi-device/reinstall experience.
- **Pure CloudKit** gives history sync but cannot guarantee exact runnable continuation.
- **Observed Sessions alone** is useful plumbing, but it is a reader/import path, not a durable Lancer-owned write model.

The hybrid model gives the product what the user expects without painting the system into a corner.

## Non-Negotiable Product Semantics

1. **The host owns execution truth.** If the conversation can be continued, `lancerd` proves that by owning the ledger row, cwd, provider, policy context, run history, and stable vendor session ID.

2. **CloudKit owns Apple-device continuity.** CloudKit mirrors conversation summaries, turns, transcript chunks, artifact metadata, read/archive state, and tombstones in the user's private database.

3. **The iOS GRDB database is a cache and UI index.** It remains important for fast UI, search, offline read, and local drafts, but it stops being the sole source of truth.

4. **Every prompt append is host-mediated.** Do not let two phones both append by writing CloudKit records and hoping the host later reconciles them. The host is the single writer for executable turns.

5. **No silent offline execution queue.** If host is offline, save the text as a local draft. Require a user tap after reconnect.

6. **Exact vendor session ID is mandatory.** Continuing "latest in cwd" is acceptable only as a backwards-compatibility fallback for old/incomplete ledgers, and the UI should surface degraded resume confidence if this fallback is used.

7. **Conversation records are append-first.** Transcript chunks/events should be immutable append records. Summary records may be last-write-wins.

8. **Do not put private keys or secrets in CloudKit.** Existing Keychain/security boundaries remain unchanged.

## External Platform Facts To Respect

Use official Apple docs as the baseline:

- CloudKit private database is per-user and only available when the device has an iCloud account: https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase
- CloudKit supports remote record change flows and subscriptions: https://developer.apple.com/documentation/cloudkit/remote-records
- `CKFetchRecordZoneChangesOperation` is the relevant primitive for zone change fetching: https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation
- `CKDatabaseSubscription` can notify on changes in custom zones: https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- CloudKit request/record limits matter. Apple's CloudKit Web Services archive lists a 1 MB maximum record size excluding assets, 50 MB asset field maximum, 200 operations per request, and 200 records per response: https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html
- `CKModifyRecordsOperation.RecordSavePolicy.changedKeys` should be used carefully. It is fine for summary metadata updates but should not be the conflict strategy for executable turn appends: https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/changedkeys

Design implication: do not store one giant transcript record. Use small immutable chunk records and assets for large payloads.

## Existing Code Surfaces

### iOS Local Conversation Storage

- `Packages/LancerKit/Sources/LancerCore/ChatConversation.swift`
  - Current model has `ChatConversation`, `ChatTurn`, `ChatArtifact`.
  - Missing host ledger sequence, vendor session ID, CloudKit sync metadata, draft state, and authoritative source state.

- `Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift`
  - Migration `v10` creates `chat_conversations`, `chat_turns`, `chat_artifacts`, `chat_fts`.
  - Add a later migration. Do not rewrite existing migrations.

- `Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift`
  - Current repository creates conversations locally, appends turns locally, updates turn output by `runID`, and persists artifacts.
  - Add mirror/upsert APIs. Do not make UI code write host-authoritative rows directly except drafts.

### iOS CloudKit Layer

- `Packages/LancerKit/Sources/SyncKit/CloudSync.swift`
  - Low-level private CloudKit wrapper.
  - Currently no-op without entitlement and simulator unsupported.

- `Packages/LancerKit/Sources/SyncKit/SyncEngine.swift`
  - Hosts/Snippets only.
  - Add a separate `ConversationSyncEngine` instead of bloating this actor.

### iOS Relay/SSH Protocols

- `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift`
  - Add shared Codable structs for conversation RPCs.

- `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift`
  - Add relay payload structs as needed.

- `Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift`
  - Add SSH RPC methods for `agent.conversations.*`.

- `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`
  - Add relay request/response methods mirroring `sendDispatch`, `sendRunContinue`, `relayListSessions`, and `relayFetchTranscript`.

### iOS UI Integration

- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
  - `performDispatch` currently calls relay/SSH dispatch then the UI creates local chat rows.
  - `resumeConversation` currently continues by `lastRunID` with fallback agent/cwd/model.
  - Route new chats and follow-ups through conversation append RPCs.

- `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
  - Currently creates a local conversation after dispatch succeeds.
  - It should receive `conversationID`, `turnID`, `runID`, `cwd`, and `vendorSessionID` from daemon-backed append/dispatch.

- `Packages/LancerKit/Sources/AppFeature/ChatHistoryView.swift`
  - Load local mirror immediately, then refresh from host if available, then refresh from CloudKit if host unavailable.

- `Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift`
  - Recent conversations should read from the local mirror, with host/cloud sync status metadata available for subtle states.

### Daemon Dispatch And Observed Sessions

- `daemon/lancerd/server.go`
  - Add JSON-RPC methods beside `agent.sessions.list`, `agent.sessions.transcript`, `agent.dispatch`, `agent.run.continue`, and `agent.observedSession.continue`.
  - `emitNotification` is the current fanout point for live output/status and is the right place to tee run events into the ledger.

- `daemon/lancerd/e2e_router.go`
  - Add relay message handlers mirroring the SSH RPCs.

- `daemon/lancerd/session_index.go`
  - Observed Sessions list/fetch provider transcript data. Keep this path, but do not make it the Lancer-created conversation store.

- `daemon/lancerd/dispatch.go`
  - `continueArgv` resumes the most recent vendor session in cwd.
  - `resumeArgv` resumes an exact vendor session ID and is already the better semantic.
  - `dispatchRun.SessionID` exists but is only reserved. Fill it.
  - `streamJSONOutput` suppresses metadata today. Change it to extract vendor session/thread IDs and emit/persist them.

### Hosted Control Plane

- `daemon/push-backend/run_logs.go`
  - This has run log persistence for hosted runner features.
  - Do not reuse this as V1 self-host conversation truth. The V1 relay is blind E2E transport, and Lancer's self-host thesis depends on host-owned execution state.

## Target Data Model

### Daemon Host Ledger

Create `daemon/lancerd/conversation_store.go` and `daemon/lancerd/conversation_store_test.go`.

Use host-local SQLite at:

```text
~/.lancer/conversations.sqlite
```

Use a pure-Go SQLite driver, preferably `modernc.org/sqlite`, so the daemon does not depend on the external `sqlite3` binary for its own canonical store. This is an intentional dependency because the ledger is core infrastructure and needs indexed reads, transactions, and crash safety.

Recommended tables:

```sql
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  provider TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  host_id TEXT,
  host_name TEXT NOT NULL,
  cwd TEXT NOT NULL,
  model TEXT,
  budget_usd REAL,
  state TEXT NOT NULL,
  source TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_activity_at TEXT NOT NULL,
  last_seq INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS conversation_turns (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  client_turn_id TEXT NOT NULL,
  prompt TEXT NOT NULL,
  run_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  vendor_session_id TEXT,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  error_message TEXT,
  UNIQUE(conversation_id, ordinal),
  UNIQUE(conversation_id, client_turn_id),
  UNIQUE(run_id)
);

CREATE TABLE IF NOT EXISTS conversation_events (
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  turn_id TEXT,
  run_id TEXT,
  kind TEXT NOT NULL,
  role TEXT,
  stream TEXT,
  text TEXT,
  payload_json TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY(conversation_id, seq)
);

CREATE TABLE IF NOT EXISTS conversation_artifacts (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  turn_id TEXT,
  run_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_conversations_last_activity
  ON conversations(last_activity_at DESC);

CREATE INDEX IF NOT EXISTS idx_turns_conversation_ordinal
  ON conversation_turns(conversation_id, ordinal);

CREATE INDEX IF NOT EXISTS idx_events_conversation_seq
  ON conversation_events(conversation_id, seq);

CREATE INDEX IF NOT EXISTS idx_turns_vendor_session
  ON conversation_turns(provider, vendor_session_id);
```

If SQLite driver dependency is rejected in review, use append-only JSONL plus compacted index files only as a deliberate reviewer-approved fallback. Do not default to ad hoc JSON maps.

### iOS Local Mirror

Add an append-only migration after `v11` in `AppDatabase.swift`.

Extend existing local tables instead of replacing them:

```sql
ALTER TABLE chat_conversations ADD COLUMN source_host_id TEXT;
ALTER TABLE chat_conversations ADD COLUMN source_host_name TEXT;
ALTER TABLE chat_conversations ADD COLUMN last_host_seq INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chat_conversations ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'localOnly';
ALTER TABLE chat_conversations ADD COLUMN cloud_record_name TEXT;
ALTER TABLE chat_conversations ADD COLUMN cloud_uploaded_at DATETIME;
ALTER TABLE chat_conversations ADD COLUMN cloud_modified_at DATETIME;
ALTER TABLE chat_conversations ADD COLUMN archived_at DATETIME;

ALTER TABLE chat_turns ADD COLUMN client_turn_id TEXT;
ALTER TABLE chat_turns ADD COLUMN vendor_session_id TEXT;
ALTER TABLE chat_turns ADD COLUMN host_seq_start INTEGER;
ALTER TABLE chat_turns ADD COLUMN host_seq_end INTEGER;
ALTER TABLE chat_turns ADD COLUMN cloud_record_name TEXT;

CREATE TABLE chat_events (
  conversation_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  turn_id TEXT,
  run_id TEXT,
  kind TEXT NOT NULL,
  role TEXT,
  stream TEXT,
  text TEXT,
  payload_json TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(conversation_id, seq),
  FOREIGN KEY(conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE
);
```

Add repository APIs:

```swift
public func upsertConversationMirror(_ conversation: ChatConversation, lastHostSeq: Int, syncState: ChatConversation.SyncState) async throws

public func upsertTurnMirror(_ turn: ChatTurn, vendorSessionID: String?, hostSeqStart: Int?, hostSeqEnd: Int?) async throws

public func appendEventsMirror(conversationID: String, events: [ChatEvent]) async throws

public func markCloudUploaded(conversationID: String, recordName: String, modifiedAt: Date?) async throws

public func localDraft(conversationID: String) async throws -> ChatDraft?
```

The exact Swift model names can be adjusted to fit existing style, but these capabilities must exist.

### CloudKit Private Mirror

Create a custom zone:

```text
LancerConversations
```

Use these record types:

#### `Conversation`

Record name: `conversationID`

Fields:

- `title: String`
- `provider: String`
- `agentID: String`
- `sourceHostID: String`
- `sourceHostName: String`
- `cwd: String`
- `cwdHash: String`
- `model: String`
- `state: String`
- `lastHostSeq: Int64`
- `lastActivityAt: Date`
- `createdAt: Date`
- `updatedAt: Date`
- `archivedAt: Date?`
- `deletedAt: Date?`

#### `ConversationTurn`

Record name: `conversationID:turnID`

Fields:

- `conversationID: String`
- `turnID: String`
- `ordinal: Int64`
- `clientTurnID: String`
- `prompt: String`
- `runID: String`
- `provider: String`
- `vendorSessionID: String`
- `status: String`
- `hostSeqStart: Int64`
- `hostSeqEnd: Int64`
- `createdAt: Date`
- `completedAt: Date?`

Use `conversationID` string fields for query/sort. Do not rely on thousands of `CKRecord.Reference` children from one root record.

#### `ConversationEventChunk`

Record name: `conversationID:seqStart:seqEnd`

Fields:

- `conversationID: String`
- `turnID: String?`
- `runID: String?`
- `seqStart: Int64`
- `seqEnd: Int64`
- `kind: String`
- `text: String?`
- `payloadJSON: String?`
- `asset: CKAsset?`
- `createdAt: Date`

Chunk text/events to stay comfortably below CloudKit limits. Prefer text fields for small chunks and `CKAsset` for larger transcript payloads.

#### `ConversationArtifact`

Record name: `conversationID:artifactID`

Fields:

- `conversationID: String`
- `turnID: String?`
- `runID: String`
- `kind: String`
- `title: String`
- `summary: String?`
- `status: String`
- `payloadJSON: String?`
- `payloadAsset: CKAsset?`
- `createdAt: Date`
- `updatedAt: Date`

Default policy: sync artifact metadata and small redacted payloads. Large or sensitive payloads should stay host-local unless product explicitly opts in.

## RPC Contract

Add Codable Swift structs in `LancerDProtocol.swift` and matching Go structs.

### `agent.conversations.list`

Request:

```json
{
  "limit": 50,
  "cursor": "",
  "includeArchived": false
}
```

Response:

```json
{
  "conversations": [
    {
      "id": "conv_...",
      "title": "Fix auth redirect",
      "provider": "claudeCode",
      "agentID": "claudeCode",
      "hostID": "host_...",
      "hostName": "Roshan MacBook",
      "cwd": "/Users/roshan/project",
      "model": "sonnet",
      "state": "active",
      "lastSeq": 42,
      "lastActivityAt": "2026-07-03T01:00:00Z",
      "createdAt": "2026-07-03T00:30:00Z",
      "updatedAt": "2026-07-03T01:00:00Z"
    }
  ],
  "nextCursor": ""
}
```

### `agent.conversations.fetch`

Request:

```json
{
  "conversationId": "conv_...",
  "sinceSeq": 0,
  "limit": 500
}
```

Response:

```json
{
  "conversation": {},
  "turns": [],
  "events": [],
  "artifacts": [],
  "nextSeq": 42,
  "hasMore": false
}
```

### `agent.conversations.append`

This is the main command for new chats and follow-ups.

Request for new chat:

```json
{
  "conversationId": null,
  "baseSeq": 0,
  "clientTurnId": "ios-device-uuid:monotonic-id",
  "agent": "claudeCode",
  "cwd": "~",
  "prompt": "Fix the failing auth test",
  "model": "sonnet",
  "budgetUSD": 5.0
}
```

Request for follow-up:

```json
{
  "conversationId": "conv_...",
  "baseSeq": 42,
  "clientTurnId": "ios-device-uuid:monotonic-id",
  "prompt": "Now add a regression test"
}
```

Response:

```json
{
  "status": "started",
  "conversationId": "conv_...",
  "turnId": "turn_...",
  "runId": "run_...",
  "vendorSessionId": "provider-session-id-if-known",
  "cwd": "/Users/roshan/project",
  "baseSeq": 42,
  "nextSeq": 43,
  "resumeMode": "exact",
  "message": null,
  "rule": null
}
```

Allowed `status` values:

- `started`
- `needsApproval`
- `denied`
- `budgetExceeded`
- `conflict`
- `hostUnavailable`
- `error`

Allowed `resumeMode` values:

- `new`
- `exact`
- `latestInCwdFallback`
- `none`

Conflict response:

```json
{
  "status": "conflict",
  "conversationId": "conv_...",
  "baseSeq": 42,
  "nextSeq": 45,
  "message": "Conversation changed. Refetch before appending."
}
```

### `agent.conversations.archive`

Request:

```json
{
  "conversationId": "conv_...",
  "archived": true
}
```

Response:

```json
{
  "ok": true,
  "conversationId": "conv_...",
  "lastSeq": 46
}
```

### `agent.conversations.attachObservedSession`

Use this to convert a terminal-originated session into a Lancer conversation.

Request:

```json
{
  "provider": "claudeCode",
  "sessionId": "vendor-session-id",
  "cwd": "/Users/roshan/project"
}
```

Response:

```json
{
  "conversationId": "conv_...",
  "importedEvents": 120,
  "lastSeq": 120
}
```

## Implementation Plan

### Task 1: Daemon host ledger

**Files:**

- Create: `daemon/lancerd/conversation_store.go`
- Create: `daemon/lancerd/conversation_store_test.go`
- Modify: `daemon/lancerd/go.mod`
- Modify: `daemon/lancerd/go.sum`

**Interfaces produced:**

- `type conversationStore struct`
- `func openConversationStore(home string) (*conversationStore, error)`
- `func (s *conversationStore) list(limit int, cursor string, includeArchived bool) (conversationListResult, error)`
- `func (s *conversationStore) fetch(conversationID string, sinceSeq int64, limit int) (conversationFetchResult, error)`
- `func (s *conversationStore) beginTurn(req conversationAppendRequest, resolvedCWD string, runID string) (conversationAppendResult, error)`
- `func (s *conversationStore) appendRunOutput(runID string, stream string, chunk string, seq int) error`
- `func (s *conversationStore) appendRunStatus(runID string, status string, exitCode *int) error`
- `func (s *conversationStore) upsertArtifact(event map[string]any) error`
- `func (s *conversationStore) bindVendorSession(runID string, vendorSessionID string) error`

**Steps:**

- [x] Add `modernc.org/sqlite` to `daemon/lancerd/go.mod`.
- [x] Implement schema creation under `~/.lancer/conversations.sqlite`.
- [x] Write tests for create/list/fetch append ordering.
- [x] Write tests for idempotent `clientTurnId`.
- [x] Write tests for conflict when `baseSeq` is stale.
- [x] Run `cd daemon/lancerd && go test ./...`.
- [x] Commit: `feat(lancerd): add host conversation ledger`.

### Task 2: Daemon conversation RPCs

**Files:**

- Create: `daemon/lancerd/conversation_rpc.go`
- Modify: `daemon/lancerd/server.go`
- Modify: `daemon/lancerd/e2e_router.go`
- Add tests near existing server/router tests.

**Interfaces produced:**

- JSON-RPC: `agent.conversations.list`
- JSON-RPC: `agent.conversations.fetch`
- JSON-RPC: `agent.conversations.append`
- JSON-RPC: `agent.conversations.archive`
- JSON-RPC: `agent.conversations.attachObservedSession`
- Relay message: `agentConversationsList`
- Relay message: `agentConversationsFetch`
- Relay message: `agentConversationsAppend`
- Relay message: `agentConversationsArchive`
- Relay message: `agentConversationsAttachObservedSession`

**Steps:**

- [x] Add request/response structs in Go.
- [x] Add `server` field for `conversationStore`.
- [x] Initialize the store at server startup.
- [x] Add server switch cases.
- [x] Add E2E router switch cases and result message types.
- [x] Add tests proving SSH RPC and relay paths return the same payload shape.
- [x] Run `cd daemon/lancerd && go test ./...`.
- [x] Commit: `feat(lancerd): expose conversation RPCs`.

### Task 3: Host-mediated append and exact resume

**Files:**

- Modify: `daemon/lancerd/dispatch.go`
- Modify: `daemon/lancerd/server.go`
- Modify: `daemon/lancerd/dispatch_stream_test.go`
- Add targeted tests for append/resume behavior.

**Required pre-step:**

- [x] Run `vendor-cli-adapter-audit` because this task changes dispatch/resume behavior.

**Behavior:**

- New chat uses `agentArgv`.
- Follow-up with known `vendorSessionID` uses `resumeArgv`.
- Follow-up without `vendorSessionID` may use `continueArgv`, but response must set `resumeMode = "latestInCwdFallback"`.
- The ledger must capture the first available vendor session/thread ID from structured CLI output.

**Steps:**

- [x] Add a metadata extraction path to `streamJSONOutput` without dumping metadata into chat.
- [x] Capture Claude `session_id` from `{"type":"system","subtype":"init","session_id":"..."}`.
- [x] Capture Codex thread/session ID from `thread.started` or current verified JSON event shape.
- [x] Capture OpenCode session ID from current verified JSON event shape.
- [x] Capture Kimi session ID from current verified JSON event shape.
- [x] Fill `dispatchRun.SessionID`.
- [x] Persist `vendorSessionID` to `conversation_turns`.
- [x] Use `resumeArgv` for follow-ups when session ID exists.
- [x] Add tests that the old Claude system metadata line now binds session ID but still emits zero transcript chunks.
- [x] Add tests that exact resume is chosen over latest-in-cwd when session ID exists.
- [x] Run `cd daemon/lancerd && go test ./...`.
- [x] Commit: `feat(lancerd): bind conversations to exact vendor sessions`.

### Task 4: Persist live output/events to the ledger

**Files:**

- Modify: `daemon/lancerd/server.go`
- Modify: `daemon/lancerd/conversation_store.go`
- Modify or add tests around `emitNotification`.

**Behavior:**

- `emitNotification("agent.run.output", params)` appends a `conversation_events` row if `runID` belongs to a conversation turn.
- `emitNotification("agent.run.status", params)` updates turn status and appends a status event.
- `emitNotification("agent.artifact", params)` upserts `conversation_artifacts`.
- Relay and SSH fanout still work exactly as before.

**Steps:**

- [x] Add a small `persistConversationEvent(method, params)` helper.
- [x] Call it at the start of `server.emitNotification` before writing frames.
- [x] Make persistence best-effort but logged. A failed ledger write must not crash live streaming.
- [x] Add tests with fake store proving output/status/artifacts are persisted once.
- [x] Run `cd daemon/lancerd && go test ./...`.
- [x] Commit: `feat(lancerd): persist conversation event stream`.

### Task 5: iOS protocol models and transport methods

**Files:**

- Modify: `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift`
- Modify: `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift`
- Modify: `Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift`
- Modify: `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`
- Modify or add wire tests in `Packages/LancerKit/Tests/LancerKitTests/`.

**Interfaces produced:**

- `ConversationSummary`
- `ConversationTurnEnvelope`
- `ConversationEvent`
- `ConversationArtifactEnvelope`
- `ConversationListRequest`
- `ConversationListResponse`
- `ConversationFetchRequest`
- `ConversationFetchResponse`
- `ConversationAppendRequest`
- `ConversationAppendResponse`
- `ConversationArchiveRequest`
- `ConversationArchiveResponse`
- `ConversationAttachObservedSessionRequest`
- `ConversationAttachObservedSessionResponse`

**Steps:**

- [x] Add Codable structs with stable coding keys matching Go JSON.
- [x] Add `DaemonChannel` methods for each `agent.conversations.*` RPC.
- [x] Add `E2ERelayBridge` methods with bounded waits and supersede behavior matching `sendDispatch`.
- [x] Add relay result decode handling in `handleMessage`.
- [x] Add wire tests for request/response payload names and optional fields.
- [x] Run `cd Packages/LancerKit && swift build`.
- [x] Run the relevant LancerKit tests. If unrelated tests fail in the dirty worktree, record exact failures. (Two pre-existing unrelated failures — `LiveActivityContentStateTests`, `RelayMachineTests` — were seen intermittently in earlier task runs; the full suite is green as of this task's final run.)
- [x] Commit: `feat(ios): add conversation sync protocol`.

### Task 6: iOS local mirror repository

**Files:**

- Modify: `Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift`
- Modify: `Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift`
- Modify: `Packages/LancerKit/Sources/LancerCore/ChatConversation.swift`
- Modify: `Packages/LancerKit/Tests/LancerKitTests/ChatConversationRepositoryTests.swift`

**Behavior:**

- Existing local chat data still reads.
- New host-backed rows carry `lastHostSeq`, sync state, vendor session IDs, and event rows.
- FTS still indexes title, prompts, assistant text, and small artifact summaries.

**Steps:**

- [x] Add a new GRDB migration after `v11`. (Landed as `v12` + `v13` — `v12` first, `v13` added the conversation mirror tables/columns.)
- [x] Add Swift model fields with backwards-compatible defaults.
- [x] Add `ChatEvent`.
- [x] Add mirror upsert APIs.
- [x] Add tests for host fetch -> local mirror -> recent/search.
- [x] Add tests for repeated event upsert idempotency by `(conversationID, seq)`.
- [x] Run `cd Packages/LancerKit && swift test --filter ChatConversationRepositoryTests`.
- [x] Commit: `feat(ios): mirror host conversations locally`.

### Task 7: Route New Chat and Thread through daemon conversations

**Files:**

- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
- Modify: `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
- Modify: `Packages/LancerKit/Sources/AppFeature/ChatHistoryView.swift`
- Modify: `Packages/LancerKit/Sources/AppFeature/SidebarShellState.swift`
- Modify UI tests if present for chat history/follow-up.

**Behavior:**

- First prompt calls `agent.conversations.append` with no `conversationId`.
- Follow-up calls `agent.conversations.append` with `conversationId` and `baseSeq`.
- The UI still streams live output through `RunOutputStore`.
- The local mirror is updated from append responses and host fetches.
- Host offline shows cached transcript and a clear unavailable state for sending.

**Steps:**

- [x] Change `performDispatch` to request a conversation append, not raw dispatch.
- [x] Change `resumeConversation` to append by `conversationId`, not last run ID.
- [x] Keep `sendRunContinue` only for legacy conversations without host ledger IDs.
- [x] Update `NewChatTabView` to store daemon-returned `conversationID` and `turnID`.
- [x] Update `ChatHistoryView` to refresh host data before enabling follow-up.
- [x] Add tests for conflict response causing refetch before send.
- [x] Run `cd Packages/LancerKit && swift build`.
- [x] Run targeted LancerKit tests.
- [x] Commit: `feat(ios): send chats through host conversation ledger`.

### Task 8: CloudKit conversation mirror

**Files:**

- Create: `Packages/LancerKit/Sources/SyncKit/ConversationSyncEngine.swift`
- Create: `Packages/LancerKit/Sources/SyncKit/ConversationCloudRecords.swift`
- Modify: `Packages/LancerKit/Sources/SyncKit/CloudSync.swift`
- Modify app environment wiring where `SyncEngine` is created.
- Add tests using wrapper/mock records where possible.

**Behavior:**

- Sync only runs when CloudKit entitlement flag says it is enabled and account status is available.
- Use private database only.
- Use custom zone `LancerConversations`.
- Pull CloudKit changes into local mirror.
- Push host-backed local mirror changes to CloudKit.
- Push local read/archive state and tombstones.
- Do not let CloudKit-created executable turns auto-run on host.

**Steps:**

- [x] Add custom-zone support and per-zone change tokens to `CloudSync`.
- [x] Add CloudKit record mapping helpers.
- [x] Add chunking for transcript events.
- [x] Add tombstone handling for archive/delete.
- [ ] Add a subscription setup path for `CKDatabaseSubscription`. **Not done** — `ConversationSyncEngine` pulls on `start()` + explicit `syncNow()` only, no push-driven background pull yet. Background pull for conversations should be added before relying on it for "another device sent a message while this one was backgrounded" freshness; polling-on-foreground/pull-to-refresh covers the interim.
- [x] Add tests for record mapping and chunking.
- [x] Run `cd Packages/LancerKit && swift build`.
- [ ] Test on a real device build with CloudKit entitlements when available. **Not done in this session** — no physical device access; `CloudSync`/`ConversationSyncEngine` are no-ops on the simulator by design (see Known Risks), so this remains an open verification gate before shipping the feature externally.
- [x] Commit: `feat(sync): mirror conversations with CloudKit`.

### Task 9: Observed Session attach/import

**Files:**

- Modify: `daemon/lancerd/session_index.go`
- Modify: `daemon/lancerd/conversation_store.go`
- Modify: `daemon/lancerd/conversation_rpc.go`
- Modify: `Packages/LancerKit/Sources/AppFeature/ObservedSessionView.swift` if present.
- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`

**Behavior:**

- An observed terminal session can be attached to a Lancer conversation.
- Imported history is stored as immutable events.
- Follow-up after attach uses exact `vendorSessionID`.

**Steps:**

- [x] Implement `agent.conversations.attachObservedSession`.
- [x] Convert `SessionMessage` transcript entries to ledger events.
- [x] Store `vendorSessionID` on the imported turn/session.
- [x] Add UI affordance in observed session view to attach/import. (`DarkTranscriptHeader`'s overflow menu gains "Import to Lancer", wired through `ObservedSessionView.onImportToLancer` → `AppRoot.importObservedSession` → SSH/relay `attachObservedSession`, navigating into the new thread on success.)
- [x] Add tests for import idempotency.
- [x] Run `cd daemon/lancerd && go test ./...`.
- [x] Run relevant LancerKit tests.
- [x] Commit: `feat: attach observed sessions to conversations`. (Landed as `feat(lancerd,ios): implement attachObservedSession import + Import to Lancer UI`.)

### Task 10: Documentation, migration, and release guardrails

**Files:**

- Modify: `ARCHITECTURE.md`
- Modify: `docs/design-questions/2026-07-02-cross-device-sync-second-opinion.md` or add a short decision record beside it.
- Modify: `docs/LIVE_LOOP_RUNBOOK.md`
- Modify: `docs/PUBLISH_READINESS_CHECKLIST.md`

**Required doc changes:**

- Update `ARCHITECTURE.md` section `11.2` so it no longer says all scrollback is out of CloudKit without distinguishing terminal scrollback from curated Lancer conversation history.
- Add a section stating: host ledger is execution truth, CloudKit is Apple-device mirror.
- Document offline behavior and no silent prompt queue.
- Document exact vendor-session binding.
- Document CloudKit record size/chunking policy.

**Steps:**

- [x] Update architecture docs. (`ARCHITECTURE.md` §0.1 Implemented list + rewritten §11.2/§11.3.)
- [x] Add a manual QA matrix for one device, two devices, host offline, host reconnect, app reinstall, and observed-session attach. (`docs/LIVE_LOOP_RUNBOOK.md` PHASE 7 + two new Triage rows.)
- [x] Add release checklist entries for CloudKit schema deployment and entitlements. (`docs/PUBLISH_READINESS_CHECKLIST.md` B9, C7, D2 CloudKit schema note.)
- [x] Run docs link/path sanity checks if available. (No automated checker exists in this repo; manually verified every file path newly cited in the doc updates above resolves.)
- [x] Commit: `docs: record conversation sync architecture`.

## Acceptance Criteria

The feature is not complete until all of these pass:

- Start a chat on iPhone A. It appears on iPhone B through CloudKit/private mirror.
- Kill/reinstall iPhone A. After iCloud sync, the conversation appears again.
- Start a follow-up on iPhone B while host is online. It appends to the same host ledger conversation.
- The daemon uses exact vendor session resume for at least Claude and Codex after current CLI verification.
- If exact vendor session ID is missing, the response says `resumeMode = "latestInCwdFallback"`.
- If two devices append to the same conversation at the same time, one append wins and the other gets `status = "conflict"` with the newer `nextSeq`.
- If host is offline, the transcript remains readable from local/CloudKit cache, but Send is blocked or saved as explicit draft. It must not auto-run later.
- Observed terminal session can be attached/imported and continued with exact session ID.
- Existing Hosts/Snippets CloudKit sync still works.
- Existing approval/live activity relay loop still works.

## Verification Commands

Daemon:

```bash
cd /Users/roshansilva/Documents/command-center/daemon/lancerd
go test ./...
```

Push backend, only if touched:

```bash
cd /Users/roshansilva/Documents/command-center/daemon/push-backend
go test ./...
```

LancerKit:

```bash
cd /Users/roshansilva/Documents/command-center/Packages/LancerKit
swift build
swift test --filter ChatConversationRepositoryTests
swift test --filter E2ERelayMessageWireTests
```

iOS app target:

- Use XcodeBuildMCP for app-target builds when app shell, SwiftUI, iOS-only, or strict-concurrency paths change.
- First call `session_show_defaults`.
- If project/workspace, scheme, and simulator defaults are set, call `build_run_sim`.
- If defaults are missing, discover/configure the correct Lancer project and simulator, then build.

Manual device/cloud verification:

- Use two physical devices or one physical device plus a simulator where CloudKit behavior is supported enough for the specific check.
- Remote push/CloudKit subscription behavior requires a real device.
- Verify with the same iCloud account.
- Verify CloudKit development schema before promoting to production.

## Failure Modes And Required Handling

### Host offline

Show cached transcript. Disable Send or save explicit local draft. Do not auto-send later.

### Two devices append concurrently

Host compares `baseSeq` to `lastSeq`. If stale, return `conflict`; client refetches and lets the user resend.

### Host wiped or unpaired

CloudKit keeps readable history. Continuation is unavailable until the original host ledger is restored or the user explicitly attaches/imports into a new host. Do not silently migrate executable state.

### CloudKit unavailable

Local device cache and host ledger still work. Show sync-unavailable state. Do not block host-mediated execution.

### CloudKit record too large

Chunk transcript events. Use assets for larger chunks. Never exceed CloudKit request/record limits intentionally.

### Vendor metadata changes

Exact session ID extraction must have tests per vendor. If a vendor stops emitting session IDs, mark `resumeMode` degraded and keep the transcript, but do not claim exact continuation.

### Push backend run logs

Do not mix hosted-runner logs with V1 self-host conversation truth. Keep the boundary clear.

## Suggested Build Order

1. Daemon ledger.
2. Conversation RPCs.
3. Exact vendor session capture and resume.
4. Event persistence.
5. iOS protocol and transports.
6. iOS local mirror.
7. UI routing through conversation append.
8. CloudKit mirror.
9. Observed-session attach/import.
10. Docs and release QA.

This order gives working, testable software before CloudKit is added. It also prevents the largest mistake: building a pretty cross-device transcript sync while leaving continuation semantics fragile.

## Short Prompt To Hand Claude Code

Implement `docs/design-questions/2026-07-03-cross-device-conversation-sync-build-handoff.md` task-by-task. The target architecture is host-owned durable conversation ledger plus CloudKit private mirror plus exact vendor-session binding. Do not implement pure CloudKit sync or a simple Observed Sessions extension. Preserve V1 relay-first architecture, do not reintroduce tab-bar navigation, and run the specified Go/Swift/Xcode verification after each task. Before changing `daemon/lancerd/dispatch.go`, run the `vendor-cli-adapter-audit` skill and re-verify current vendor CLI resume/session metadata behavior.
