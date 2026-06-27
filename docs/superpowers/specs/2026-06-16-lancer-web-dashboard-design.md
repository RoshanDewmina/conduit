# Lancer Web Dashboard — Design Spec

**Date:** 2026-06-16 · **Author:** Claude (plan/verify role) · **Status:** awaiting owner review → opencode execution

## 1. Why / goal

Web/Android is the **biggest reach gap** vs the field (`docs/audit/competitive-landscape-2026-06.md`). Omnara and Happy Coder both ship *full-control* web clients (approve, reply, redirect, even launch agents). A read-only dashboard would underwhelm. This spec defines a **v1 web dashboard** that closes the gap on the surfaces the live relay can carry **today**, wired for real (not mock), while carrying Lancer's governance moat onto the web via a **WebAuthn/passkey gate** on critical approvals — something no competitor does.

### Locked scope (owner decisions, 2026-06-16)

| Dimension | Decision |
|---|---|
| Surfaces (v1) | Fleet glance · Agent-detail "lite" · Inbox/approvals |
| Actions (v1) | Approve / Deny over the live relay |
| Web auth gate | WebAuthn/passkey for Critical; one-tap for Low/Med |
| Transport | Web is a first-class **blind-relay peer** (reuses the exact wire contract) |
| Data source | Wire to the **real relay now** (no mock backend) |
| Location | `web/` in this repo |
| Stack | Next.js (App Router, latest) + shadcn/ui + Tailwind · **bun** · TypeScript |
| Deferred | Live block transcript on web · reply-to-agent (both need a relay-protocol extension) |

### Non-goals (v1)

- **No live block/terminal stream** — the relay carries no block/transcript message today (`E2ERelayMessage.swift` has only `approvalPending`/`agentStatus`/`loopUpdate`/`approvalResponse`/`ping`/`pong`). Deferred to a relay-extension pass.
- **No reply-to-agent free text** — no relay message exists; deferred.
- **No launch-agent** — `dispatch` exists but is the known open blocker (`project_relay_dispatch_roundtrip`); deferred.
- **No Android** — web-first; a PWA/Capacitor wrap is a later step.
- **No new backend service** — the web is a relay *peer*, like the phone. We do not stand up a server that holds session keys (that would break the blind-relay E2E model).

## 2. Architecture

```
┌─────────────┐   wss  ┌───────────────┐  wss   ┌──────────────┐
│  web/  (TS) │◄──────►│ blind relay   │◄──────►│  lancerd    │
│  role=phone │  E2E   │ (forwards     │  E2E   │  role=daemon │
│  Next.js    │ opaque │  ciphertext)  │ opaque │  (agent host)│
└─────────────┘        └───────────────┘        └──────────────┘
        ▲ approvalResponse / decrypt approvalPending,agentStatus,loopUpdate
```

The web client is a **`role=phone` peer** speaking the authoritative wire contract in `daemon/push-backend/PAIRING_PROTOCOL.md`. The relay never holds a key; the web derives the same ChaCha20-Poly1305 session key the iOS app does. **No code on the relay or daemon changes for v1** — they already accept a second phone-role peer.

### Layers (all under `web/`)

1. **`lib/relay/`** — the relay-peer module (transport + crypto + codec). The linchpin. Pure TS, framework-agnostic, independently unit-tested.
2. **`lib/store/`** — an observable store fed by decrypted frames: `agents[]`, `loops[]`, `pendingApprovals[]`, `connection state`. (Zustand — small, no provider boilerplate.)
3. **`lib/auth/`** — WebAuthn gate for critical approvals.
4. **`app/` + `components/`** — Next.js App Router pages + shadcn components for the three surfaces, themed with Lancer tokens.

### Design language

Theme shadcn with the **Lancer design tokens** (the same CSS vars as the `.dc.html` board / prototype) so it reads as Lancer, not default shadcn: `--bg #0a0b0d`, `--surface #0e0f12`, `--border #23262d`, `--text #e9e9e2`, `--accent #2f43ff`, `--ok #36c26b`, `--warn #f0a93b`, `--danger #e0533f`, risk ramp `--rLow/rMed/rHigh/rCrit`, fonts Chakra Petch (display) + Fira Code (mono). Square corners (radius 2px), dark, mono-forward — matches the board.

## 3. The relay-peer module (`lib/relay/`) — precise contract

**This is the highest-risk piece. It must match `PAIRING_PROTOCOL.md` byte-for-byte or every frame fails the AEAD tag check.** WebCrypto does NOT provide ChaCha20-Poly1305, so use **@noble** (audited, pure-TS, browser-safe):

- `@noble/curves/ed25519` → `x25519` (ECDH)
- `@noble/hashes/hkdf` + `@noble/hashes/sha256` (key derivation)
- `@noble/hashes/sha256` for the salt hash
- `@noble/ciphers/chacha` → `chacha20poly1305` (AEAD)

### 3.1 Connect

```
url = `${relayBase}/ws/relay?role=phone&code=${code}&publicKey=${b64urlNoPad(ownX25519Pub)}`
```
- `relayBase`: e.g. `wss://host.tailnet.ts.net` (no trailing `/ws/relay`).
- `code`: 6-digit string from `lancerd pair`.
- `publicKey`: own raw 32-byte X25519 public key, **base64url no-pad** (`base64.RawURLEncoding` equivalent), then URL-query-escaped.

### 3.2 Relay control frames (JSON text)

- `{type:"waiting"}` → daemon not present yet; close & retry with backoff.
- `{type:"peer_joined", role:"daemon", peerPublicKey:"<b64url>"}` → derive session key (3.3), channel is live.
- `{type:"ping"}` / `{type:"pong"}` keepalive; web pings every 30 s.
- `{type:"message", from:"daemon", payload:"<opaque string>"}` → decrypt (3.4).
- `{type:"close"}` → tear down.

### 3.3 Session-key derivation (role-anchored — get the order right)

```
shared       = x25519(ownPriv, daemonPub)              // raw 32 bytes
helperKeyB64 = b64urlNoPad(daemonPub)                  // ALWAYS the daemon key
appKeyB64    = b64urlNoPad(ownPub)                     // ALWAYS the phone(web) key
salt         = sha256(utf8("lancer-pairing:lancer-relay"))   // 32 bytes
info         = utf8("lancer-v1:" + helperKeyB64 + ":" + appKeyB64)
key          = hkdf(sha256, /*ikm*/ shared, salt, info, 32)
```
The web is `role=phone`, so it passes the **daemon** key as `helperKeyB64` and **its own** key as `appKeyB64` (matches the phone block in PAIRING_PROTOCOL.md §4). Inverting these yields a different key and silent total failure.

### 3.4 Frame AEAD (ChaCha20-Poly1305)

`encryptedFrame` JSON: `{ version:1, nonce, ciphertext, tag }`, all fields **base64url no-pad**.
- Nonce: 12 random bytes per frame (`crypto.getRandomValues`).
- AAD: ASCII `"lancer-frame-v1"`.
- **Tag split:** Go seals to `ciphertext||tag` and stores the **last 16 bytes** as `tag`, the rest as `ciphertext`. @noble's `chacha20poly1305.seal` also returns `ciphertext||tag` — so split the last 16 bytes out on encrypt, and re-concat `ciphertext||tag` before `.open()` on decrypt.
- Reject any `version !== 1`.

### 3.5 Envelope (app message in/out)

- **Out** (web→daemon): `{type:"message", target:"daemon", payload: JSON.stringify(encryptedFrame)}`.
- **In** (daemon→web): `{type:"message", from:"daemon", payload}` where `payload` is the JSON string of an `encryptedFrame`.

### 3.6 App payloads (plaintext inside a frame)

Decode (daemon→web):
- `{type:"approvalPending", payload:{approvalID, agent, kind, command?, risk:Int, cwd?, toolName?}}`
- `{type:"agentStatus", payload:{agent, model?, sessionCount:Int, usageUSD?}}`
- `{type:"loopUpdate", payload:{loopID, status, currentStep?, spendUSD?}}`

Encode (web→daemon):
- `{type:"approvalResponse", approvalID, decision:"approve"|"deny"|"approveAlways", editedToolInput?}`

> Note the envelope shape: recent daemon commits unwrap a `{type,payload}` inner envelope for `approvalPending/agentStatus/loopUpdate`. Mirror the iOS `RelayInnerEnvelope<T>` shape exactly (see `E2ERelayMessage.swift`). The web encoder for `approvalResponse` matches the phone→daemon JSON in PAIRING_PROTOCOL.md §5 (flat fields, not nested under `payload`).

### 3.7 Test vectors (correctness gate, not eyeballed)

Claude will generate authoritative vectors from the Go reference (`daemon/lancerd/e2e_crypto.go` + a tiny Go harness) and drop them into `web/lib/relay/__fixtures__/vectors.json`: known `(ownPriv, daemonPub) → key`, and known `(key, nonce, plaintext) → encryptedFrame`. `lib/relay/crypto.test.ts` (bun test) must reproduce them exactly. This makes interop mechanically checkable before any live test.

## 4. State store (`lib/store/`)

A Zustand store updated by the relay module's `onMessage`:
- `connection: "disconnected" | "pairing" | "connected" | "error"`
- `agents: Record<string, {agent, model?, sessionCount, usageUSD?, lastSeen}>` ← `agentStatus`
- `loops: Record<string, {loopID, status, currentStep?, spendUSD?}>` ← `loopUpdate`
- `pending: ApprovalPending[]` ← `approvalPending` (append; remove on local decision)
- actions: `approve(id, gate)`, `deny(id)` → encode `approvalResponse`, send, optimistically remove from `pending`.

## 5. Surfaces

### 5.1 Fleet glance (`app/page.tsx`)
Grid of agent cards from `agents` + `loops`: agent name (PixelAvatar-style seeded square or initials), model, session count, loop status chip (running/idle/blocked → ok/accent/warn), spend (usageUSD/spendUSD), current step line. Quota-ring style gauge per agent from `usageUSD` if a cap is known (else hide). Click → Agent detail. A "pending approvals: N" banner links to Inbox.

### 5.2 Agent-detail "lite" (`app/agent/[id]/page.tsx`)
Header (agent, model, status) + current loop step + spend + a list of that agent's recent approvals (from `pending` filtered by agent, plus a short local history of decided ones this session). **No live block transcript** — show an explicit "Live transcript available on the phone / coming to web" affordance so the absence is intentional, not broken.

### 5.3 Inbox / approvals (`app/inbox/page.tsx`)
List of `pending` approvals, newest first. Each card: agent · kind · command (mono, truncatable) · cwd · risk chip (Low/Med/High/Critical from `risk:Int` → rLow/rMed/rHigh/rCrit). Actions: **Deny** / **Approve**. On Approve:
- risk < Critical → one-tap → `approve(id)`.
- risk == Critical → trigger WebAuthn gate (§6); only on success → `approve(id)`. On failure/cancel → no-op, show "Critical actions require biometric verification."
- `approveAlways` optional secondary (encode `decision:"approveAlways"`).

## 6. WebAuthn gate (`lib/auth/`)

The web-native mirror of the phone's Face-ID gate.
- **Enrollment:** on first run, register a platform authenticator (`navigator.credentials.create`, `authenticatorAttachment:"platform"`, `userVerification:"required"`), store the credential ID in localStorage. UI: "Set up biometric approval (Touch ID / Windows Hello)."
- **Gate:** before a Critical approval, `navigator.credentials.get({userVerification:"required", allowCredentials:[storedId]})`. Success unlocks the single approval. No server-side attestation in v1 (the gate is a *local* presence/biometric check, exactly like the phone's local Face-ID — it does not replace the daemon-side audit, which remains authoritative).
- Threshold: gate when **`risk >= 3`** (Critical). Confirmed against `LancerCore/Approval.swift` (`Risk: Int` — low=0, medium=1, high=2, critical=3) and the canonical relay-payload mapping in `DesignSystem/Components/InboxCards.swift:290` (`risk>=3 critical, ==2 high, ==1 medium, else low`). Mirror that exactly in `web/lib/store` so the chip labels match iOS.
- Graceful fallback: if no platform authenticator, fall back to "approve on phone" deep-link for Critical (keep Low/Med one-tap).

## 7. Pairing UX

Web has no QR scanner, so **manual entry**: a Connect screen with `relay base URL` + `6-digit code` (from `lancerd pair`). The web generates its X25519 keypair on first run and persists `{relayBaseURL, code, keypairPriv}` in localStorage for reconnect (v1; note "durable pairing tokens / encrypted-at-rest keystore" as hardening in §9 — ties to `relay_token.go`). Connection status badge mirrors the iOS `E2ERelayStatusBadge`.

## 8. Build & verification plan (Claude verifies — never trust opencode blind)

1. **Build:** `cd web && bun install && bun run build` must pass clean (TS strict). Claude runs this.
2. **Crypto unit test:** `bun test lib/relay` reproduces the Go-derived vectors (§3.7). Hard gate.
3. **Live interop (authoritative):** Claude stands up a local `lancerd` + relay, runs `lancerd pair` to mint a code, connects the web client, triggers a real `approvalPending`, confirms the web **decrypts** it and the daemon **accepts** the web's `approvalResponse` (the approval loop was just closed in commits 19c4d08/647c107 — same path). Screenshot the Inbox rendering the real approval.
4. **Visual:** render Fleet/Inbox/Agent-detail (chrome-devtools), check console clean, verify Lancer theming.
5. **WebAuthn:** verify the Critical-approval gate prompts the platform authenticator (virtual authenticator in chrome-devtools).

## 9. Open items / hardening (post-v1 or confirm-before-wiring)

- ~~**Risk integer scale:**~~ RESOLVED — `risk>=3` = Critical (`Approval.swift` `Risk: Int`; `InboxCards.swift:290`). WebAuthn gate wired to that cutoff.
- **Durable pairing:** localStorage keypair is v1; design an encrypted-at-rest keystore + long-lived pairing token (`relay_token.go`) later.
- **Relay-extension pass (unblocks deferred scope):** add `blockChunk`/`transcript` + `agentReply` message types in lockstep across Go daemon ↔ Swift client ↔ web (verified via iOS app-target build) → then live blocks + reply on web.
- **Android:** PWA/Capacitor wrap once web is stable.

## 10. opencode execution plan (Claude dispatches; parallel agents never share files)

**Wave 1 — scaffold (1 agent, must finish first; creates the tree):**
- `bunx --bun shadcn@latest init -t next` in `web/`, Tailwind + `components.json` (`cssVariables:true`), Lancer token theme in `app/globals.css`, base dark shell/layout + nav (Fleet/Inbox), fonts. Add `@noble/curves @noble/hashes @noble/ciphers zustand` deps. Acceptance: `bun run build` passes.

**Wave 2 — parallel, disjoint files:**
- **Agent A — `lib/relay/`** (crypto.ts, codec.ts, client.ts, types.ts + crypto.test.ts against fixtures). No UI. Acceptance: `bun test lib/relay` green against vectors.
- **Agent B — `lib/store/` + `lib/auth/`** (zustand store + WebAuthn gate). Depends only on `lib/relay/types.ts` (shared types created in Wave 1 stub or by Agent A first-write — to avoid collision, **types live in `lib/relay/types.ts`, authored in Wave 1 scaffold**).
- **Agent C — surfaces** (`app/page.tsx` Fleet, `app/inbox/page.tsx`, `app/agent/[id]/page.tsx` + `components/`). Consumes store + types.

**Wave 3 — Claude:** integration wiring check, the §8 verification (build + unit + live interop + visual + WebAuthn). Re-dispatch corrections per agent on any failure.

To avoid write collisions in Wave 2, `lib/relay/types.ts` (shared TS types) is authored in Wave 1 so A/B/C all import a stable contract. Agents A/B/C touch disjoint directories.
