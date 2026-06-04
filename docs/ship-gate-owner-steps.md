# Ship Gate — Owner Action Items

> These steps require human action (Apple Developer portal, App Store Connect).
> The code/config changes on this branch are already done — this doc tells you what to do next.

---

## Step 1: Enroll in Apple Developer Program ($99/year)

**Why:** Push Notifications and CloudKit require a paid Apple Developer account. The current account (free personal team `39HM2X8GS6`) cannot use these entitlements.

**Action:**
1. Go to [developer.apple.com/enroll](https://developer.apple.com/enroll)
   **OR** — if `sidewhinder2k3@gmail.com` already has a paid program:
   - Open Xcode → Settings → Accounts → `+` → Sign in with that Apple ID
2. Note your 10-character Team ID (shown in Xcode Accounts or at [developer.apple.com/account](https://developer.apple.com/account))
3. Update `project.yml` (all four targets):
   ```yaml
   settings:
     base:
       DEVELOPMENT_TEAM: "YOURTEAMID"  # replace 39HM2X8GS6 with your paid Team ID
   ```
4. Run `xcodegen generate`

---

## Step 2: App Store Connect setup

After enrolling (or signing in with paid account):

1. **Create the app record** at [appstoreconnect.apple.com](https://appstoreconnect.apple.com):
   - Bundle ID: `dev.conduit.mobile`
   - App name: Conduit

2. **Enable capabilities** in Certificates, Identifiers & Profiles → Identifiers → `dev.conduit.mobile`:
   - **Push Notifications** — required for approval alerts
   - **CloudKit** — enable container `iCloud.dev.conduit.mobile`
   - **App Groups** — `group.dev.conduit.mobile` (already declared in entitlements)

3. **Activate CloudKit container**, then flip `CONDUIT_ICLOUD_ENABLED` to `true` in `project.yml`:
   ```yaml
   CONDUIT_ICLOUD_ENABLED: true
   ```
   Then run `xcodegen generate`.

4. **Create IAP**:
   - Product ID: `dev.conduit.mobile.pro`
   - Type: Non-Consumable
   - Price: $14.99
   - Display name: "Conduit Pro"

5. **Fill Privacy Nutrition Label**:
   - No tracking
   - Declare: optional APNs device identifier (push registration for approval alerts)
   - Declare: subscription data if Stripe billing is enabled

6. **Age rating**: 4+

7. **Upload screenshots** from `docs/screenshots/` (6 images at 1320×2868 for iPhone 6.9")

---

## Step 3: Deploy push backend + set URL

1. Follow `daemon/push-backend/README.md` to deploy the push backend (GCP Cloud Run or equivalent)
2. After deploying, set the HTTPS URL in `project.yml` Info.plist properties:
   ```yaml
   CONDUIT_PUSH_BACKEND_URL: "https://your-backend-url.example.com"
   ```
3. Run `xcodegen generate`

**Note:** The cleartext `http://` fallback has been removed from `ConduitApp.swift`. If `CONDUIT_PUSH_BACKEND_URL` is not set, push token registration is silently skipped (no ATS violation, no crash).

---

## Step 4: DNS for conduit.dev (2 minutes)

Prerequisites: AWS CLI configured with Route53 write access to the `conduit.dev` hosted zone.

```bash
aws configure  # if not already done
./scripts/update-dns.sh
```

Or manually in [AWS Route53](https://console.aws.amazon.com/route53/):
- **A record**: `conduit.dev` → `76.76.21.21`, TTL 60
- **CNAME**: `www.conduit.dev` → `cname.vercel-dns.com`, TTL 60

---

## Step 5: TestFlight + release

**Via Xcode Organizer (easiest):**
1. Product → Archive
2. Xcode Organizer → Distribute App → App Store Connect → Upload
3. Visit App Store Connect → TestFlight to add internal testers

**Via Fastlane (if configured):**
```bash
export APPLE_ID="sidewhinder2k3@gmail.com"
export APP_STORE_CONNECT_TEAM_ID="<your paid team ID>"
fastlane beta    # upload to TestFlight
# or after TestFlight testing:
fastlane release # submit to App Store
```

---

## What this branch already changed (no owner action needed)

| Item | File | Change |
|------|------|--------|
| Entitlements | `project.yml` | Points to `Conduit.entitlements` (push + CloudKit declared inline) |
| Background modes | `project.yml` | `remote-notification` added to `UIBackgroundModes` |
| ATS compliance | `Conduit/ConduitApp.swift` | Cleartext `http://` fallback removed; returns `""` (skips registration silently) |
| Export compliance | `project.yml` | `ITSAppUsesNonExemptEncryption: false` added to Info.plist properties |
