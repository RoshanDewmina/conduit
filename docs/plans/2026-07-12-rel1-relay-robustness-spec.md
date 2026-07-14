# REL-1 — relay session robustness (tester blocker #1)

Spec author: Fable orchestrator (sensitive path — relay protocol). Implementer: Claude Sonnet
(full-diff review by Fable required before PR). Worktree: `.worktrees/rel1-relay`,
branch `feat/rel1-relay-robustness`.

## Evidence (why this is the #1 tester blocker)

- 2026-07-12 gap audit (`docs/plans/2026-07-12-roadmap-gap-audit.md:45-54`): after an app
  relaunch, every phone-role websocket was closed by the backend within ~500ms across TWO fresh
  pairing codes even after successful pairing handshakes; terminally blocked a sim gate.
- Silent code expiry: an unconfirmed code dies after `pairConfirmWindow` (10 min,
  `daemon/push-backend/websocket_relay.go:21`). Neither side surfaces it: the daemon gives up
  after 3 rejections with only a log line (`daemon/lancerd/e2e_client.go:276-283`,
  `e2eMaxExpiredCodeRejections` in `e2e_liveness.go:36`); the phone sets
  `.pairingFailed` but `handleDisconnect` keeps redialing the dead code forever
  (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift:587-620`). Result: both sides
  stuck "waiting for peer" on codes that can never pair.
- First-send race: seen ×3 live on 2026-07-12 — the first dispatch after a fresh
  pairing/reconnect races the session re-key → "machine didn't respond"; manual Retry recovers.

## Current protocol facts (do not regress)

- Key pinning + newest-wins reconnect semantics (`websocket_relay.go:196-236`) are security
  properties — keep them exactly.
- A code that completed key exchange (`PairedAt` set) never expires; only unconfirmed codes do.
- Error frames today are `{"type":"error","message":"<text>"}`; daemon matches on
  `strings.Contains(msg.Message, "expired")` (`e2e_client.go:276`) — brittle.
- Backend registry is in-memory; redeploy wipes it (known limitation, OUT OF SCOPE here).

## Changes

### A. Backend — structured, actionable error frames (`daemon/push-backend/websocket_relay.go`)

1. Add a machine-readable `code` field to error frames (additive; keep `message`):
   - `code_expired` — the expired-unconfirmed rejection (`websocket_relay.go:168`)
   - `key_mismatch` — the two pinned-key rejections
   Old clients ignore the extra field; new clients switch on it.
2. Include `expiresAt` (RFC3339, CreatedAt+pairConfirmWindow) in the `waiting` frame sent to the
   first peer, and in the pair-created path, so both clients can show a TTL countdown. Omit it
   once `PairedAt` is set.
3. Log the close *reason* whenever the backend closes a phone/daemon conn (newest-wins replace,
   expiry, key mismatch) — one line each, greppable, to make the ~500ms-close reproducer
   diagnosable in Cloud Run logs.

### B. Daemon — auto re-mint on dead code (`daemon/lancerd/e2e_client.go`, `e2e_liveness.go`)

1. Parse the structured `code` field (fallback: keep the "expired" substring match for old
   backends).
2. On `code_expired` while the code is UNCONFIRMED (never paired): instead of giving up after 3
   attempts with a log line, **auto re-mint** — generate a fresh pairing code exactly as
   `lancerd pair` does, replace the persisted pairing state, reconnect on the new code, and log
   `e2e: pairing code expired — re-minted <code>` so `lancerd status`/Mac UI can surface it.
   Safety: a dead unconfirmed code means NO phone ever completed exchange on it, so re-minting
   cannot orphan a paired phone. Never re-mint a code whose pairing was previously confirmed
   (PairedAt semantics live backend-side; daemon-side proxy = we have a stored peer key /
   completed exchange marker — inspect the persisted pairing struct and use the strictest
   available signal).
3. Unit tests: expired→re-mint state machine (pure, like `expiredCodeTracker`); confirmed
   pairing never re-mints.

### C. Phone — stop churning, show the truth (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift` + pairing UI)

1. Decode `code`/`expiresAt`. On `code_expired`: cancel the reconnect loop (do NOT redial a dead
   code), set a new explicit `pairingState = .codeExpired`, clear the persisted code (mirror the
   2026-07-03 empty-code hygiene — never persist-and-retry a known-dead code).
2. Pairing sheet: render `.codeExpired` as "Pairing code expired — generate a new one on your
   machine" with the re-pair affordance; while `waiting`, show a countdown from `expiresAt`.
3. Reconnect discipline: `handleDisconnect` must not reconnect when pairingState is
   `.codeExpired` or the persisted code is empty/invalid (extends the existing empty-code guard
   at `E2ERelayClient.swift:343`).

### D. First-send retry after re-key (`Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift` + send path)

1. Root cause: a dispatch sent in the window between socket-connected and session-key
   derivation/peer ack is lost — surface is "machine didn't respond", Retry works.
2. Fix: gate the first send on session readiness (sessionKey derived AND peer_joined observed),
   and add ONE automatic retry of a send that times out within N seconds of a re-key event
   (idempotence: re-sending the same dispatch envelope is already safe — Retry proves it).
   Choose the narrowest implementation that kills the race; do not add a general retry queue.
3. Unit test the readiness gate; the race itself is proven live (sim gate below).

## Acceptance (run all yourself; Fable re-runs)

- `cd daemon/push-backend && go build ./... && go vet ./... && go test ./...`
- `cd daemon/lancerd && go build ./... && go vet ./... && go test ./...`
- `cd Packages/LancerKit && swift build && swift test`
- New tests exist for: backend expiry frame carries `code`+`expiresAt`; daemon re-mint state
  machine; phone `.codeExpired` stops reconnect; first-send readiness gate.
- Do NOT touch the live daemon, the owner's production pairing, or run `lancerd pair`.

## Out of scope

Backend registry persistence across redeploys; multi-device slots; epoch nonce P2
(`project_approval_security_hardening_2026-07-04`).
