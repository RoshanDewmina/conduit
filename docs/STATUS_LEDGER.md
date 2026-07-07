# Lancer status ledger

**Last updated:** 2026-07-06 (Cursor shell design reconciliation)  
**Open this file first** for current priority, canonical doc map, and branch status.

Living trackers (update these when code or tests change):

- Implementation status → [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md)
- Feature scope decisions → [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md)
- Full feature list with wireframe links → [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md)
- Agent read order → [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md)

---

## Current priority (engineering)

**Tier 0 exit bar** (Codex `019f3763`, 2026-07-06): prove the **live Cursor shell** end-to-end against real `lancerd`:

> pair → dispatch prompt → receive approval → approve/deny → follow-up/continue

| Step | Status (2026-07-06) | Evidence |
|------|---------------------|----------|
| Live shell wiring | Partial — `LANCER_CURSOR_SHELL_LIVE=1` + `CursorShellLiveBridge` | gap matrix, `ARCHITECTURE.md` §0.1 |
| Simulator UI test | PASS | `codex/tier-0-live-cursor-shell` |
| Relay E2E harness | **PASS** — `relay-approval-e2e.sh` through live Cursor shell | [`test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`](test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) |
| Physical device governed loop | Owner-gated | [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md), [`docs/test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`](test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) |

**Freeze until Tier 0 is proven:** Away Launch Composer, Proof Suite/Reel, Git/PR ship actions, Siri fast-follow merge, further IA redesign, Watch embed.

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
| 105-item wireframe checklist | [`docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md`](design-audit/2026-07-05-feature-checklist-for-wireframing.md) | — |
| Away workflow spec | [`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`](product/2026-07-04-v1-paid-away-workflow-spec.md) | — |
| Launch / TestFlight gates | [`docs/PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md) | — |
| Agent working rules | [`AGENTS.md`](../AGENTS.md) + [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md) | — |
| Session archaeology (Jul 3–6) | [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md) | Re-running full transcript audits |

**Removed 2026-07-06:** V1_* specs, `LAUNCH_AUDIT`, July-4 product strategy batch, `superpowers/`, competitive-intelligence, wwdc26 audit, design-redo, design-questions, old sidebar handoffs, `workflows/01-06`, `screenshots/current`, `lancer-ui-prototype/`, pre–Jul-6 `test-runs/`. Scope lives in master plan + `FEATURE_BACKLOG.md`.

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

**Git status:** Most Jul 4–5 design-audit and product files are **on disk but untracked** (`??`). They exist — commit when ready.

**Screenshot evidence (2026-07-06):**

- [`docs/test-runs/user-ready-tier0-2026-07-06/`](test-runs/user-ready-tier0-2026-07-06/) — 21/21 `CursorAppShellExhaustiveTests` attachments
- [`docs/test-runs/composer-verify-2026-07-06/`](test-runs/composer-verify-2026-07-06/) — live + mock composer/work-thread captures

---

## Branch / merge status

| Item | State |
|------|-------|
| `master` | Cursor shell in-tree; live bridge partial; iOS **26.0** deployment target; wave2 merged (`7c5c0b0d` PR #30) — `CursorAppShellExhaustiveTests` 20/20 PASS |
| `codex/tier-0-live-cursor-shell` | Tier 0 wiring + P0 BiometricGate + atomic emergency stop (commits on branch) |
| Siri Phase 2 (`cursor/siri-phase2-fixes-9257`, PRs #16/#24) | Implemented, **not merged** — iOS 27 APIs vs iOS 26 target (`ARCHITECTURE.md` §0.1) |
| `claude/amazing-mayer-246fef` | Active worktree — **do not wholesale merge** |
| Jul 4–5 docs + wireframes | Untracked on `master` — index here, commit separately |

---

## Open P0 / P1 (correctness)

From master plan §7 + gap matrix + Codex `019f2f6d`:

| Gap | Severity | Status |
|-----|----------|--------|
| BiometricGate fail-open (no passcode) | P0 | **Fixed** on `codex/tier-0-live-cursor-shell` (`531685b6`); owner device validation pending |
| Emergency stop non-atomic | P0 | **Fixed** on same branch — daemon latch + RPC |
| JWT HS256-only | P1 | Open |
| StoreKit IAP dormant vs Stripe cloud entitlement | P1 | Open — billing reconciliation needed |
| Watch app not embedded in iOS target | P1 | Open |
| Daemon single relay pairing slot | P2 | Open by design |
| Audit chain no external anchor | P1 | Open |

---

## Owner-gated checklist

1. **Tier 0 live loop** on physical iPhone + running `lancerd` — [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md)
2. **APNs lock-screen approve (5c)** — screen recording required
3. **Jul 21 validation gate** — run or explicitly descope
4. **Commit untracked Jul 4–6 docs** — after reviewing this SSOT set

---

## Jul 5–6 session delta (vs morning audit `77003d0c`)

Afternoon additions folded into this ledger:

- Owner confirmed Codex sessions `019f2dec`, `019f2ebf`, `019f2f6d`, `019f3763` as authoritative feature-finalization chain
- Wireframe bundle `lancer-workflows-2026-07-05` indexed as canonical design artifact (was missing from morning audit's living trackers)
- Gap matrix updated: P0 fixes landed on `codex/tier-0-live-cursor-shell`; Cursor shell merged to master with live bridge begun
- `ARCHITECTURE.md` §0.1 refreshed (2026-07-06): Cursor live shell, Siri parked, biometric gap noted

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
- Write to main `command-center` repo under `docs/` — **awaiting owner approval before git commit**
