# Managed AI Credits — implementation plan

**Date:** 2026-07-16 · **Status:** owner-approved decisions locked; lanes not yet dispatched
**Design (source of truth for rationale + file:line evidence):**
[`../product/2026-07-16-managed-ai-credits-design.md`](../product/2026-07-16-managed-ai-credits-design.md)

## Locked decisions (owner, 2026-07-16)
| Decision | Value |
|---|---|
| Unfreeze | Yes — narrow slice, ledger amended same day; hosted-cloud *execution* stays frozen |
| Pricing | **$24/mo** subscription · **$12/mo** included OpenRouter sub-key cap (`limit_reset: monthly`) · top-ups deferred to Phase 1.5 |
| Trial | **$5** one-time grant (`limit_reset: null`), **overage OFF**, gated by Supabase sign-in + **App Attest** device binding (one trial per attested device) |
| Storage | **Redis for all billing stores** (extend the existing entitlement Redis backend to sub-keys, credits, usage) |
| Default model (default, owner may override in review) | Qwen3 Coder-class mid-tier open model; re-verify OpenRouter slug + live pricing at build time |
| K3 premium toggle | Phase 1.5, with burn-rate warning |
| Enforcement | OpenRouter sub-key `limit` is the ONLY hard cap; `POST /usage` ledger is UI telemetry; authoritative balance derived server-side from the provisioning API's per-key usage |
| Storefront | US-only external Stripe link-out (existing `BillingEligibility` gate); non-US sees BYOK only |

## Scope guardrails
- **No hosted execution.** Nothing in this plan touches `fly_provider.go` / `agent-runner` / `gcp_*` beyond leaving them compiling.
- **StoreKit Pro stays dormant** — no reconciliation. Paywall testing must set explicit debug overrides (DEBUG defaults grant Pro, `PurchaseManager.swift:44-51`).
- **Never log key material** (Redactor covers patterns; keep it that way). Managed key + `clientToken` live in iOS **Keychain**, not UserDefaults.
- Phase 1 powers **on-phone AI features** (composer/command assistant, explain-block, summaries). Machine/CLI key inject over the relay is Phase 2; keep the vend payload provider-shaped (`{provider, key, limitUSD, resetCadence}`) so Phase 2 is additive.

## Work packages

Dependency graph: **WP1 ∥ WP3 → WP2 → WP4 → WP5** (WP1/WP3 have disjoint write-sets — daemon vs iOS — and run in parallel).

### WP0 — Owner-gated externals (owner, anytime before WP5)
No code. Blockers for live E2E, not for coding:
1. Stripe **test-mode** product + monthly price → `STRIPE_PRICE_MONTHLY`; webhook endpoint secret → `STRIPE_WEBHOOK_SECRET`. (Live keys only at launch.)
2. OpenRouter **provisioning key** (`OPENROUTER_PROVISIONING_KEY`) + a credit tranche loaded in one purchase (5.5% fee, avoid small top-ups).
3. Managed **Redis** instance reachable from the push-backend deploy (`ENTITLEMENTS_REDIS_URL`; WP1 will consolidate naming).
4. App Store Connect: request the **External Purchase Link entitlement** (approval latency is the long pole — file this week).

### WP1 — Backend: Redis-backed billing stores
**Router:** Cursor Grok 4.5 high · **Risk:** low · **Worktree:** `lane/mac-redis-stores`
**Write-set:** `daemon/push-backend/{redis_client.go,openrouter.go,credits.go,usage.go,store.go}` + tests. Do NOT touch `entitlements.go` (WP2 owns it), dispatch/policy files.
- Port the `openRouterKeysStore` (`openrouter.go:157-221`), credits (`credits.go:25-98`), and usage (`usage.go:35-39`) file stores to a backend interface with Redis + file implementations, following the entitlement pattern (`entitlements.go:46-75,198-336`). One `BILLING_REDIS_URL` (fallback: `ENTITLEMENTS_REDIS_URL`) selects Redis for all of them; file fallback stays for self-host.
- Credits deduction must be atomic under Redis (single-connection WATCH/MULTI or Lua; no read-modify-write race).
- **Gate:** `cd daemon/push-backend && go build ./... && go vet ./... && go test ./...` — including new tests proving balances/keys survive a simulated restart (fresh store instance, same Redis).

### WP2 — Backend: key vend + trial issuance + balance (SECURITY-SENSITIVE)
**Router:** **Claude Sonnet 5 high** (auth/key-handling path) + **Fable full-diff review** · **Risk:** sensitive · **Worktree:** `lane/mac-key-vend` · **Depends:** WP1
**Write-set:** `daemon/push-backend/{entitlements.go,openrouter.go,billing.go}` + new `trial.go`, `balance.go` + tests.
1. **Key vend:** `handleBillingEntitlement` (`entitlements.go:435-477`) — for an **authenticated, active, managed-tier** entitlement, ensure a sub-key exists (move `ensureOpenRouterSubKey` off `handleCreateAgent`, `agents.go:129`) and include `openRouterAPIKey` in the response. Only over the Supabase-JWT or clientToken-authenticated path — never the unauthenticated customerId/appAccountToken query path. Cap by plan: paid $12 `monthly`, trial $5 `null`.
2. **Trial issuance:** `POST /billing/trial` — requires Supabase JWT **and** a valid App Attest assertion bound to the device key (reuse `app_attest.go` / `device_bindings.go`); enforce one trial per attested device key AND per user id (Redis set); creates entitlement `status:"trial", Active:true` + $5 sub-key + credits row with `AllowOverage:false`. `subscriptionIsActive` (`billing.go:439-446`) must NOT change; trial activation is explicit at issuance.
3. **Balance:** `GET /billing/balance` — derive remaining from the OpenRouter provisioning API's per-key usage (`GET /api/v1/keys/{hash}`), cache ~60s; ledger (`GET /billing/credits`) stays as telemetry.
4. **Env defaults:** `OPENROUTER_LIMIT_MONTHLY=12`, `TRIAL_GRANT_USD=5`, `CREDITS_ALLOW_OVERAGE=false` for trial rows (note: current global default is allow-overage, `credits.go:57-63`).
- **Gate:** full go build/vet/test + negative tests: unauthenticated fetch never contains a key; second trial for same device/user → 409; inactive entitlement → no key. **Fable reviews the full diff before merge.**

### WP3 — iOS: managed-key plumbing (SECURITY-SENSITIVE storage, parallel with WP1)
**Router:** Cursor Grok 4.5 high, **Sonnet-or-Fable full-diff review** (Keychain/key handling) · **Risk:** sensitive-storage · **Worktree:** `lane/ios-managed-key`
**Write-set:** `Packages/LancerKit/Sources/{SettingsFeature/PurchaseManager.swift,AgentKit/CloudEntitlementClient.swift,AgentKit/OpenRouterClient.swift,AppFeature/AppRoot.swift,SessionFeature/SessionViewModel.swift}` + tests. Do NOT touch paywall UI (WP4).
1. Move `clientToken` persistence from UserDefaults (`PurchaseManager.swift:194-196`) to Keychain; store vended `openRouterAPIKey` in Keychain via the existing `KeychainAIKeyStore` under a distinct managed account; wipe on entitlement loss.
2. Wire the dead seam: construct session/composer AI features with `AppRoot.aiClient(provider: .openrouter, managedOpenRouterKey:)` (`AppRoot.swift:86`, currently 0 call sites); precedence = managed key when entitled, else BYOK Keychain key.
3. Wire `onAIUsage` (`SessionViewModel.swift:219`, currently never passed) → `AgentStore.ingestUsage` (`AgentStore.swift:560`) so `POST /usage` telemetry flows.
4. Managed-mode default model constant (Qwen3 Coder-class; verify slug) replacing `anthropic/claude-sonnet-4` (`OpenRouterClient.swift:18`) when running on the managed key.
- **Gate:** `cd Packages/LancerKit && swift build && swift test` + **XcodeBuildMCP app-target build** (iOS-gated code invisible to plain `swift build`).

### WP4 — iOS: trial CTA, balance UI, paywall, link-out
**Router:** Cursor Grok 4.5 high · **Risk:** ui (owner eyeballs) · **Worktree:** `lane/ios-credits-ux` · **Depends:** WP2 (endpoints), WP3 (key plumbing)
**Write-set:** `SettingsFeature/*` (Profile/Settings surfaces), new paywall view, `PurchaseManager.swift` additions only via rebase on WP3.
1. Profile/Settings: "AI Credits" row — remaining balance from `GET /billing/balance`, plan label, refresh on foreground.
2. Trial CTA (signed-in, US or any storefront — trial itself isn't a purchase): calls `POST /billing/trial` with App Attest assertion.
3. Empty-credit paywall on 402 / exhausted key: **Add credits** (Stripe checkout link-out via `SFSafariViewController`, existing `lancer://billing/complete` return) gated by `BillingEligibility` · **Use my own key** → existing BYOK flow.
4. External Purchase Link entitlement plumbing in `project.yml` + required Apple disclosure sheet before link-out.
- **Gate:** swift build/test + app-target build + **simulator screenshots** of: balance row, trial CTA, paywall (both buttons), disclosure sheet.

### WP5 — E2E proof + deploy (no "done" without this)
**Router:** Sonnet 5 (needs XcodeBuildMCP/Simurgh) driven by Fable; physical-device steps owner-gated.
1. Deploy push-backend (test env) with WP0 env: Redis, Stripe test keys, provisioning key.
2. **Paid loop (sim):** Stripe test checkout → webhook → entitlement refresh → key vended → real OpenRouter completion on-sim with the managed key → usage telemetry lands → balance row updates.
3. **Cap loop:** exhaust a $0.50-limit test sub-key → OpenRouter rejects → paywall appears; ledger 402 path exercised with overage OFF.
4. **Trial loop (physical device — App Attest doesn't run on sim):** fresh sign-in → trial issued → second attempt on same device → 409.
5. Restart/redeploy the backend mid-test → keys/credits survive (Redis proof).
- **Evidence:** commands + screenshots into `docs/test-runs/2026-07-XX-managed-ai-credits-e2e/`. Per the standing dogfood done-bar, no "done" report without the full loop run.

## Sequencing & estimates
| Order | Package | Est. | Parallel with |
|---|---|---|---|
| now | WP0 (owner externals; file ASC entitlement request first) | owner time | everything |
| 1 | WP1 Redis stores | 1–2 days | WP3 |
| 1 | WP3 iOS key plumbing | 1–2 days | WP1 |
| 2 | WP2 key vend + trial (sensitive) | 2–3 days | — |
| 3 | WP4 UX + paywall | 2 days | — |
| 4 | WP5 E2E + deploy | 1–2 days + owner device session | — |

Nothing here touches the Phase-1 dogfood lanes (thread UX, relay, approvals) — different write-sets; safe to run alongside.

## Risks / stop-rules
- **ASC External Purchase Link entitlement approval latency** — file in WP0 week 1; if rejected/stalled, ship trial + BYOK first (no purchase UI), paywall Add-credits hidden behind a server flag.
- **Apple commission framework lands mid-build** — pricing survives single-digit fees; if a 20%+ fee is imposed, revisit price point before launch (design note §3).
- **OpenRouter provisioning API drift** — WP2 must re-verify request/response against live docs before coding (context7/web), same discipline as vendor-CLI adapters.
- **Redis atomicity** — if the minimal client (`redis_client.go`) can't express atomic deduct cleanly, escalate to Fable before adding a dependency.
