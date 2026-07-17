# Worktree cleanup report — 2026-07-17

Survey of all 82 worktrees present at session start (command-center + one stray simurgh
cluster). 27 were fully-merged-and-clean and have been **deleted** (worktree + local branch —
their content is safely preserved in `origin/master`'s history). Everything else is listed
below with a reasoning-backed recommendation; nothing in these groups was touched.

## Merged into master this session (1)

- `fix/pairing-state-disagreement` — docs-only investigation report (F3 pairing repro, no code
  fix, no defect found), explicitly flagged "orchestrator to review" in its own CHANGELOG entry.
  Landed as `2425c3ca`. Its worktree still exists but its content is now redundant — safe to
  delete like the Group A branches below.

## Group A — stale, content already superseded (recommend: delete branch + worktree)

Read each diff in full before excluding — these are NOT "unmerged work," they're duplicates.
Their functionality already exists on `master` under different commit hashes, so merging them
would only reintroduce dead/duplicate code.

| Worktree | Branch | Why superseded |
|---|---|---|
| `.worktrees/a3-r1-workspaces` | `spec/a3-r1-workspaces` | Targets `AppFeature/CursorStyle/` — deleted by commit `6b97da65` (2026-07-11) |
| `.worktrees/a3-r2-thread` | `spec/a3-r2-thread` | Same — `CursorStyle` module retired |
| `.worktrees/a3-r3-composer` | `spec/a3-r3-composer` | Same |
| `.worktrees/a3-r4-lancer` | `spec/a3-r4-lancer-surfaces` | Same |
| `.worktrees/codex-approval-queue-fix` | `codex/fix-approval-queue-sync` | Identical fix already landed via PR #118 (`approvalRetired` hook) under commit `7aba5b7b` |
| `.worktrees/codex-relay-rekey-safety` | `codex/fix-relay-rekey-safety` | Superseded — master's `peer_joined` handler already resets `sendSeq` post-derive AND has a `sendGen` generation-mint mechanism this branch doesn't even know about |
| `.worktrees/codex-pr114-device-proof` | `codex/pr114-device-proof` | Superseded — master already uses `chatRepo.hydratedEventCursor(...)` at the exact call sites this branch touches |
| `.worktrees/fix-daemon-flake` | `fix/daemon-conversations-append-flake` | The exact test-flake fix (`m.Method != ""` notification filter) is already in master's `conversation_rpc_test.go` |
| `.worktrees/fix-iso8601-tests` | `fix/iso8601-protocol-tests` | Already merged — its own diff's CHANGELOG line says "PR #148" |
| `.worktrees/push-gaps` | `fix/push-secret-request-and-question` | `postQuestionPush`/`/question` push-backend endpoint already fully present on master under a different original commit |
| `.worktrees/simurgh-pilot` | `feat/simurgh-pilot` | Superseded by this session's own Simurgh-adoption PR #156 (same `.mcp.json`/`AGENTS.md` config, different/older version) |
| `.worktrees/simurgh-dogfood-a` | (detached, same commit as `simurgh-pilot`) | Same |
| `.worktrees/simurgh-dogfood-b` | (detached, same commit as `simurgh-pilot`) | Same |
| `.worktrees/fix-pairing-state-disagreement` | `fix/pairing-state-disagreement` | Content merged this session (`2425c3ca`) — worktree now redundant |

## Group B — leave alone, live open PRs (per original session brief: ignore)

- `.worktrees/codex-fly-relay-cutover` (`codex/fly-device-proof`) — open PR #117, draft
- `.worktrees/codex-oracle-skill` (`docs/codex-oracle-skill`) — open PR #126, conflicting

## Group C — real uncommitted work, unmerged commits (highest priority — do not touch without you)

These have BOTH real unmerged commits AND uncommitted local changes on top. Deleting or merging
either risks losing work nobody's reviewed yet.

| Worktree | Branch | Ahead |
|---|---|---|
| `.claude/worktrees/agent-ae710ea1167dd1157` | `perf/conversation-turn-cold-start` | 1 |
| `.claude/worktrees/clever-payne-ff4643` | `claude/clever-payne-ff4643` | 3 |
| `.worktrees/chat-p0-bash-label` | `feat/chat-p0-bash-double-label` | 2 |
| `.worktrees/fix-composer-addrepo` | `fix/composer-addrepo-deadend` | 1 |
| `.worktrees/fix-composer-mic-morph` | `fix/composer-mic-morph` | 1 |
| `.worktrees/fix-onboarding-connect` | `fix/onboarding-connect-obscured` | 1 |
| `.worktrees/g2-review-ui` | `feat/g2-review-sheet` | 5 |
| `.worktrees/p1b-live-review` | `feat/p1b-live-review-wire` | 2 |
| `.worktrees/rel1-relay` | `feat/rel1-relay-robustness` | 5 |
| `.worktrees/s27-deep-integration` | `feat/s27-deep-integration` | 2 |
| `.worktrees/untested-sweep-2026-07-16` | `integration/2026-07-16-untested-sweep` | 2 |

## Group D — branch content already merged, but uncommitted local changes remain

The committed tip of each branch is already safely in `origin/master`'s history — but there's
uncommitted diff sitting in the worktree that would be silently lost by any cleanup. Leave alone.

Includes the **main repo checkout** (`cursor/desktop-history-and-terminal-3510`) — this is the
terminal-rewrite work the original session brief explicitly said to preserve — plus 21 other
worktrees (`frontend-rebuild-closeout-10640e`, `lancer-ios-orchestration-f491ad`,
`review-claude-code-session-b7495a`, `attachment-integration`, `composer-inline-morph`,
`daily-use-audit-2026-07-16`, `desktop-session-decrypt-fix`, `dogfood-sim-test`,
`g3-live-status`, `grok-duplicate-investigation`, `integration-daily-drive`,
`integration-night`, `relay-append-resume`, `s2-agents-continuity`, `terminal-phase1`,
`w2-govui`, `wp1-composer-picker`, `wp2-toolcall-dedup`, `wp3-pending-approvals`,
`wp4-onboarding-gate`, `wp5-profile-usage-hide`, `wp7-pairing-timeout`).

## Group E — anomaly, flag only (not acted on)

Three worktrees registered under `/Users/roshansilva/Documents/simurgh/.claude/worktrees/benchmark-blockers-2026-07-13-37773c/...`
appeared in the **Lancer repo's** `git worktree list` — they're Simurgh benchmark-run artifacts
that somehow got linked into the wrong repo's worktree registry. Left completely untouched;
worth a manual look at some point (likely a stray `git worktree add` run from the wrong cwd).

## What was NOT deleted, and why this stayed conservative

Per your answer, this pass only deleted worktrees that were **both** fully merged into
`origin/master` **and** had a clean working tree — 27 of 82. Everything in Groups A–E above
needed either a value judgment (A: read the diff to prove supersession) or contains real
uncommitted/unmerged work that only you can triage safely (C, D). Group A is a low-risk
"approve and I'll delete" list if you want the disk space back; Groups C/D need your eyes first.
