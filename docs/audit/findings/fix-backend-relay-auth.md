# Fix: Governed Approvals v1 — BLOCKER B2, authenticate the decision relay (per-session capability token)

**Scope:** Go only — `daemon/push-backend/**` and `daemon/lancerd/**` (two separate modules). No Swift, no `project.yml`. Branch `feat/governed-approvals`, worktree `governed-approvals-audit`.
**Builds on** `review-backend.md` (TTL/eviction, body caps, dedupe-by-approvalId, decision-verb allow-list, `/register` validation, the optional `APPROVAL_RELAY_SECRET` guard). None of that is regressed.
**Status:** B2 complete. lancerd poll-path audit/policy gap closed. `go vet` / `go test` / `go test -race` green in BOTH modules.

---

## 1. The problem (recap)

`POST /approval/decision`, `GET /decisions`, `/register` and `/approval` trusted a caller-supplied `sessionId` as the capability. `sessionId` is disclosed (APNs payloads, `GET` query/access logs), so anyone who learned one could forge `approveAlways` (governance bypass) or drain another session's decisions. A single deployment-wide `APPROVAL_RELAY_SECRET` cannot distinguish one legitimate client from another, so it is not sufficient on the capability-sensitive endpoints. The fix is a **per-session capability token**.

## 2. Two-tier authentication model (implemented)

| Tier | Secret | Guards | Enforced by | Who sends it |
|---|---|---|---|---|
| **1 — control plane** | `APPROVAL_RELAY_SECRET` (deployment-wide) | `POST /register`, `POST /approval`, `POST /run-complete` | `relayAuthorized()` | lancerd (relayToken registration, approval push) + the iOS app (APNs token registration) |
| **2 — per-session capability** | `relayToken` (32 random bytes, base64url, per session) | `POST /approval/decision`, `GET /decisions` | `relaySessionAuthorized()` (constant-time) | the iOS app (decision POST) + lancerd (decision poll) |

Tier 1 exists so lancerd can **bootstrap** a session's `relayToken` before any per-session capability exists. Tier 2 is the actual anti-spoofing control: even a party holding the shared secret cannot forge a cross-session decision without the session's `relayToken`, which is delivered only over the already-authenticated DaemonChannel.

This model is documented in a header comment in `daemon/push-backend/relay_security.go`, and the old "BLOCKER-1 / not yet fixed" SECURITY NOTE there has been updated to say the per-session token now exists.

## 3. Exact wire contract (for the Swift worker / coordinator to match)

All field names are **pinned** — do not rename.

### 3a. lancerd → app: relayToken delivery (DaemonChannel handshake)
- **RPC method:** `lancer.device.register` (the existing app→lancerd session handshake; the app already sends this with its session info).
- **Request params (unchanged):** `{ "pushBackendURL": "<url>", "sessionID": "<id>" }` — note `sessionID` (capital `ID`), the existing field.
- **Response result — CHANGED:** previously the string `"ok"`; now a JSON object:

```json
{ "relayToken": "<base64url-no-pad, 43 chars>" }
```

  The app must read `result.relayToken` from the `lancer.device.register` reply and store it for the session. Treat it as a secret.

### 3b. app → backend: decision POST
- `POST {backend}/approval/decision`
- **Header:** `Authorization: Bearer <relayToken>`
- **Body (unchanged):** `{ "approvalId": ..., "decision": "approve|approveAlways|deny", "sessionId": ..., "editedToolInput"?: ... }`
- The `sessionId` in this body **must equal** the `sessionID` the app passed to `lancer.device.register` (that is the key the relayToken was registered under). Missing/wrong/unknown token → **401**, no side effects.

### 3c. lancerd → backend: decision poll (already wired here)
- `GET {backend}/decisions?sessionId=<id>`
- **Header:** `Authorization: Bearer <relayToken>`

### 3d. lancerd → backend: relayToken registration (already wired here)
- `POST {backend}/register`
- **Header:** `Authorization: Bearer <APPROVAL_RELAY_SECRET>` (when configured)
- **Body:** `{ "sessionId": "<id>", "relayToken": "<token>" }`

### 3e. app → backend: APNs registration (unchanged behavior)
- `POST {backend}/register` with body `{ "sessionId": ..., "deviceToken": ... }` and the control-plane secret. `/register` now upserts `deviceToken` and `relayToken` **independently**, so the app's APNs registration and lancerd's relayToken registration can arrive in any order without clobbering each other.

## 4. Files changed

### push-backend (`daemon/push-backend/`)
- **`main.go`**
  - `registry` is now `map[string]*sessionRecord` where `sessionRecord = { apnsToken, relayToken, seen }` (replaces the parallel `tokens`/`seen` maps).
  - `registerRequest` gains optional `relayToken`. `handleRegister` requires `sessionId` + at least one of `{deviceToken, relayToken}`, length-caps all three, upserts each field independently, keeps the capacity guard, and **logs presence only — never token material**.
  - `evictExpiredDevices` evicts whole stale `sessionRecord`s (so the relayToken shares the ~24h TTL and the existing janitor sweep). `handleApproval` / `handleRunComplete` read `rec.apnsToken`.
- **`relay_security.go`**
  - New `relaySessionAuthorized(sessionID, provided)` — Tier-2 constant-time (`crypto/subtle`) compare against the stored relayToken; fail-closed on empty/unknown/mismatch; refreshes `seen` on success (sliding TTL for active sessions).
  - New `bearerToken(r)` helper; `relayAuthorized` now uses it. New `maxRelayTokenLen = 512`.
  - Two-tier model documented; SECURITY NOTE updated; startup warning reworded for the control plane.
- **`decisions.go`** — `handlePostDecision` and `handlePollDecisions` now authorize with `relaySessionAuthorized` (Tier 2) instead of the shared secret. Input validation runs first (malformed → 400); a valid-shaped request with a bad token → 401 with **no map mutation / no drain** (fail-safe).
- **Tests:** `decisions_test.go`, `relay_security_test.go`, `approval_push_test.go` updated for the record store + token auth; added `TestDecisionRelayPerSessionTokenAuth`, `TestControlPlaneSecretEnforcedOnRegister`, `TestRegisterUpsertsRelayAndApnsIndependently`, relayToken TTL eviction assertion, plus new register-validation cases.

### lancerd (`daemon/lancerd/`)
- **`relay_token.go` (new)** — `generateRelayToken()`: 32 bytes `crypto/rand`, base64url no-pad.
- **`server.go`**
  - `server` gains `relayToken` (guarded by `deviceMu`).
  - `lancer.device.register` mints (or reuses, across reconnects) the per-session relayToken, registers it with the backend via `postRelayRegistration` (async, control-plane authed), starts the poller with it, and returns `{ "relayToken": ... }`.
  - New `applyDecision(id, decision, edited)` = `resolve` + audit + (approveAlways → policy), the single place both the live RPC path and the poll path now use.
  - `agent.approval.response` routes through `applyDecision`. `handleHookWithNotify` no longer double-records on wake; on **timeout** it audits the auto-deny and `remove()`s the orphan (fail-safe).
  - New `postRelayRegistration(...)` — never logs the token.
- **`approval.go`** — `waitWithTimeout` now returns `(decision, received bool)`; added `approvalStore.remove(id)`.
- **`decision_poll.go`** — poller carries the relayToken; `ensureRunning(backendURL, sessionID, relayToken)`; the `GET /decisions` poll sends `Authorization: Bearer <relayToken>`; decisions applied via `apply` (= `applyDecision`); body decoded only on HTTP 200.
- **Tests:** `server_test.go` (`TestDeviceRegister` rewritten to assert mint + handshake field + backend registration), `decision_poll_test.go` (signature + `TestDecisionPollerSendsBearerToken`), `server_policy_test.go` (`TestApplyDecisionApproveAlwaysPersistsPolicyAndAudit`, `TestApplyDecisionApproveAuditedNoPolicy`).

## 5. lancerd poll-path approveAlways / audit gap — closed

Before: `decision_poll.go` called `p.resolve(...)` and ignored the result. The live `agent.approval.response` RPC explicitly recorded the audit entry and wrote the always-policy; the poll fallback relied on the waiting hook to do so, which **does not happen** once that hook has timed out (the > ~120s case) — so a phone-decided `approveAlways` could be applied without being audited or persisted as an always-rule, and the audit trail (the product's whole value) had a hole.

After: both paths route through `server.applyDecision`, which is the single delete-under-lock chokepoint, so a poll-delivered decision persists **identically** to the live-SSH path — audit entry always written; `approveAlways` always written to `policy-always.yaml`. The change also removes a pre-existing **double**-record/double-policy-write in the live attached path (the RPC handler *and* the woken hook both recorded). FAIL-SAFE: a failed `appendAllowAlways` is logged, never fatal (a dropped always-rule means more prompting later, never an unintended allow). On hook timeout the orphan is retired so a late relay decision can't mis-audit an approve after an auto-deny. Verified by `TestApplyDecisionApproveAlwaysPersistsPolicyAndAudit` (+ the plain-approve negative case).

## 6. Verification (evidence)

```
$ cd daemon/push-backend && go vet ./... && go test ./...
ok  	lancer/push-backend
$ go test -race ./...
ok  	lancer/push-backend

$ cd daemon/lancerd && go vet ./... && go test ./...
ok  	lancer/lancerd
ok  	lancer/lancerd/policy
$ go test -race ./...
ok  	lancer/lancerd
ok  	lancer/lancerd/policy
```

vet clean, race clean, both modules. Test runs (incl. subtests): push-backend **90**, lancerd **59**. New/changed coverage: correct token → 2xx; missing/wrong/unknown token → 401 (POST and poll); rejected posts leak nothing; relayToken TTL eviction → de-authorizes; control-plane secret on `/register`; independent apns/relay upsert; relayToken minted + returned in the handshake + registered with the backend; poll sends `Bearer`; poll-path `approveAlways` → policy + audit (and plain approve → audit only, no policy).

## 7. Residual risk / flags

1. **Registration trust = control-plane secret (no TOFU).** `/register` is last-writer-wins (per the "keep it simple" follow-up): a holder of `APPROVAL_RELAY_SECRET` could overwrite a session's relayToken. Mitigations: the secret is deployment-scoped and never client-distributed; the original "anyone with a leaked sessionId" bypass is closed. Hardening option (deferred): TOFU — record the relayToken on first registration and 409 on change for a live session — at the cost of breaking re-registration after a lancerd restart that re-mints. Flagged, not implemented.
2. **`APPROVAL_RELAY_SECRET` unset = open control plane.** If the deployment leaves it unset, anyone can register/overwrite a session's relayToken (Tier 1 is open), which undermines Tier 2. `warnIfRelayUnauthenticated` logs a loud startup warning; production MUST set it. (Tier-2 compare itself still rejects anyone who doesn't know the registered token.)
3. **sessionId consistency is a cross-component contract.** The app must use the *same* session identifier for `lancer.device.register.sessionID` and the decision POST `sessionId`; otherwise the backend looks up the wrong record and 401s (fails safe → 120s auto-deny). This is the existing `identifierForVendor` consistency concern from `review-approvals.md` — surfaced here as a coordination requirement, owned Swift-side.
4. **lancerd restart with a long-lived app session.** A restart re-mints the relayToken (in-memory only); lancerd re-registers it on the next `lancer.device.register` (last-writer-wins, so the backend updates) and returns the new token to the app over the handshake. If the app caches the old token and does not re-handshake, its decision POSTs 401 until it re-attaches. Fail-safe (auto-deny backstop), but flagged.
5. **Timeout/late-decision race.** Exactly at the ~120s boundary a decision arriving as the hook times out can produce both a real-decision and an auto-deny audit entry. Extremely narrow window; both outcomes are safe (the agent is never auto-approved). Flagged.
