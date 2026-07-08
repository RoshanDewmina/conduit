Researching the Happier codebase for relay protocol, reconnect, PTY, and pairing mechanics. I'll explore the repo structure and key protocol files first.
The repo has dedicated protocol docs — I'll read those alongside the relay-server and protocol package source.
# Happy Coder (Happier) Architecture Research Report

**Scope:** Read-only analysis of `research-repos/happier` (cloned 2026-07-07). No files modified.

**Naming note:** The product is branded **Happier** (`happier` CLI, `happierdev/relay-server` Docker image). The relay is **`apps/server`** — `packages/relay-server` is only a binary runner that downloads/starts that server (`packages/relay-server/package.json`).

---

## 1. Relay wire format

### Transport stack

| Layer | Technology | Path / detail |
|-------|------------|---------------|
| HTTP | Fastify + Zod | `/v1/*`, `/v2/*` JSON |
| Realtime | **Socket.IO** (not raw WebSocket) | Path `/v1/updates`; transports `websocket` + `polling` |
| Optional scale-out | Redis Streams adapter | `apps/server/sources/app/api/socket.ts` |

Canonical docs: `docs/protocol.md`, `docs/encryption.md`, `docs/backend-architecture.md`.

### Socket.IO handshake auth

From `docs/protocol.md` and `apps/server/sources/app/api/socket.ts`:

```json
{
  "token": "<bearer token>",
  "clientType": "user-scoped" | "session-scoped" | "machine-scoped",
  "sessionId": "<required for session-scoped>",
  "machineId": "<required for machine-scoped>"
}
```

Three connection scopes route updates differently (`apps/server/sources/app/events/connectionEventRouter.ts`):
- **user-scoped** — mobile/web; all account updates
- **session-scoped** — CLI agent process bound to one session
- **machine-scoped** — daemon; machine state + RPC target

### Server → client events (JSON only, no binary framing)

Two top-level Socket.IO event names:

**`update`** (durable):
```json
{
  "id": "<string>",
  "seq": <number>,          // per-user update sequence
  "body": { "t": "<type>", ... },
  "createdAt": <epoch ms>
}
```

**`ephemeral`** (not persisted):
```json
{ "type": "<type>", ... }
```

Persistent `body.t` types include: `new-session`, `update-session`, `delete-session`, `new-message`, `update-account`, `new-machine`, `update-machine`, `new-artifact`, `update-artifact`, `delete-artifact`, `relationship-updated`, `new-feed-post`, `kv-batch-update`, `pending-changed` (from `docs/protocol.md` + `apps/server/sources/app/events/eventPayloadTypes.ts`).

Ephemeral types include: `activity`, `machine-activity`, `usage`, `machine-status`, **`transcript-stream-segment`** (live streaming only).

### Client → server socket events (selected)

From `docs/protocol.md` + handlers in `apps/server/sources/app/api/socket/`:
- `message` — create encrypted session message (ACK-based)
- `update-metadata`, `update-state` — optimistic concurrency (`expectedVersion`)
- `session-alive`, `session-end`, `usage-report`
- `machine-alive`, `machine-update-metadata`, `machine-update-state`
- `rpc-register` / `rpc-unregister` / `rpc-call` — cross-device RPC (`packages/protocol/src/socketRpc.ts`)
- `transcript-stream-segment` — live transcript chunks (ephemeral only; `sessionUpdateHandler.ts:506`)

### Encrypted blobs

**All encryption is client-side.** Server stores opaque base64 strings/bytes.

**Storage envelope** (`packages/protocol/src/sessionMessages/sessionStoredMessageContent.ts`):
```json
{ "t": "encrypted", "c": "<base64 ciphertext>" }
// or
{ "t": "plain", "v": <unknown> }
```

**Binary layouts before base64** (`docs/encryption.md`, `apps/cli/src/api/encryption.ts`):

| Variant | Layout |
|---------|--------|
| **legacy** (NaCl secretbox) | `[nonce 24B \| ciphertext+auth]` |
| **dataKey** (AES-256-GCM) | `[ver 1B \| nonce 12B \| ciphertext \| authTag 16B]` |
| **dataEncryptionKey bundle** | `[ver \| ephPubKey 32B \| nonce 24B \| box ciphertext]` |

**Decrypted message plaintext shapes** (`docs/encryption.md`, `apps/cli/src/api/types.ts`):
- User: `{ role: "user", content: { type: "text", text: "..." }, meta?, localKey? }`
- Agent: `{ role: "agent", content: { type: "output", data: <any> }, meta? }`

Socket `message` emit sends **raw base64 ciphertext** in the `message` field; server wraps it as `{ t: "encrypted", c: "..." }` in Postgres.

### RPC over the relay

RPC is **not a separate transport** — it rides Socket.IO:

1. Daemon registers: `rpc-register` with method `${machineId}:daemon.terminal.ensure` (`RpcHandlerManager.ts:187-188`, `serverScopedMachineRpc.ts:175`)
2. Mobile calls: `rpc-call` with `{ method, params }` → server forwards `rpc-request` to registered socket
3. Params/results are **encrypted base64** in E2EE mode (`RpcHandlerManager.ts:76-80`)

Method constants: `packages/protocol/src/rpc.ts` (`DAEMON_TERMINAL_*`, `SPAWN_HAPPY_SESSION`, etc.).

### What I could not determine

- Exact Redis Streams cross-node RPC registry semantics beyond `rpcRedisRegistryCoordinator` existing
- Full `machine-transfer-envelope` wire format (feature-gated; saw `SOCKET_RPC_EVENTS.MACHINE_TRANSFER_ENVELOPE` only)

---

## 2. Reconnect / catch-up mechanics

**Key finding: This is message-log / change-log replay over HTTP, not raw PTY stream replay and not socket backlog replay on connect.**

### What the relay stores while a client is offline

| Data | Storage | Survives offline? |
|------|---------|-------------------|
| Session messages | `SessionMessage` rows (encrypted/plain envelope + monotonic `seq`) | **Yes** |
| Session/machine metadata, agent state | Encrypted strings + version counters | **Yes** |
| Account change index | `AccountChange` rows (coalesced per `kind`+`entityId`) | **Yes**, with prune floor |
| Pending user prompts | `PendingMessage` queue (v2) | **Yes** |
| Presence, usage, transcript-stream-segment | Ephemeral socket events only | **No** |
| Daemon terminal PTY output | **Daemon-local ring buffer only** (not relay) | **No** (gap events if cursor too old) |

### Account-level change log (`/v2/changes`)

Implementation: `apps/server/sources/app/api/routes/changes/changesRoutes.ts`, `apps/server/sources/app/changes/markAccountChanged.ts`.

- Each durable mutation increments `Account.seq` and upserts `AccountChange` with `{ cursor, kind, entityId, changedAt, hint }`.
- Client polls: `GET /v2/changes?after=<cursor>&limit=<n>`
- Session message hints: `{ lastMessageSeq, lastMessageId }` written in `sessionWriteService.ts:734` via `markSessionParticipantsChanged`.
- **Cursor safety:** HTTP 410 `{ error: "cursor-gone", currentCursor }` if client cursor is in the future or behind `changesFloor` (pruned) — forces snapshot rebuild.

Client orchestration: `apps/ui/sources/sync/runtime/orchestration/socketReconnectViaChanges.ts` — paginated changes fetch, optional full snapshot refresh on `cursor-gone` or page budget exhaustion.

### Message-level catch-up (`/v1/sessions/:id/messages`)

Implementation: `apps/server/sources/app/api/routes/session/registerSessionMessageRoutes.ts:215-250`.

- **Incremental:** `?afterSeq=N` → `WHERE seq > N ORDER BY seq ASC LIMIT ...`
- **Snapshot/tail reset:** `GET .../messages` **without** `afterSeq` (newest-first paging)
- E2E tests confirm client policy (`packages/tests/suites/ui-e2e/session.transcript.catchup.*.spec.ts`):
  - Small gap → `afterSeq=` incremental fetch
  - Large gap while pinned → full snapshot (no `afterSeq`)
  - Unpinned viewport → deferred catch-up until user scrolls to bottom

### Socket reconnect behavior

On `connection` (`apps/server/sources/app/api/socket.ts:193-286`): server **does not replay** historical `update` events. It only registers the connection and emits ephemeral machine-online if applicable.

Offline catch-up path (from tests + `sync.ts`):
1. Reconnect socket
2. `GET /v2/changes` (and/or `/v2/cursor`) to learn what changed
3. `GET /v1/sessions/:id/messages?afterSeq=` for transcript gaps
4. Apply `update` events live going forward

Confirmed by `packages/tests/suites/core-e2e/reconnect.multiDevice.test.ts` — device B after reconnect uses **HTTP transcript fetch**, not socket replay.

### Pending queue while offline

Mobile can enqueue prompts via HTTP pending routes (`apps/server/sources/app/api/routes/session/pendingRoutes.ts`). Server emits `pending-changed` updates; CLI daemon materializes into real messages when session is active (`pendingMessageService.ts`).

### PTY reconnect (separate from transcript)

Daemon keeps a **local ring buffer** (`terminalPtySessionManager.ts:44-116`). Clients poll `daemon.terminal.stream.read` with `cursor`. If cursor < `baseCursor` (trimmed), response includes `{ t: "gap", droppedBefore: N }`. **Not stored on relay.**

---

## 3. Terminal / PTY vs structured agent output

**Happier does both, on separate paths.**

### Primary path: structured agent sync (not interactive shell over relay)

- CLI/daemon spawns provider backends (Claude, Codex ACP/appServer, OpenCode, etc.) under `apps/cli/src/backends/`.
- Agent output is normalized into encrypted **session messages** (`role: agent`, `content.type: output`) and tool envelopes under `packages/protocol/src/tools/v2/`.
- Mobile renders a **transcript UI**, not a raw byte stream from the agent process.
- Live partial output can use ephemeral **`transcript-stream-segment`** (`sessionUpdateHandler.ts:506`) — **not persisted**.

### Secondary path: real embedded PTY (feature `terminal.embeddedPty`)

Evidence:
- `node-pty` / `@homebridge/node-pty-prebuilt-multiarch` in CLI binary (`apps/cli/src/integrations/pty/ptyProvider.ts`)
- Daemon manager: `apps/cli/src/daemon/terminalPty/terminalPtySessionManager.ts` — spawns shell via PTY, buffers events `{t: data|url|gap|exit}`
- RPC surface: `packages/protocol/src/daemonTerminal.ts`, handlers in `apps/cli/src/api/machine/rpcHandlers.terminal.ts`
- UI: xterm in mobile/web (`apps/ui/sources/components/terminal/`, E2E `session.terminal.embeddedPty.spec.ts`)
- **Poll-based**, not WebSocket stream: `machineTerminalStreamRead(machineId, { terminalId, cursor, maxBytes })`

Default: feature disabled server-side (`packages/protocol/src/features/catalog.ts` — `terminal.embeddedPty`).

### Tertiary path: local terminal attach (tmux / Windows Terminal)

`apps/cli/src/terminal/attachment/*` — attaches local terminal multiplexer for **on-machine** use; metadata stored in session (`metadata.terminal` in encryption docs). Not the same as relay-multiplexed PTY.

### Answer for Lancer

Happier’s **default “Happy” experience is structured message sync**, not relay-hosted interactive shell. PTY is an **optional, separate, cursor-poll RPC** with **daemon-local** replay buffer only.

---

## 4. Auth / pairing mechanics

### A. Initial CLI ↔ phone login (terminal connect)

**CLI** (`apps/cli/src/ui/auth.ts`):
1. Generates NaCl box keypair; stores secret in `~/.happy/access.key`
2. `POST /v1/auth/request` with `{ publicKey, supportsV2?, claimSecretHash? }` (`registerTerminalAuthRequestRoutes.ts:43`)
3. Shows QR / URL (`buildTerminalConnectLinks`) — mobile opens approve UI (`terminal-connect-approve` in E2E tests)
4. Polls until authorized; with claim secret uses `POST /v1/auth/request/claim` (not legacy poll-only path)

**Mobile (already logged in)** approves:
- `POST /v1/auth/response` with `{ publicKey, response }` where `response` is **encrypted account secret** for the CLI’s public key (`registerTerminalAuthRequestRoutes.ts:281-322`)

**CLI receives:**
- Bearer token + encrypted response bundle; decrypts to get account encryption material

**Account crypto auth (alternative):** `POST /v1/auth` with `{ publicKey, challenge, signature }` (`docs/api.md`).

Tokens: privacy-kit derived from `HANDY_MASTER_SECRET`; verified server-side (`docs/backend-architecture.md`).

### B. Add second phone via desktop QR pairing

Flow from `packages/tests/suites/core-e2e/auth.pairing.desktopQrMobileScan.roundtrip.*.e2e.test.ts` + `registerPairingAuthRoutes.ts`:

1. **Desktop (authenticated):** `POST /v1/auth/pairing/start` `{ secretHash }` → `{ pairId, expiresAt }`
2. Desktop shows deep link `happier://pair?pairId=...&secret=...` (optional `server=`)
3. **Mobile:** `POST /v1/auth/pairing/request` `{ pairId, secret, publicKey, deviceLabel? }` → `{ state: "requested", confirmCode }`
4. **Desktop polls:** `GET /v1/auth/pairing/status?pairId=`
5. **Desktop approves:** `POST /v1/auth/account/response` `{ publicKey, response }` — encrypts account secret seed to mobile’s public key
6. **Mobile polls:** `POST /v2/auth/account/request` `{ publicKey }` → `{ state: "authorized", tokenEncrypted, response }`
7. **Desktop cleanup:** `POST /v1/auth/pairing/consume`

Pairing is **cryptographic transfer of account secret**, not a machine/session pairing code.

### C. Machine registration (dev machine ↔ account)

After auth, CLI/daemon:
- `POST /v1/machines` with encrypted metadata + `daemonState`
- Opens **machine-scoped** socket with `machineId`
- Machine identity / replacement / revoke flows in `apps/server/sources/app/api/routes/machines/`

Sessions link to machines via encrypted metadata (`machineId` field in `docs/encryption.md` metadata shape).

### D. Session ↔ machine access keys

`AccessKey` table — opaque encrypted per `(sessionId, machineId)`; socket `access-key-get` / HTTP CRUD (`docs/protocol.md`). Used for cross-machine session crypto, not initial phone pairing.

---

## 5. Other architecture worth porting to Lancer

### High relevance for Lancer E2E relay + lancerd PTY

| Pattern | Why it matters | Where |
|---------|----------------|-------|
| **Three socket scopes** (user / session / machine) | Clean multiplexing without SSH | `docs/protocol.md`, `socket.ts` |
| **RPC register/call over relay** | Phone → daemon commands without direct TCP | `rpcHandler.ts`, `RpcHandlerManager.ts` |
| **`${machineId}:${method}` namespacing** | Route RPC to correct daemon | `serverScopedMachineRpc.ts:175` |
| **Cursor-poll stream read for PTY** | Simple reconnect: `cursor` + `gap` events | `daemonTerminal.ts`, `terminalPtySessionManager.ts` |
| **Change log + message log two-tier catch-up** | Cheap “what changed” then targeted fetch | `/v2/changes` + `afterSeq` |
| **Pending message queue** | Phone sends while agent busy; daemon drains | `pendingRoutes.ts`, `pendingMessageService.ts` |
| **Optimistic concurrency** (`expectedVersion`) | Safe metadata/agentState updates | `docs/protocol.md` |
| **E2EE with per-session data keys** | Server-blind storage | `docs/encryption.md` |
| **Connection supervisor package** | Resilient reconnect policy | `@happier-dev/connection-supervisor` (used in `apiMachine.ts`) |
| **Feature gating catalog** | Server + client fail-closed flags | `packages/protocol/src/features/catalog.ts`, `docs/feature-gating.md` |
| **Machine socket ownership / takeover** | One active daemon per machine | `machineSocketOwnershipRegistry` in `socket.ts` |
| **Ephemeral vs durable split** | Presence/streaming without DB bloat | `connectionEventRouter.ts` |

### Medium relevance

| Pattern | Notes |
|---------|-------|
| **Agent provider catalog** (`apps/cli/src/backends/catalog.ts`) | Multi-vendor CLI wrap pattern |
| **Session replay / fork** | `SESSION_CONTINUE_WITH_REPLAY`, `SESSION_FORK` RPC |
| **Direct sessions / handoff** | `DirectSessionMetadataV1`, `transportStrategy: direct_peer \| server_routed_stream` in `types.ts` |
| **Transcript stream segments** | Ephemeral live tail without persisting every chunk |
| **Retention + `changesFloor`** | Prune safety forcing snapshot rebuild |
| **Binary-safe CLI packaging** | No system node in product paths (`docs/binary-runtime.md`) |

### Lower relevance / different from Lancer

- Socket.IO vs raw WebSocket (Lancer already has WebSocket relay)
- Social graph, feed, artifacts, KV store, voice, connected-services OAuth
- Self-host Tailscale Serve docs (`apps/stack/docs/remote-access.md`) — optional remote access pattern, not core protocol

---

## Summary comparison for Lancer

| Question | Happier answer |
|----------|----------------|
| Wire format | **JSON over HTTP + Socket.IO**; no binary relay framing |
| Encrypted blobs | Base64-wrapped NaCl or AES-GCM; storage envelope `{t,c}` or `{t,v}` |
| Offline storage | **Postgres message rows + AccountChange index**; not socket buffer |
| Reconnect replay | **HTTP `afterSeq` message pages + `/v2/changes` hints**; optional full snapshot; socket does not backfill |
| PTY over relay? | **Yes, but optional** — real `node-pty`, **RPC poll + daemon-local ring buffer**, not byte stream on relay |
| Default agent UX | **Structured transcript messages**, not shell |
| Phone pairs how? | **Terminal auth** (QR + `/v1/auth/request` → `/v1/auth/response`) or **QR pairing** for account secret transfer |

---

## Explicit unknowns / not verified in code read

1. Full production deployment topology (Cloud Run vs self-host) beyond Postgres + optional Redis/S3 mentioned in `backend-architecture.md`
2. Complete `machine-transfer` / direct-peer protocol when `machines.transfer.serverRouted` is off
3. Whether any code path streams PTY over socket events (found only RPC poll + ephemeral transcript segments for agent output)
4. Exact Redis adapter behavior under partition / multi-region
5. Rate-limit and abuse-policy numbers (routes reference catalogs; not enumerated here)