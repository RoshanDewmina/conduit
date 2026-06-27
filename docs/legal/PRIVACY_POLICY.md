# Privacy Policy — Lancer

**Last updated:** {{DATE}}

---

## 1. Introduction

Lancer (the "App") is an iOS application that lets you approve, deny, and review
actions initiated by AI coding agents (Claude Code, Codex, opencode) running on
your own computer or server. The App is published by **[Legal entity name —
_placeholder: insert company/individual name here_]**.

This Privacy Policy explains what data the App collects, how it is used, and
your rights over your data. It applies to all users of the App worldwide.

**Lancer does not use analytics SDKs, advertising networks, or third-party
tracking of any kind.** We do not sell your data.

---

## 2. Data we collect

### 2.1 Data stored exclusively on your device

The following data never leaves your iPhone or iPad unless you explicitly
transmit it (see §3):

| Data | Where stored | Purpose |
|------|-------------|---------|
| SSH private keys (Ed25519, ECDSA, RSA) | iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) | Authentication to your remote hosts |
| Host configurations (hostname, port, username) | Local encrypted database | Connecting to your hosts |
| X25519 pairing key material | iOS Keychain | End-to-end encryption of relayed approval blobs |
| Session history / block transcripts | Local encrypted SQLite database | Offline review of past agent activity |
| App preferences | `UserDefaults` (local) | UI state and user settings |

### 2.2 Data transmitted to Apple

- **APNs device token.** When you opt in to push notifications for remote
  approval alerts, the App registers a device token with Apple Push
  Notification service (APNs). This token is a random identifier that Apple
  assigns to your device — Lancer does not read or store it as raw text; we
  forward it to our push relay so Apple can deliver notifications to your
  device.

- **CloudKit sync (optional).** If you enable iCloud sync, your host list and
  snippets are stored in your personal Apple CloudKit container. Lancer does
  not have access to your CloudKit data — it is governed by Apple's privacy
  policy.

### 2.3 Data transmitted to Lancer's push relay

When you enable remote approval alerts, your app sends the following to
Lancer's push notification relay (hosted on Fly.io):

- **APNs device token** (forwarded from Apple — see §2.2)
- **An app-generated session identifier** (a UUID scoped to the pairing
  between your phone and a specific host)

The relay does **not** receive:
- Your SSH keys, hostnames, usernames, or passwords
- Your command output, source code, or file contents
- Your IP address beyond standard HTTP server logs (see §3.2)

### 2.4 Data transmitted through the relay (end-to-end encrypted)

Approval requests and your decisions (approve / deny / edit) are sent as
encrypted blobs through the relay. The encryption uses X25519 ECDH key
agreement with ChaCha20-Poly1305 symmetric encryption. The relay **cannot
read** the contents of these blobs — it sees only opaque ciphertext and
routing metadata (destination host identifier).

### 2.5 Purchase data (if applicable)

If you purchase Lancer Pro (a one-time in-app purchase) or a future
subscription, Apple processes the transaction. Lancer receives only a
receipt token from StoreKit that confirms the purchase — we never see your
payment card details.

---

## 3. How we use data

### 3.1 Primary purposes

| Data | Purpose |
|------|---------|
| SSH keys | Authenticate to your remote host (only sent over the SSH connection you initiate) |
| APNs token | Deliver push notifications when an agent needs your approval |
| Session identifier | Route notifications to the correct paired host |
| X25519 keys | Establish end-to-end encrypted channel between your device and your host |
| Purchase receipt | Unlock Pro features |

### 3.2 Standard server logs

Our push relay infrastructure (Fly.io) records standard HTTP access logs that
may include the originating IP address, request timestamp, and User-Agent
string. These logs are retained for **14 days** for operational troubleshooting
and then deleted. We do not correlate these logs with any other data.

---

## 4. Data sharing

We do **not** share your personal data with third parties, except:

1. **Apple** — for push notification delivery (APNs) and optional CloudKit
   sync, governed by Apple's privacy policy.
2. **Fly.io** — as our hosting provider for the push relay. Fly.io processes
   data solely on our instructions and is contractually prohibited from using
   it for any other purpose.
3. **Law enforcement** — only if required by applicable law and accompanied by
   valid legal process. We will notify you unless legally prohibited.

We do **not** share data with analytics providers, advertising networks, data
brokers, or AI model providers.

---

## 5. Data retention and deletion

### 5.1 Data on your device

All SSH keys, host configurations, session history, and preferences are stored
locally. Deleting the App from your device removes all local data.

### 5.2 Data on Lancer's push relay

APNs device tokens and session identifiers are retained for as long as your
session is registered with the relay. You can unregister at any time from
within the App's settings. After unregistration, tokens are deleted within
**30 days**.

### 5.3 No account = no server-side personal data

Lancer does not operate a user account system. There is no registration,
login, or profile stored on our servers. Consequently, there is no
server-side personal data to delete beyond the push tokens described above.

### 5.4 Requesting deletion

To request deletion of any data held by Lancer's services, contact
**[privacy@conduit.dev — _placeholder: insert support email_]**.
We will respond within 30 days.

---

## 6. Security

- SSH keys and X25519 pairing keys are stored in the iOS Keychain with
  accessibility set to `whenUnlockedThisDeviceOnly` and synchronization
  disabled. They never leave the device except over the SSH connection you
  explicitly initiate.
- Approval relay traffic is end-to-end encrypted (X25519 + ChaCha20-Poly1305)
  so that the relay cannot read the contents.
- Communication with the push relay is over HTTPS (TLS).
- Face ID / Touch ID can be enabled to gate access to stored keys.

**Lancer is not a backup service.** We cannot recover your SSH keys,
host configurations, or session history if you lose your device. Maintain
independent backups of your SSH credentials.

---

## 7. Children

Lancer is not directed at children under 13 and does not knowingly collect
personal information from children. If you believe a child has provided
personal data, contact **[privacy@conduit.dev]**.

---

## 8. Your rights

Depending on your jurisdiction, you may have rights under GDPR (EU/EEA),
CCPA (California), or similar laws:

- **Right to know** what data is collected and how it is used (this policy)
- **Right to access** your data
- **Right to deletion** (see §5.4)
- **Right to withdraw consent** for push notifications (via iOS Settings)
- **Right to non-discrimination** for exercising your rights

To exercise any of these rights, contact **[privacy@conduit.dev]**.

---

## 9. Changes to this policy

We may update this Privacy Policy to reflect changes in our practices or
legal requirements. Material changes will be notified through the App or at
the privacy URL listed in App Store Connect.

---

## 10. Contact

| Role | Contact |
|------|---------|
| Privacy inquiries | **[privacy@conduit.dev — placeholder]** |
| Legal inquiries | **[legal@conduit.dev — placeholder]** |
| Responsible disclosure | **[security@conduit.dev — placeholder]** |

---

## Sources

- Apple App Store Review Guidelines §5.1.1 (Privacy):
  <https://developer.apple.com/app-store/review/guidelines/>
- Apple App Privacy Details:
  <https://developer.apple.com/app-store/app-privacy-details/>
- Apple SDK minimum requirements (April 28, 2026):
  <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>
- Apple Account Deletion requirement:
  <https://developer.apple.com/support/offering-account-deletion-in-your-app/>
