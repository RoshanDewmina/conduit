# Security Architecture — Conduit

**Last updated:** {{DATE}}

**Audience:** Security researchers, system administrators, and technically
sophisticated users evaluating Conduit's threat model.

---

## 1. Overview

Conduit is an iOS approval-cockpit for AI coding agents (Claude Code, Codex,
opencode) that run on the user's own computer or server. The security model
relies on three principles:

1. **No cloud escrow.** SSH keys and pairing secrets live on your devices.
   Conduit operates no infrastructure that can decrypt your agent traffic.
2. **Defense in depth.** On-device Keychain + SSH transport encryption +
   optional end-to-end encryption through the push relay.
3. **User sovereignty.** You choose which relay (Conduit's default or
   self-hosted), which hosts to pair with, and when to approve.

---

## 2. Pairing (device-to-host)

### 2.1 The pairing flow

```
┌──────────────────┐                ┌─────────────────────┐
│   iOS Device     │                │  Mac / Linux Host   │
│                  │                │                     │
│  1. Scan QR code │◄─── QR ────── │  2. conduitd pair   │
│                  │    (contains  │     generates QR     │
│  3. Parse QR     │     host +    │     containing:      │
│     extract      │     key info) │     - host address   │
│     host info    │                │     - X25519 pubkey  │
│     + pubkey     │                │                     │
│                  │                │                     │
│  4. Generate     │                │                     │
│     X25519 key   │                │                     │
│     pair         │                │                     │
│                  │                │                     │
│  5. Compute      │◄─── SSH ───── │  6. conduitd         │
│     shared       │    (encrypted │     receives client  │
│     secret via   │     transport)│     pubkey, computes │
│     ECDH         │                │     shared secret    │
└──────────────────┘                └─────────────────────┘
```

Steps:

1. The user runs `conduitd pair` on their host. The daemon generates an
   X25519 key pair and displays a QR code containing the host address,
   the X25519 public key, and a one-time nonce.
2. The user scans the QR code with the iOS app (camera permission required).
3. The iOS app generates its own X25519 key pair.
4. Both sides compute the shared secret using X25519 ECDH (Elliptic Curve
   Diffie-Hellman).
5. The shared secret is used to derive a session key via HKDF (SHA-256).
6. The X25519 private key is stored in the iOS Keychain with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
   `kSecAttrSynchronizable: false` — it never leaves the device.

### 2.2 Security properties

- **QR code is single-use.** Once scanned, `conduitd` invalidates the
  pairing nonce. An intercepted QR code cannot be replayed.
- **The QR does not contain SSH credentials.** It only contains the host's
  X25519 public key and addressing info. A compromised QR code reveals no
  SSH secrets.
- **The SSH connection is authenticated separately** using the user's own SSH
  keys. Conduit never sends SSH private keys over the network.
- **MITM resistance:** The QR code is displayed on the host's screen and
  scanned in person (or via a trusted video call). A network attacker
  intercepting the later SSH connection cannot forge the X25519 key exchange
  because the host's public key was communicated out-of-band via the QR code.

---

## 3. Session keys

After pairing, both sides derive session keys:

```
shared_secret = X25519(ios_private, host_public)
                = X25519(host_private, ios_public)

session_key = HKDF-SHA256(
    ikm:  shared_secret,
    salt: pairing_nonce || epoch,
    info: "conduit-v1-session-key",
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
negotiated cipher). The SSH tunnel is the sole transport — Conduit's relay
is not involved.

### 4.2 Push relay path (end-to-end encrypted)

When the phone is offline or on a different network, notifications can be
delivered via Conduit's push relay. The payload is encrypted **before** it
leaves either endpoint:

```
Encryption (iOS → Host decision):
  1. Generate random 12-byte nonce
  2. ciphertext = ChaCha20-Poly1305_Encrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "conduit-relay-v1",
       plaintext: decision_bytes
     )
  3. Transmit: nonce || ciphertext || tag

Decryption (Host receives):
  1. Parse nonce, ciphertext, tag
  2. plaintext = ChaCha20-Poly1305_Decrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "conduit-relay-v1",
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
- Any identifying user information (Conduit has no account system)
- IP addresses beyond standard HTTP access logs (retained 14 days)

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

- **SSH keys:** Rotated independently by the user on their host. Conduit
  stores whatever private key the user imports.
- **X25519 pairing keys:** A new QR pairing generates fresh X25519 keys on
  both sides. Old keys are discarded from the Keychain.
- **Session keys** are derived fresh each session (HKDF with a new epoch
  nonce). Past session keys cannot be recovered from Keychain material.

---

## 9. Self-host relay option

Users who prefer not to use Conduit's default relay can self-host:

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
| Attacker steals QR code | Single-use nonce; no SSH credentials in QR |
| Attacker MiTM SSH connection | SSH key authentication; X25519 key bindings verified out-of-band |
| Relay is compromised | Relay sees only ciphertext — key material stays on device and host |
| Phone is lost or stolen | Face ID / device passcode gate Keychain access; `whenUnlockedThisDeviceOnly` prevents iCloud sync |
| Host is compromised | Conduit cannot prevent this — attack is outside the threat model; user is responsible for host security |
| Malicious push from relay | Payloads require valid ChaCha20-Poly1305 decryption with session key; relay cannot forge valid payloads |
| Traffic analysis | Relay sees routing IDs and timing — metadata is not encrypted; self-host relay to reduce exposure |

---

## 11. Assumptions and caveats

- **You trust your SSH host.** Conduit protects the transport and relay
  channels, but the host running your agents has full access to your code and
  data.
- **You are responsible for your SSH key security.** If an attacker obtains
  your SSH private key, they can connect to your host directly.
- **Notifications are best-effort.** Push notifications from the relay are
  delivered by Apple's APNs — Conduit cannot guarantee delivery timing.
- **Export compliance.** The App declares `ITSAppUsesNonExemptEncryption:
  false` — the encryption used (SSH protocol, Apple CryptoKit, CommonCrypto)
  is exempt from U.S. export reporting requirements.

---

## 12. Responsible disclosure

If you discover a security vulnerability in Conduit, conduitd, or the push
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
