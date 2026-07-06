# Codex Verification Results

Prepared: 2026-07-04
Source: Codex session `019f2f6d-e4d8-7c11-aa1f-532e5d28c506` ("Verify consolidation claims"),
responding to `docs/product/2026-07-04-codex-verification-brief.md`
Status: independent second-pass verification, complete — corrections already applied to the
underlying docs (see "Corrections applied" below)

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only; its confirmed facts are folded into that doc.

## Headline result

**All 21 fact-checking items (Tiers 1-3): CONFIRMED**, with two nuances that changed the record
(see below) and several stale file paths that didn't change the underlying claims. **Tier 0
(strategic second opinion): Codex independently reached the same governance-differentiation
conclusion, but stated the scope call more sharply** — and reconfirmed zero evidence either
validation gate has ever been run.

## Tier 0 — strategic verdict (verbatim significance, paraphrased here)

> "Tier 0 does not change the factual claim that none of the six local competitor repos has
> Lancer's exact stack: policy engine + hash-chained audit + emergency stop. But I would not treat
> 'governance is the moat' as settled customer value. The stronger conclusion is: governance is
> Lancer's clearest technical differentiation, but only becomes sellable if packaged as a narrow
> Away Mode / proof / risk-control loop. The current docs still read too broad if taken wholesale."

And, separately:

> "I also found no local evidence that either validation gate has been run: no interview results,
> tracking sheet, paid-pilot records, repeat-use evidence, or team-customer proof.
> `docs/validation-cycle-v1.md:1-5,68-90` is still an interview plan, not completed validation."

**This is the single most important finding from this whole verification pass.** Two independent
research efforts (this session's, and Codex's fresh re-derivation) agree: the technical
differentiation argument holds, but the product direction as currently documented is broader than
what's actually validated or arguably sellable, and the customer-need question remains completely
untested. See "What this means for planning" below.

## Corrections applied to the underlying docs (2026-07-04)

1. **`ARCHITECTURE.md`** §0.1 (line 74) and §10.2 (line 757) — corrected from "biometric gate
   removed for V1" to "reinstated 2026-07-04, `695d2440`, risk-tiered for high/critical decisions,"
   with the residual no-passcode degrade-open gap noted explicitly.
2. **`docs/competitive-intelligence/reports/current-product-baseline.md`** — same correction applied
   at all 4 locations Codex identified (the feature table, §4's "Notable regression," §7's weakness
   list, §9's contradiction table).
3. **`docs/competitive-intelligence/data/competitors.jsonl`** — added a `happier` row (previously
   entirely untracked) and upgraded the `happy` row from "unknown"/"claimed" fields to code-verified
   facts, per this session's repo clones.
4. **`docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md`** — added a
   correction note above the Prioritization section flagging that Micro Editor, Developer App
   Drawer, and broad Automations for Code (listed there as "later") are actually
   CONFLICTS_WITH_NONGOAL per both consolidation docs, not just deferred.
5. **`docs/product/2026-07-04-lancer-whole-app-consolidation.md`** §6 — corrected the overstated
   "billing gates nothing" framing: only the one-time StoreKit IAP is dormant; the separate cloud/
   hosted-agent Stripe entitlement (`PurchaseManager.hasCloudEntitlement`) genuinely gates real
   functionality and should not have been conflated with the dormant IAP.

## Tier 1 verdicts (all CONFIRMED, exact citations from Codex)

1. Biometric gate reinstatement — `695d2440` on `master`; `ApprovalDecisionAuth.swift:15-18`;
   wired at `InboxView.swift:29-50`, `InboxViewModel+Live.swift:62-81`, `ApprovalRelay.swift:137-168`.
   Watch bypass at `AppRoot.swift:2428-2436`.
2. Degrade-open hole — `BiometricGate.swift:16-24`.
3. Non-atomic emergency stop — `AppRoot.swift:1591-1603` (client loop); `MenuBarContentView.swift:49-57`,
   `ManagementView.swift:109-117` (disabled LancerMac stubs); no daemon-side all-runs RPC found.
4. Watch app not embedded — `project.yml:138-143`; iOS target embeds only widgets at `:128-137`.
5. JWT HS256-only — `daemon/push-backend/auth.go:46-60`.
6. No audit-chain external anchor — `daemon/lancerd/audit.go:135-180`.
7. Single pairing slot — `relaypair.go:13-25,47-70`; entry points at `main.go:74`, `pair_rpc.go:59`,
   `relay_install_helper.go:109`. Note: `KNOWN_ISSUES.md:408-422` says a related restart bug was
   fixed, but the single-slot ceiling itself remains by design.
8. **Dormant paywall — CONFIRMED WITH CORRECTION.** `showingPaywall` never set true
   (`AppRoot.swift:203,374-375`); `isPro` used only for Settings/Billing display
   (`SettingsView.swift:602-627`, `BillingView.swift:43-55`). But the separate Stripe cloud
   entitlement *does* gate hosted-agent operations — don't conflate the two.
9. iOS 27/26 deployment-target discrepancy — `ARCHITECTURE.md:6,159` vs. `project.yml:13,231,269`
   and `Package.swift:19`.
10. Nav lock — `ARCHITECTURE.md:253-276`, confirmed with nuance: 5 visible sidebar roots plus
    `.thread(id)` as a depth destination (6 enum cases total, still no tab bar).
11. Non-goals list — `ARCHITECTURE.md:136-149`.

## Tier 2 verdicts (all CONFIRMED, some wording/path corrections)

12. Omnara plaintext storage — `models.py:257-281`. Wording correction: "zero crypto hits
    repo-wide" was too strong (dependencies include crypto libraries generally); no *content* E2EE
    path found, which is the load-bearing claim.
13. Omnara no Live Activity — confirmed, no `ios/` folder, no ActivityKit hits.
14. Happy's real encryption + zero governance — `encryption.ts:87-128,148-228`;
    `permission-resolution.md:10-17,59-85`.
15. Vibe Kanban comparison gap — `task.rs:23-33`, `workspace.rs:41-54`; confirmed no shipped
    multi-attempt comparison component (some side-by-side *diff* view hits exist, but not attempt
    comparison).
16. Happier share links — confirmed, path corrected to `.../sharing/components/`
    (`SessionShareDialog.tsx:98-104`, `PublicLinkDialog.tsx:52-65,255-283`).
17. Happier's Tauri-wrapped desktop client — `tauri.conf.json:6-11,21-40`, `README.md:128-176`.
18. OpenCode plugin API match — `packages/plugin/src/index.ts:222-269` vs.
    `opencode_plugin_install.go:59-88`.

## Tier 3 verdicts (all CONFIRMED — see "Corrections applied" above for the fixes)

19. Missing Happier competitor entry — fixed.
20. Stale baseline doc claims — fixed.
21. Pivot-inventory internal contradiction — fixed.

## What this means for planning

Given both Codex's and this session's independent conclusions converge on the same two points,
this should directly shape the next phase:

1. **Narrow the build scope.** Don't plan an implementation across the full 9-area whole-app sweep
   at once. The recommended frame (Codex's words): "a narrow Away Mode / proof / risk-control loop."
2. **The customer-need question is still completely open.** No amount of further code research or
   competitive analysis substitutes for the design-partner interviews in `docs/validation-cycle-v1.md`
   or the Away Mode pricing validation gate — both remain unrun. This should be raised explicitly
   before committing significant build effort, not treated as a formality to route around.
