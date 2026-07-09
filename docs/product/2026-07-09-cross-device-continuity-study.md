# Cross-device conversation continuity — Orca / Happier / Omnara vs. Lancer

Date: 2026-07-09. Read-only research in `research-repos/{orca,happier,omnara}` (see
`docs/product/2026-07-09-chat-ui-port-map.md` for licenses — Orca MIT, Happier MIT, Omnara
Apache-2.0). Companion angle: that port map covers UI rendering; this doc covers **state
ownership, discovery, resumption, streaming handoff, offline/reconnect, and idempotency** — "start
on device A, continue on device B."

---

## 1. Per-competitor architecture

### Orca — no real multi-device continuity; a remote-control client of one machine

Orca's "chat" is a PTY-scraping reconstruction of a vendor CLI's own transcript file, owned
entirely by the desktop process — there is no server (`docs/native-chat-codex-tui-parity.md:27-37`).
The `mobile/` app is a **remote-control client of that single desktop instance**, not an
independent device with its own copy of history:

- **Discovery/pairing**: `mobile/src/transport/pairing.ts:8-76` decodes an `orca://pair?code=...`
  QR/deep-link into a `PairingOffer`; there is no session/conversation list to discover — the
  phone pairs to one desktop process on the LAN/Tailscale.
- **Transport**: `mobile/src/transport/rpc-client.ts:342` opens a raw `WebSocket(endpoint)`
  directly to the desktop app (see `docs/reference/plans/2026-06-27-orca-mobile-manual-network-address.md` —
  the desktop shows a QR encoding its own IPv4/Tailscale address; the plan explicitly scopes out
  any server-side endpoint).
- **State ownership**: 100% desktop-resident. If the desktop is off or unreachable, mobile has
  nothing to show and nothing to resume — there is no independent ledger to fall back to.
- **Conflict handling**: N/A — only one writer (the desktop PTY) ever exists.
- **Streaming handoff mid-run**: trivial by construction — mobile is just another WebSocket
  subscriber to the one live stream; there's no "device B picks up device A's turn," only "device
  B watches the same turn."

**Takeaway for Lancer**: Orca proves the remote-control model is real competitive UX (simple,
zero-latency, no conflict semantics needed) but is not what Lancer promises — Lancer's daemon
ledger + CloudKit mirror is a strictly harder, more valuable design (works when the paired
device is asleep/offline), so Orca offers no pattern to port here beyond "the local-network
direct-WebSocket path is fast when the host is reachable," which Lancer doesn't currently use as
a fast-path optimization (Lancer always goes through the daemon RPC / relay, not a raw local
socket) — worth noting as a possible latency win, not a continuity gap.

### Omnara — thin client over a server-authoritative Postgres table, poll-based

Omnara's server is the sole source of truth; there is no local-first client state to reconcile.

- **State ownership**: `Message` rows in Postgres, one `messages` table shared by
  agent/user turns (`src/shared/database/models.py:257-289`), ordered by
  `created_at` via `Index("idx_messages_instance_created", "agent_instance_id", "created_at")`
  (line 260) — **no `seq`/version column at all**; ordering is wall-clock timestamp order.
- **Discovery**: any device simply lists `agent_instances` scoped by `user_id` (multi-tenant
  design per `src/backend/`) — there's no separate device-registration or pairing step; discovery
  is "log in, see your instances."
  server."
- **Resumption**: none needed in the reconciliation sense — a second device just re-queries the
  same table. There's no client-local pending-turn concept to merge.
  the `requires_user_input` boolean).
- **Live handoff**: **polling**, not push. `apps/web/src/hooks/usePolling.ts:1-21` — a plain
  `setInterval` (default `interval = 5000`ms) re-runs the query callback; `useSubscription.ts:1-15`
  layers `@tanstack/react-query` on top for caching. A second device "picks up" a mid-run turn
  simply by polling and rendering the latest rows — no special mid-stream handoff logic exists
  because there is no live-stream concept, only "did the table change since I last asked."
- **Conflict handling**: none — server is the only writer of record for any given row; two
  devices sending different `Message` inserts just produces two rows in timestamp order (no
  merge, no last-write-wins on a single field, because nothing is ever updated in place except
  `requires_user_input`/read cursors).
- **Offline/reconnect**: no special-cased catch-up — the next poll tick (or query invalidation on
  focus) just re-fetches current state; there is no gap-fill/cursor mechanism because polling
  always fetches the full current picture (paginated by `created_at`), not a delta.
- **Idempotency**: none found (`grep -rn idempoten` returns no message-send code path — only
  unrelated Alembic migration/Amp-wrapper hits). A retried send from a flaky connection could
  double-post; the model doesn't protect against it.
- **Read cursor**: `last_read_message_id` on the instance/access model (per Omnara's own
  `CLAUDE.md`: *"Reading messages: Use `last_read_message_id` to track reading progress"*) — a
  **per-device-agnostic, per-user read cursor** Lancer has no analog of.

**Takeaway for Lancer**: Omnara is the simplest model and it works precisely because it gives up
two things Lancer has already committed to (an append-only seq ledger with conflict detection,
and live low-latency streaming) — so it's not a source of state-machine patterns, but its
**read-cursor field** and **"discovery is just a scoped list, no separate registration"** design
are worth a glance.

### Happier — real E2E multi-device sync client, closest analog to Lancer

This is the deep one, per the task brief; already partially surfaced in the port map.

- **State ownership**: server-side per-user monotonic `seq` (docs/protocol.md: *"`UpdatePayload.seq`
  is a single per-user counter... apply updates in order and you are consistent for that user"*).
  Sessions/messages/machines/artifacts each carry their own `seq` too. Payloads are E2E-encrypted
  client-side; the server stores opaque blobs (`docs/protocol.md` "Client-side encryption
  boundaries").
- **Discovery**: `user-scoped` Socket.IO connections receive account-wide `new-session` /
  `update-session` / `delete-session` events (`docs/protocol.md` "Update event types") — every
  signed-in device gets pushed the full session list live, not just a poll. Session-scoped
  connections (`clientType: "session-scoped"`) additionally get an isolated per-session feed once
  a device opens one.
- **Resumption / idempotency — the localId mechanism** (the part the brief asked to go deeper on):
  - Client generates `localId` client-side, defaulting to `randomUUID()` if the caller doesn't
    supply one (`apps/ui/sources/sync/sync.ts:2046-2047`).
  - It's written into a **local pending-message queue** immediately
    (`storage.getState().upsertPendingMessage(sessionId, {id: localId, localId, ...})`,
    `sync.ts:2085-2094`) so the UI shows an optimistic bubble before any network round trip.
  - The message is sent over the wire tagged with `localId` (`sync.ts:2137-2144`,
    `{ sid, message, localId, ... }`, matching the protocol's `message` event shape:
    `docs/protocol.md` "`{ sid, message, localId? }`").
  - On ACK, the pending entry is removed and the message is "committed" into the canonical
    transcript via `normalizeRawMessage(ack.id, localId, createdAt, content, {seq: ack.seq})`
    (`sync.ts:2186-2189`) — **`localId` is carried through as a field on the committed message**,
    not discarded once the server assigns its own `id`/`seq`.
  - **This is the idempotency key.** If the ACK never arrives (dropped connection), a scheduled
    retry (`schedulePendingMessageCommitRetry`, `sync.ts:2156,2173,2385-2401`) resends; if the
    server had actually already durably stored the first attempt, the wire protocol's `new-message`
    broadcast (`docs/protocol.md`: `body: { t: "new-message", sid, message: { id, seq, content,
    localId, createdAt, updatedAt } }`) still carries the original `localId`, and the reducer's
    dedupe rule fires on it: `apps/ui/sources/sync/store/domains/messages.ts:693-704` — *"We key
    this off localId, which is preserved when a pending item is materialized into a
    SessionMessage"* — clears the matching pending entry by `localId` set membership so the same
    logical send never renders twice, regardless of how many times it was retried or how many
    devices are watching the same `new-message` broadcast.
  - Stream-segment upserts (assistant text growing mid-turn) use the SAME localId-keyed upsert
    discipline, including a fallback key (`segmentLocalId`) for durable snapshots written under a
    different id than the live stream used — see test names
    `reducer.streamSegmentSnapshots.test.ts:54-90` ("upserts assistant stream segments by localId
    and replaces snapshot text") and `:93-140` ("...by segmentLocalId when durable snapshots were
    written with different localIds").
- **Mid-run streaming handoff to a second device**: because every signed-in device holds a
  `user-scoped` (or session-scoped, once opened) Socket.IO connection and the server pushes
  `new-message` / ephemeral `activity` events to all of them, a second device opening the same
  session mid-turn just starts receiving the live event stream from wherever it is — no
  hand-off state machine is needed because there's no exclusive "owner" of the live connection;
  it's pub/sub, not a single subscriber pipe. `ephemeral` `activity {type: "activity", id:
  sessionId, active, activeAt, thinking?}` events (`docs/protocol.md` "Ephemeral event types")
  give the second device the live thinking/typing indicator too.
- **Offline / reconnect catch-up**: `afterSeq`-based delta catch-up —
  `this.sessionMaterializedMaxSeqById[sessionId] ?? 0` is used as the low-water mark
  (`sync.ts:4113,5168-5169,5241,5249`), and `runSocketReconnectCatchUpViaChanges` (`sync.ts:5441`)
  drives the reconnect-specific version of the same mechanism, persisting an "approved cursor"
  (`sync.ts:5600-5606`) so a resumed connection only replays what it missed. Test names make the
  matrix explicit: `sync.liveTailCatchUp.test.ts`, `sync.gapFillDeferral.test.ts`,
  `sync.socketOfflineDuration.test.ts`, `sync.resumeSync.backgroundInterruption.test.ts`,
  `sync.deferredNewerReactiveDrain.test.ts`.
- **Conflict handling on versioned (non-append) fields**: optimistic concurrency via
  `expectedVersion` on metadata/agentState/artifact header+body/access keys/KV
  (`docs/protocol.md` "Sequencing and concurrency" + the `update-metadata`/`update-state`/
  `artifact-update` event contracts, each returning `"version-mismatch"` with the current
  value/version on conflict) — client-driven resolution, same shape as Lancer's `baseSeq` gate but
  applied per-field, not just per-conversation-append.

**Takeaway for Lancer**: Happier is the primary donor. Its localId/idempotency pattern is
*structurally* the same idea as Lancer's `clientTurnId`, but Happier additionally threads the
local id all the way through into the **committed, broadcast message** so every device — not just
the sender — can dedupe against it, and it applies the identical mechanism to **mid-stream
segment upserts**, not just whole-turn appends. Its pub/sub "every device gets pushed the live
feed" design is what gives it real mid-run streaming handoff; Lancer's daemon is currently a
single-attached-transport model (see gap table).

---

## 2. Gap table — what competitors handle that Lancer doesn't

| Capability | Happier | Omnara | Orca | Lancer today | Evidence |
|---|---|---|---|---|---|
| Server/host pushes live turn updates to **every** connected device (not just the one that opened it) | Yes — `user-scoped` Socket.IO gets `new-message`/`activity` account-wide | Yes (via poll, not push) | Yes (single machine, trivially) | **No** — daemon streams to whichever transport dispatched the run; a second device only sees it by polling `agent.conversations.fetch` after the fact | `ConversationSyncUIState.streamingElsewhere` exists as an enum case (`ConversationSyncCoordinator.swift:51`) but is **never set anywhere** — `grep -rn streamingElsewhere Packages/LancerKit/Sources` matches only the declaration. The state was designed for and never wired. |
| Idempotency key survives into the **broadcast/committed** record so every device (not just the sender) can dedupe a retried send | Yes — `localId` field on committed `new-message` (`docs/protocol.md`) | N/A (no client-local writes) | N/A | **Partial** — `clientTurnId` dedupes the *append* itself (server-side, `existingTurnByClientTurnID`, `conversation_store.go:703-714`) but is not itself echoed onto every `conversation_events` row a second device pulls, and no equivalent exists for streamed **event chunks** (`appendRunOutput`'s `seq` is a fresh per-conversation seq every call, no per-chunk idempotency key — see the `conversation_store.go:840-852` comment: dedupe is explicitly *not done at this layer* because it assumes single in-process delivery, which is false once CloudKit or relay retries are added) | `daemon/lancerd/conversation_store.go:616-627,838-852` |
| Mid-stream segment upsert dedup (assistant text growing turn-by-turn) keyed the same way as whole-message dedup | Yes — `localId`/`segmentLocalId` (`reducer.streamSegmentSnapshots.test.ts`) | N/A | N/A (single stream) | **No equivalent** — `appendRunOutput` just appends immutable chunks by ledger seq; a live-overlay vs. persisted-row reconciliation exists client-side (`CursorTranscriptMapper.swift` per the port map) but only for the single attached device, not for reconciling two devices' views of the same in-flight stream | `daemon/lancerd/conversation_store.go:840-880` |
| Per-device read cursor (unread/last-viewed tracking) | No explicit per-device cursor found (session-level `activity`/presence only) | Yes — `last_read_message_id` | N/A | **No** — `grep -rn "readCursor\|lastReadSeq\|last_read"` across `Packages/LancerKit/Sources` and `daemon/lancerd` returns nothing | grep run during this study |
| Push-triggered list refresh so a **second device discovers** a conversation *started* on device A without opening it | Yes — account-wide `new-session` push | Yes (poll picks it up) | N/A | **Partial** — `mergeConversationSummaries` exists and is documented as letting `AppRoot.refreshCursorLiveBridge` "surface a conversation started on another device **without waiting on CloudKit**" (`ConversationSyncCoordinator.swift:363-368`), but it's driven by an explicit `agent.conversations.list` call, not a server push — no evidence of a push trigger calling it automatically on a host-side event | `ConversationSyncCoordinator.swift:363-392` |
| Local-first optimistic send with a pending-queue UI state, decoupled from network round trip | Yes — `upsertPendingMessage` before send (`sync.ts:2085-2094`) | No (server-authoritative, no local pending state) | N/A | **No dedicated pending-turn UI state** — `ConversationSyncUIState` has `.syncing` as a blanket in-flight state but no per-message optimistic-bubble concept comparable to Happier's pending queue; `.syncing` is set/cleared around the whole `append` call (`ConversationSyncCoordinator.swift:187-209`) | `ConversationSyncCoordinator.swift:32-52,183-209` |
| Field-level optimistic concurrency (metadata/agent-state) independent of the append-seq gate | Yes — `expectedVersion` per field | No | No | **No** — Lancer's only conflict gate is the conversation-level `baseSeq` on `beginTurn`; there's no analog for e.g. concurrently editing a conversation's `model`/`budgetUSD`/title from two devices | `conversation_store.go:677-694` (single gate); no per-field version columns in the `conversations` schema (`conversation_store.go:111-129`) |

## 3. Recommendations, ranked by dogfood impact for W0.B

1. **(L, high impact) Wire `.streamingElsewhere` for real, or delete it.** The enum case already
   exists and is exactly the right shape for the #1 gap (mid-run streaming handoff) — but it's
   dead code today, which is worse than not having it (a reviewer or future agent will assume it
   works). Two paths: (a) minimal — when `ConversationSyncCoordinator.refreshConversation` or
   `mergeConversationSummaries` observes a conversation whose latest turn `status == "running"`
   and `hostSeqEnd == nil` but this device didn't originate the run (no local pending turn for
   that `runID`), publish `.streamingElsewhere` instead of `.synced`; (b) full — daemon pushes
   `agent.conversations.append`-triggered notifications to *all* attached transports for that
   conversation, not just the dispatcher's, mirroring Happier's `user-scoped` broadcast (would
   touch `daemon/lancerd/server.go`'s notification fan-out and `dispatch.go`). Start with (a) — it
   needs zero daemon changes and directly answers "device B opens a conversation while device A is
   mid-turn" for W0.B's QA script. Target: `ConversationSyncCoordinator.swift` (new state-derivation
   helper near `finishAppendResponse`/`mergeFetchResponse`), `ChatHistoryView`/thread banner for the
   UI treatment.

2. **(M, high impact) Give `appendRunOutput` a real per-chunk idempotency key before CloudKit/relay
   retries can double-append.** The existing code comment in `conversation_store.go:840-852`
   explicitly documents the assumption that lets this be skipped today ("called exactly once per
   emitted notification, in-process, off a single per-run goroutine with no replay/redelivery
   path") — but `ConversationSyncEngine.pushTurns`/`mergeTurnChunk` (CloudKit) and any future relay
   retry logic *are* a redelivery path once they touch this data, and `conversation_store.go`'s own
   assumption note is the single point where a future change could silently violate it. Add an
   optional `chunkID` (caller-supplied, e.g. `runID:seq` from the streaming source) with a
   `UNIQUE` constraint + `INSERT OR IGNORE`/`ON CONFLICT DO NOTHING`, mirroring the `client_turn_id`
   uniqueness pattern already used for turns (`conversation_store.go:130-146`). Target:
   `daemon/lancerd/conversation_store.go` (`appendRunOutput`, schema `conversation_events` table),
   call site in `server.go`'s `persistConversationEvent`.

3. **(S, medium impact) Add a per-device read cursor.** Omnara's `last_read_message_id` is the
   simplest version of a real gap: today Lancer has no way to know "has this device seen up to
   seq N," so a returning device can't distinguish "nothing new" from "I haven't looked yet" without
   diffing timestamps client-side. A single `last_read_seq` column on the iOS mirror's conversation
   row (or a tiny new `conversation_read_cursors(conversation_id, device_id, seq)` table if
   multi-device-aware cursors matter later) updated on thread-open, surfaced as an unread badge.
   Target: `Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift` (new
   column/table + `markRead(conversationID:upToSeq:)`), call site in the thread view's `onAppear`.

Also worth a follow-up, lower priority for W0.B specifically: extend `clientTurnId`'s
dedupe-by-broadcast pattern (Happier's `localId`-on-committed-message) so a `conversation_events`
row for a turn-start carries `clientTurnId` visibly enough that a second device's mirror merge can
recognize "this is the turn I already have pending locally" without relying solely on `runId`
matching (today `mergeFetchResponse` has no such reconciliation — it just appends by seq).

---

## 4. Two-device QA script for W0.B

Prereqs: two physical Apple devices signed into the **same iCloud account**, both paired to the
same `lancerd` host (or reachable via relay), `docs/LIVE_LOOP_RUNBOOK.md` Phase 7 environment.
This extends C7's existing "start on A → appears on B; kill/reinstall A → restores from CloudKit"
scope with the specific cases the three competitors above handle and Lancer's gap table flags.

1. **Baseline discovery.** Start a new conversation on Device A. Without touching Device B, open
   Device B's conversation list within ~5s (before any CloudKit sync could plausibly complete) and
   confirm it does **not** yet appear (documents current push-vs-poll gap — expected fail today,
   not a bug). Then pull-to-refresh (triggers `agent.conversations.list` → `mergeConversationSummaries`)
   and confirm it now appears with correct title/host/cwd.
2. **Mid-run open on second device (the `.streamingElsewhere` case).** On Device A, send a prompt
   that takes >20s to complete (a real build/test command). While it's still running, open the
   SAME conversation on Device B. Expect (post-recommendation-1 fix): Device B shows a
   "running on another device" indicator, not a stale "idle" state and not a duplicate composer
   invite to send a conflicting turn. Today: capture whatever Device B actually shows (likely
   `.synced` with a stale/no-turn view) as the baseline defect.
3. **Reply race — both devices send near-simultaneously.** Let Device A's run above finish. On
   both A and B, type a different follow-up prompt and tap send within ~1s of each other. Expect:
   exactly one turn wins the `baseSeq` race and starts; the loser gets the `.conflict` banner
   (`ConversationSyncCoordinator.blockConflict`) and, per existing code, auto-refetches once before
   surfacing a conflict — confirm the loser's refetch either succeeds transparently or shows a
   clear "this changed on another device, your message wasn't sent — resend?" banner (never a
   silently dropped prompt).
4. **Streamed-output duplication under retry.** Force a transient relay/host disconnect mid-turn
   (airplane-mode toggle on the host's network, or kill/relaunch `lancerd`) so the daemon's
   notification path retries. On reconnect, confirm the conversation transcript on both devices
   shows each output chunk exactly once — no repeated paragraphs. This is the direct test for gap
   table row 2 (currently un-guarded).
5. **Offline queue / no silent local execution.** Turn on Airplane Mode on Device B. Attempt to
   send a follow-up. Expect `.hostOffline` state, message NOT silently queued-and-sent-later, and
   an explicit "couldn't reach host" error (per `ConversationSyncCoordinator.appendWithRetry` /
   `transportErrorMessage`) — never a duplicate-looking send when connectivity returns.
6. **Fresh-install restore.** Uninstall and reinstall the app on Device B (same iCloud account, not
   yet re-paired to any host). Confirm conversation history for previously-synced conversations
   reappears from the CloudKit mirror (`ConversationSyncEngine.pull`) before any host reconnect —
   this is C7's original scope, kept here since it's the foundation the above cases build on.
7. **Read-state check (only if recommendation 3 lands before this QA pass).** Open a conversation
   on Device A, causing its last-seq to advance via a new message from Device B sent while A's app
   is backgrounded. Foreground A and confirm an unread indicator was shown before opening, and
   clears after.

---

**Final answer:** gap table in §2 above; top 3 recommendations in §3 (wire or delete
`.streamingElsewhere` for mid-run second-device handoff [L]; give `appendRunOutput` a per-chunk
idempotency key before CloudKit/relay retries can double-append [M]; add a per-device read cursor
[S]). Doc path: `docs/product/2026-07-09-cross-device-continuity-study.md`.
