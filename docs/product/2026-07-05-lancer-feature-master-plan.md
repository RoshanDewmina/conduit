# Lancer Feature Master Plan — Phase 1 (Audit + Decisions)

Compiled: 2026-07-05
Status: **This is now the single source of truth for Lancer feature scope.** Supersedes the July-4
product-strategy batch (purged from disk 2026-07-06; disposition summary in §1).
Phase 1 only — feature inventory, decisions, rationale, IA, wireframe links. Phase 2 (data models,
APIs, daemon/relay changes, Xcode 27 + Device Hub testing strategy) is a separate follow-up pass,
scoped after this doc is reviewed. No code changes made as part of this doc.

**Scope of this audit:** the 2026-07-04/07-05 batch of Codex, Claude Code, and Cursor sessions only
(per explicit scope decision) — not the earlier June 2026 design-audit history, which is treated as
already-settled/archived.

---

## 1. Source of truth + document disposition

No single existing doc already has the shape this plan needs (final feature inventory + rationale +
implementation status + wireframe links), so this is a **new canonical doc**, not an edit of an
existing one.

**Purged 2026-07-06:** the July-4 product-strategy batch (`2026-07-04-lancer-strategy-feature-source-of-truth.md`, `away-mode-master-consolidation`, `whole-app-consolidation`, `mobile-primary-pivot-feature-inventory`, `second-opinion-away-mode-v1`, `codex-verification-brief`, `codex-verification-results`, `2026-07-05-mobile-native-ai-coding-workflow-research.md`, proof-to-ship visual board) — content folded into §3–§8 below; do not recreate.

| Doc | Disposition |
|---|---|
| **This doc** | ✅ Canonical, living. Update here going forward. |
| `docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md` | Kept, referenced. Canonical **wireframe/audit process record**. |
| `docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md` | Kept, referenced. 105-item wireframe-tracking checklist. |
| `docs/design-audit/2026-07-05-final-cursor-wireframe-handoff.md` | Kept — canonical IA/handoff doc. |
| `docs/design-audit/lancer-workflows-2026-07-05/audit-findings/*.md` (4 files) | Kept, referenced. Raw audit findings; resolved in §4. |
| `docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities.md` | Kept — iOS 27/WWDC reference. |
| `docs/product/FEATURE_BACKLOG.md` | Kept — sortable feature tracker (companion to this doc). |

---

## 2. Approved Information Architecture (confirmed, resolves 3 open discrepancies)

**3 visible roots: Home, Workspaces, Settings.** Not 4. This resolves three items the research
agents found still open:

- **Workflow 02's "four roots" language is a documentation error** — align it to the 3-root IA in
  the next wireframe touch-up. The **target shipped shell** is the Cursor-style app under
  `AppFeature/CursorStyle/` (`CursorAppShell`, 3 roots: Home / Workspaces / Settings via
  `LANCER_CURSOR_SHELL` / `LANCER_CURSOR_SHELL_LIVE`). The legacy `LancerSidebarView` sidebar /
  Command Home remains in-tree but is **deprecated** — an implementation gap, not design truth.
  `ARCHITECTURE.md` §4.1 is flagged for correction to match.
- **Inbox folds into Home** (as an Away Digest ledger row grouping, not a separate root) — confirmed
  correct direction; the real app hasn't migrated yet (implementation gap, not a design ambiguity).
- **Governance folds into Settings** (Security & Approvals section, not a separate root) — confirmed
  correct direction; the real app hasn't migrated yet either (same kind of gap, not ambiguity).

Contextual (non-root) surfaces, unchanged from the handoff doc: Work Thread, Review/Diff, Machine
detail, Onboarding, Search (see below).

**Search/Command consolidation (resolves Discrepancy: Command Palette vs Work Search):** these
merge into **one** "Search" surface for V1. A phone doesn't need two separate jump-to-things
patterns (a Cmd+K-style command launcher *and* a status-filtered mission search) — that's desktop
power-user clutter transplanted onto mobile with no demonstrated mobile-specific need. Ship one
Search/Recent surface that does both (fuzzy jump-to-mission/repo/machine *and* status-filtered work
search); revisit a distinct command-mode toggle post-MVP only if usage data shows people actually
want quick-action-without-navigation on a phone.

---

## 3. The proof-to-ship pivot: resolved, not adopted as a rewrite

Per the approved direction, the wireframed ledger IA stays the locked baseline. Auditing the
proof-to-ship research (`docs/product/2026-07-05-mobile-native-ai-coding-workflow-research.md`,
the Codex `019f32b3` differentiation brainstorm) against the already-wireframed feature set shows
**why this is the right call on the evidence, not just deference to what's already built**:

| Proof-to-ship concept | Wireframed baseline equivalent | Verdict |
|---|---|---|
| Mission Contract | Thin Launch Contract (chips: repo, machine, agent, run mode, proof expected, interrupt rules) | **Same functional shape, different name.** No new feature needed. |
| Decision Capsule / Risk Card | Question Cards + the Review/Diff approval sheet (risk-tiered) | **Same functional shape.** No new feature needed. |
| Proof Bundle / Proof Reel | Proof Suite (thin proof object, `lancer.proof` schema, video Proof Reel) | **Same functional shape**, already the most-praised differentiator across every doc read in this audit. No new feature needed. |
| Return-to-Desk Packet | "Return-to-desk context," already folded into Work Thread | **Same functional shape** — but flagged below as worth a design check, not a net-new build. |
| Away Mode Live Activity (selective) | Minimal Away Status + landscape Dynamic Island research (§ iOS 27 doc) | **Same functional shape**, "selective not per-agent" is already an existing product rule (Live Activity Risk Meter was explicitly cut for being too much). No new feature needed. |
| Needs-Me Queue as Home | Away Digest ledger (Needs you / Today / Yesterday, attention-first ordering) | **Rejected as a rename.** Both solve the same triage-first problem; the ledger model is further along (already wireframed, audited, and fix-passed by Cursor) with no demonstrated gap the Needs-Me framing closes that the ledger doesn't already cover. Restructuring Home now would throw away completed, audited work for a relabeling. |

**Conclusion:** the "pivot" is mostly the same product under different vocabulary — which is itself
useful confirmation that the wireframed direction converged on the right shape independently. The
one open action item, not a rewrite: **verify Return-to-Desk context is a real, coherent single
recap surface** (what changed, what's proven, what's still open) rather than scattered across Work
Thread without a dedicated moment — flag for the Phase 2 design pass on Work Thread, not a new
feature.

**Carried forward as a first-class principle** (from the second-opinion doc, reconfirmed by the
Codex `019f32b3` differentiation session): **proof alone is not the differentiator — Cursor/Codex
mobile are converging on it too. Governance (the policy engine, hash-chained audit, cross-vendor
dispatch) is what's structurally hard for a single-vendor competitor to copy.** Every MVP/Post-MVP
call below weighs this: a feature that only demonstrates proof-parity scores lower on
differentiation than one that demonstrates governance or cross-vendor structural advantage.

---

## 4. Resolved discrepancies and open audit findings (P0/P1)

Using product judgment (no hard date/customer gate), these are now **decided**, not open:

| # | Finding | Decision | Rationale |
|---|---|---|---|
| D1 | Onboarding account gate at step 2 (mandatory) | **Adopt audit finding**: defer/skip — default silently to local pairing; "Add a Lancer account" becomes a skippable, low-weight option, ideally moved out of the blocking sequence entirely | Forcing an account decision between "pairing succeeded" and "you can use the app" adds friction for exactly the persona most likely to bail: a developer evaluating the product. Self-hosted/offline is a fully working zero-account mode. |
| D2 | Onboarding policy step: 3 equal-weight preset cards | **Adopt audit finding**: ship "Balanced" pre-selected with one-tap "Continue with recommended," "Customize" secondary | A first-run user has no context yet for what "risky writes" means; an uninformed 3-way choice is friction without comprehension. |
| D3 | Onboarding notifications at step 5 (last) | **Adopt audit finding**: move to step 3, immediately after pairing succeeds | If the first real approval fires before notification permission is granted, the single most important moment in the app silently fails to reach the user — worse than asking one screen earlier. |
| D4 | Repo Playbook drawn only in Launch Setup, absent from Workspaces despite every doc saying it belongs there | **Add explicit Playbook row to Workspace Detail** | Multiple docs (including the artifact's own flow text) already claim this placement; the wireframe just hasn't caught up. Fixes a real navigation dead-end. |
| D5 | 7 checklist items marked "wireframed" but absent from any artifact (Policy Diff Review, Cross-host policy check, On-device audit digest, Account Switcher, Vendor Performance, Continuous Cross-Vendor Audit, Compliance Export) | **All 7 are correctly Post-MVP** (see §6 for individual evaluation) — reclassify checklist status from "wireframed" to "post-MVP, deferred design" rather than leaving it wrong | None of the 7 are needed for a solo-user V1 loop; several are explicitly team-tier (Compliance Export, Vendor Performance needs cross-user data volume Lancer won't have at launch). |
| D6 | Work Thread ships chat bubbles in real code; locked spec says Cursor-dark transcript with artifact-rich activity rows, not a chat clone | **Adopt the locked spec** — this is a real implementation gap to close in build, not a design ambiguity | Chat-bubble framing undersells Lancer's actual differentiator (structured artifacts: proof, diffs, to-dos) by making it look like a generic chat client. |
| D7 | Cross-vendor "Verify…" drawn as an equal-weight, optional third rail action even for high-risk proof | **Make Verify primary/first (or require dismissing it) for high-risk proof**, not equal-weight-and-last | Inconsistent with the proportional-friction rule already applied to approvals (high-risk approvals force full review). The one safeguard specifically designed for high-risk proof shouldn't be the easiest one to skip. |
| D8 | Proof Suite gap screens (Device Matrix, Visual Diff, Auto Bug Replay) don't visibly gate "Mark Ready" | **Make the "Proof ready" card an explicit rollup** ("3 of 4 checks passed, 1 needs review") that reflects sub-check state, not a set of disconnected drill-ins | Matches the already-stated product rule "no approval success state until confirmed" — extends it to "no ship state past an unresolved check." |
| D9 | Duplicate "Export audit log" rows (Settings vs. Ship & History's "Account" screen) + a second duplicate audit-log row within Settings itself | **Settings owns the canonical Account/Billing/audit-export surface.** Ship & History's panel becomes only a contextual "Share this mission's proof" action that deep-links to Settings for everything else. Within Settings, merge the two audit-log rows into one (Security & Approvals owns it; Data group's row becomes an export action on the same log, not a second entry point) | Two screens claiming ownership of the same data is a trust risk (which one is real?), not just a style inconsistency. |
| D10 | Fast Follows' "Verify with…" (optional second opinion) uses identical visual anatomy to Review/Diff's mandatory approval sheet | **Give cross-vendor Verify a distinct accent/badge** ("second opinion" styling) so it can't be mistaken for the governance gate | A user must be able to tell "another AI thinks this looks off" apart from "this requires your approval to proceed" at a glance. |
| D11 | Two independent timeline components (Flight Recorder in Ship & History, Time-Travel/Fork in Fast Follows) where every doc says there should be one | **Consolidate into one Flight Recorder screen**; Fork/Export become actions on that same timeline | Matches what the handoff doc already claims is true ("lives inside Flight Recorder, not as a root") — the wireframe just hasn't caught up. |
| D12 | Container/dev-service status ambiguous: captioned as a Home "Away Status" row but titled/scoped like a Workspace-detail screen | **Workspace-scoped** (ties to a specific repo's docker-compose), not a Home row type | It's inherently per-repo state; showing it on Home implies a fleet-wide dashboard Lancer deliberately avoids elsewhere. |
| D13 | Inline git blame drawn only in Platform & Gaps, but its own text says it belongs in Work Thread's Changed Files | **Move it into Work Thread's Changed Files card spec**; remove as a standalone Platform & Gaps panel (cross-reference only) | Matches the artifact's own stated intent; fixes a reachability gap. |
| D14 | Changed Files Review shows free-text "Ask for changes," not per-hunk/line-anchored comments, despite the checklist calling for "hunk-level" | **Confirmed as an intentional V1 simplification.** Full PR-review-style threaded hunk comments are real complexity (threading, resolve/unresolved state, notification fan-out) for marginal V1 mobile value — free-text is sufficient for "send this back with context." Hunk-anchored comments are Post-MVP if usage shows demand. | Applying the differentiation/clutter lens: threaded hunk comments are parity with GitHub mobile, not a Lancer-specific advantage — not worth the build cost at V1. |
| D15 | Mobile attachments composer only shows a generic "+" pill; the 4-type picker (photo/screenshot/video/voice) itself is never drawn | **Finish the existing spec** — draw the actual picker UI. This is completing a committed V1-core item, not evaluating a new one. | — |
| D16 | Billing shows one PRO/FREE badge; checklist explicitly warns not to flatten the dormant IAP (`isPro`) and the real Stripe cloud entitlement (`hasCloudEntitlement`) into one status | **Wireframe should show the real, single mechanism** (the Stripe cloud entitlement) and the dormant IAP should either be wired to gate something real or removed before ship — this is a correctness gap, tracked in §7, not a design choice | Shipping a UI that implies one billing status when two independent, uncoordinated mechanisms exist underneath is a trust/correctness risk. |
| D17 | Onboarding copy never explains what "your machine" means before the pairing command | **Add one line above the pairing card**: "Lancer connects to the coding-agent CLIs already running on your computer." | Closes a real first-run comprehension gap for a first-time evaluator. |
| D18 | 3 weak/unverified Mobbin citations (Tailscale/Termius with no URL, Manus diff missing a URL, MLS/Zocdoc/Finimize/NYTimes partially unlinked) | **Wireframe polish, not a strategic decision** — replace or drop the Tailscale/Termius citation, add the missing Manus URL, drop the unconfirmed Zocdoc/Finimize references | Low stakes, mechanical fix; noted here so it isn't lost. |
| D19 | Two API-framing errors still uncorrected in some artifacts (Platform & Gaps' widget panel still says "full-screen widgets" instead of citing `.systemExtraLargePortrait`; View Annotations framed as iOS-27-new in 3 artifacts instead of "modifier is iOS 18.4+, guidance is new") | **Apply the same one-line correction** already used correctly in sibling artifacts | Mechanical consistency fix; both corrections are already independently confirmed accurate in the refreshed iOS 27 doc (§ this plan's iOS research pass). |

All 19 are small, mechanical, or already-evidence-backed calls — none require new user research to
resolve. Fold D1–D19 into the workflow docs (`docs/design-audit/workflows/*.md`) and the wireframe
artifacts on the next design touch-up pass; not done as part of this doc to avoid a second giant
diff before you've reviewed the decisions themselves.

---

## 5. Final feature inventory — MVP

Every item below is **already locked as V1 core** across the July-4 docs and the wireframe
checklist, wireframed, and not in dispute. Listed compactly; see the workflow docs for full detail.
"Wireframe" column links to the artifact/workflow doc; `[fixed]` marks items whose spec needs the §4
correction before it's fully accurate.

| Feature | Category | Wireframe | Notes |
|---|---|---|---|
| Away Launch Composer + thin launch contract | Core loop | `workflows/03-work-thread.md`, `artifacts/04-launch-setup.html` | = "Mission Contract" per §3 |
| Mobile attachments (photo/screenshot/video/voice) | Core loop | `artifacts/04-launch-setup.html` | needs picker UI drawn — D15 |
| Share Sheet / Universal Link Intake | Core loop | `artifacts/04-launch-setup.html` | — |
| Smart Default Target | Core loop | `artifacts/02-home.html`, `artifacts/03-workspaces.html` | — |
| Away Mode Setup (per-repo progressive checklist) | Core loop | `artifacts/04-launch-setup.html` | — |
| Repo Playbook | Core loop | `artifacts/04-launch-setup.html` `[fixed: D4]` | add Workspace Detail row |
| Agent Readiness Check | Core loop | `artifacts/04-launch-setup.html` | — |
| Run Mode / Run Budget / Interruption Budget (Mission Defaults sheet) | Core loop | `artifacts/04-launch-setup.html` | — |
| Minimal Away Status | Core loop | `artifacts/03-work-thread.md`, `artifacts/02-home.html` | = "Away Mode Live Activity" per §3 |
| Question Cards + Question Ladder | Core loop | `artifacts/05-work-thread.html` | full 5-stage ladder needs drawing (finding 1.4) |
| Away Digest as Home (needs-you-first ordering, all-clear state) | Core loop | `artifacts/02-home.html` | = "Needs-Me Queue" per §3, kept as-is |
| Proof Suite base layer (test/changed-file/screenshot cards) | Core loop | `artifacts/05-work-thread.html` | — |
| Proof Reel / Proof Timeline | Core loop | `artifacts/05-work-thread.html` | — |
| Visual Diff Review, Device Matrix Proof, Auto Bug Replay | Core loop | `artifacts/05-work-thread.html` (Proof Suite gap panels) | must gate "Mark Ready" — D8 |
| Mobile QA Annotation (Tap-to-Isolate, Vision-mask upgrade) | Core loop | `artifacts/05-work-thread.html` | headline differentiator |
| Error Autopsy | Core loop | `artifacts/05-work-thread.html` | — |
| Stop and Snapshot / Emergency Stop (UI) | Core loop | `artifacts/06-review-diff.html`, `artifacts/10-settings.html` | atomic backend RPC is a correctness gap, §7 |
| Git / PR / Merge Actions | Core loop | `artifacts/08-ship-history.html` | — |
| Flight Recorder + Work Search | Core loop | `artifacts/08-ship-history.html` `[fixed: D11]` | consolidate w/ Time-Travel/Fork |
| Web Preview / Preview Cockpit | Core loop | `artifacts/05-work-thread.html` | — |
| Contextual Command Cards | Core loop | `artifacts/05-work-thread.html` | — |
| Changed Files Review (free-text, not hunk-anchored) | Core loop | `artifacts/06-review-diff.html` | hunk-anchoring is Post-MVP — D14 |
| Voice Everywhere (dictation) | Core loop | footnote across artifacts | `SpeechAnalyzer`/`SpeechTranscriber` already iOS 26 baseline, no iOS 27 wait needed |
| Light Automations (4 variants) | Core loop | `artifacts/05-work-thread.html` | only 2 of 4 drawn (finding 1.8) — finish on next pass |
| Provider Capability Badges | Core loop | `artifacts/03-workspaces.html` | — |
| Governance/Security: risk-tiered biometric gate | Governance | `artifacts/06-review-diff.html`, `10-settings.html` | **already shipped in real code** (commit `695d2440`); degrade-open gap tracked §7 |
| Governance/Security: policy engine, hash-chained audit (existing) | Governance | `10-settings.html` | shipped; the actual moat per §3 |
| Governance/Security: drift detector | Governance | `10-settings.html` | shipped |
| Workspaces (repo-first, replaces Machines) | Whole-app | `artifacts/03-workspaces.html` | data-model decision (repo-first vs. host-first) still genuinely open, see §9 |
| Onboarding / Pairing (code-only, Cursor-simple) | Whole-app | `artifacts/01-onboarding.html` | sequencing fixed per D1-D3, D17 |
| Settings (native grouped list) | Whole-app | `artifacts/10-settings.html` | scope-creep fixed per D9 |
| LancerMac (thin desktop companion) | Whole-app | shipped, Phase A+B done | keep thin, no scope growth |
| Final IA: Home / Workspaces / Settings, 3 roots | IA | `2026-07-05-final-cursor-wireframe-handoff.md` | confirmed §2 |

---

## 6. Post-MVP fast-follows (evaluated)

Each scored against: user value / mobile-specific / clutter risk / differentiation / verdict.

| Feature | User value | Mobile-specific? | Clutter risk | Differentiation | Verdict |
|---|---|---|---|---|---|
| **Cross-Vendor Second-Agent Review** | High — a second, different vendor critiques a result without re-solving it | No, but risk-gated (only appears for high-risk missions) keeps mobile surface small | Low, gated by risk score | **Highest of any Post-MVP item** — structurally impossible for a single-vendor competitor | **Ship first, right after MVP** — not bundled with the other 6 team/governance items below |
| **Proof Becomes Regression / Regression Watchlist** | Medium-high, compounds over time (proof from run N re-validates on run N+1 if a flow is touched) | No | Low (a list) | Medium — reinforces the proof moat | Post-MVP, second priority |
| Policy Diff Review (governance changes reviewed like code diff, 2nd-approver) | Real for teams with >1 admin | No | Adds a governance sub-screen | Ties to the audit-chain moat | Post-MVP, **team-tier gated** — a solo user has no "second approver" |
| Cross-host policy-consistency check | Real once 2+ machines have divergent policy | No | Low (a banner) | Ties to governance moat; no competitor supports multi-own-machine consistency | Post-MVP — most V1 users will have 1 paired machine |
| On-device audit digest (Foundation Models digest of audit.log) | Nice-to-have narration | Yes — on-device compression is a genuine mobile value-add | Low | Medium, contingent on Foundation Models reliability | Post-MVP — needs real audit volume to be worth summarizing, which V1 users won't have yet |
| Account Switcher (multi-account hot-swap per vendor) | Real for people juggling multiple CLI provider accounts | Somewhat — quick switching is a mobile-native convenience | Low (a settings row) | Matches a real competitor gap (Orca) but unvalidated demand for Lancer's own users | Post-MVP |
| Vendor Performance comparison (revert-rate by vendor) | Needs real cross-vendor usage data to mean anything | No | Adds a stats screen | Would be real if data existed | **Weakly justified at V1** — no user will have enough runs across enough vendors early on; revisit only once usage data exists |
| Continuous Cross-Vendor Audit (unbroken hash chain across a vendor switch) | Real, compliance-adjacent | No | Mostly backend; UI is one status row | Ties directly to the audit-chain moat | Post-MVP, depends on Cross-Vendor Review shipping first |
| Compliance Export (signed audit report for a compliance/security buyer) | Real, but specifically for team/enterprise buyers | No | One settings row + export flow | Directly serves team-tier upsell | Post-MVP, **team-tier feature**, not solo V1 |
| Terminal / SSH escape hatch (already built, unwired) | Real safety-valve for power users | Actively anti-mobile-native | High risk of "phone IDE" scope creep if promoted | **Negative if marketed** — contradicts "not a phone IDE" positioning | **Keep hidden, off primary nav, unmarketed** — no change, already correctly scoped |
| Watch app packaging (embed in iOS target) | Real — currently reaches zero users despite being fully built/tested | Yes (it's Watch) | Low, it's a distribution fix not new UI | Neutral | Post-MVP — this is a CI/embedding decision, not a design decision; low effort, real payoff, do soon |
| True Handoff (Apple Continuity to exact Mac hunk/proof) | Medium | Yes (native OS feature) | Low | Medium | Post-MVP |
| Run Comparison (single-vendor A/B) | Medium | No | Low | Medium | Post-MVP |
| Weekly Away Mode Digest | Medium, retention lever | No | Low | Low-medium | Post-MVP |
| Clips (Builder.io) integration, `lancer.proof` schema | Speculative | No | Medium (new external dependency) | Medium if Clips adoption is real | Post-MVP, re-evaluate once V1 core Proof Suite ships |
| Siri status query / multi-step decision batch / View-Annotations question cards | Real but gated by EU/China Siri AI delay (open-ended, per iOS 27 doc) and "App Intents mandatory" being unconfirmed | Yes | Low | Medium | Post-MVP fast-follow, explicitly not a launch gate (matches existing "don't gate V1 on iOS 27 Siri" call) |
| StandBy / full-screen (`.systemExtraLargePortrait`) widget states | Real, corrected per iOS 27 doc | Yes | Low | Medium | Post-MVP |
| Mobile Command Palette | See §2 — merged into Search for V1 | — | — | — | **Merged, not rejected** — revisit a distinct command-mode only if usage data shows demand |
| Inline mobile git blame | Real, small | No | Low | Low | Post-MVP, small — move into Work Thread's Changed Files per D13 when built |
| Dependency/security alert intake (Dependabot/Snyk → mission) | Real, matches a competitor pattern (Factory) | No | Low | Medium | Post-MVP |
| Container/dev-service status | Real, workspace-scoped per D12 | No | Low | Low | Post-MVP |
| Slack/Teams-triggered missions | Real, matches a competitor gap | No | Medium (new integration surface) | Medium | Post-MVP |
| Whole-thread context ingestion (paste a full thread, not one message) | Real | No | Low | Low-medium | Post-MVP, cheap to build alongside the composer |
| Team / Client Proof Layer (share links, weekly report, approval delegation) | Real for team-tier | No | Medium | Medium | Post-MVP, team-tier |
| On-device Foundation Models features (contract drafting, proof narration, semantic diff captions, multimodal clarifying cards) | Real, consolidated into one "on-device compression" pattern already | Yes — this is the definition of mobile-native, on-device-only capability | Low (already consolidated from 5 ideas into 1 pattern) | High — genuinely hard for a non-Apple-platform competitor to match | Post-MVP fast-follow, good candidate for first iOS-27-gated release once iOS 27 GAs |

---

## 7. Correctness / security gaps — must fix before MVP ships (not feature decisions)

These aren't features to evaluate; they're gaps between what's designed/claimed and what the real
code does. Carried forward from the July-4 verification docs, still open per this audit:

| Gap | Severity | What's wrong |
|---|---|---|
| Biometric gate degrades open on no-passcode devices | **P0 — security** | Returns success instead of throwing on unlocked devices with no passcode set, allowing high-risk actions with zero friction. |
| Emergency Stop is not atomic | **P0 — correctness** | Loops client-side per-run instead of one daemon-side RPC; LancerMac's Pause-All button is wired as a disabled stub waiting on this same primitive. |
| JWT verification is HS256-only | **P1 — security** | RS256/ES256 (JWKS) path referenced in docs doesn't exist in code yet. |
| Dormant `StoreKit` "Lancer Pro" IAP gates nothing | **P1 — correctness** | Built and wired to gate nothing real, while a separate, real Stripe cloud entitlement (`hasCloudEntitlement`) does the actual gating — two uncoordinated billing mechanisms is a real bug risk, not just a UI simplification (D16). |
| Watch app not embedded in iOS target | **P1 — distribution** | Fully built, tested 4-tab watchOS app reaches zero real users because it's not embedded in the shipping app target — a packaging/CI fix, not a design task. |
| Daemon single pairing-slot ceiling | **P2 — architecture** | One relay pairing system-wide; a new pairing silently orphans the old one. Existing architecture, not a regression, but worth a conscious decision before team-tier multi-device use grows. |

None of these block writing this plan, but all should be resolved (or explicitly re-scoped) before
calling V1 "done" — recommend folding into Phase 2's implementation plan as P0/P1 backend tasks
alongside the daemon/relay changes already planned for that pass.

---

## 8. Rejected

| Feature | Rationale |
|---|---|
| Needs-Me Queue as Home (restructure) | See §3 — same job as the existing ledger, no demonstrated gap it closes; would discard completed/audited work for a relabeling. |
| Evidence Inbox (original, rich version) | Redundant with the Away Launch Composer; the composer already does this job. |
| Heavy Mission Draft / plan-mode clone | Redundant with the agent's own planning; duplicates work the CLI agent already does. |
| Live Activity Risk Meter | Explicit owner cut ("not the best"). |
| Haptic Risk Language | Explicit owner cut. |
| Live Shadow Second Opinion (always-on background second-agent watcher) | Explicit owner cut; also very high build/inference cost for unclear value over the risk-gated Cross-Vendor Review. |
| Break-Point-Aware Nudges (Calendar/Focus-aware review timing) | Explicit owner cut. |
| Live Camera Bug Repro | Explicit owner cut; moonshot, high cost. |
| Big Agent Router ("send to best agent" auto-routing) | Superseded by Smart Default Target, which already solves the practical case with far less complexity. |
| Frustration Signal Missions (rage-click detection auto-proposes a mission) | Cut in Claude's own redundancy pass; speculative behavioral-signal feature with no validated demand and real false-positive risk. |
| Micro Editor | **Conflicts with a locked `ARCHITECTURE.md` non-goal** ("no local iOS code editor"). |
| Developer App Drawer | **Conflicts with the locked 3-root Cursor shell IA** (§2). |
| Vendor Performance comparison | Weakly justified at V1 — see §6, no data volume to be meaningful yet; not a hard reject, a "not yet." |
| Multi-Agent Showdown (compare 2+ vendors side by side) | Only resurfaces if Cross-Vendor Review ships and shows demand for >2-way comparison; premature to design now. |

---

## 9. Still genuinely open (not resolved by this audit — needs your input, not evidence)

- **Workspaces data model: repo-first vs. host-first.** This is a real architecture decision (not a
  rename) that changes `FleetStore`/`FleetView`'s underlying schema. The wireframe assumes repo-first;
  the current shipped code is host-first. Needs an explicit decision before Phase 2 can spec the data
  model changes.
- **Billing consolidation**: which of the 3 uncoordinated mechanisms (dormant IAP, real Stripe cloud
  entitlement, planned $25/mo solo · $99/mo team subscription) is the one that ships — this is a
  business decision, not a design one, and blocks the Settings billing row's final copy.
- **Verify Return-to-Desk is a real, single recap surface** (§3) — a small design check, not a
  strategic question, but needs eyes before Phase 2.

---

## 10. What's NOT in this doc (Phase 2, pending your review of the above)

Per the approved phasing: data models, API/RPC signatures, daemon and relay changes, iOS
implementation tasks, dependencies/build order, Xcode 27 + Device Hub testing strategy, and detailed
edge-case/accessibility/privacy/performance treatment are a separate follow-up pass once you've
reviewed and either approved or adjusted the decisions in §2–§8 above.
