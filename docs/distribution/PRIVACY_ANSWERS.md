# App Privacy ("nutrition label") answers — draft

Status: **DRAFT for owner review**, based on reading the codebase concepts as of
branch `codex/ios27-shell-workspace`. This is not a legal privacy policy and is not
a substitute for actually walking the App Store Connect App Privacy questionnaire
— it's a working inventory to make that questionnaire fast and accurate. Anything
marked **VERIFY** means the code suggests a behavior but this pass did not
confirm it precisely enough to answer ASC's questionnaire with confidence — the
owner (or a follow-up code read) should confirm before submitting.

No secret values are included anywhere in this document.

---

## Data types inventory

### 1. Device push token (APNs)

- **What:** the device's APNs push token, registered so the backend can send
  approval/run-complete notifications.
- **Code:** `Conduit/ConduitApp.swift` (`didRegisterForRemoteNotificationsWithDeviceToken`)
  → `NotificationsKit/Notifications.swift` `registerDeviceToken(_:sessionID:backendURL:)`.
- **Collected:** Yes.
- **Linked to identity:** Linked to a `sessionId` (a device/session identifier, not
  a real-world name/email) on the backend, to route notifications to the right
  device. Not linked to a user account unless the user also signs in with a
  Conduit account (see #4) — **VERIFY** whether the backend ever joins the push
  token to the Supabase account row; the device-binding flow in
  `docs/SUPABASE_ACCOUNT_SETUP.md` describes daemon binding via hashed device
  credentials, not push-token-to-account linkage explicitly.
- **Used for tracking:** No. Not shared with third parties or used across apps;
  used solely to deliver this app's own notifications.
- **Purpose:** App functionality (push notifications for approvals).

### 2. Pairing / relay identifiers (session ID, device public key, pairing code)

- **What:** the X25519 public key generated for the relay pairing handshake, the
  6-character pairing code, and the derived session identifier used to address
  this device/daemon pair on the relay.
- **Code:** `daemon/push-backend/PAIRING_PROTOCOL.md` (wire contract);
  `Packages/ConduitKit/Sources/SSHTransport/E2ERelayClient.swift`.
- **Collected:** Yes (transiently, by the relay, to route encrypted frames between
  the paired phone and daemon).
- **Linked to identity:** No — these are device-generated keys/codes, not tied to
  a real name or email. The relay is documented as "blind": it forwards opaque
  ciphertext and cannot read message contents (`daemon/push-backend/websocket_relay_test.go`,
  cited in the pairing protocol doc).
- **Used for tracking:** No.
- **Purpose:** App functionality (establishing the encrypted control channel
  between phone and host daemon). Data is described as ephemeral/in-memory on a
  self-hosted relay (`SELF_HOST.md`) — **VERIFY** retention behavior on whatever
  relay instance is actually used for the shipped build (self-hosted vs. the
  hosted default relay), since retention may differ by deployment.

### 3. SSH credentials and host keys (on-device only)

- **What:** SSH private keys, host fingerprints/known-hosts entries, and
  connection passwords/passphrases for hosts the user adds.
- **Code:** `Packages/ConduitKit/Sources/SecurityKit/Keychain.swift`,
  `KeyStore.swift`, `HostKeyStore.swift`; surfaced in `KeysFeature/KeysView.swift`,
  `KeyImportView.swift`, `WorkspacesFeature/AddHostView.swift`.
- **Collected:** Stored **only on-device**, in the iOS Keychain (not transmitted to
  Conduit's own servers; only ever used to open the user's own SSH connection to
  their own host).
- **Linked to identity:** N/A — never leaves the device under Conduit's control.
- **Used for tracking:** No.
- **Purpose:** App functionality only. For the App Privacy questionnaire this is
  typically answered as **"data not collected"** by the developer (it never
  reaches Conduit's servers), but **VERIFY** this framing is correct under Apple's
  current definitions — Keychain-only, on-device, app-functionality data
  sometimes still needs to be disclosed depending on how strictly Apple's
  reviewers interpret "collection." Treat this as the single most important item
  to confirm before submitting, since SSH key handling is the most sensitive data
  type in the app.

### 4. Conduit account: email (optional standard sign-in)

- **What:** email address + password (Supabase Auth), used for the optional
  "Conduit account" mode (as opposed to the account-free self-hosted pairing mode).
- **Code:** `Packages/ConduitKit/Sources/AccountKit/AccountClient.swift`;
  `docs/SUPABASE_ACCOUNT_SETUP.md`.
- **Collected:** Yes, but **only if the user opts into standard sign-in** — the
  self-host/offline pairing path explicitly does not contact Supabase
  (`SUPABASE_ACCOUNT_SETUP.md`: "does not contact Supabase and intentionally has
  no recovery, device list, or hosted billing").
- **Linked to identity:** Yes (email is directly tied to the account).
- **Used for tracking:** No (used for authentication, not advertising/tracking).
- **Purpose:** App functionality (account sign-in, billing identity, daemon device
  list/recovery). Password itself: backend stores hashes, never the raw password
  or raw device credential, per `SUPABASE_ACCOUNT_SETUP.md` §"Daemon bind
  contract."
- **VERIFY:** confirm with the owner whether email is also used for any marketing
  communication (e.g. product update emails) — if so it additionally needs to be
  disclosed as "used for marketing," which is a different ASC answer than pure
  account functionality. Nothing in the code suggests marketing use, but this
  pass did not check Supabase Auth/SMTP configuration for that.

### 5. Purchase / billing identifiers

- **What:** `appAccountToken`, `clientToken`, and an optional Stripe customer ID
  (`stripeCustomerIDKey`), used to tie an Apple IAP transaction or a Stripe
  subscription to this installation.
- **Code:** `Packages/ConduitKit/Sources/SettingsFeature/PurchaseManager.swift`.
- **Collected:** Yes, for users who purchase Conduit Pro (Apple IAP) or subscribe
  to the separate Stripe-billed "Conduit Cloud" tier.
- **Linked to identity:** Apple IAP receipts/tokens are handled by StoreKit per
  Apple's own privacy rules (Apple is the data controller for the transaction
  itself). The Stripe customer ID is linked to whatever identity Stripe Checkout
  collected (email at minimum) — **VERIFY** exactly what Stripe collects in this
  flow's checkout configuration before answering the "purchases" category in ASC,
  since Stripe-side data collection is outside this codebase's direct view.
- **Used for tracking:** No.
- **Purpose:** App functionality (unlocking purchased features), and "Purchases"
  category in the ASC questionnaire (transaction history).

### 6. Crash/diagnostic data (Sentry) — currently disabled

- **What:** Sentry crash/error reporting SDK is integrated but the DSN is an empty
  string in `Conduit/ConduitApp.swift` (`private let sentryDSN = ""`), and
  `SentrySDK.start` is gated behind `guard !sentryDSN.isEmpty else { return }` — so
  **no crash data is currently sent anywhere** in the build as committed.
- **Collected:** No, in the current build. **VERIFY before submission** that the
  DSN is still empty in whatever build is actually archived for the App Store —
  if the owner sets a real DSN before shipping (as the `project.yml` comment
  referencing "See ARCHITECTURE.md §19" implies is the eventual plan), the ASC
  privacy answers must be updated to disclose Crash Data / Diagnostics (typically
  "linked to you: no" / "used for tracking: no" for a self-hosted Sentry, but
  confirm Sentry's own data handling for whatever Sentry deployment is used).
- **Purpose if enabled:** App functionality (crash diagnostics), not tracking.

### 7. No advertising identifier / tracking SDK found

- A repo-wide search found no `AppTrackingTransparency`, `ATTrackingManager`,
  IDFA, or third-party ad/analytics SDK usage. **Answer:** the app does not appear
  to track users across apps/websites for advertising, and the "Data Used to
  Track You" ASC section can likely be answered "No data collected for tracking
  purposes." VERIFY this holds for the final shipped build (e.g. confirm the
  Sentry SDK, if enabled later, isn't configured with any IP-based tracking
  add-ons beyond default crash reporting).

---

## Summary table (draft ASC answers)

| Data type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Device push token | Yes | Linked (session, not real identity) | No | App functionality |
| Pairing/relay identifiers | Yes (transient) | Not linked | No | App functionality |
| SSH credentials/host keys | On-device only — **VERIFY disclosure framing** | N/A | No | App functionality |
| Account email (optional) | Yes, opt-in | Linked | No | App functionality |
| Purchase/billing identifiers | Yes | Linked (Apple/Stripe side) — **VERIFY Stripe scope** | No | App functionality / Purchases |
| Crash data (Sentry) | No (disabled in current build) — **VERIFY at archive time** | N/A | No | App functionality, if enabled |
| Advertising/tracking ID | Not found in code | N/A | No | N/A |

---

## In-app purchase note

Product `dev.conduit.mobile.pro` is a **non-consumable** one-time purchase (not a
subscription), per `Conduit/Conduit.storekit`. The "Purchases" data category
applies; no recurring billing data beyond the original transaction needs to be
disclosed for this specific product. The separate Stripe "Conduit Cloud"
subscription is billed outside Apple's IAP system — **VERIFY** whether Apple's
current External Purchase / "reader app" disclosure rules require any additional
privacy-label or listing language for that path at submission time.

---

## Top items the owner should confirm before submitting (also called out in the
final report to the user)

1. Whether on-device-only Keychain data (SSH keys, host credentials) needs an
   explicit ASC disclosure under Apple's current "data collection" definition, or
   can correctly be marked not collected.
2. Whether the account email is ever used for marketing/product emails (changes
   the ASC answer from pure "App Functionality" to also "Marketing").
3. Whether Sentry will have a real DSN by the time of the actual App Store
   archive — if so, Crash Data/Diagnostics must be added to the label before
   submission, not left as "not collected."
