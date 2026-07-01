# 11 — Monetization and Upgrade Strategy

> Source: Wave-2 monetization research (App Store Review Guidelines + Mobbin pay-once corpus + repo grounding). This is guideline interpretation, **not legal advice**; re-read the Cloud/IAP boundary at submission time.

## Five conclusions

1. **The paywall is dead code.** `PaywallSheet` exists but `showingPaywall` is never set `true` anywhere (declared `AppRoot.swift:191`, consumed `:356`, assigned nowhere), and DEBUG forces `isPro=true`. **Lancer ships a paywall it never shows and gates zero features.** Wiring `showingPaywall`/`paywallFeatureName` at scale/automation trigger points is the single highest-leverage fix.
2. **Keep StoreKit 2 direct, not RevenueCat** (V1). For one non-consumable "pay once" SKU, RevenueCat's offerings/experiments/cross-platform analytics are unused, while it adds a 1% MTR fee, a third party in the purchase path, and privacy cost — wrong for a trust-positioned app. The IAP plumbing is already correct and compliant.
3. **Lancer Cloud (Stripe), not the one-time IAP, is the App Review risk.** A one-time Pro unlock for own-hardware software is squarely allowed under 3.1.1. Hosted/managed-AI compute experienced in-app is digital SaaS that Apple defaults to requiring IAP. Keep Cloud deferred to V2 and ship it as a **US-storefront external link-out** (3.1.1(a) post-2025 anti-steering ruling) — exactly what the existing US-only `BillingEligibility` gate anticipates.
4. **Never paywall safety.** Emergency stop, approve/deny, audit viewing, device revocation, biometric lock, TOFU, and the app-closed push-approval loop stay **FREE**.
5. **No timed trial, no onboarding paywall.** The generous free tier is the trial; show contextual upsells at the moment of scale friction (3rd host, first automation rule) and via the persistent Settings/Billing row.

## Current state (grounding)

Two money paths are already coded:
- **`isPro`** — Apple StoreKit 2 **one-time non-consumable**, product id `dev.lancer.mobile.pro`, placeholder $14.99 "once". Correctly implemented: `Product.products`, `product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates` listener, `AppStore.sync()` restore (`PurchaseManager.swift`).
- **`hasCloudEntitlement`** — **Stripe** "Lancer Cloud" subscription/credits via `push-backend`/`CloudEntitlementClient`; gates hosted agents/managed AI. **Deferred to V2** per `ARCHITECTURE.md §0.1`.

Copy is committed to **"no subscriptions, ever / pay once, yours forever"** (`PaywallSheet.swift:35,50–59`) — treat as a load-bearing brand promise. Stripe is correctly gated to US storefront (`BillingEligibility.isExternalStripeEligible`). App Review hygiene present: visible restore + visible purchase-error surfaces in `BillingView`.

**The gap is product (what Pro unlocks + when the wall appears), not plumbing.**

## App Review nuance (the most important compliance section)

- **One-time Pro unlock for own-hardware software** — 3.1.1 requires IAP to "unlock features." There is **no exception** for "the value runs on your own server." The unlock happens in-app → IAP. Apple does not care that agents run on the user's machine. **Compliant. Confidence: High.** Watch-out: never implement a web-bought license-key redemption to unlock Pro (3.1.1 forbids license-key unlocks) — keep Pro = StoreKit non-consumable.
- **Lancer Cloud via Stripe** — 3.1.2(a) lists SaaS/cloud as a *permissible auto-renewable subscription*, i.e. Apple's default expectation is consumer SaaS uses IAP. Reviewers tend to read "you see the output in the app" as **consumed in-app → IAP required**. Selling Cloud via an in-app Stripe form is the highest monetization risk. **Confidence: Med.**
- **US anti-steering escape hatch** — post-April-2025 *Epic v. Apple* ruling + 3.1.1(a): on the **US storefront**, apps may include external-purchase links with no entitlement and (currently) 0% commission (a Dec 2025 appeals ruling lets Apple charge a TBD "reasonable" fee — monitor). This is why `BillingEligibility` gates Stripe to US. **Correct instinct.**
- **Recommendation:** (1) V1 — don't sell Cloud in-app at all (already deferred). (2) V2 Cloud — US-storefront external link-out (`ASWebAuthenticationSession` → hosted Stripe Checkout), never an embedded in-app Stripe form on App Store builds; standard "leaving the App Store" disclosure interstitial. (3) Optionally sell Cloud credits as Apple IAP consumables for non-US to remove reviewer-judgment risk (15–30% cut vs Stripe ~3% trade).

## Free-vs-paid matrix

**Principle: everything required to safely govern a small personal fleet is FREE; scale, automation, and power tooling are PRO. Safety/recovery is never paid.**

| Feature | Free | Pro (one-time) | Rationale |
|---|---|---|---|
| Emergency stop / kill all agents | ✅ | ✅ | Safety — never paywalled |
| Approve / deny / inspect approval | ✅ | ✅ | Core safety loop |
| Policy engine fail-closed | ✅ | ✅ | Safety default |
| Hash-chained audit log (view) | ✅ | ✅ | Trust core |
| TOFU / biometric app-lock / device revoke | ✅ | ✅ | Security |
| APNs push approvals (app-closed loop) | ✅ | ✅ | #1 V1 value prop — must be free to prove it |
| Paired hosts/daemons | 1–2 | Unlimited | **Primary value metric** |
| Concurrent live agent sessions | 1 | Up to 3 (fleet cap) | Scale lever |
| Multi-vendor dispatch | 1 vendor / all-basic | All vendors | Breadth as power |
| Durable chat history retention | recent (7–14 d) | Full | Mild scale lever; keep generous |
| Policy presets / templates | ❌ | ✅ | Automation/power |
| Scheduled / auto-approve rules | ❌ | ✅ | Automation depth |
| Advanced blast-radius config | basic view | ✅ full | Power governance |
| Fleet drift detection + remediation | detect/alert | remediate | Post-launch moat → Pro |
| Audit export / cryptographic verify | view | export + verify | Compliance value |
| Cross-provider policy matrix | ❌ | ✅ | Power governance |
| Team roles / shared ownership | ❌ | (Team/V2) | Defer to Team tier |
| Watch app + Live Activity depth | basic | rich | Prosumer polish |
| Lancer Cloud (hosted agents) | n/a | **separate Stripe/credits, V2** | Not part of Pro |

> **Tension flagged for synthesis:** §0.1 strategy says "lead with policy/audit to showcase the moat." That argues for keeping *some* governance depth free and monetizing **scale + automation** rather than governance features per se. Lean free on anything that *demonstrates* the differentiator; Pro on anything about doing it *at scale or automatically*. **Confidence: Med-High.**

## Value metric

**Primary: number of paired hosts/daemons (the fleet)**, secondary: automation depth (presets, auto-rules, drift remediation). Free = 1–2 hosts, manual governance; Pro = unlimited hosts + automation. **Do NOT meter approvals, audits, or emergency stops** — metering safety is hostile. (Lancer Cloud V2 meters AI compute USD/credits — separate from Pro.) **Confidence: Med-High.**

## Upgrade-trigger matrix

| Trigger | Surface | Tone | Why |
|---|---|---|---|
| Adds **3rd host** (over cap) | `PaywallSheet(featureName:"Unlimited hosts")` | Soft, value-framed | Scale friction felt exactly here — best-converting moment |
| Taps a **Pro feature** (preset, auto-rule, audit export, drift remediation, cross-provider matrix) | Contextual sheet naming that feature | Soft | mymind/Vivino contextual pattern |
| Opens **2nd concurrent session** over cap | Inline fleet banner | Soft | Felt scale limit |
| **Persistent** | Settings "Free plan · upgrade" row (exists) + Billing screen | Passive | Sunlitt/Fabulous/Raycast pattern |
| **After a value moment** (first lock-screen approve, first active week) | One-time gentle dismissible prompt | Soft, once | Post-value converts better |
| **Onboarding / first launch** | ❌ NONE | — | Anti-pattern for this audience |
| **Emergency stop / approval / audit view** | ❌ NEVER gate | — | Safety |

Wire `showingPaywall = true` + `paywallFeatureName = <feature>` at these points — infrastructure already exists. **Confidence: High.**

## Trial

Apple free trials exist only for auto-renewable subscriptions; a one-time non-consumable can't carry one. **No timed trial — the generous free tier IS the trial.** A developer tool's governance value takes weeks to prove; a ticking clock hurts trust. Avoid any trial-with-auto-charge (contradicts "no subscriptions, ever"). **Confidence: High.**

## Tier structure

| Tier | Mechanism | Price (placeholder) | What it is |
|---|---|---|---|
| **Free** | — | $0 forever | Full governance of a 1–2 host personal fleet; every safety feature |
| **Pro** | StoreKit 2 **non-consumable** (one-time) | ~$14.99–$39.99 once (test) | Unlimited hosts, automation, advanced governance, Watch/LA depth |
| **Team** *(V2)* | IAP or web seats (decide later) | per-seat | Shared ownership, team roles, org audit. **Defer.** |
| **Lancer Cloud** *(V2)* | Stripe credits (US link-out) ± IAP consumables (non-US) | metered USD | Hosted agent execution + managed AI. **Separate product.** |

Self-host product = **one-time only** (brand promise + right fit). Monthly/annual belong only to **Lancer Cloud** (genuinely recurring compute cost). Pricing: $14.99 is plausibly low for a prosumer governance tool (comparable Mobbin lifetime SKUs: Sunlitt $129.98, Hevy ~S$104.98); consider testing $24.99–$39.99. **Confidence: High that it's one-time; Low-Med on the number.** Enable **Family Sharing** on the Pro SKU (near-zero-cost pro-consumer signal).

## StoreKit 2 vs RevenueCat decision matrix

| Dimension | StoreKit 2 direct | RevenueCat | Lancer fit |
|---|---|---|---|
| Eng. complexity (1 SKU) | Very low — already written | SDK + dashboard + mapping | **SK2** |
| Backend required | None (on-device entitlements) | RC servers in path | **SK2** — fewer hosted deps is on-brand |
| Receipt validation | JWS on-device | Same SK2 underneath | Tie |
| Cross-device entitlement | `AppStore.sync()` | RC handles | SK2 fine (one SKU) |
| Cross-platform subs | Not handled | Strong | N/A (iOS-only V1) |
| Paywall remote config | Code/ASC | Remote offerings | RC only if iterating often — not for 1 SKU |
| Experiments / A-B | Manual, weak | Built-in | RC only once real sub tiers exist |
| Cost | Free | Free <$2.5k MTR, then **1% MTR** | **SK2** zero-cost |
| Vendor dependence | Apple only | + RC in purchase path | **SK2** — fewer third parties in a trust product |
| Privacy | No third party sees purchases | RC receives purchase/identity | **SK2** |
| Later migration to RC | Low (RC reads `currentEntitlements`) | — | Starting on SK2 keeps door open |

**Decision: StoreKit 2 direct for V1. Confidence: High.** Re-evaluate RevenueCat only if/when Lancer Cloud (V2) ships real auto-renewable tiers + you want cross-platform pricing experiments — migration is cheap because RC reads `Transaction.currentEntitlements`.

## Final architecture recommendation

1. Keep `PurchaseManager` on StoreKit 2 direct; enable Family Sharing on Pro; ensure restore always reachable; **prove sandbox purchase + restore before App Review** (outstanding per §0.1).
2. **Wire the dead paywall** — set `showingPaywall`/`paywallFeatureName` at the trigger points above (highest-leverage fix).
3. **Decide the Free/Pro split before launch** and gate features in code.
4. **Leave Lancer Cloud / Stripe deferred to V2**; when it ships, US-storefront external link-out and/or IAP consumables, never an in-app Stripe form. Keep US-only `BillingEligibility`.

## Patterns that damage trust (avoid)

Paywalling safety controls · onboarding hard paywall before a governed approval lands · fake scarcity/countdowns · subscription bait-and-switch on the self-host product · in-app Stripe form for Cloud on App Store builds · metering approvals/audit entries · hiding Restore Purchase.

## Sources

[App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (3.1.1/3.1.1(a)/3.1.2/3.1.3) · [US external-links update](https://developer.apple.com/news/?id=9txfddzf) · [Dec 2025 appeals ruling](https://www.macrumors.com/2025/12/11/apple-app-store-fees-external-payment-links/) · [StoreKit 2 vs RevenueCat (indie)](https://theswiftk.it.com/blog/storekit-2-vs-revenuecat-ios-subscriptions) · Mobbin: [QUITTR lifetime](https://mobbin.com/flows/41117274-9dce-4ed9-97b1-eab35d2f3bfa), [Sunlitt lifetime](https://mobbin.com/flows/4614b2ac-dfde-4674-92dd-c8aed48ce4ff), [Hevy lifetime](https://mobbin.com/screens/0b5bea12-f9ce-47dd-8594-b0d362aee43c), [Raycast Pro](https://mobbin.com/screens/fc3c4a7f-d86d-43b0-8397-1cf5eacc5754), [Manus usage](https://mobbin.com/flows/18273cd9-4bd5-45a6-8cb3-1792098c4c9a), [mymind contextual paywall](https://mobbin.com/flows/e5893443-6b29-4cfb-813d-156ee8142960).
