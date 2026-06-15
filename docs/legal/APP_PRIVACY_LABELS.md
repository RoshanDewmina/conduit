# App Privacy Nutrition Label — App Store Connect Mapping

This document maps Conduit's actual data collection onto Apple's App Privacy
questionnaire in App Store Connect. Use these answers when filling out the
"App Privacy" section for the submission.

---

## Overview

Conduit collects **minimal data** — only what is strictly necessary for
push notification delivery and optional iCloud sync. There is **no tracking**
(no third-party analytics, no ads SDK, no data brokers).

**Tracking status:** No tracking.

---

## Data types — complete table

| # | Data category | Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|---|---|
| 1 | **Contact Info** | Email Address | No | — | — | — |
| 2 | **Contact Info** | Physical Address | No | — | — | — |
| 3 | **Contact Info** | Phone Number | No | — | — | — |
| 4 | **Health & Fitness** | Any | No | — | — | — |
| 5 | **Financial Info** | Payment Info | **No** (see note) | — | — | — |
| 6 | **Financial Info** | Credit Info | No | — | — | — |
| 7 | **Financial Info** | Other Financial Info | No | — | — | — |
| 8 | **Location** | Precise Location | No | — | — | — |
| 9 | **Location** | Coarse Location | No | — | — | — |
| 10 | **Sensitive Info** | Any | No | — | — | — |
| 11 | **Contacts** | Any | No | — | — | — |
| 12 | **User Content** | Emails or Text Messages | No | — | — | — |
| 13 | **User Content** | Photos or Videos | No | — | — | — |
| 14 | **User Content** | Audio Data | No **(1)** | — | — | — |
| 15 | **User Content** | Gameplay Content | No | — | — | — |
| 16 | **User Content** | Customer Support | No | — | — | — |
| 17 | **User Content** | Other User Content | No **(2)** | — | — | — |
| 18 | **Search History** | Any | No | — | — | — |
| 19 | **Browsing History** | Any | No | — | — | — |
| 20 | **Diagnostics** | Crash Data | **No (3)** | — | — | — |
| 21 | **Diagnostics** | Performance Data | **No (3)** | — | — | — |
| 22 | **Diagnostics** | Other Diagnostic Data | No | — | — | — |
| 23 | **Device ID** | Device ID (APNs token) | **Yes** | No | No | App Functionality |
| 24 | **Purchase History** | Any | **No (4)** | — | — | — |
| 25 | **Usage Data** | Product Interaction | No | — | — | — |
| 26 | **Usage Data** | Advertising Data | No | — | — | — |
| 27 | **Usage Data** | Other Usage Data | No | — | — | — |
| 28 | **Identifiers** | User ID | No | — | — | — |
| 29 | **Identifiers** | Device ID | **Yes (5)** | No | No | App Functionality |

---

## Notes — explaining each "Yes" and notable "No" answers

### Note 1: Audio Data — No (microphone permission declared)

Conduit declares `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription` in Info.plist **for a planned future
feature** (voice dictation of terminal commands). The feature is not yet
shipped, and no audio data is collected or transmitted at this time.

**App Store Connect answer:** No (audio data is not currently collected). If
the feature ships, update the label to "Yes, linked to identity, not used for
tracking."

### Note 2: Other User Content — No

The App lets you type commands. Command text is sent over SSH to your host
(not to Conduit's servers) and is stored locally on-device in an encrypted
database. Apple's guidelines consider user-supplied text "other user content"
— but Conduit does not transmit this to its own infrastructure. It is
transmitted over SSH (your own connection) and stored locally.

**Safe conservative answer:** No (Conduit does not send user content to its
own servers).

### Note 3: Crash Data / Performance Data — No

Sentry SDK is linked in the binary but the DSN is empty — Sentry is
never initialized and no crash data is transmitted. Conduit has no other
crash-reporting or performance-monitoring SDK.

**App Store Connect answer:** No.

### Note 4: Purchase History — No

Apple's StoreKit processes the Conduit Pro in-app purchase. Conduit receives
only a receipt validation token from Apple (on-device). No purchase history
is sent to Conduit's servers.

**App Store Connect answer:** No.

### Note 5: Device ID — APNs token (Yes)

Conduit registers an APNs device token for push notification delivery. This
is a random, rotatable identifier assigned by Apple. It is forwarded to
Conduit's push relay for the sole purpose of sending you approval
notifications.

- **Linked to user?** No — the token is not associated with a user identity.
  Conduit has no user account system.
- **Used for tracking?** No — it is never used for analytics, advertising, or
  any purpose other than push delivery.
- **Purpose:** App Functionality

**App Store Connect answer:** Yes → Linked to user: No → Used for tracking:
No → Purpose: App Functionality

---

## Data not collected — important to declare

The following data categories are **common in other apps but entirely absent
from Conduit:**

- **Email / Phone / Address** — no account system, no registration form
- **Location** — not collected, not needed
- **Photos / Media** — not collected
- **Contacts** — not accessed
- **Browsing / Search history** — not collected
- **Advertising data** — no ad SDKs
- **Third-party analytics** — none present

---

## Third-party data collection

Conduit integrates **no third-party SDKs that collect data** for their own
purposes. The linked SDKs that touch the network are:

| SDK / Framework | Role | Collects data for itself? |
|-----------------|------|--------------------------|
| SwiftNIO + Citadel (SSH) | SSH client library | No |
| Sentry (linked, empty DSN) | Crash reporting | **Not initialized — no data sent** |
| StoreKit 2 | In-app purchases | Apple handles all payment data |
| CloudKit (optional) | iCloud sync | Apple handles all sync data |

---

## Tracking and App Tracking Transparency

Conduit does **not** use any form of tracking as defined by Apple (no
targeted advertising, no cross-app tracking, no data sharing with data
brokers). **No App Tracking Transparency (ATT) prompt is required or
shown.**

---

## Privacy manifest (`PrivacyInfo.xcprivacy`)

The project already includes a `PrivacyInfo.xcprivacy` file at
`Conduit/PrivacyInfo.xcprivacy` with:

- `NSPrivacyTracking: false`
- `NSPrivacyCollectedDataTypeDeviceID` for `AppFunctionality` (APNs token)
- Required Reason API entries for:
  - File timestamps (`C617.1`) — SFTP browser timestamp display
  - UserDefaults (`CA92.1`) — `@AppStorage` for preferences

---

## Verification checklist

Before submission, confirm the App Store Connect answers match this
document:

- [ ] Device ID → Yes → Not linked → Not tracking → App Functionality
- [ ] All other data types → No
- [ ] No tracking declared (ATT not required)
- [ ] `PrivacyInfo.xcprivacy` matches these declarations
- [ ] Privacy policy URL matches these declarations (no contradictions)

---

## Sources

- Apple App Privacy Details: <https://developer.apple.com/app-store/app-privacy-details/>
- Apple Privacy Nutrition Labels: <https://developer.apple.com/videos/play/wwdc2022/10167/>
- App Store Connect Help — Manage App Privacy:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
