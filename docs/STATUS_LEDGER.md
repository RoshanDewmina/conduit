# Lancer status ledger

**Last updated:** 2026-07-08  
**`master` tip:** `23563bb5` — open this file first for current priority, canonical doc map, and branch status.

> **Sidebar/Command Home IA refs scrubbed from active docs 2026-07-08** (A2 audit, PR #53); historical
> evidence files may still mention the old shell. Cross-check any "Fixed"/"Shipped"/"PASS" claim here
> against `git log` / `gh pr list` — this ledger was refreshed 2026-07-08 against live `master`.

Living trackers (update these when code or tests change):

- Implementation status → [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md)
- Feature scope decisions → [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md)
- Full feature list with wireframe links → [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md)
- Agent read order → [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md)

---

## Current priority (engineering)

**Tier 0 exit bar** (Codex `019f3763`, 2026-07-06): prove the **live Cursor shell** end-to-end against real `lancerd`:

> pair → dispatch prompt → receive approval → approve/deny → follow-up/continue

| Step | Status (2026-07-08) | Evidence |
|------|---------------------|----------|
| Live shell wiring | **Shipped** — `LANCER_CURSOR_SHELL_LIVE=1` + `CursorShellLiveBridge`; Layers 0–3 merged (#34) | gap matrix, `ARCHITECTURE.md` §0.1 |
| Simulator UI test | PASS | `codex/tier-0-live-cursor-shell`, wave merges #28–#32 |
| Relay E2E harness | **PASS** — `relay-approval-e2e.sh` through live Cursor shell | [`test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`](test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) |
| Physical device governed loop (D0.2) | **PASS** (owner, 2026-07-08 evening) — host audit `approve` + `deny` | [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md); prior morning FAIL [`test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md) |
| APNs lock-screen approve (5c) | **PASS** — force-quit + lock Approve (`79137ae4…`) and Reject (`461bc3e0…`) | [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md); #52 + uncommitted content-hash echo/race fixes |

**Unfrozen by D0.2 / 5c PASS:** Away Launch Composer, Watch embed, wholesale A3 surface rebuild merge (lanes R1–R4 open as PRs #63–#66) — still need review/merge; content-hash fix files still dirty (commit next).

**Unfrozen / merged (2026-07-07–08):** proof receipts + home attention (Layers 0–3, #34); approve-and-remember (#47); deep-link auth/billing paths (#48); Siri entity intents D2/D3 (#46), I1 (#38), I2 (#41), I3 (#43), E3 voice-answer (#45); question/Ladder pipeline E1 (#49) + QuestionCardView E2 (#44); gated git/PR ship actions G (#50); Proof Reel H1 (#51); 5c lock-screen delivery fix (#52); A2 dead-code cleanup (#55); settings feedback rows (#56); A3 design tokens (#57); observed sessions J1–J2 (#54, #58); Return-to-Desk J3 (#59); push `/secret-request` + `/question` routes (#62); append-retry offline fix (#19); daemon/conn test deflake (#60, #61).

**Do not wholesale-merge** `.claude/worktrees/amazing-mayer-246fef` — deletion-heavy diff; cherry-pick verified slices only. See [`docs/design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md`](design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md).

---

## Business / validation deadline

From Codex `019f2dec` (2026-07-04), confirmed unrun by `019f2f6d`:

| Gate | Target | Deadline | Local evidence |
|------|--------|----------|----------------|
| Away Mode pricing validation | 10 contacted / 5 repeat-use / 3 paying / 1 team | **2026-07-21** | None found in repo |
| Design-partner interviews | Per [`docs/validation-cycle-v1.md`](validation-cycle-v1.md) | — | Plan only, not completed |

**Pricing target (unreconciled):** $25/mo solo · $99/mo team vs dormant StoreKit IAP + live Stripe cloud entitlement.

---

## Canonical doc map

> **Doc purge (2026-07-06):** pre–Jul-5 planning artifacts (V1_* specs, `LAUNCH_AUDIT`, July-4 strategy batch, `superpowers/`, competitive-intelligence, wwdc26 audit, design-redo, design-questions, older `test-runs/`) were removed from the repo. Scope and evidence live in the table below — do not recreate deleted paths.

| Question | Read this | Not this |
|----------|-----------|----------|
| What is Lancer / V1 scope? | [`ARCHITECTURE.md`](../ARCHITECTURE.md) §0.1 + §4.1 | Purged V1_* specs, July-4 strategy batch, legacy sidebar screenshots |
| Feature scope + rationale | [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md) | Purged July-4 strategy docs (master plan §1 is the disposition record) |
| Shipped vs mocked vs gap | [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md) | Stale "mock only" comments in code |
| Sortable feature backlog | [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md) | Re-deriving from chat transcripts |
| Implementation dispatch (lanes + worktrees) | [`docs/product/2026-07-06-implementation-dispatch-plan.md`](product/2026-07-06-implementation-dispatch-plan.md) | Ad-hoc agent prompts |
| Owner relay test session | [`docs/product/OWNER_RELAY_TEST_GUIDE.md`](product/OWNER_RELAY_TEST_GUIDE.md) | Re-reading full runbook each time |
| Wireframes / UI design | [`docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md`](design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md) | Superseded intermediate wireframe bundles (removed) |
| Screenshot evidence (Tier 0) | [`docs/test-runs/user-ready-tier0-2026-07-06/`](test-runs/user-ready-tier0-2026-07-06/), [`docs/test-runs/composer-verify-2026-07-06/`](test-runs/composer-verify-2026-07-06/) | — |
| Device proof (D0.2 / 5c) | [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (**PASS**), morning FAIL [`test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md), [`test-runs/2026-07-08-5c-root-cause.md`](test-runs/2026-07-08-5c-root-cause.md) | — |
| 105-item wireframe checklist | [`docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md`](design-audit/2026-07-05-feature-checklist-for-wireframing.md) | — |
| Away workflow spec | [`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`](product/2026-07-04-v1-paid-away-workflow-spec.md) | — |
| Launch / TestFlight gates | [`docs/PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md) | — |
| Agent working rules | [`AGENTS.md`](../AGENTS.md) + [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md) | — |
| Session archaeology (Jul 3–6) | [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md) | Re-running full transcript audits |

**Removed 2026-07-06 (declared); stragglers actually deleted 2026-07-08 (A2 audit):** V1_* specs, `LAUNCH_AUDIT`, July-4 product strategy batch, `superpowers/`, competitive-intelligence, wwdc26 audit, design-redo, design-questions, old sidebar handoffs, `workflows/01-06`, `screenshots/current`, `lancer-ui-prototype/`, pre–Jul-6 `test-runs/`. Scope lives in master plan + `FEATURE_BACKLOG.md`.

---

## Design & wireframe index

**Primary bundle:** [`docs/design-audit/lancer-workflows-2026-07-05/`](design-audit/lancer-workflows-2026-07-05/)

| Artifact | Path |
|----------|------|
| Master report | `MASTER-REPORT.md` |
| Onboarding | `artifacts/01-onboarding.html` |
| Home / Away Digest | `artifacts/02-home.html` |
| Workspaces | `artifacts/03-workspaces.html` |
| Launch setup / contract | `artifacts/04-launch-setup.html` |
| Work Thread / Proof | `artifacts/05-work-thread.html` |
| Review & Diff | `artifacts/06-review-diff.html` |
| Fast follows | `artifacts/07-fast-follows.html` |
| Ship & History | `artifacts/08-ship-history.html` |
| Platform gaps | `artifacts/09-platform-gaps.html` |
| Settings | `artifacts/10-settings.html` |
| Combined + interactive | `artifacts/11-combined-all-workflows.html`, `12-interactive-prototype.html` |

**A3 Cursor design reference (2026-07-08):** committed `c461d56b` — screen-map + light/dark screenshots for token baseline (#57).

**Screenshot evidence (2026-07-06):**

- [`docs/test-runs/user-ready-tier0-2026-07-06/`](test-runs/user-ready-tier0-2026-07-06/) — 21/21 `CursorAppShellExhaustiveTests` attachments
- [`docs/test-runs/composer-verify-2026-07-06/`](test-runs/composer-verify-2026-07-06/) — live + mock composer/work-thread captures

---

## Branch / merge status

| Item | State |
|------|-------|
| `master` (`23563bb5`) | Layers 0–4 largely merged (Jul 7–8 batch); iOS **26.0** deployment target; live Cursor shell + Siri I1–I3 on tree |
| Layers 0–3 integration | **Merged** — PR #34 (`2e33b434`…`c626e29a` stack): proof receipts, home attention, Siri D1 entities, relay delivery fixes |
| Tier 0 wave (#27–#32) | **Merged** — Cursor shell polish, live approval sync (#32), UITest stabilization |
| Layer 4 lanes | **Merged** — #44–#51 (E1/E2/G/H1), #45 (E3), #46–#48 (D2/D3, A4, deeplink), #52 (5c fix) |
| Layer 5–6 / J lanes | **Merged** — #54–#59 (J1 observed sessions, J2 UI, J3 Return-to-Desk), #55–#57 (A2 cleanup, settings feedback, A3 tokens) |
| Push / reliability (Jul 8) | **Merged** — #19 append retry, #60 daemon deflake, #61 conn-state deflake, #62 push routes |
| Siri Phase 2 (I1–I3) | **Merged** — #38 (StartAgentRun), #41 (CoreSpotlight), #43 (iOS 27 App Intents); iOS 27 APIs gated `swift(>=6.4)` |
| A3 surface rebuild (R1–R4) | **Open** — PRs #63 (Workspaces), #64 (Composer), #65 (Thread/PR/diff), #66 (Lancer surfaces + Review) |
| `codex/tier-0-live-cursor-shell` | Superseded by #28–#34 merges; branch may still exist — treat `master` as source of truth |
| `claude/amazing-mayer-246fef` | Active worktree — **do not wholesale merge** |
| Jul 4–5 design-audit bundle | On disk; A3 reference screenshots committed `c461d56b`; remainder may still be untracked |

---

## Open P0 / P1 (correctness)

From master plan §7 + gap matrix + Codex `019f2f6d`:

| Gap | Severity | Status |
|-----|----------|--------|
| BiometricGate fail-open (no passcode) | P0 | **Moot — removed entirely** on `master` 2026-07-07; nothing left to validate |
| Emergency stop non-atomic | P0 | **Fixed** — daemon latch + RPC (tier-0 branch, merged via #28/#34) |
| Tier 0 D0.2 / 5c physical-device gate | P0 | **PASS** (owner, 2026-07-08 evening) — [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md); commit content-hash fixes still pending |
| JWT HS256-only | P1 | Open |
| StoreKit IAP dormant vs Stripe cloud entitlement | P1 | Open — billing reconciliation needed |
| Watch app not embedded in iOS target | P1 | Open |
| Daemon single relay pairing slot | P2 | Open by design |
| Audit chain no external anchor | P1 | Open |

---

## Owner-gated checklist

1. **Tier 0 live loop** on physical iPhone + running `lancerd` — [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md) — **PASS** (2026-07-08 evening); optional screen recording archive
2. **APNs lock-screen approve (5c)** — **PASS** — [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md); **commit** content-hash / race-fix dirty files
3. **Jul 21 validation gate** — run or explicitly descope
4. **Review + merge A3 R1–R4 PRs** (#63–#66) — Tier 0 gate closed

---

## Jul 7–8 session delta (vs Jul 5–6 ledger)

Major merges on `master` since the prior ledger refresh:

- **Layers 0–3** (#34): `lancer.proof/v0` receipt pipeline, needs-you-first home attention, IntentsKit Siri entities (D1), relay approval-delivery fixes
- **Layer 4**: question/Ladder events E1 (#49), QuestionCardView E2 (#44), voice-answer Siri E3 (#45), gated ship actions G (#50), Proof Reel H1 (#51)
- **Layer 0 polish**: approve-and-remember A4 (#47), entity intents D2/D3 (#46), deeplink auth/billing fix (#48)
- **Siri**: I1 Phase 2 resurrect (#38), I2 CoreSpotlight (#41), I3 iOS 27 App Intents (#43)
- **Cleanup + design**: A2 legacy UI/docs delete (#53, #55), A3 design tokens (#57), settings feedback (#56)
- **Observed sessions + continuity**: J1 relay mirror (#54), J2 "On your Mac" UI (#58), J3 Return-to-Desk (#59)
- **5c + reliability**: lock-screen decision delivery fix (#52); push `/secret-request` + `/question` (#62); append retry (#19); test deflake (#60, #61)
- **Owner D0.2 device proof** morning FAIL [`test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md); evening **PASS** [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md)
- **Docs**: device-proof results + terminal research (`566dd156`, `7e991c6f`), A3 design reference (`c461d56b`)

Prior Jul 5–6 delta (still accurate): Codex sessions `019f2dec`–`019f3763` chain, wireframe bundle indexed, `ARCHITECTURE.md` §0.1 Cursor shell refresh.

---

## Authoritative Codex session chain

| Session | Role |
|---------|------|
| `019f2dec` | Away Mode with proof; Question Ladder; Clips/`lancer.proof`; pricing + Jul 21 gate |
| `019f2ebf` | Feature-by-feature V1 prune → `v1-paid-away-workflow-spec.md` |
| `019f2f6d` | Independent verification — 21/21 CONFIRMED; validation unrun |
| `019f3763` | Tier 0 engineering pivot; consolidated status; freeze Tier 2 |

Full inventory: [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md)

---

## SSOT implementation decisions (this pass)

Plan defaults applied (owner approved execution without alternate answers):

- Extend morning Claude audit — promote scratchpad to `docs/audits/`
- Split doc set: this ledger + `AGENT_READ_FIRST` + `FEATURE_BACKLOG`
- Feature scope: Tier 0 tracker + full master-plan inventory
- Write to main `command-center` repo under `docs/`
