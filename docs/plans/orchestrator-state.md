# Orchestrator state — Fable swarm dashboard

**Updated:** 2026-07-11 PM (update after every merge or blocker; this file is compaction insurance)
**Phase:** 1 — dogfood MVP. Phase 0 CLOSED: PR #69 merged (`fd7b56d5`); stashes + checkpoint/backup refs dropped; w0a branch deleted.

## Phase 1 lanes (dispatched 2026-07-11, Grok 4.5 xhigh via cursor-agent)

| Lane | Branch / worktree | Scope | Write-set | Status |
|---|---|---|---|---|
| A | `feat/p1-tool-cards` / `.worktrees/p1-tool-cards` | Tool-call cards + working-indicator enum (§1.1 step 3) | CursorThreadTranscriptModel/Mapper, CursorWorkThreadView, new CursorToolCall* | dispatched |
| B | `feat/p1-policy-matrix` / `.worktrees/p1-policy-matrix` | Happier permission-matrix SHAPE → Go policy tests (§1.2) | daemon/lancerd `*_test.go` only | dispatched |
| D | `feat/p1-thread-order` / `.worktrees/p1-thread-order` | Thread-list ordering by AttentionReason (§1.3) | CursorThreadAttention, CursorWorkspaceThreadListView | dispatched |
| C (queued) | — | Re-port master-line M1 question card onto W0.A shell (from #69 integration) | CursorWorkThreadView + new card file | blocked by A (same write-set) |
| queued | — | Stop ladder + derived-offline (§1.1 step 5) | chat internals | after A |
| queued | — | Unread read-cursor (§1.3) | thread view + list | after A+D |
| queued | — | SiriRelevanceCoordinator warning cleanup (25 warnings) | Lancer/SiriRelevanceCoordinator.swift | Composer, anytime |

**Integration decision #69 (see STATUS_LEDGER):** W0.A owns the iOS UI; master's parallel
Workspaces-shell line dropped from tree (git history keeps it); master backend kept incl.
questions M3 daemon + relay wire fixes; dispatch-cwd fix re-applied.

**Tier 0 re-proof prep:** daemon redeployed from tip (running); signed device build SUCCEEDED;
checklist `docs/test-runs/2026-07-11-tier0-owner-checklist.md`; **blocked: phone 557A7877
unavailable — owner must connect it, then install + ping.**

**CI reviewer:** cursor-agent headless, `claude-opus-4-8-thinking-high`, prompt via stdin
(first run failed on MAX_ARG_STRLEN, fixed `a8101d9c`). After first successful run, verify
Cursor dashboard shows plan usage, not metered — if metered, STOP CI reviews and tell owner.
**Roadmap SSOT:** `docs/product/2026-07-10-lancer-agent-build-roadmap.md` · direction:
`docs/product/2026-07-10-lancer-daily-driver-definition.md`

## Model slugs (verified via `agent models`, 2026-07-11)

| Role | Slug |
|---|---|
| Default implementer | `grok-4.5-xhigh` (Cursor Grok 4.5; `grok-4.5-fast-xhigh` when speed matters) |
| Mechanical edits / first-pass review summaries | `composer-2.5` |
| Fallback + sensitive + repo-skill work | Claude `sonnet` high via Agent tool |
| CI stage-4 reviewer | `claude-opus-4-8-thinking-high` via cursor-agent headless (`CURSOR_API_KEY` repo secret; NOT Grok, cross-model independence) |
| Cursor auth | logged in (sidewhinder2k3@gmail.com); `gh` auth OK (RoshanDewmina, repo=conduit) |

**Standing constraint (owner, 2026-07-11): subscription-only billing.** No pay-per-use API
keys anywhere in the pipeline; all model calls ride Cursor Ultra or the Claude subscription.
Metered-only tool → propose subscription-backed alternative + ask owner. After the first CI
review run, verify the owner's Cursor dashboard shows it as plan usage, not metered — if
metered, STOP CI reviews and tell the owner.

## Phase 0 log (2026-07-11)

| Item | Status | Evidence |
|---|---|---|
| **Empty-tree tip repaired** | DONE | `1c102940` had tree `4b825dc6…` (the empty tree — wiped index at commit time). Backup ref `backup/w0a-empty-tree-tip`; `git reset --mixed bd4bcef8`; recommitted as `4c350a52` (869 files in tree) |
| Dispatch cwd fix landed | DONE | `4c2634df` fix(daemon): fail-fast missing/non-dir cwd (`resolveDispatchCWD`); `go test ./...` ok (lancerd 44s + policy); Fable full-diff review passed (sensitive path) |
| Scorched-wipe worktree removed | DONE | worktree was clean, on master; branch `feat/frontend-scorched-wipe` tip `80407933` verified ancestor of master → `-D` deleted. Frontend KEPT = W0.A CursorStyle shell (present on this branch) |
| build_sim green | DONE | XcodeBuildMCP build_sim SUCCEEDED 29.8s on `feat/chat-overhaul-w0a` (post-repair). Warnings only: `Lancer/SiriRelevanceCoordinator.swift` unused `try?` / var-never-mutated ×25 — queued as Composer cleanup |
| REVIEW_STANDARDS.md | DONE | created, seeded from ENGINEERING_PROCESS review bar + verdict JSON contract |
| claude-code-action workflow | DONE (blocked on secret) | `.github/workflows/claude-review.yml`; **owner must `gh secret set ANTHROPIC_API_KEY -R RoshanDewmina/conduit`** — repo has no secrets |

## Branch / worktree state

- `feat/chat-overhaul-w0a` — active, tree clean (only untracked: owner's personal
  `visual-first-communication.md`, left alone). Ahead of origin; push pending.
- Stashes kept until W0.A merges: `stash@{0}` (W0.A 19-file checkpoint), `stash@{1}` (pairing
  fixes) — content believed landed in branch commits; verify before dropping.
  `checkpoint/w0a-dogfood-pre-scorched-wipe` + `backup/w0a-empty-tree-tip` refs kept.
- Stale worktrees under `.worktrees/` (a3-r*, chat-*, w0-*, push-gaps, fix-daemon-flake) —
  audit each for unmerged work before removal; NOT part of Phase 0 scope.
- `claude/amazing-mayer-246fef`: cherry-pick only, never wholesale-merge.

## Owner-gated queue

1. Merge `feat/chat-overhaul-w0a` → master (ui risk + daily-loop change ⇒ owner gate).
2. Tier 0 / 5c device re-proof on current tip (physical phone).
3. `gh secret set ANTHROPIC_API_KEY` for the PR reviewer workflow.
4. Start `docs/dogfood-log.md` (one line/day).

## Decisions log

- 2026-07-11: dispatch.go dirty change was pre-existing dogfood-fix work found in tree during
  repair; landed as its own commit after Fable full-diff review + go gate (no argv/vendor
  changes, cwd validation only — vendor-cli-adapter-audit concerns not implicated).
- 2026-07-11: stashes NOT popped — branch commits supersede; keep as safety until merge.

## Phase 1 lanes (next — spec before dispatch)

Six pieces per roadmap §1: pairing/trusted machines · thread list · chat thread finesse ·
composer · push approvals incl. lock screen · emergency stop. Disjoint write-sets; shared
files (Package.swift, project.yml) land first as tiny solo commits.
