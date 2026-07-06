# Agent read-first index

Tool-agnostic entry point for Claude Code, Codex, Cursor, and Kimi working in this repo.

**Owner hub:** [`docs/STATUS_LEDGER.md`](STATUS_LEDGER.md) — current priority, branches, deadlines.

---

## Read order by task

| Task | Read in order |
|------|----------------|
| **Any non-trivial work** | [`AGENTS.md`](../AGENTS.md) → [`ARCHITECTURE.md`](../ARCHITECTURE.md) §0.1 + §4.1 → this file |
| **Feature scope / what to build** | [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md) |
| **Feature backlog (sortable)** | [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md) |
| **What's shipped vs mocked** | [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md) |
| **Wireframes / UI design** | [`docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md`](design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md) → `artifacts/` |
| **105-item design checklist** | [`docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md`](design-audit/2026-07-05-feature-checklist-for-wireframing.md) |
| **Away Mode workflow** | [`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`](product/2026-07-04-v1-paid-away-workflow-spec.md) |
| **iOS UI / design system** | [`.claude/rules/ios-ui-and-gallery.md`](../.claude/rules/ios-ui-and-gallery.md) |
| **Daemon / dispatch changes** | [`docs/agent-contract.md`](agent-contract.md) → run `vendor-cli-adapter-audit` skill before editing `daemon/lancerd/dispatch.go` |
| **Verification before "done"** | `lancer-verification-gate` skill (`.claude/skills/` or `~/.codex/skills/`) |
| **Launch / TestFlight** | [`docs/PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md) |
| **Live device loop** | [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md) |
| **Known bugs** | [`docs/KNOWN_ISSUES.md`](KNOWN_ISSUES.md) |
| **Prior session context** | [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md) |

---

## Standing instructions (encoded from Jul 3–6 audits)

These recur across owner prompts — follow without being re-told:

1. **Verify against the live repo.** Distrust another agent's or tool's self-report ("done", "merged", "verified"). Re-check with `git log`, `git status`, `gh pr list`, and the actual file before relying on a transcript or doc.

2. **Ask questions before large multi-deliverable work** when scope is ambiguous — especially cross-tool handoffs and doc synthesis.

3. **Worktree merges:** diff/rebase against current tip — **never** whole-file `cp` across worktrees.

4. **Physical device:** never reinstall to a paired physical device without asking first (wipes pairing state).

5. **Design checklist claims:** verify against HTML wireframes (`grep` artifacts), not status captions in markdown alone.

6. **Tier 0 before Tier 2:** do not expand Away Mode / Proof Suite / Git ship actions until live Cursor shell proves pair → dispatch → approval → continue (`019f3763`).

7. **Do not wholesale-merge `amazing-mayer-246fef`** — cherry-pick only.

8. **Product positioning:** phone steers and approves — **not** a phone IDE. Governance + cross-vendor dispatch is the moat; proof is necessary parity.

9. **Deployment target:** iOS **26.0** in `project.yml` — not 27, despite older doc wording.

10. **Claude Code `AskUserQuestion`:** max **4 options** per question — split larger lists into paired questions.

---

## Authoritative Codex sessions (feature finalization)

When reconciling feature scope, these four threads win over chat memory:

| Session | Output |
|---------|--------|
| `019f2dec-b131-7fa2-b96a-ca5dca31b095` | Away Mode with proof; pricing; Jul 21 gate |
| `019f2ebf-513f-73e0-91ff-13cd74e0a412` | V1 feature prune; `v1-paid-away-workflow-spec.md` |
| `019f2f6d-e4d8-7c11-aa1f-532e5d28c506` | Verification results; P0/P1 gaps |
| `019f3763-db95-77e0-bee2-6fae3224a4cf` | Tier 0 pivot; consolidated status |

---

## Skills to invoke

| When | Skill |
|------|-------|
| Starting non-trivial work | `lancer-context-onboarding` |
| Before claiming done | `lancer-verification-gate` |
| Touching `dispatch.go` | `vendor-cli-adapter-audit` |
| Parallel agent work | `lancer-parallel-handoff` |
| iOS design handoff | `lancer-design-handoff` |
| Reading past sessions | `agent-session-history-reader` |

---

## Do not cite

- `docs/LANCER_PROJECT_DOSSIER.md` — archived
- `docs/V1_PRODUCT_SPEC.md`, `docs/V1_STATE_AND_ACTION_MATRIX.md`, `docs/V1_IMPLEMENTATION_PLAN.md` — **purged 2026-07-06**; use master plan + `FEATURE_BACKLOG.md`
- `docs/LAUNCH_AUDIT-2026-06-18.md` — **purged 2026-07-06**; use `STATUS_LEDGER.md` + `PUBLISH_READINESS_CHECKLIST.md`
- July-4 `docs/product/2026-07-04-*` strategy docs as living scope — **purged 2026-07-06** (except `v1-paid-away-workflow-spec.md`); superseded by master plan
- `docs/superpowers/` — **purged 2026-07-06**; use `KNOWN_ISSUES.md`, gap matrix, or `PUBLISH_READINESS_CHECKLIST.md`
- `docs/competitive-intelligence/` — **purged 2026-07-06**
- `docs/wwdc26-lancer-opportunity-audit/` — **purged 2026-07-06**; iOS 27 reference kept in `docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities.md`
- `docs/design-redo/` — **purged 2026-07-06**; wireframes in `lancer-workflows-2026-07-05/` are canonical
- `docs/design-questions/` — **purged 2026-07-06**
- `docs/product/chat-device-test-checklist.md` — **purged 2026-07-06**; rerun against live Cursor shell per `LIVE_LOOP_RUNBOOK.md`
- `docs/product/2026-07-05-lancer-proof-to-ship-visual-board`, `docs/product/2026-07-05-mobile-native-ai-coding-workflow-research.md` — superseded; see master plan §3
- `docs/lancer-ui-prototype/`, `docs/CLEANUP-REPORT.md` — removed
- `docs/design-audit/workflows/`, `screenshots/`, `handoff-*`, `command-home-ledger`, `work-thread-cursor`, `lancer-core-wireframes`, `proof-to-ship-wireframes`, `onboarding-motion-prototype`, `multi-machine-relay-2026-07-01` — removed intermediate bundles
- Pre–Jul-6 `docs/test-runs/*` — **purged 2026-07-06**; current evidence under `docs/test-runs/user-ready-tier0-2026-07-06/`, `docs/test-runs/composer-verify-2026-07-06/`, `docs/test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`
- Legacy sidebar / Command Home as current navigation — **deprecated**; Cursor shell (`AppFeature/CursorStyle/`) is canonical
- Tab bar / `enum Tab` as navigation truth — vestigial
