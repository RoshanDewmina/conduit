# RevenueCat setup for Lancer Pro (owner checklist)

The app code uses RevenueCat as a StoreKit wrapper for the **one-time** Lancer Pro purchase (`dev.lancer.mobile.pro`). Apple still processes payment; RevenueCat validates receipts and exposes a `pro` entitlement the app checks at runtime.

Until you complete the steps below, purchases will not authenticate (the app ships with a placeholder API key) and Pro gates will stay locked in Release builds.

## 1. Create a RevenueCat account and project

1. Sign up at [https://app.revenuecat.com](https://app.revenuecat.com).
2. Create a new project for **Lancer** (iOS app).

## 2. Connect App Store Connect

1. In RevenueCat: **Project settings → Apps → + New**.
2. Platform: **Apple App Store**.
3. Bundle ID: `dev.lancer.mobile` (must match the Xcode target).
4. Follow RevenueCat's guide to upload the **App Store Connect API key** (Issuer ID, Key ID, `.p8` file) so RevenueCat can read products and validate transactions.

## 3. Create the product mapping (must match existing StoreKit config)

The local StoreKit test file and App Store Connect should already define:

| Field | Value |
|-------|--------|
| Product ID | `dev.lancer.mobile.pro` |
| Type | **Non-consumable** (one-time purchase) |
| Display name | Lancer Pro |
| Price | $14.99 (or your chosen tier) |

In RevenueCat:

1. **Products** → import or add `dev.lancer.mobile.pro` from App Store Connect.
2. **Entitlements** → create entitlement identifier **`pro`** (exact string — the app checks `customerInfo.entitlements["pro"].isActive`).
3. Attach `dev.lancer.mobile.pro` to the `pro` entitlement.
4. **Offerings** → create a current offering (e.g. `default`) with a package pointing at `dev.lancer.mobile.pro` (lifetime / one-time package type).

## 4. Paste the iOS public API key into the app

1. RevenueCat dashboard → **Project settings → API keys → Apple App Store**.
2. Copy the **public** iOS SDK key (starts with `appl_…`).
3. In the repo, open `Packages/LancerKit/Sources/SettingsFeature/PurchaseManager.swift`.
4. Replace the placeholder:

```swift
// TODO(owner): replace with real RevenueCat API key from https://app.revenuecat.com
private static let revenueCatAPIKey = "REVENUECAT_API_KEY_PLACEHOLDER"
```

with your real key.

5. Rebuild and run on a device or simulator with **Lancer.storekit** selected in the Xcode scheme (for local StoreKit testing before ASC submission).

## 5. Verify before App Store submission

- [ ] Sandbox purchase completes and `PurchaseManager.isPro` becomes `true`.
- [ ] **Restore purchase** works on a second install / fresh simulator.
- [ ] RevenueCat dashboard shows the test customer with `pro` entitlement active.
- [ ] Pro gates unlock: Inbox, 3rd host pairing, SFTP file browser, policy presets, CloudKit sync section.

## What the code does *not* use RevenueCat for

- **`daemon/push-backend/billing.go` (Stripe)** — separate cloud compute billing; unchanged.
- **Subscriptions** — Lancer Pro is one-time only; no auto-renewable products in this path.

## Reference constants in code

| Constant | Location | Value |
|----------|----------|-------|
| Product ID | `BillingEligibility.proProductID` | `dev.lancer.mobile.pro` |
| Entitlement ID | `BillingEligibility.proEntitlementID` | `pro` |
| Free host limit | `BillingEligibility.freeHostLimit` | `2` |

## Debug overrides (development only)

- `LANCER_FORCE_PRO=1` — force Pro gates open (DEBUG).
- Settings debug toggles: `lancerDebugProBypass` / `lancerDebugCloudEntitlement` (cloud Stripe path only).
