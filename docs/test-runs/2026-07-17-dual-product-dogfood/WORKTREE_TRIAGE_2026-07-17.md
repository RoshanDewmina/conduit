# Worktree triage — 2026-07-17 (Group C/D follow-up)

Follow-up to `WORKTREE_CLEANUP_REPORT.md` (same folder). Starting count this pass: **41**.
Every Group C/D worktree now has a disposition. Method: content-level supersession checks
(`git cherry`, per-file three-dot diffs against `origin/master`, master tree/grep for re-landed
functionality) — never ahead-counts alone. That discipline caught **7 more silently-superseded
branches** today (same failure mode as the four caught in the prior session).

## Deleted this pass (2 — both fully merged AND clean, per the standing rule)

- `.claude/worktrees/swarm-orchestrator-design-52d07a` (`claude/session-44c36d`) — at merged PR #152 tip, clean tree.
- `.worktrees/fix-auth-preflight-dogfood` (plain `master` checkout) — clean, redundant.

Count after deletions: **39**.

## Merged this pass (salvage branch `salvage/worktree-triage-2026-07-17`)

- `fix/composer-addrepo-deadend` (`.worktrees/fix-composer-addrepo`) — real un-landed fix:
  master's `RepoPickerView.swift` still has no `AddRepoView` wiring (only a shared-chrome
  comment at :112). +76 lines + `WorkspaceRepoCatalogTests` additions. Gates run before merge
  to master (see PR).
- `integration/2026-07-16-untested-sweep` committed content (`.worktrees/untested-sweep-2026-07-16`) —
  Lane C4 partial-run evidence: report, screenshots, `scripts/sweep-lane-c4-run.sh`, sweep
  UITest. `GAP_LIST.md` conflict resolved **ours** (master's version is newer: phone-verified
  PASS states, #144/FX10 landed). Worktree itself LEFT ALONE — it still holds uncommitted
  `SweepLaneC2/C3/D2/FFinal` test files (real unreviewed work).
- Salvaged single file `docs/plans/2026-07-15-competitor-mobile-chat-notes.md` from
  `feat/chat-p0-bash-double-label` (165-line research doc, nowhere else).

## Superseded — recommend delete, awaiting owner OK (uncommitted-changes rule blocks deletion)

Each verified against master content, not commit hashes:

| Worktree | Branch | Proof of supersession | Uncommitted residue |
|---|---|---|---|
| `.claude/worktrees/agent-ae710ea1167dd1157` | `perf/conversation-turn-cold-start` | Master `9992701f` is the identical patch (`git cherry` `-`) | `Package.resolved` drift only |
| `.claude/worktrees/clever-payne-ff4643` | `claude/clever-payne-ff4643` | Targets `AppFeature/CursorStyle/` — module deleted by `6b97da65`; uncommitted diffs also target the deleted module | CursorStyle edits (dead) |
| `.worktrees/chat-p0-bash-label` | `feat/chat-p0-bash-double-label` | Master has `ToolCallChipView.swift` + `LiveThreadTranscriptTests.swift` + wp2 label-dedup merged (`45e7864a`); `LiveThreadTranscript` rewritten since. Unique doc salvaged (above) | `Package.resolved` drift only |
| `.worktrees/fix-composer-mic-morph` | `fix/composer-mic-morph` | Master resolved differently: dead mics removed (`6310727e`) + inline morph landed (`b0f104ab`) + chips collapse (`01b9a47d`) | `spec-mic-morph.md` residue |
| `.worktrees/fix-onboarding-connect` | `fix/onboarding-connect-obscured` | Master `a8a91761` (same day, 5h later) = same safeAreaInset fix, more complete (`!isAtCap` gate) | `spec-onboarding-connect.md` residue |
| `.worktrees/g2-review-ui` | `feat/g2-review-sheet` | Master has the full `AppFeature/Review/` module (ReviewSheetView, DiffFileSection, FileTreeView, ReviewModels, AddCommentSheet…) + `ReviewModelsTests.swift` re-landed under different hashes | `Package.resolved` drift only |
| `.worktrees/p1b-live-review` | `feat/p1b-live-review-wire` | Master `ReviewDataSource.swift` already has the live relay path (`relayRepoTurnDiff/SessionDiff/FileDiff/Tree`) | `spec-p1b.md` + `dispatch-p1b.json` residue |

## Owner-decision-needed (real un-landed work; not safe to auto-merge)

| Worktree | Branch | What it is | Why it needs you |
|---|---|---|---|
| `.worktrees/rel1-relay` | `feat/rel1-relay-robustness` | 5 commits, +740 lines: relay structured error codes, dead-code re-mint, first-send gating, push-backend tests (07-12) | **Sensitive path** (relay protocol) + heavy drift since (Fly cutover PR #117, `292525b7` append-correlation). Needs a dedicated re-verification session, not a mechanical merge |
| `.worktrees/s27-deep-integration` | `feat/s27-deep-integration` | iOS deployment target 26.0 → 27.0 + dual-SDK gate removal | Master is still on 26.0 (`project.yml`). Platform-wide decision: device support + CI + TestFlight implications |
| `.worktrees/relay-append-resume` | `fix/relay-append-resume` (branch merged) | **Uncommitted**: +83 lines in `E2ERelayBridge.swift`, new `E2ERelayBridgeAppendResumeTests.swift` | Real unreviewed relay-path work sitting only in the working tree |
| `.worktrees/terminal-phase1` | `feat/terminal-phase1-rewire` (branch merged) | **Uncommitted**: new `AppFeature/Terminal/` folder + TrustedMachines/ThreadDetail edits | Terminal-rewrite line — same protected stream as the main checkout |
| main checkout | `cursor/desktop-history-and-terminal-3510` | Terminal rewrite + uncommitted docs/config | Explicitly preserved per prior session brief |

## Left alone with reason (noise-only residue; delete-on-your-OK list)

Branch content fully merged; the only "uncommitted changes" are the known Sentry
`Package.resolved` drift or dispatch-harness residue (`spec.md` / `agent-output.json` /
`agent-stderr.log`) — no real work:

- `Package.resolved` drift only: `attachment-integration`, `composer-inline-morph`,
  `daily-use-audit-2026-07-16` (detached), `desktop-session-decrypt-fix`, `dogfood-sim-test`,
  `g3-live-status`, `integration-night`, `w2-govui`
- Harness residue only: `wp1-composer-picker`, `wp2-toolcall-dedup`, `wp5-profile-usage-hide`,
  `wp7-pairing-timeout`, `frontend-rebuild-closeout-10640e` (stray transcript .txt)
- Harness residue + uncommitted CHANGELOG lines (likely duplicates of merged lines — verify on
  deletion): `wp3-pending-approvals`, `wp4-onboarding-gate`
- Untracked one-off files worth a 30-second look before deleting: `grok-duplicate-investigation`
  (`investigate-duplicate.md`), `review-claude-code-session-b7495a`
  (`docs/product/2026-07-07-fable-research-brief.md`), `integration-daily-drive`
  (`LancerUITests/ReconnectCycleUITests.swift`), `lancer-ios-orchestration-f491ad`
  (`docs/test-runs/2026-07-15-reconnect-10x-sim/`)

## Unchanged groups

- **Group B (open PRs, per standing brief: ignore):** `codex-fly-relay-cutover` (PR #117 draft),
  `codex-oracle-skill` (PR #126 conflicting).
- **Group E anomaly:** 3 Simurgh bench worktrees still registered in Lancer's registry —
  flagged again, untouched.
- **Group A** (prior report's approve-and-delete list) — still awaiting the owner's one-word OK.

## Net position

41 → 39 by deletion; 2 branches + 1 doc merged via `salvage/worktree-triage-2026-07-17`.
With the owner's OK on the two delete lists (Group A from the prior report + the superseded/noise
lists above), the count drops to ~14 genuinely-live worktrees.
