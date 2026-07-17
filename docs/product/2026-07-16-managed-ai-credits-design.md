# Managed AI Credits — research verdict & design note

**Date:** 2026-07-16 · **Author:** Fable orchestrator (research escalation; no product code changed)
**Ask:** validate the Cursor-proposed "Managed AI Credits" slice (~$20/mo + trial credits, phone-first
OpenRouter sub-key) against live code, unit economics, and App Store/Stripe constraints.

---

## Verdict: AMEND (confirm the scope, fix four concrete gaps before build)

The direction is right and cheap to ship — **but the central premise ("sub-key via existing
entitlement") is only half true in live code**. The backend can *mint and persist* per-customer
OpenRouter sub-keys, and the iOS client is *shaped* to receive one, but **no code path ever
returns the key to the phone**, and the two ends of the usage-metering pipe are both unwired.
This is an AMEND, not a REJECT: every gap is a small, bounded build on existing seams, not
greenfield billing.

**Do not ship anything until the owner approves the ledger-language amendment in §8.**

---

## 1. What live code actually has (verified this session, file:line)

### Production-capable today
| Piece | Evidence | Notes |
|---|---|---|
| Stripe subscription checkout / portal / webhook (sig-verified) / entitlement lookup | `daemon/push-backend/billing.go:76-83` (routes), `:257-302` (webhook + HMAC verify `:448-489`) | Needs `STRIPE_SECRET_KEY`, `STRIPE_PRICE_MONTHLY`/`_ANNUAL`, `STRIPE_WEBHOOK_SECRET` env (`billing.go:313-327,491`). Return deep-link `lancer://billing/complete` (`billing.go:304-311`) |
| Entitlement store, bearer-token auth, per-request scoping | `entitlements.go:59-75` (Redis or file), `:389-406` (`resolveEntitlementFromBearer`) | Redis backend exists **for entitlements only** (`ENTITLEMENTS_REDIS_URL`) |
| OpenRouter sub-key minting with per-customer spend cap + monthly reset | `openrouter.go:114-149` (`ensureOpenRouterSubKey`), `:223-266` (`POST /api/v1/keys`) | Cap from `OPENROUTER_LIMIT_MONTHLY` (default $20, `openrouter.go:93`); key persisted server-side (`:168-185`) |
| Prepaid credit ledger with overage flag + 402 fail-closed | `credits.go:107-159` (`deductCredits`), `usage.go:98-102` (`X-Credit-Overage: blocked` → HTTP 402) | Overage default is **allow** (`credits.go:57-63`) — must flip for trial |
| Usage ingest endpoint + daily USD quota | `usage.go:50-109`, `quotas.go:31-33` (`QUOTA_DAILY_USAGE_USD` default $100) | Cost is **client-self-reported** — advisory only (see §4) |
| iOS Stripe checkout eligibility gate (US storefront only) | `SettingsFeature/BillingEligibility.swift:1-6`, `PurchaseManager.swift:39-41` | Already the right shape for the App Store constraint (§3) |
| iOS entitlement client + refresh | `AgentKit/CloudEntitlementClient.swift:91-131`, `PurchaseManager.swift:161-200` | Decodes `openRouterAPIKey` field (`CloudEntitlementClient.swift:14`) |
| iOS OpenRouter chat client with per-call usage/cost capture | `AgentKit/OpenRouterClient.swift` (usage record at `:102-108`) | Default model `anthropic/claude-sonnet-4` (`:18`) — must change for managed tier |
| iOS BYOK Keychain store (escape hatch) | `AgentKit/AIKeyStore.swift:7-30`, `KeychainAIKeyStore` in `AppFeature/AppRoot.swift` | `AIProvider.supportsManagedKeys == .openrouter` only (`AIKeyStore.swift:27-29`) |
| iOS usage-report plumbing (client → backend) | `AppFeature/AgentStore.swift:560-587` (`ingestUsage` → `POST /usage`) | Exists but on the unwired hosted-agent surface |

### Broken premises / gaps (the AMEND)
1. **The sub-key never reaches the phone.** The Go `subscriptionEntitlement` struct has **no
   `openRouterAPIKey` field** (`entitlements.go:18-37`); grep of the backend finds zero writers
   of that JSON key. iOS `CloudEntitlement.openRouterAPIKey` (`CloudEntitlementClient.swift:14`)
   therefore always decodes `nil`, so `PurchaseManager.managedOpenRouterKey`
   (`PurchaseManager.swift:68-70`) is always nil. Sub-keys are minted only inside
   `handleCreateAgent` (`agents.go:129`) and injected only into **cloud-runner** dispatch
   (`dispatch.go:96`) — i.e. the frozen hosted-cloud path, not the phone path.
2. **The phone-first AI client seam is dead code.** `AppRoot.aiClient(provider:managedOpenRouterKey:)`
   (`AppFeature/AppRoot.swift:86`) has **zero call sites** in the app. `SessionViewModel` receives
   an optional `aiClient` and an `onAIUsage` callback (`SessionFeature/SessionViewModel.swift:218-250`),
   but **nothing constructs it with either** — grep finds no wiring. So neither managed-key usage
   nor usage reporting fires anywhere today.
3. **No trial-entitlement issuance path.** Entitlements are only created from Stripe events
   (`billing.go:280-299`, `:460-468`). There is no "signed-in user gets a $5 trial grant + trial
   sub-key without a Stripe subscription" flow. `CREDITS_INITIAL_USD` (`credits.go:65-73`) is a
   single global default, not a trial grant, and `resolveEntitlementFromBearer` rejects inactive
   entitlements (`entitlements.go:402-404`) — a trial customer has no way to get a bearer token.
4. **Billing state is not durable in production.** All JSON stores (credits, usage, OpenRouter
   keys, control-plane) fall back to `os.TempDir()` (`store.go:10-18`); the deploy runbook itself
   flags this: *"On Cloud Run this means state is lost on every cold start/revision… a real
   problem for billing/entitlements/credits durability"* (`DEPLOY_RUNBOOK_HANDOFF.md:145`). Only
   entitlements have a Redis backend. Losing `lancer-openrouter-keys.json` strands customers'
   minted sub-keys (OpenRouter vends the key material once — `openrouter.go:143-147`).

Also noted: `clientToken` is persisted to **UserDefaults**, not Keychain
(`PurchaseManager.swift:194-196`); sub-keys are plaintext-at-rest server-side by acknowledged MVP
posture (`openrouter.go:151-156`). Both must be fixed in this slice (§5).

## 2. Unit economics (external, cited)

- **OpenRouter mechanics** — provisioning key mints per-customer runtime keys with a `limit` and
  `limit_reset: daily|weekly|monthly` (resets midnight UTC). Exactly matches `openrouter.go`'s
  request shape. ([OpenRouter provisioning docs](https://openrouter.ai/docs/features/provisioning-api-keys),
  [OpenRouter help](https://openrouter.zendesk.com/hc/en-us/articles/51680687417499))
- **OpenRouter platform fee** — **5.5% on credit purchases** ($0.80 min; 5% crypto). Our COGS per
  $1 of member inference ≈ $1.055. Buy credits in large tranches, never small top-ups.
  ([openrouter.ai/pricing](https://openrouter.ai/pricing), [fee breakdown](https://ofox.ai/blog/openrouter-pricing-hidden-markup-breakdown-2026/))
- **Kimi K3** — confirmed **$3 / 1M in (cache miss), $0.30 cached, $15 / 1M out**, 1M context;
  weights promised late July 2026, not yet self-hostable. Brief's numbers check out.
  ([Moonshot pricing](https://platform.kimi.ai/docs/pricing/chat), [OpenRouter model page](https://openrouter.ai/moonshotai/kimi-k3), [VentureBeat](https://venturebeat.com/technology/chinas-moonshot-ai-releases-kimi-k3-the-largest-open-source-model-ever-rivaling-top-u-s-systems))
- **Mid-tier open models (OpenRouter, ~Jun–Jul 2026; re-verify at build time)** — Qwen3 Coder
  $0.22/$1.80 · DeepSeek V4 Pro ~$0.44/$0.87 · GLM-5.2 ~$0.98/$3.08 per 1M in/out.
  ([openrouter.ai/qwen/qwen3-coder](https://openrouter.ai/qwen/qwen3-coder), [comparison](https://www.developersdigest.tech/blog/glm-5-2-vs-deepseek-v4-vs-qwen3-open-weights-coding-showdown))

### COGS sketch (recommended numbers)
| Line | Trial | Paid $24/mo |
|---|---|---|
| Stripe fee (~2.9% + $0.30) | $0 | ≈ $1.00 |
| Sub-key spend cap (`limit`) | **$5, `limit_reset: null`, overage OFF** | **$12/mo, `limit_reset: monthly`** |
| OpenRouter 5.5% credit fee on cap | ≤ $0.28 | ≤ $0.66 |
| **Worst-case COGS / margin** | **≤ $5.28 loss-leader per account** | **≤ $13.66 → ≥ 43% gross margin at 100% utilization**; typical utilization well below that |

$12 of mid-tier inference is real usage (~5–6M Qwen3-Coder output tokens); on **K3 it is ~0.8M
output tokens — a handful of heavy agent sessions**. Hence: mid-tier default, K3 as an opt-in
"premium model" toggle with an explicit burn-rate warning. **Unlimited-K3-at-$20 stays ruled out**
(one heavy user ≈ $50–150/mo COGS). Price band $19–29 works; recommend **$24/mo** with $12
included, top-ups Phase 1.5 (Stripe one-time price + bump the sub-key `limit` via `PATCH /api/v1/keys`).

### Enforcement model (amendment — kills the self-reporting problem)
The **sub-key `limit` is the only hard cap**; OpenRouter enforces it server-side regardless of
client honesty. The `POST /usage` → `deductCredits` ledger (`usage.go:93-102`) trusts
client-reported cost, so treat it as **UI telemetry only**, and derive the authoritative
"remaining balance" server-side from the provisioning API's per-key usage (GET `/api/v1/keys`)
rather than from the ledger. The existing 402 fail-closed path remains for overage-off accounts.

## 3. App Store / Stripe constraint (US)

As of July 2026: US-storefront apps **may link out to external payment** (Stripe) for digital
goods; Apple's 27% external commission was struck (contempt, May 2025), the Ninth Circuit largely
upheld the injunction (Dec 2025) while allowing Apple to pursue a "reasonable" commission, and the
district-court framework is **still unresolved** (Apple reply brief was due 2026-07-13). Net: the
slice is shippable US-only via link-out today, with a priced-commission risk later — margin
sketch above survives a future single-digit fee, not 27%.
([RevenueCat](https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy/), [Adapty](https://adapty.io/blog/can-you-use-stripe-for-in-app-purchases/), [9to5Mac 2026-07-13](https://9to5mac.com/2026/07/13/epic-games-fights-apples-request-to-pause-app-store-commission-proceedings/))

Practical requirements: US-only gate (already live — `BillingEligibility.swift`), Apple's
**StoreKit External Purchase Link entitlement** in the app's entitlements + ASC declaration
(must-build, small), link opens Safari/SFSafariView → existing `/billing/return` deep link.
Leave dormant StoreKit Pro (`PurchaseManager.swift:28`, `dev.lancer.mobile.pro`) untouched, per
brief — but note its DEBUG default is **entitlement-granted** (`PurchaseManager.swift:44-51`),
so all testing of the paywall must use explicit overrides.

## 4. Must-build vs reuse (Phase 1)

**Reuse as-is:** Stripe checkout/portal/webhook (`billing.go`) · entitlement store + bearer auth
(`entitlements.go`) · sub-key minting (`openrouter.go:114-149,223-266`) · credits ledger + 402
(`credits.go`, `usage.go`) · iOS entitlement client (`CloudEntitlementClient.swift`) · BYOK
Keychain store (`AIKeyStore.swift`) · `OpenRouterClient` · US gate (`BillingEligibility.swift`).

**Must build (ordered):**
1. **Key vend to phone** — add `openRouterAPIKey` to the `/billing/entitlement` response for
   active managed-tier entitlements, minting via `ensureOpenRouterSubKey` on first fetch (move
   the call off `handleCreateAgent`); return only over the authenticated path
   (`entitlements.go:435-477`).
2. **Trial issuance** — Supabase-signed-in user with no Stripe sub gets a synthetic active
   entitlement (`status: "trial"`) + $5 sub-key (`limit_reset: null`), overage OFF; relax the
   `Active` check or set trial entitlements Active (`entitlements.go:402-404`).
3. **Durable stores** — extend the Redis backend (pattern at `entitlements.go:198-336`) to the
   OpenRouter-keys and credits stores, or mount a persistent `DATA_DIR`; blocker per
   `DEPLOY_RUNBOOK_HANDOFF.md:145`.
4. **iOS wiring** — call `AppRoot.aiClient(managedOpenRouterKey: PurchaseManager.shared.managedOpenRouterKey)`
   from the live composer/session path (today: zero call sites); wire `onAIUsage` →
   `AgentStore.ingestUsage`; store the managed key + `clientToken` in **Keychain**, replacing the
   UserDefaults write at `PurchaseManager.swift:194-196`.
5. **UX minimum** — Profile balance row (server-derived remaining, §2) · empty-credit paywall on
   402 / exhausted key with two buttons: *Add credits* (Stripe link-out) and *Use my own key*
   (BYOK, already built) · managed-tier default model = mid-tier open model, K3 toggle + burn
   warning (change `OpenRouterClient.swift:18` default for managed mode).
6. **External Purchase Link entitlement** + ASC declaration (§3).

**Can wait:** top-up SKUs · annual plan (env already supports it, `billing.go:319-321`) · model
picker beyond default+K3 · non-US IAP fallback · StoreKit-Pro/Stripe reconciliation (stays frozen).

## 5. Security notes
- Managed key + clientToken → **iOS Keychain** (reuse `KeychainAIKeyStore`), never UserDefaults, never logged (Redactor already covers API-key patterns).
- Server-side sub-keys are plaintext-at-rest (acknowledged at `openrouter.go:151-156`) — acceptable for this slice, encrypt-at-rest before GA.
- Trial abuse: one trial per Supabase account is weak alone; **bind trial issuance to App Attest** — attestation infra already exists (`app_attest.go`, `device_bindings.go`; memory: prod already requires `APP_ATTEST_*` env). One trial per attested device key. $5 cap bounds worst-case loss.
- Blast radius of a leaked sub-key = its remaining `limit`; revocable via provisioning API (delete + re-mint).

## 6. Phase-2 seam (machine/CLI key inject)
Keep the vend payload provider-shaped, not phone-shaped: entitlement returns
`{provider: "openrouter", key, limitUSD, resetCadence}`. Phase 2 forwards the same payload over
the existing E2E relay to `lancerd`, which exports `OPENROUTER_API_KEY` into vendor-CLI dispatch
env — mirroring what `dispatch.go:96` already does for cloud runners. No Phase-1 decision blocks
this; just don't collapse the payload to a bare string field consumed only by `PurchaseManager`.

## 7. Non-goals (unchanged from brief)
No Fly/agent-runner/GCP hosted execution · no unlimited-frontier flat tier · no shared production
inference key (`OPENROUTER_SHARED_KEY` at `openrouter.go:206-213` stays dev/self-host-only) · no
K3 self-hosting · no StoreKit reconciliation · no team tier.

## 8. Unfreeze recommendation (owner decision — ledger not edited)
Amend `docs/STATUS_LEDGER.md` "Still frozen" line to:
> **Still frozen:** team tier, hosted-cloud **execution** (Fly/agent-runner), Away Launch
> Composer, StoreKit↔Stripe reconciliation. **Unfrozen (narrow): "Managed AI Credits"** — Stripe
> subscription + capped per-customer OpenRouter sub-key vended to the phone, per
> `product/2026-07-16-managed-ai-credits-design.md`. US storefront only.

Timing: the ledger already schedules "billing + legal/review unfreeze early August"
(`STATUS_LEDGER.md:91`); this slice can start ~2 weeks earlier without touching the Phase-1
dogfood lanes (backend + Settings/Profile surface only).

## 9. Open decisions for the owner
1. Approve the §8 unfreeze language (nothing builds until then).
2. Price point ($24/mo w/ $12 cap recommended) and trial size ($5 recommended).
3. Managed default model (recommend Qwen3 Coder-class; re-verify live pricing at build time).
4. Trial requires Supabase sign-in + App Attest — accept that onboarding friction?
5. Durable-store path: Redis for all billing stores vs persistent `DATA_DIR` volume.
6. Ship K3 toggle in Phase 1 or hold for Phase 1.5.
