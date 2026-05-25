# Conduit — Remaining Work Before Production

Last updated: 2026-05-25

## What's confirmed done (code complete, tested)
- SSH connect to real GCP server (35.201.3.231) — block-mode terminal confirmed ✅
- `uptime` command output rendered correctly in block mode ✅
- All 6 App Store screenshots captured at 1320×2868 (including live SSH session) ✅
- conduit.dev website deployed to Vercel — all 3 HTML pages live ✅
- conduit.dev domain added to Vercel project ✅
- APNs token wiring: `AppDelegate` added to ConduitApp.swift, calls `Notifications.shared.registerDeviceToken()` on launch ✅
- Team ID 39HM2X8GS6 set in project.yml + xcodeproj ✅
- APNs entitlement updated to `production` (correct for App Store) ✅
- 97/97 tests passing, BUILD SUCCEEDED ✅

---

## BLOCKER 1: Paid Apple Developer Program ($99/year)

The current Apple Developer account (`dewminaimalsha2003@gmail.com`, team `39HM2X8GS6`) is a **free personal team**. Free accounts cannot:
- Use CloudKit or Push Notifications entitlements
- Submit to the App Store
- Use TestFlight

**To fix:** Enroll in the Apple Developer Program at developer.apple.com/enroll  
**OR:** If you already have a paid account under a different Apple ID (e.g. sidewhinder2k3@gmail.com):
1. Open Xcode → Settings → Accounts → + → sign in with your paid Apple ID
2. Update `DEVELOPMENT_TEAM` in `project.yml` with the new team ID
3. Run `xcodegen generate`

Once you have a paid account, archive will succeed automatically (project is configured for Automatic signing).

---

## BLOCKER 2: DNS for conduit.dev (2 min)

The website is deployed on Vercel. conduit.dev needs one DNS record to go live.

**In AWS Route53 → conduit.dev hosted zone:**
- Type: **A** | Name: `conduit.dev` | Value: `76.76.21.21` | TTL: 60
- Type: **CNAME** | Name: `www` | Value: `cname.vercel-dns.com` | TTL: 60

Once set, https://conduit.dev/privacy, /terms, and /subscribe will be live (Apple checks these during review).

---

## BLOCKER 3: App Store Connect setup (30 min, requires paid account)

After enrolling in the paid program:
- [ ] Create app in App Store Connect → Bundle ID: `dev.conduit.mobile`
- [ ] Add IAP: `dev.conduit.mobile.pro` | Non-Consumable | $14.99 | "Conduit Pro"
- [ ] Enable CloudKit container: `iCloud.dev.conduit.mobile`
- [ ] Enable Push Notifications capability
- [ ] Fill Privacy Nutrition Label → "No data collected"
- [ ] Age rating → 4+
- [ ] App description + keywords (see `docs/app-store-metadata.md`)
- [ ] Upload screenshots from `docs/screenshots/`

---

## BLOCKER 4: TestFlight upload (20 min, requires paid account)

1. In Xcode: Product → Archive (scheme: Conduit, destination: Any iOS Device)
2. Xcode Organizer → Distribute App → App Store Connect → Upload
3. App Store Connect → TestFlight → Add external testers
4. Test golden path on a real iPhone: add host → connect → inbox → approve

---

## Non-blocking (do after TestFlight)

### Stripe payment link (5 min)
1. dashboard.stripe.com → Payment Links → Create → "Conduit Pro" $9/mo
2. Edit `docs/website/subscribe.html` → replace `YOUR_STRIPE_LINK`
3. Redeploy: in `docs/website/`, run `vercel --prod`

### Push backend (30 min, requires APNs .p8 key from paid account)
1. developer.apple.com → Keys → Create → Enable APNs → Download `AuthKey_KEYID.p8`
2. Copy to `daemon/push-backend/AuthKey_KEYID.p8`
3. `cd daemon/push-backend && fly launch && fly secrets set APNS_KEY_ID=... && fly deploy`
4. Set `pushBackendURL` constant in `Conduit/ConduitApp.swift` to your Fly.io URL

### conduitd end-to-end test (optional)
The conduitd binary is installed at `~/conduitd` on GCP. See `docs/SERVER.md` for the test setup.
