# App Store Submission Checklist — Conduit

## Done (code complete, 98/98 tests pass in 23 suites as of 2026-05-27, BUILD SUCCEEDED)

- [x] **Build** — Xcode 26 / iOS 26 SDK, Swift 6.2 strict concurrency
- [x] **Bundle ID** — `dev.conduit.mobile`
- [x] **Version** — 0.1.0 (build 1) in `project.yml`
- [x] **Face ID usage description** — `NSFaceIDUsageDescription` in Info.plist
- [x] **Background modes** — `remote-notification`, `fetch` in Info.plist
- [x] **Entitlements** — push (`aps-environment`), CloudKit, Keychain in `Conduit.entitlements`
- [x] **PrivacyInfo.xcprivacy** — no tracking; device identifier declared for optional APNs approval alerts
- [x] **Privacy policy link** — `https://conduit.dev/privacy` in BillingView
- [x] **Terms of service link** — `https://conduit.dev/terms` in BillingView
- [x] **StoreKit** — `PurchaseManager` + `Conduit.storekit` config for local testing
- [x] **Restore purchases** button in BillingView
- [x] **US storefront subscription link** — conduit.dev/subscribe (Stripe Checkout Sessions) in BillingView
- [x] **AppIcon asset catalog** — skeleton at `Conduit/Resources/Assets.xcassets/AppIcon.appiconset/`
- [x] **App Transport Security** — `NSAllowsLocalNetworking` for dev server preview
- [x] **Biometric gate** — `LaunchLockView` + `BiometricGate.shared.unlock()` at app root
- [x] **Approval inbox** — `InboxView` with real `ApprovalCard` Allow/Reject buttons (not a stub)
- [x] **Approval flow wired** — `DaemonChannel` → `ApprovalIngest` → `LiveInboxViewModel` → `channel.respond()`
- [x] **NL→command synthesis** — `#` prefix in composer calls `ai.complete()` and fills input
- [x] **Explain block AI** — context menu "Explain with AI" streams from `ai.streamCompletion()`
- [x] **SFTP file browser** — `SFTPFilesView` + `SFTPFilesViewModel` with text preview, fully wired in `SessionShellView`
- [x] **Dev server preview** — `SSHProxyURLSchemeHandler` + `SmartPreviewView` with port detection
- [x] **CloudKit sync** — `SyncEngine` LWW sync for hosts and snippets (CloudKit capability required in Dev portal)
- [x] **Local notifications** — `Notifications.shared` fires on approval pending, reconnect failure, session suspend
- [x] **Notification actions** — Approve/Reject category registered in `UNUserNotificationCenter`

---

## Still needed (manual / designer / backend tasks)

### App icon (REQUIRED — submission will fail without it)
- [x] `AppIcon-1024.png` (1024 × 1024 px, PNG) created at
  `Conduit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
  — programmatically generated dark terminal aesthetic. Replace with designer asset before ship.

### Screenshots (REQUIRED)
- [x] iPhone 6.9" (1320 × 2868 px) — captured:
  - `01-onboarding-6.9.png` — Onboarding welcome screen
  - `02-workspaces-6.9.png` — Workspaces with seeded hosts
  - `03-inbox-6.9.png` — Inbox with HIGH RISK + medium risk approval cards, Allow/Reject buttons ← hero differentiator
  - `03-provisioning-6.9.png` — Cloud provisioning wizard
  - `04-session-empty-6.9.png` — Session tab (no active session)
  - `04-session-live-6.9.png` — Live SSH session to GCP server, block-mode terminal with uptime output ✅
- [x] Replaced empty-session with live block-mode session screenshot
- [ ] iPhone 6.5" (1242 × 2688 px) — optional but recommended

### App Store Connect setup
- [ ] Create the app in App Store Connect (`dev.conduit.mobile`)
- [ ] Add the product `dev.conduit.mobile.pro` as a Non-Consumable IAP at $14.99
- [ ] Enable CloudKit capability in the Dev portal (container `iCloud.dev.conduit.mobile`)
- [ ] Enable Push Notifications capability in the Dev portal
- [ ] Fill in Privacy Nutrition Label (no tracking; declare device identifier for optional push alerts, and subscription data if web billing is enabled)
- [ ] Set age rating to **4+**
- [ ] Write App Store description and keywords

### conduit.dev website (for payment redirect)
- [x] `docs/website/subscribe.html` — Stripe Checkout Sessions page ($9/mo, $79/yr) — deploy to conduit.dev/subscribe
- [x] `docs/website/privacy.html` — Privacy policy — deploy to conduit.dev/privacy
- [x] `docs/website/terms.html` — Terms of service — deploy to conduit.dev/terms
- [x] **DEPLOYED**: Vercel project `conduit-website` created, all 3 HTML files live
  - Preview URL: `conduit-website-roshandewminas-projects.vercel.app`
  - conduit.dev added to project (verified). DNS missing: add A record `conduit.dev → 76.76.21.21` in Route53
- [ ] **DNS**: In AWS Route53, add A record: `conduit.dev` → `76.76.21.21` (Vercel anycast IP)
- [ ] Configure backend env: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_ANNUAL`, `PUBLIC_BASE_URL`, `WEBSITE_BASE_URL`

### APNs remote push (approval alerts when app is killed)
- [x] `daemon/push-backend/main.go` — Go HTTP server for APNs delivery (register token, send push)
- [x] `daemon/push-backend/fly.toml` + `Dockerfile` — ready to deploy on Fly.io
- [x] `Notifications.registerDeviceToken()` method in NotificationsKit wired up
- [ ] Create APNs `.p8` key in Apple Developer portal → download → place at `daemon/push-backend/AuthKey_KEYID.p8`
- [ ] Set env vars: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`, `APNS_BUNDLE_ID`
- [ ] Deploy: `fly launch` in `daemon/push-backend/` (or Railway/Render/Lambda)
- [ ] Wire backend URL into AppRoot so device token is POSTed on launch

### conduitd deployment (for end-to-end approval flow)
- [ ] Deploy conduitd binary to your remote server (`go build -o conduitd ./cmd/conduitd`)
- [ ] Place it in PATH (e.g. `/usr/local/bin/conduitd`) so `conduitd serve` works over SSH
- [ ] Test the golden path: Claude Code hook → conduitd → phone Inbox → Allow/Reject

### Real-host SSH validation
- [ ] Test against a real SSH host (GCP instance documented in `docs/SERVER.md`)
- [ ] Confirm TOFU sheet appears on first connect, persists on second
- [ ] Confirm block output renders correctly in production

### TestFlight
- [ ] Upload a build via Xcode Organizer (Product → Archive → Distribute)
- [ ] Invite 10–20 developers as external testers
- [ ] Test the golden path: add host → SSH connect → run command → AI explain
- [ ] Test approval flow: Claude Code hook → conduitd → phone Inbox → Allow/Reject

---

## Payment Architecture Reminder

| Revenue stream | Method | Review note |
|---|---|---|
| One-time app purchase | Apple IAP (StoreKit, `dev.conduit.mobile.pro`) | App Store-safe access path |
| AI credits / Pro subscription | Stripe Checkout Sessions via `conduit.dev/subscribe` | Show the CTA only for United States storefronts |
| Fly.io / Lightsail compute | Billed directly by provider | Provider account management |

**Do not** mention pricing differences between IAP and web purchase in the app (App Review will reject).

---

## Post-submission checklist

- [ ] Monitor crash reports in Xcode Organizer (or Crashlytics)
- [ ] Watch App Review feedback (usually 24–48 hours)
- [ ] Common rejection reasons for SSH apps:
  - **4.2** — Minimum functionality (show the approval inbox, diff review, and AI features prominently in screenshots)
  - **2.1** — App completeness (make sure onboarding flow completes without errors)
  - **3.1.1** — In-App Purchase (confirm the BillingView purchase flow works in TestFlight)
