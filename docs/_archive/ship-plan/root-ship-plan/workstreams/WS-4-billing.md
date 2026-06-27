# WS-4 — Stripe / billing finish  (covers 17-pt #9)

> Independent of the Swift UI workstreams (mostly Go backend + a release-gating check). Owner does the Stripe dashboard steps; you do the code + local test. Coordinates with WS-5 (the webhook URL becomes the Cloud Run URL).

## Context
Lancer ships a **paid v1** (locked decision): a StoreKit 2 one-time purchase **plus** a US-only external Stripe subscription path. Repo `/Users/roshansilva/Documents/command-center`. iOS build: `cd Packages/LancerKit && swift build`. Go backend: `daemon/push-backend/` (`go build`).

**Confirmed state:**
- StoreKit 2 one-time `dev.lancer.mobile.pro` ($14.99) fully wired: `PurchaseManager.swift` (products ~L57–71, `purchase()` ~L73–96, `Transaction.updates` ~L121–130). 6 features gated behind `isPro` (`SessionShellView.swift` L140–166; multi-host in `AppRoot.swift onAddHostGated`). `PaywallSheet.swift` complete.
- `BillingView.swift` links US-only to `https://conduit.dev/subscribe` (L40–51), gated by `BillingEligibility.isExternalStripeEligible` (US only).
- **Backend `daemon/push-backend/billing.go`: routes `/billing/{checkout,portal,webhook,return}` registered, structs defined (Stripe `2026-04-22.dahlia`), but implementation is INCOMPLETE past ~L100.** Uses raw HTTP to Stripe (no SDK).
- **`isPro` DEBUG bypass:** `PurchaseManager.swift:34–41` returns `true` unless `lancerDebugProBypass=false` (Settings→Terminal→Debug). **Must not be true in Release.**

## Tasks
1. **Finish `billing.go`** — complete all four routes:
   - `/billing/checkout` — create a Stripe Checkout Session (monthly/annual price from env), return `{url}`.
   - `/billing/portal` — create a billing-portal session for an existing customer.
   - `/billing/webhook` — **verify the Stripe signature** (`STRIPE_WEBHOOK_SECRET`), handle `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`; update the entitlement cache.
   - `/billing/return` — redirect to the `lancer://billing/return?session_id=…` deep link.
   - Read prices/keys from env: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_ANNUAL`.
2. **Release-gate `isPro`** — ensure the DEBUG bypass cannot return true in a Release build (`#if DEBUG` guard, not just a UserDefaults default). Confirm the 6 gated features + multi-host actually lock when `isPro=false`.
3. **Local end-to-end test** with the Stripe CLI (no deploy needed):
   ```bash
   cd daemon/push-backend && go run .            # reads .env
   stripe listen --forward-to localhost:8080/billing/webhook
   stripe trigger checkout.session.completed
   stripe trigger customer.subscription.updated
   ```
   Confirm the webhook verifies the signature and flips the entitlement; `GET /billing/subscription-status` returns active.
4. **Deep-link handling** — confirm the app handles `lancer://billing/return?session_id=…` and refreshes entitlement on return.

## Owner-only (do in the Stripe dashboard — list these in your report, don't fake them)
Create "Lancer Pro" product + monthly/annual prices (copy IDs → env); create the webhook endpoint (URL = the Cloud Run URL from WS-5 + `/billing/webhook`; copy signing secret → `STRIPE_WEBHOOK_SECRET`).

## Constraints
- **Never commit a live or test secret key.** Use `.env` (gitignored) + provide `.env.example` with placeholders.
- Webhook MUST verify the signature — an unverified webhook is a security hole.

## Acceptance
- All four routes return real responses; webhook verifies signature + updates entitlement. · `isPro` cannot be true in Release. · Stripe CLI local test passes (paste output). · `.env.example` added; no secrets committed. · `go build` + iOS `swift build` green.

## Report Template (fill in, return)
```
## WS-4 Report
### billing.go routes: checkout <done?> portal <done?> webhook(sig-verified?) <done?> return <done?>
### isPro release-gate: <how guarded; features lock when false?>
### Stripe CLI local test: <paste trigger output + entitlement flip>
### Deep link lancer://billing/return: <handled?>
### .env.example: <added?> secrets committed: <none — confirm>
### Owner-action items left: <Stripe dashboard steps>
### go build + swift build: <green/red> · Files changed: <list> · Deviations/risks:
```
