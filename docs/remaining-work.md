# Conduit — Remaining Work Before Production

Last updated: 2026-05-25

## What's confirmed done (code complete, tested)

### Core SSH
- SSH connect (password + Ed25519) ✅
- TOFU host-key confirmation sheet ✅
- Block-mode terminal (command + output as units) ✅
- Raw PTY mode via SwiftTerm (vim, htop, tmux) ✅
- Auto mode-switch (block ↔ PTY) ✅
- Keyboard accessory rail (Ctrl, arrows, presets) ✅
- tmux auto-attach on connect ✅
- Auto-reconnect on network change ✅
- ANSI SGR parser (colors, bold, italic) ✅
- Ed25519 key generation + Keychain ✅
- GRDB persistence (hosts, blocks, snippets) ✅

### AI + Agent
- Risk scorer (low/medium/high/critical) ✅
- AI clients (Anthropic, OpenAI) ✅
- NL→command synthesis (`#` prefix wired to `SessionViewModel.translateAndInsert`) ✅
- "Explain block" AI action (streaming, wired in `SessionView`) ✅
- Biometric gate at app launch (LaunchLockView + BiometricGate.shared) ✅
- DaemonChannel (conduitd JSON-RPC over SSH) wired ✅
- ApprovalIngest (ingest daemon events into ApprovalRepository) wired ✅
- LiveInboxViewModel with real Allow/Reject → conduitd response ✅

### Session surfaces
- SFTP file browser (SFTPFilesView / SFTPFilesViewModel / SFTPClient) ✅
- Preview (SmartPreviewView + WKWebView + SSHProxyURLSchemeHandler) ✅
- Port auto-detection (PortDetector wired in PreviewViewModel) ✅
- Diff review (DiffView + UnifiedDiffParser) ✅
- Session Inbox (per-session approval filter) ✅

### Payment + App Store prep
- StoreKit 2 one-time purchase (PurchaseManager + BillingView) ✅
- External link to conduit.dev/subscribe (Stripe) ✅
- Privacy manifest (Conduit/PrivacyInfo.xcprivacy) ✅
- App Store metadata (fastlane/metadata/en-US/) ✅
- Screenshots (docs/screenshots/, 6 images at 1320×2868) ✅
- Fastlane automation (fastlane/Fastfile) ✅
- APNs entitlement updated to `production` ✅

### Quality
- 97/97 tests passing ✅
- Zero Swift 6 concurrency warnings ✅
- BUILD SUCCEEDED ✅
- Verified against real GCP server (35.201.3.231) ✅
- conduit.dev website deployed to Vercel ✅

---

## BLOCKER 1: Paid Apple Developer Program ($99/year)

The current Apple Developer account (`dewminaimalsha2003@gmail.com`, team `39HM2X8GS6`) is a **free personal team**. Free accounts cannot:
- Use CloudKit or Push Notifications entitlements
- Submit to the App Store
- Use TestFlight

**To fix:** Enroll at developer.apple.com/enroll  
**OR:** If you have a paid account under a different Apple ID (e.g. sidewhinder2k3@gmail.com):
1. Open Xcode → Settings → Accounts → + → sign in with paid Apple ID
2. Update `DEVELOPMENT_TEAM` in `project.yml` with the new team ID
3. Run `xcodegen generate`

---

## BLOCKER 2: DNS for conduit.dev (2 min)

The website is deployed on Vercel. conduit.dev needs one DNS record to go live.

**In AWS Route53 → conduit.dev hosted zone:**
- Type: **A** | Name: `conduit.dev` | Value: `76.76.21.21` | TTL: 60
- Type: **CNAME** | Name: `www` | Value: `cname.vercel-dns.com` | TTL: 60

Script ready: `scripts/update-dns.sh` (run `aws configure` first, then `./scripts/update-dns.sh`)

Once set, https://conduit.dev/privacy and /subscribe will be live (Apple checks these during review).

---

## BLOCKER 3: App Store Connect setup (30 min, requires paid account)

After enrolling in the paid program:
- [ ] Create app: Bundle ID `dev.conduit.mobile`
- [ ] Add IAP: `dev.conduit.mobile.pro` | Non-Consumable | $14.99 | "Conduit Pro"
- [ ] Enable CloudKit container: `iCloud.dev.conduit.mobile`
- [ ] Enable Push Notifications capability
- [ ] Fill Privacy Nutrition Label → "No data collected"
- [ ] Age rating → 4+
- [ ] Upload screenshots from `docs/screenshots/`
- [ ] App description is in `fastlane/metadata/en-US/description.txt`

---

## BLOCKER 4: TestFlight + release (20 min, requires paid account)

```bash
# Set env vars
export APPLE_ID="sidewhinder2k3@gmail.com"
export APP_STORE_CONNECT_TEAM_ID="<your paid team ID>"

# Upload to TestFlight
fastlane beta

# Or upload to App Store (after TestFlight testing)
fastlane release
```

Alternatively via Xcode:
1. Product → Archive (scheme: Conduit, destination: Any iOS Device)
2. Xcode Organizer → Distribute App → App Store Connect → Upload

---

## Non-blocking (do after TestFlight)

### Stripe payment link (5 min)
1. dashboard.stripe.com → Payment Links → "Conduit Pro" $9/mo
2. Edit `docs/website/subscribe.html` → replace `YOUR_STRIPE_LINK`
3. Redeploy: `vercel --prod` from `docs/website/`

### Push backend (30 min, requires APNs .p8 key from paid account)
1. developer.apple.com → Keys → Create → Enable APNs → Download `AuthKey_KEYID.p8`
2. Copy to `daemon/push-backend/AuthKey_KEYID.p8`
3. `cd daemon/push-backend && fly launch && fly secrets set APNS_KEY_ID=... && fly deploy`
4. Set `pushBackendURL` in `Conduit/ConduitApp.swift` to the Fly.io URL

### CloudKit sync (needs paid account for container activation)
SyncKit architecture is implemented. The container `iCloud.dev.conduit.mobile` needs to be
activated in App Store Connect → CloudKit Dashboard before it works.

### conduitd end-to-end test (optional)
conduitd binary is at `~/conduitd` on GCP (35.201.3.231). See `docs/SERVER.md`.
