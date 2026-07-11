# Agent read-first index

Tool-agnostic entry point for Claude Code, Codex, Cursor, and Kimi working in this repo.

**Owner hub:** [`docs/STATUS_LEDGER.md`](STATUS_LEDGER.md) — current priority, branches, gates.

> **Docs purge 2026-07-10 (owner-directed):** docs/ was aggressively reduced to the minimum set.
> If a doc is not in the tree, do not cite it and do not recreate it — git history holds
> everything. The 2026-07-10 pair below supersedes ALL prior strategy/roadmap framing.

---

## Read order by task

| Task | Read in order |
|------|----------------|
| **Any non-trivial work** | [`AGENTS.md`](../AGENTS.md) → [`ARCHITECTURE.md`](../ARCHITECTURE.md) §0.1 + §4.1 → this file → `STATUS_LEDGER.md` |
| **Direction / scope / what matters now** | [`docs/product/2026-07-10-lancer-daily-driver-definition.md`](product/2026-07-10-lancer-daily-driver-definition.md) — owner-confirmed SSOT |
| **How to build each feature (+ competitor reference code)** | [`docs/product/2026-07-10-lancer-agent-build-roadmap.md`](product/2026-07-10-lancer-agent-build-roadmap.md) |
| **Chat UI implementation patterns** | [`docs/product/2026-07-09-chat-ui-port-map.md`](product/2026-07-09-chat-ui-port-map.md) |
| **Receipt/contract build spec** | [`docs/plans/2026-07-07-lancer-layers-0-3-implementation-spec.md`](plans/2026-07-07-lancer-layers-0-3-implementation-spec.md) §C, B3–B4 |
| **Siri / iOS 27 lane** | [`docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md`](plans/2026-07-09-siri-ios27-all-in-roadmap.md) + [`docs/plans/2026-07-09-wwdc-ios-capability-inventory.md`](plans/2026-07-09-wwdc-ios-capability-inventory.md) |
| **Feature backlog (sortable)** | [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md) |
| **iOS UI / design system** | [`.claude/rules/ios-ui-and-gallery.md`](../.claude/rules/ios-ui-and-gallery.md) |
| **Daemon / dispatch changes** | [`docs/agent-contract.md`](agent-contract.md) → run `vendor-cli-adapter-audit` before editing `daemon/lancerd/dispatch.go` |
| **Verification before "done"** | `lancer-verification-gate` skill |
| **Launch / TestFlight** | [`docs/PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md) (frozen until post-fork) |
| **Live device loop** | [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md) + [`docs/product/OWNER_RELAY_TEST_GUIDE.md`](product/OWNER_RELAY_TEST_GUIDE.md) |
| **Known bugs** | [`docs/KNOWN_ISSUES.md`](KNOWN_ISSUES.md) |
| **Production P0 burn list** | [`docs/product/2026-07-09-production-readiness-gaps.md`](product/2026-07-09-production-readiness-gaps.md) |

## Standing instructions

1. **Verify against the live repo.** Distrust any agent/tool self-report — re-check with
   `git log`, `git status`, `gh pr list`, and the actual file.
2. **Ask before large multi-deliverable work** when scope is ambiguous.
3. **Worktree merges:** diff/rebase against current tip — never whole-file `cp` across worktrees.
4. **Physical device:** never reinstall to a paired phone without asking (wipes pairing state).
5. **Product framing (2026-07-10):** personal daily-driver first; wedge = "don't watch your
   agents — govern them"; chat is the vehicle, not the differentiator; deep iOS-native
   integration is core identity. The MVP exit bar and phase order live in the definition doc.
6. **Frontend (owner decision 2026-07-11, supersedes the 07-10 "W0.A kept" note):** the app
   shell is the **Codex-built Workspaces shell** (master line `80407933..b472ffd3`, restored
   by PR #75): Workspaces root + avatar/search/+ chips + docked "Plan, ask, build…" composer,
   **no tab bar**. Canonical visual reference: `docs/design/cursor-reference/` (matches
   Cursor's mobile app, system light/dark). The W0.A `CursorStyle` shell is **retired** —
   do not resurrect it. **No agent deletes frontend chrome without a fresh owner ask.**
7. **Do not wholesale-merge `amazing-mayer-246fef`** — cherry-pick only.
8. **Deployment target:** iOS **26.0** — not 27, until the Phase 3 raise decision.
9. **Permanent safety rules:** no Siri approve intent · no Face ID reintroduction ·
   voice-approve rejected · fail-closed mutating kinds · never "all clear" on stale relay data.
10. **`AskUserQuestion`:** max 4 options per question.

## Skills to invoke

| When | Skill |
|------|-------|
| Starting non-trivial work | `lancer-context-onboarding` |
| Before claiming done | `lancer-verification-gate` |
| Touching `dispatch.go` | `vendor-cli-adapter-audit` |
| Parallel agent work | `lancer-parallel-handoff` |
| Reading past sessions | `agent-session-history-reader` |
