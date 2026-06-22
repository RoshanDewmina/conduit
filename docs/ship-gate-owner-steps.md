# Ship Gate — what's left to publish

> Single source of truth for getting Lancer onto the App Store.
> **Engineering is complete.** Everything below is an owner action (App Store Connect, a device, DNS).
> Last verified: 2026-06-11.

## Already done (do not redo)

| Item | State | Evidence |
|------|-------|----------|
| Paid Apple Developer account | ✅ | Team `39HM2X8GS6`. (A free team can't mint the APNs key below, so this is confirmed paid.) |
| APNs Auth Key (`.p8`) | ✅ | `~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` — Key ID `L8LVU9X82W`, Team `39HM2X8GS6`, bundle `dev.lancer.mobile` |
| Entitlements wired | ✅ | `project.yml` → `Lancer.entitlements`: `aps-environment: production`, CloudKit `iCloud.dev.lancer.mobile`, App Group `group.dev.lancer.mobile` |
| Background modes / export compliance | ✅ | `remote-notification` in `UIBackgroundModes`; `ITSAppUsesNonExemptEncryption: false` in Info.plist |
| push-backend deployed | ✅ | `https://35.201.3.231.sslip.io/health` → HTTP 200 |
| App points at the backend | ✅ | `LANCER_PUSH_BACKEND_URL` set in `project.yml` |
| Decision relay (decide while away) | ✅ | phone → `/approval/decision` → lancerd poller resolves; ships in this milestone |
| Code/tests | ✅ | iOS engine + lancerd + push-backend suites green; app target builds |

The APNs deploy env values live in **`push-backend-deploy-env.md`** (Key ID, Team ID, bundle, `.p8` path). App Store copy/metadata lives in **`app-store-metadata.md`**.

---

## Remaining owner steps

### 1. Confirm APNs secrets on the *running* backend (~5 min)
The instance is up, but health doesn't prove the APNs env is set (push reads env lazily at first send). Confirm the four secrets are present on the live service per `push-backend-deploy-env.md`:
`APNS_KEY_ID=L8LVU9X82W`, `APNS_TEAM_ID=39HM2X8GS6`, `APNS_BUNDLE_ID=dev.lancer.mobile`, `APNS_KEY_PATH` → the `.p8`.

### 2. App Store Connect setup
At [appstoreconnect.apple.com](https://appstoreconnect.apple.com):
1. **Create the app record** — Bundle ID `dev.lancer.mobile`, name *Lancer*.
2. **Enable capabilities** on the identifier: **Push Notifications**, **CloudKit** (container `iCloud.dev.lancer.mobile`), **App Groups** (`group.dev.lancer.mobile`). Push is already provisioned (the `.p8` exists). After activating CloudKit, set `LANCER_ICLOUD_ENABLED: true` in `project.yml` and run `xcodegen generate` (it is already `true` — confirm it matches the activated container).
3. **Create the IAP** — Product ID `dev.lancer.mobile.pro`, Non-Consumable, $14.99 ("Lancer Pro"). AI credits use the Stripe web flow (US storefront only) — never compare IAP vs web pricing in-app (App Review rejects this).
4. **Privacy nutrition label** — no tracking; declare the APNs device token (push registration for approval alerts) and subscription data if Stripe billing is on. State plainly: **source code never leaves the device.**
5. **Age rating** — 4+. **Screenshots** — `docs/screenshots/governed-approvals/` (inbox card, a decision, fleet glance, activity feed, autonomy presets).
6. **Reviewer notes** — Lancer drives a *remote* shell; it does not download or execute code locally (pre-empts Guideline 2.5.2 scrutiny). Inbox is pre-seeded in DEBUG builds for review. The Billing screen offers a $14.99 StoreKit purchase (use a sandbox account).

### 3. Physical-device validation (APNs is a no-op in the simulator)
On a real device: connect a host, background the app, trigger an approval on the host → expect a push within ~2 s with the command + risk → tapping **Approve** resolves it via the decision relay even though the app was backgrounded.

### 4. Pre-public polish (before TestFlight/public)
- Repoint `LANCER_PUSH_BACKEND_URL` off the raw IP `https://35.201.3.231.sslip.io` onto a vanity domain (e.g. `https://push.conduit.dev`) so the shipped binary isn't pinned to an IP. Update `scripts/update-dns.sh` accordingly, then `xcodegen generate`.
- **DNS for conduit.dev** (Route53, ~2 min): A `conduit.dev → 76.76.21.21`, CNAME `www.conduit.dev → cname.vercel-dns.com`. Or `aws configure && ./scripts/update-dns.sh`.

### 5. Archive → TestFlight → release
**Xcode Organizer:** Product → Archive → Distribute App → App Store Connect → Upload → add testers in TestFlight.
**Fastlane (if configured):** `fastlane beta` → TestFlight; after testing, `fastlane release`.

---

## Common SSH-app rejection reasons to pre-empt
- **2.5.2 / remote shell** — make the reviewer notes explicit (remote, not local, execution).
- **4.2 minimum functionality** — lead screenshots with the approval inbox, the decision, and the diff/policy surfaces.
- **2.1 completeness** — onboarding must complete cleanly.
- **3.1.1 IAP** — confirm the StoreKit purchase works in TestFlight.
