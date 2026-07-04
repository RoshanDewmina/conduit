# Security Architecture — Lancer

**Last updated:** 2026-07-04

**Audience:** Security researchers, system administrators, and technically
sophisticated users evaluating Lancer's threat model.

---

## 1. Overview

Lancer is an iOS approval-cockpit for AI coding agents (Claude Code, Codex,
opencode) that run on the user's own computer or server. The security model
relies on three principles:

1. **No cloud escrow.** SSH keys and pairing secrets live on your devices.
   Lancer operates no infrastructure that can decrypt your agent traffic.
2. **Defense in depth.** On-device Keychain + SSH transport encryption +
   optional end-to-end encryption through the push relay.
3. **User sovereignty.** You choose which relay (Lancer's default or
   self-hosted), which hosts to pair with, and when to approve.

**Implementation note, 2026-06-17:** the self-host SSH path is the verified production path in the
current app. Backend-relayed decisions are present in code through `ApprovalRelay`, but end-to-end
relay pairing and physical-device APNs behavior still require live validation before release.

---

## 2. Pairing (device-to-host)

### 2.1 The pairing flow

Pairing is **code-only** — the app no longer scans a QR code. Both sides
dial out to Lancer's push relay and exchange X25519 public keys through it;
the relay only ever forwards opaque routing/key data, never SSH credentials
or session-key material (see §2.2, §4.3).

1. The iOS app generates an X25519 key pair, mints a one-time 6-digit
   pairing code, and opens a relay connection (`/ws/relay`) as the `phone`
   role, displaying the code to the user.
2. The user enters that code on the host — via `lancerd pair` or the
   install flow. `lancerd` generates its own X25519 key pair and opens a
   relay connection as the `daemon` role with the same code. (The relay
   accepts either side first; in the product flow the phone displays the
   code before the host is told to enter it.)
3. Once both roles have joined a code, the relay sends each side a
   `peer_joined` message carrying the *other* side's public key. Each side
   then derives the shared session key via X25519 ECDH (see §3).
4. The X25519 private key is stored in the iOS Keychain with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
   `kSecAttrSynchronizable: false` — it never leaves the device. The setup
   code itself is not persisted after pairing completes.

The full wire contract (relay frame shapes, key-derivation inputs, sequence
diagram) lives in `daemon/push-backend/PAIRING_PROTOCOL.md`.

### 2.2 Relay-side pairing-code protections

A 6-digit code is far lower-entropy than a scanned QR payload, so the relay
(`daemon/push-backend/websocket_relay.go`) treats it strictly as a
short-lived rendezvous identifier — never a permanent credential — and
enforces three protections:

- **Key pinning.** Once a role's (`phone` or `daemon`) public key is
  recorded for a code, a later connection on that code presenting a
  *different* key is rejected outright instead of silently replacing it.
  This closes a hijack/MITM path where an attacker who guesses or observes
  the code could otherwise take over a role mid-pairing. The legitimate key
  can always reconnect (e.g. a daemon restart, or the app re-opening the
  pairing screen).
- **Unconfirmed-code expiry.** A code where only one side ever joined
  expires 10 minutes after creation and is deleted from the relay — an
  abandoned or guessed-but-unused code does not stay valid indefinitely. A
  code that completed a full key exchange keeps working for legitimate
  reconnects regardless of age.
- **Per-IP rate limiting.** Connection attempts are capped at 20 per minute
  per source IP (HTTP 429 beyond that), bounding brute-force guessing
  against the 6-digit (1,000,000-combination) code space. A periodic sweep
  bounds the limiter's own memory under sustained source-IP rotation.

### 2.3 Security properties

- **The pairing code is single-use per pairing attempt and not persisted**
  after pairing completes — see §2.2 for what enforces this on the relay
  side.
- **The code carries no SSH credentials.** It only allows the two sides to
  find each other on the relay and exchange X25519 public keys. A
  compromised code reveals no SSH secrets, and §2.2's key pinning means it
  cannot be used to hijack an in-progress or completed pairing.
- **The SSH connection is authenticated separately** using the user's own SSH
  keys. Lancer never sends SSH private keys over the network.
- **The relay is blind to key material** — it forwards public keys and
  opaque ciphertext only; private keys and the derived session key never
  reach it (see §4.3).

### 2.4 Account device binding — App Attest (hosted flow)

Separate from the relay pairing above, the hosted account flow binds a daemon
to a user account via a QR challenge (`push-backend` `/v1/devices/*`): the
daemon mints a challenge + secret, a signed-in phone binds it, the daemon
redeems an opaque capability credential. As of 2026-07-04 the **bind step
additionally requires Apple App Attest** when the backend is configured for it
(`APP_ATTEST_TEAM_ID` / `APP_ATTEST_BUNDLE_ID`; fail-closed `log.Fatal` at
startup if unset in a production deployment):

- The phone requests a single-use, per-user server nonce
  (`POST /v1/devices/attest-challenge`), generates an App Attest key, and
  attests it over the nonce (`DCAppAttestService`).
- The backend verifies the attestation per Apple's documented steps —
  certificate chain to the pinned Apple App Attest root CA, nonce binding,
  key-identifier match, App ID (team + bundle), counter 0, environment aaguid —
  and rejects the bind on any failure **even when the QR capability secret is
  correct**. A leaked/guessed/phished QR secret plus a signed-in session is
  deliberately not sufficient to bind a device.
- Attestation is applied at **bind** (the iOS entry point), not redeem: redeem
  is performed by the Go daemon, which cannot attest, and redeem already
  requires a completed bind plus the secret. The verified App Attest key ID is
  stored on the binding for audit.
- The simulator and non-Apple hardware cannot attest; binds without attestation
  are accepted **only** by a backend explicitly running with App Attest
  disabled (local dev). Production refuses them (HTTP 401).

---

## 3. Session keys

After pairing, both sides derive session keys:

```
shared_secret = X25519(ios_private, host_public)
                = X25519(host_private, ios_public)

session_key = HKDF-SHA256(
    ikm:  shared_secret,
    salt: pairing_nonce || epoch,
    info: "lancer-v1-session-key",
    len:  32
)
```

- The session key is used as the symmetric key for encrypting approval
  request payloads (see §4).
- Session keys are ephemeral — a new HKDF derivation runs each session using
  a fresh epoch nonce.

---

## 4. Payload encryption

### 4.1 Direct SSH path (default)

When the phone is on the same network as the host (or reachable via the
internet), all approval traffic travels over the **existing SSH connection**.
SSH provides its own encryption (AES-256-GCM or ChaCha20-Poly1305 per
negotiated cipher). The SSH tunnel is the sole transport — Lancer's relay
is not involved.

### 4.2 Push relay path (end-to-end encrypted)

When the phone is offline or on a different network, notifications can be
delivered via Lancer's push relay. The payload is encrypted **before** it
leaves either endpoint:

```
Encryption (iOS → Host decision):
  1. Generate random 12-byte nonce
  2. ciphertext = ChaCha20-Poly1305_Encrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "lancer-relay-v1",
       plaintext: decision_bytes
     )
  3. Transmit: nonce || ciphertext || tag

Decryption (Host receives):
  1. Parse nonce, ciphertext, tag
  2. plaintext = ChaCha20-Poly1305_Decrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "lancer-relay-v1",
       ciphertext: ciphertext
     )
```

### 4.3 What the relay sees

The push relay (hosted on Fly.io) has access to:

- **Source and destination routing metadata** (which host identifier should
  receive this blob)
- **Opaque ciphertext** — the payload is indistinguishable from random bytes
- **Timestamps** of when blobs pass through

The relay does **not** have access to:
- SSH keys, hostnames, usernames, or passwords
- Agent commands, file contents, source code, or terminal output
- Session key material (X25519 keys never reach the relay)
- Any identifying user information (Lancer has no account system)
- IP addresses beyond standard HTTP access logs (retained 14 days)

### 4.4 Approval-event integrity (replay + content binding)

Two integrity mechanisms protect governed approvals end to end (2026-07,
audited 2026-07-04):

- **Replay resistance.** Every E2E relay frame wraps a monotonically increasing
  per-direction sequence number *inside* the encrypted payload
  (`seqFrame`/`replaySequencer`, `daemon/lancerd/e2e_crypto.go`; Swift mirror
  `SeqFrame`/`ReplaySequencer` in `SSHTransport/E2ERelayClient.swift`). Both
  sides stamp what they send and reject any received frame whose sequence is
  not strictly greater than the last accepted one; counters reset on each
  `peer_joined` key (re)establishment. Known limitation (accepted, P2): the
  session key is derived deterministically from the static pairing keys, so a
  relay that forges `peer_joined` can reset the counters and replay
  prior-generation frames — the impact is bounded because approval IDs are
  single-use (a replayed decision for a resolved approval is a no-op) and every
  decision must also pass the content-hash check below. Epoch nonces in the key
  derivation would close this fully and are tracked as follow-up.
- **Content-hash binding.** Every approval event carries a SHA-256 over the
  exact command / patch / cwd / tool-input the human reviews
  (`computeContentHash`, `daemon/lancerd/approval.go`), and a decision must
  echo it back; `approvalStore.resolve` rejects any decision whose hash doesn't
  match the stored pending event, on every transport (SSH attach, E2E relay,
  backend REST). The Go and Swift canonicalizations are pinned to a shared
  cross-language test vector on both sides.

### 4.5 Risk tiering and the no-client grace

Escalated approvals with **no reachable client** (no attach channel, no relay
pairing, no push device) auto-approve after an 8-second grace **only for
low/medium-risk events** (`policy.PermitsNoClientGrace`) so unattended on-host
agent runs are not stalled; high/critical events wait indefinitely for an
explicit human decision (owner directive 2026-07-02). Since 2026-07-04 the
risk tier used for this gate is **floored at the daemon's own scoring**
(`policy.Evaluate` + `ScoreRiskInt`): a hook adapter may raise an event's risk
band but can never lower it below what the daemon computes from the command
and kind, so a lied or omitted wire risk cannot make a dangerous escalation
grace-eligible.

---

## 5. On-device key storage

| Secret | Storage mechanism | Exportable? |
|--------|-------------------|-------------|
| SSH private keys | iOS Keychain, `whenUnlockedThisDeviceOnly` | Never exported — used only for SSH auth |
| X25519 key pair | iOS Keychain, `whenUnlockedThisDeviceOnly` | Never exported |
| Session history | Encrypted SQLite database (local) | Via app UI only (user-initiated export) |
| APNs device token | Forwarded to push relay (via HTTPS) | — |

All Keychain items have `kSecAttrSynchronizable: false` — they never sync to
iCloud.

### 5.1 Approval-decision local authentication

Since 2026-07-04, committing an approve/reject decision on a **high or
critical-risk** approval requires a fresh biometric/passcode unlock
(`ApprovalDecisionAuth` in SecurityKit, backed by `BiometricGate`); the gate
runs *before* the decision is persisted or forwarded. Scope, stated precisely:

- **Gated:** the in-app inbox cards (`InboxViewModel` / `LiveInboxViewModel.decide`),
  notification-action routing, and the `ApprovalRelay.enqueue` entry point that
  serves Live Activity / Dynamic Island buttons, Siri/Shortcuts
  (`CommandGateway`) and the cold-launch action drain. Live Activity buttons
  are widget intents, which `UNNotificationActionOptions.authenticationRequired`
  does **not** cover — hence the explicit gate.
- **Unknown risk fails closed:** a decision for an approval with no local row
  (so no tier to read) requires the unlock.
- **Not gated (by design):** low/medium-risk decisions — the same tier split as
  the daemon's `PermitsNoClientGrace`; prompting on every routine approval
  would defeat the product's core loop. Notification actions still require an
  unlocked device via `authenticationRequired`.
- **Documented exception — Apple Watch:** watch decisions arrive over WCSession
  only from a paired watch that is unlocked and on-wrist; wrist detection + the
  watch passcode are Apple's auth boundary for that surface (trusted enough to
  unlock the paired iPhone itself). No phone-side Face ID prompt is inserted
  for watch taps.
- **Residual (pre-existing, P2):** `BiometricGate` degrades open on devices
  with no passcode/biometry enrolled and on the simulator (see
  `docs/KNOWN_ISSUES.md` §2) — the gate is only as strong as `BiometricGate`
  itself until that fail-closed hardening lands.

---

## 6. Network security

| Channel | Encryption | Notes |
|---------|-----------|-------|
| SSH (to your host) | Per-negotiated cipher (AES-256-GCM, ChaCha20-Poly1305, etc.) | You control the server and cipher policy |
| Push relay → APNs | TLS (Apple's push infrastructure) | Apple delivers the notification |
| iOS app → push relay | HTTPS (TLS 1.3) | Fly.io edge terminates TLS |
| CloudKit sync (optional) | Apple-managed encryption | Governed by Apple security |

- `NSAppTransportSecurity` is set to the default (strict) — all network
  connections require TLS 1.2+.
- The push relay uses `force_https = true` at the Fly.io edge — HTTP requests
  are rejected.

---

## 7. Offline behavior

- **Notifications cannot be delivered** when the phone is offline (no network
  connectivity). The agent on the host waits for a configurable timeout, then
  either retries or proceeds with a default policy (configurable in
  `policy.yaml`).
- **Session history remains viewable** offline — the encrypted local database
  is always accessible on-device.
- **SSH connections** that drop due to network change are handled by the SSH
  library's reconnection logic. No user data is lost.

---

## 8. Key rotation

- **SSH keys:** Rotated independently by the user on their host. Lancer
  stores whatever private key the user imports.
- **X25519 pairing keys:** Pairing with a fresh code generates fresh X25519
  keys on both sides. Old keys are discarded from the Keychain.
- **Session keys** are derived fresh each session (HKDF with a new epoch
  nonce). Past session keys cannot be recovered from Keychain material.

---

## 9. Self-host relay option

Users who prefer not to use Lancer's default relay can self-host:

1. Clone the push backend repository.
2. Deploy to Fly.io (or any Docker-compatible host) using the provided
   Dockerfile.
3. Set the environment variable in the iOS app under Settings →
   Advanced → Relay URL.

All encryption is unchanged — the self-hosted relay still sees only opaque
ciphertext. The benefit is network-level privacy: the relay operator's TLS
termination and HTTP logs are under your control.

---

## 10. Threat model summary

| Threat | Mitigation |
|--------|-----------|
| Attacker guesses/observes the pairing code | No SSH credentials in the code; relay key-pinning rejects a different key claiming an already-pinned role; per-IP rate limiting bounds brute-force guessing; unconfirmed codes expire after 10 minutes (§2.2) |
| Attacker MiTM SSH connection | SSH key authentication; X25519 key bindings verified out-of-band |
| Relay is compromised | Relay sees only ciphertext — key material stays on device and host |
| Phone is lost or stolen | Face ID / device passcode gate Keychain access; `whenUnlockedThisDeviceOnly` prevents iCloud sync |
| Host is compromised | Lancer cannot prevent this — attack is outside the threat model; user is responsible for host security |
| Malicious push from relay | Payloads require valid ChaCha20-Poly1305 decryption with session key; relay cannot forge valid payloads |
| Traffic analysis | Relay sees routing IDs and timing — metadata is not encrypted; self-host relay to reduce exposure |

---

## 11. Assumptions and caveats

- **You trust your SSH host.** Lancer protects the transport and relay
  channels, but the host running your agents has full access to your code and
  data.
- **You are responsible for your SSH key security.** If an attacker obtains
  your SSH private key, they can connect to your host directly.
- **Notifications are best-effort.** Push notifications from the relay are
  delivered by Apple's APNs — Lancer cannot guarantee delivery timing.
- **Export compliance.** The App declares `ITSAppUsesNonExemptEncryption:
  false` — the encryption used (SSH protocol, Apple CryptoKit, CommonCrypto)
  is exempt from U.S. export reporting requirements.

---

## 12. Responsible disclosure

If you discover a security vulnerability in Lancer, lancerd, or the push
relay, please report it privately:

**[security@conduit.dev — placeholder]**

We will acknowledge receipt within 72 hours and work toward a fix before
public disclosure. We do not currently operate a bounty program.

---

## Sources

- Apple CryptoKit documentation: <https://developer.apple.com/documentation/cryptokit>
- Apple Keychain Services: <https://developer.apple.com/documentation/security/keychain_services>
- IETF RFC 7748 (Elliptic Curves for Security — X25519):
  <https://datatracker.ietf.org/doc/html/rfc7748>
- IETF RFC 8439 (ChaCha20-Poly1305):
  <https://datatracker.ietf.org/doc/html/rfc8439>
- IETF RFC 5869 (HKDF):
  <https://datatracker.ietf.org/doc/html/rfc5869>
- Apple ITSAppUsesNonExemptEncryption guidance:
  <https://developer.apple.com/documentation/security/export-compliance/self-classifying-a-build>
