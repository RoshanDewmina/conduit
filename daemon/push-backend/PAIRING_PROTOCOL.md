# Lancer keyless QR + blind-relay pairing — wire contract

This is the **authoritative wire contract** the iOS client must match to pair with a
`lancerd` daemon through the blind relay. Both ends dial **out** to the relay; the
relay forwards opaque ciphertext between two peers sharing a pairing channel and
**never** holds a key, so it can never read plaintext (proven by
`daemon/push-backend/websocket_relay_test.go` and
`daemon/lancerd/e2e_loopback_test.go`).

Go reference implementation:
- relay forwarding — `daemon/push-backend/websocket_relay.go`
- daemon client — `daemon/lancerd/e2e_client.go`
- crypto — `daemon/lancerd/e2e_crypto.go`

> **Crypto note:** the channel AEAD is **ChaCha20-Poly1305** (256-bit key, 96-bit
> nonce), not AES-GCM. The original design brief said "AES-GCM"; the shipped Go
> code uses ChaCha20-Poly1305 and the iOS side MUST match that. Everything else
> (X25519 ECDH + HKDF-SHA256) is as designed.

---

## 1. Relay URL format

The relay endpoint is configured on the daemon via the `LANCER_RELAY_URL` env var
(default `wss://relay.conduit.dev`). It is a **base** URL with **no path** — the
client appends `/ws/relay`. Example:

```
LANCER_RELAY_URL = wss://my-host.tailnet-name.ts.net
→ daemon dials  wss://my-host.tailnet-name.ts.net/ws/relay?role=daemon&code=<code>&publicKey=<b64>
```

WebSocket connect URL (both peers):

```
<relayBase>/ws/relay?role=<daemon|phone>&code=<6-char-code>&publicKey=<base64url(rawPubKey)>
```

Query params (all required; relay rejects 400 otherwise):

| Param       | Value                                                                 |
|-------------|-----------------------------------------------------------------------|
| `role`      | `daemon` or `phone`. The daemon connects as `daemon`, the phone as `phone`. |
| `code`      | The 6-character pairing code from the QR / `lancerd pair`. Daemon mints 6 **digits**; relay only checks `len == 6`. |
| `publicKey` | This peer's X25519 **public** key, raw 32 bytes, **base64url, no padding** (`base64.RawURLEncoding`), then URL-query-escaped. |

WebSocket subprotocol: none required. The relay speaks **text frames** carrying JSON.

---

## 2. Channel join & pairing handshake (relay control messages)

All relay frames are JSON text frames. The relay sends these control messages:

1. **Daemon connects first.** If no pair exists for `code`, the relay creates it and
   replies to the daemon:
   ```json
   { "type": "paired", "role": "daemon" }
   ```
   (If a phone connects before any daemon, the relay replies `{"type":"waiting",...}`
   and closes — the phone should retry.)

2. **Phone connects** with the same `code`. The relay now has both peers and sends a
   `peer_joined` to **each** side carrying the **other** peer's public key:
   - to the phone:  `{ "type": "peer_joined", "role": "daemon", "peerPublicKey": "<daemonPubB64>" }`
   - to the daemon: `{ "type": "peer_joined", "role": "phone",  "peerPublicKey": "<phonePubB64>" }`

   `peerPublicKey` is the peer's raw 32-byte X25519 public key, base64url no-pad.

3. On receiving `peer_joined`, **each side derives the shared session key** (see §4).
   No further handshake frames are exchanged — the channel is now live.

**Keepalive:** either side may send `{ "type": "ping" }`; the relay replies
`{ "type": "pong" }`. The daemon pings every 30 s.

**Buffering:** if one peer sends a `message` before the other has joined, the relay
buffers up to 100 messages and replays them verbatim (still opaque) on join.

---

## 3. Framing — encrypted application messages

To send an application message, a peer wraps an **encrypted frame** (§5) inside a
relay envelope and sends it as a JSON text frame:

```json
{
  "type": "message",
  "target": "phone",          // or "daemon" — the OTHER side
  "payload": "<JSON string of the encryptedFrame>"
}
```

`payload` is the **JSON-encoded `encryptedFrame` object, as a string** (i.e. the
frame is `json.Marshal`'d, and that string is placed in `payload`). The relay never
parses `payload`; it forwards it verbatim.

The relay re-emits it to the target as:

```json
{ "type": "message", "from": "daemon", "payload": "<same opaque string>" }
```

`close` (`{"type":"close"}`) tears down the peer's side.

---

## 4. Session-key derivation (X25519 ECDH → HKDF-SHA256)

Both peers compute the **same** 32-byte key. Inputs:

- `shared = X25519(myPrivateKey, peerPublicKey)` — raw 32-byte ECDH output.
- `helperID  = "lancer-relay"`  (constant string, both sides)
- `helperKeyB64 = base64url(daemonPublicKey)`  — **always the daemon's** public key
- `appKeyB64    = base64url(phonePublicKey)`    — **always the phone's** public key

Then:

```
salt = SHA256("lancer-pairing:" + helperID)            // 32 bytes
info = "lancer-v1:" + helperKeyB64 + ":" + appKeyB64    // ASCII bytes
key  = HKDF-Expand(HKDF-Extract(salt, shared), info, 32) // golang.org/x/crypto/hkdf
```

**Critical for interop:** `helperKeyB64`/`appKeyB64` are **role-anchored, not
self/peer-anchored**. The daemon's key is always `helperKeyB64`, the phone's key is
always `appKeyB64`, on **both** sides. The Go daemon (which is always `role=daemon`)
calls:

```go
deriveSessionKey(daemonPriv, phonePubB64,
    "lancer-relay",
    base64url(daemonPub),   // helperKeyB64 = own (daemon) key
    phonePubB64)            // appKeyB64    = peer (phone) key
```

So the **phone** (role `phone`) must call:

```
deriveSessionKey(phonePriv, daemonPubB64,
    "lancer-relay",
    daemonPubB64,           // helperKeyB64 = peer (daemon) key
    base64url(phonePub))    // appKeyB64    = own (phone) key
```

i.e. the phone passes the **daemon** key as `helperKeyB64` and **its own** key as
`appKeyB64`. Getting this order wrong yields a different key and every frame fails
the AEAD tag check. (Verified by `TestE2ELoopbackThroughBlindRelay`.)

base64 everywhere is `base64.RawURLEncoding` (URL-safe alphabet, **no padding**).

---

## 5. Encrypted frame (ChaCha20-Poly1305 AEAD)

`encryptedFrame` JSON object:

```json
{
  "version": 1,
  "nonce":      "<base64url(12-byte nonce)>",
  "ciphertext": "<base64url(ciphertext WITHOUT the tag)>",
  "tag":        "<base64url(16-byte Poly1305 tag)>"
}
```

- AEAD: **ChaCha20-Poly1305** (`golang.org/x/crypto/chacha20poly1305`, 32-byte key).
- Nonce: 12 random bytes per frame.
- AAD (additional authenticated data): the ASCII string **`lancer-frame-v1`**.
- `ciphertext` and `tag` are split: Go seals to `ciphertext||tag` then stores the
  last 16 bytes as `tag` and the rest as `ciphertext`. To decrypt, re-concatenate
  `ciphertext || tag` and `Open` with the nonce and AAD.
- `version` must be `1`; a decryptor MUST reject any other version.

### Application payloads (the plaintext inside a frame)

Plaintext is JSON. Daemon → phone:

```json
{ "type": "approvalPending",
  "payload": { "approvalID": "...", "agent": "...", "kind": "...",
               "command": "...", "risk": "...", "cwd": "...", "toolName": "..." } }
```
```json
{ "type": "agentStatus",
  "payload": { "agent": "...", "model": "...", "sessionCount": 1, "usageUSD": 0.0 } }
```

Phone → daemon:

```json
{ "type": "approvalResponse",
  "approvalID": "...", "decision": "approve|deny|approveAlways",
  "editedToolInput": "...optional..." }
```

The daemon routes `approvalResponse` straight into its single `applyDecision`
chokepoint (audit + approveAlways policy) — see `e2e_router.go`.

---

## 6. Full sequence (happy path)

```
daemon                         relay (blind)                      phone
  | --- WS connect role=daemon ---> |                               |
  | <-- {type:paired} ------------- |                               |
  |                                 | <--- WS connect role=phone -- |
  | <-- {peer_joined, phonePub} --- | -- {peer_joined, daemonPub} ->|
  | derive key (§4)                 |  (forwards keys only)         | derive key (§4)
  | -- {message, target:phone, ---> | -- {message, from:daemon} --> | decrypt approvalPending
  |    payload: encFrame}           |    (opaque ciphertext)        |
  |                                 | <- {message, target:daemon} - | encrypt approvalResponse
  | <- {message, from:phone} ------ |                               |
  | decrypt → applyDecision()       |                               |
```
