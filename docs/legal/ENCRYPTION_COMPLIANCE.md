# Encryption Export Compliance — Conduit

## ITSAppUsesNonExemptEncryption

**Current setting:** `false`

**Conduit/Info.plist:**
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

This is correct. Conduit qualifies for the mass-market encryption exemption (ERN) under EAR Category 5 Part 2 (ENC).

## Rationale

Conduit uses only encryption that qualifies for exemption:

| Cryptography used | Where | Exemption basis |
|---|---|---|
| **TLS 1.2/1.3** | All network connections (WebSocket relay, push-backend, SFTP, SSH transport) | Standard, publicly available protocol — mass-market exemption |
| **X25519 ECDH + ChaCha20-Poly1305** | End-to-end encryption of the approval relay | Publicly available algorithms (RFC 7748, RFC 8439). Ephemeral per-session keys. Not a primary app feature. |
| **Apple CryptoKit / CommonCrypto** | Keychain operations (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) | Platform feature — covered by Apple's existing exemptions |
| **SwiftNIO / Citadel (SSH)** | SSH transport layer | Standard protocol using platform/NIO crypto |

### Why `false` is justified

1. The app does **not** implement a custom cryptosystem for file or data-at-rest encryption.
2. Encryption is **not a primary feature** — the app is a terminal/approval client.
3. No encryption function is provided that could be used by third parties as a general-purpose security product.
4. All algorithms are publicly available standards (TLS, X25519, ChaCha20-Poly1305).
5. No proprietary or closed encryption algorithm is used.
6. The encryption is used solely for authentication (pairing channel) and confidentiality of relayed metadata between the user's own daemon and phone.

## France Declaration Note

If you distribute through the French App Store, Apple may require a declaration to the
French Agency for Information Systems Security (ANSSI). In practice, apps using only
TLS + platform crypto with `ITSAppUsesNonExemptEncryption = false` are routinely
approved without additional documentation.

**If Apple requests a classification:** submit a CCATS (commodity classification)
self-assessment using the standard "mass market" questionnaire. The CCATS process
is documented at:
- https://developer.apple.com/documentation/security/export-compliance-for-apps-with-encryption
- https://www.bis.doc.gov/index.php/policy-guidance/encryption

## Pre-Submission Verification

Before final submission:

- [ ] Confirm `Conduit/Info.plist` contains `<key>ITSAppUsesNonExemptEncryption</key><false/>`
- [ ] Verify the app does not load any custom crypto framework or call deprecated crypto APIs
- [ ] Verify Sentry crash reporter is never initialized (DSN is empty) — no crash data collected
- [ ] Review [current Apple export compliance docs](https://developer.apple.com/documentation/security/export-compliance-for-apps-with-encryption) for any policy changes
