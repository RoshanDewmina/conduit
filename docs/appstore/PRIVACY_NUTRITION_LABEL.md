# App Privacy nutrition label — Lancer (`dev.lancer.mobile`)

**Purpose:** exact App Store Connect → App Privacy answers, derived from what
the shipping app actually collects/transmits, each backed by a code-evidence
pointer read in this session. Supersedes `docs/legal/APP_PRIVACY_LABELS.md`
and `docs/distribution/PRIVACY_ANSWERS.md` where they disagree — those
predate the current relay-pairing UI and the CloudKit conversation mirror;
this doc is the one to paste from.

**Tracking status: No tracking.** No analytics/ads/attribution SDK is linked.
Verified by grepping the app + LancerKit sources for Firebase, Google
Analytics, Mixpanel, Amplitude, Segment, AppsFlyer, Adjust, Facebook SDK, and
Crashlytics — zero hits (`grep -rniE "firebase|google.?analytics|mixpanel|
amplitude|segment\.io|appsflyer|adjust\.com|facebook.?sdk|crashlytics"
Packages/ Lancer/`, this session).

---

## Data types — App Store Connect table

| Category | Data type | Collected? | Linked to identity? | Used for tracking? | Purpose | Evidence |
|---|---|---|---|---|---|---|
| Contact Info | Email, phone, address | No | — | — | — | No account system for offline pairing; Supabase email sign-in is opt-in standard-account path, ships with empty keys by default (`project.yml:88-89` `LANCER_SUPABASE_URL`/`LANCER_SUPABASE_PUBLISHABLE_KEY` build settings) — if the owner enables standard accounts, revisit this row before submission (see note 1). |
| Health & Fitness | Any | No | — | — | — | Not applicable; no HealthKit import anywhere in the target. |
| Financial Info | Payment info | No | — | — | — | StoreKit 2 processes the Lancer Pro IAP; Apple holds payment data, Lancer never receives card/payment details (`Lancer/Lancer.storekit`). |
| Location | Precise / coarse | No | — | — | — | No `CLLocationManager` usage found in `Lancer/` or `Packages/LancerKit/Sources/`. |
| Sensitive Info | Any | No | — | — | — | — |
| Contacts | Any | No | — | — | — | No Contacts framework import. |
| User Content | Photos/videos | No | — | — | — | `AttachmentLocalMediaStore.swift`/`AttachmentMediaView.swift` read photo/video attachments the user explicitly picks for a chat prompt; the file is sent to the user's own host over the E2E relay, never to Lancer's servers — same "not collected by Lancer" logic Apple applies to on-device/on-transport-only content. |
| User Content | Audio data | No | — | — | — | `NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription` are declared in `Lancer/Info.plist` (via `project.yml:62-63`) for a **voice-dictation feature not yet shipped** — no live microphone capture code found in `Packages/LancerKit/Sources/AppFeature/`. If the feature ships, update this row. |
| User Content | Other (chat/command text) | No | — | — | — | Chat/command text and AI conversation transcripts travel over the E2E relay (ciphertext only reaches Lancer's `push-backend`) to the user's own `lancerd` host, and mirror to the user's own private CloudKit database (`LancerConversations` zone) — never to Lancer-operated storage that Lancer can read. See §11.2 of `ARCHITECTURE.md` and evidence below. |
| Search/Browsing History | Any | No | — | — | — | — |
| Diagnostics | Crash data | No | — | — | — | Sentry is linked but `sentryDSN = ""` in `Lancer/LancerApp.swift:26`; `SentrySDK.start` is gated behind `guard !sentryDSN.isEmpty else { return }` (`LancerApp.swift:50`) — never initialized, no crash data leaves the device. **Re-check this row if a real DSN is ever set before a future submission.** |
| Diagnostics | Performance data | No | — | — | — | Same gate as above — no APM/perf SDK runs. |
| Identifiers / Device ID | APNs push token | **Yes** | No | No | App Functionality | The app registers for remote notifications and forwards the APNs device token to Lancer's push relay (`push-backend`) solely to route approval/Live-Activity pushes (`ARCHITECTURE.md` §0.1 "Push-driven Live Activity"; `docs/legal/SECURITY_ARCHITECTURE.md` §5 table: "APNs device token — Forwarded to push relay (via HTTPS)"). Not tied to any Lancer account (offline pairing has none); not used for tracking, advertising, or cross-app correlation. |
| Purchase History | Any | No | — | — | — | StoreKit 2 validates the Lancer Pro receipt on-device/via Apple; Lancer's own servers never see purchase history. |
| Usage Data | Product interaction / advertising data | No | — | — | — | No analytics SDK (see tracking-status grep above). |

---

## CloudKit — private, per-user database, not Lancer-operated

The one sync path that could look like "collection" on a casual read is
**not** collection by Lancer: `ConversationSyncEngine`
(`Packages/LancerKit/Sources/SyncKit/ConversationSyncEngine.swift`) and
`ConversationCloudRecords.swift` mirror `Conversation` and
`ConversationTurnChunk` records into the **user's own private CloudKit
database** (`CKContainer` private DB, custom zone `LancerConversations`,
`CKCurrentUserDefaultName` owner — `ConversationCloudRecords.swift:47`).
Apple, not Lancer, operates that store, and Lancer's infrastructure never
reads it. Apple's own guidance is that data a user's *own* iCloud account
holds, which the developer's servers cannot access, is not reportable as
"collected by the developer" in the nutrition label — declare it only if
Apple's current questionnaire explicitly asks about CloudKit private-DB
usage (recheck the live ASC questionnaire at submission time; this doc does
not assume the questionnaire's exact wording won't change).

## Third-party SDKs that touch the network

| SDK | Role | Collects its own data? | Evidence |
|---|---|---|---|
| SwiftNIO + Citadel (SSH transport) | SSH client library | No | Transport library only; no telemetry callback found. |
| Sentry (linked, empty DSN) | Crash reporting | No — never initialized | `Lancer/LancerApp.swift:26,50-53`. |
| StoreKit 2 | In-app purchase | Apple handles all payment data | `Lancer/Lancer.storekit`. |
| CloudKit | User's own iCloud sync | Apple-managed, user's own container | `SyncKit/ConversationSyncEngine.swift`, `SyncKit/CloudSync.swift`. |

## Notes

1. **Standard-account email sign-in.** `project.yml:85-89` ships
   `LANCER_SUPABASE_URL`/`LANCER_SUPABASE_PUBLISHABLE_KEY` **empty by
   default** ("Empty build-setting values leave standard sign-in unavailable
   (offline pairing still works)"). If the shipped build injects real
   Supabase values (enabling optional account sign-in with email/password),
   add an **Email Address — Yes, linked to identity, not used for tracking,
   App Functionality** row before submission, and confirm against
   `ARCHITECTURE.md` §0.1 "Standard accounts and daemon binding" whether that
   path is wired into the build being archived.
2. **Camera permission is currently dead code, not a data-collection
   surface.** `project.yml:60` declares `NSCameraUsageDescription` ("scan the
   pairing QR code..."), but the actual pairing UI
   (`Packages/LancerKit/Sources/AppFeature/Settings/RelayPairingSheet.swift`)
   is a 6-digit text-entry field, not a camera scanner —
   `docs/legal/SECURITY_ARCHITECTURE.md` §2.1 confirms pairing is "code-only
   — the app no longer scans a QR code." No `AVCaptureSession`, `CodeScanner`,
   or `VisionKit` scanner symbol exists anywhere in
   `Packages/LancerKit/Sources/` (grepped this session). Camera/photo-picker
   code that does exist (`AttachmentLocalMediaStore.swift`) is for attaching
   existing photos/video to a chat prompt, not live capture — verify with
   `grep -rn "AVCaptureSession\|UIImagePickerController.*camera" Lancer/
   Packages/` before submission and either wire a real camera flow or drop
   the stale `NSCameraUsageDescription` string (a declared-but-unused
   permission string is itself a review-risk flag, see
   `REVIEWER_NOTES.md`).

## Verification checklist

- [ ] Device ID (APNs token) → Yes → Not linked → Not tracking → App Functionality
- [ ] All rows above → No, unless standard-account Supabase sign-in ships live (note 1)
- [ ] No tracking declared; ATT prompt not shown
- [ ] `Lancer/PrivacyInfo.xcprivacy` matches these declarations (already present: `NSPrivacyTracking=false`, one `NSPrivacyCollectedDataTypeDeviceID` / App Functionality entry, `C617.1` file-timestamp + `CA92.1` UserDefaults required-reason API entries)
- [ ] Privacy Policy URL live and matches these declarations (no live URL confirmed in this repo as of 2026-07-17 — `docs/distribution/APP_STORE_CONNECT_METADATA.md` flags this as owner-gated)
