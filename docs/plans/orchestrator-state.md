# Orchestrator state — Fable swarm dashboard

## ⚡ HANDOFF 2026-07-12 ~00:20 — PUNCH LIST FULLY CLEARED (PRs 89–94 merged); device build ready, phone offline

**#94 merged** (Agents row → conversation directly; interstitial deleted; sim-gated with the
live orchestrator session's own transcript). CI note: the app-target job on #94 failed ONLY on
the known-flaky `waitForAnyConnected` test (deflaked once in #61; ConnectionStateStore untouched
by the diff; local app-target build + full suite green) — flake, not regression; deflake again
if it repeats. **Owner relay pairing RESTORED** (code 208937, daemon hot-reloaded + reconnected;
phone auto-reconnects via stable identity — no code needed). ~/.cursor/mcp.json restored ✓.
**Device build from master `c49ec4f5` INSTALLED + LAUNCHED on the owner's phone (2026-07-12 ~08:36); pairing auto-restored on code 208937 (stable identity, zero taps). ⚠️ One stale approval card on the phone ("git log", empty-RunID so #92's prune correctly kept it; agent process dead) — owner taps Deny once.** Owner review list: ① thread badges clear on
foreground ② receipt card + Proof Reel after a run ③ Flight Recorder rows in thread detail
④ Agents row opens the chat directly. Remaining owner-gated: APNs lock-screen co-test ·
emergency-stop verify · Cursor-dashboard plan-usage check (ledger #2).

**Routing confirmation (owner check 2026-07-12):** all five punch items were Cursor-dispatched
(lanes Q/S/R = grok-4.5-xhigh); Fable edits were confined to root-cause one-liners found mid-gate
(#90 optional field + verbatim-payload test; #93 hydration-wait, mirroring an existing pattern)
plus docs. Next parallel lanes per owner-asks ledger (~/Downloads/lancer-owner-asks-ledger-2026-07-11.md):
#22 plan-limits collector (⚠️ needs owner call: skip Cursor per-device for V1?) · #23 account
switcher (sensitive → Sonnet) · #25 bug reporting · #26 artifact rendering · #27 S27 lane ·
#28 cross-device proof — disjoint write-sets, dispatch after owner sees the device build.

## PREVIOUS 2026-07-12 ~00:00 (punch list CLEARED except direct-open lane; PRs 89–93 merged)

**Live state:** daemon running lane-Q-era binary == master content (list enrichment + approval
prune live; backup at `~/.lancer/bin/lancerd.bak-pre-p93`). **Owner phone is ORPHANED** — sim
holds the relay slot (code 892188); owner backup at `~/.lancer/relay-pairing.json.owner-backup-2237`
(code 208937 — stable identity means phone auto-reconnects when that file is restored, no code
entry). RESTORE after the final sim gate + tell owner. `~/.cursor/mcp.json` restored ✓.

**Merged tonight (all sim-live-loop-gated, evidence in docs/test-runs/2026-07-11-sim-live-loop-gate/):**
- **#89** repo-match grouping/dedup — PASS (trailing-slash dedup, thread grouped, live pong round-trip).
- **#90** Proof Reel + receipt card — PASS after the gate caught a real ship-blocker: required
  `conversationId` vs daemon `omitempty` → every real receipt failed decode (fixed `28fb0a7c`,
  regression test on verbatim daemon payload). Reel sheet proven with an approved `ls` run
  (approval card → Approve → receipt card → Stop 1/1 playback).
- **#91** Flight Recorder — PASS (timeline of real ledger events; stdout/receipt/exit; expand OK).
  Backlog nit: turn-row a11y label repeats 4×.
- **#92** startup prune of dead-run pending approvals (punch #5) — Fable full-diff reviewed
  (fail-closed: terminal/absent→drop, unknown/live/empty→keep); **live-proven** in daemon log:
  `restoreQueue: pruned 1 stale approval(s)`.
- **#93** honest thread-list status (punch #1) — daemon list carries lastTurnID/lastTurnStatus;
  merge advances running→terminal only; refresh syncs when a local turn is running + on
  scenePhase active. Gate caught a second bug: connection-state-read-once hydration race
  (fixed `7e03b466`). Proven end-to-end: Working badge → daemon restart mid-run → list shows
  Failed WITHOUT opening the thread.

**Punch list status:** #1 ✓ (#93) · #2 ✓ (6 live sends round-tripped tonight incl. approval
flow) · #3 ✓ (#89) · #4 IN FLIGHT — lane R `fix/p1-agents-direct-open` (Grok, dispatched):
row tap → arm observed continue → LiveThreadView adopt-without-initial-send; interstitial
deleted. Needs: my verify + app-target build + sim gate (Agents row tap) + merge. · #5 ✓ (#92)
· #6 ✓ (transcript responsive post-#87) · #7 APNs co-test still owner-gated.

**Then:** ONE device build to owner from master (after lane R) — review list: thread-list
badges clear on foreground; receipt card + Proof Reel on completed runs; Flight Recorder rows
in thread detail; Agents-row direct open. Then feature queue (plan-limits collector → account
switcher → in-app messaging).

**New gotchas (also appended to REVIEW_STANDARDS):** Go `omitempty` ↔ Swift required field =
prod-only decode failure — wire fixtures must include a verbatim daemon capture · never read
`firstConnectedMachine` once at call time (hydration race — wait like ShellLiveBridge) ·
sim typing: HID type_text doesn't land in this iOS 27 sim's fields — use `simctl pbcopy` +
long-press + `idb ui tap` on the Paste callout (SwiftUI buttons still need snapshot_ui refs;
UIKit callouts accept idb) · two command-center repo rows on Workspaces root (discovered-16 vs
added-1) — likely path-spelling split predating #89's normalizer on host-side cwds; backlog.

## PREVIOUS HANDOFF 2026-07-11 ~21:15 (superseded above; kept for context)

**Live state:** daemon deployed from master `d89a69e4`+#88 on owner code 208937, queue.json
clean (2 ghost approvals hand-purged; class fix pending), 0 running turns. Owner phone has
wave-4 build (master `027e6ef4`), pairing auto-restores (stable identity WORKS — proven ×6
tonight). Sim identity pinned to dead codes — clean-reinstall sim before any sim gate.

**CHAT RELIABILITY PUNCH LIST (owner: fix ALL today):**
1. **Thread LIST shows stale "Working"** for turns the daemon marked failed (screenshot
   21:10) — list statuses only refresh on thread open; need list-level refetch on
   foreground/poll (ConversationSyncCoordinator / thread list store). NOT yet fixed or laned.
2. Owner's send got 'machine didn't respond' twice tonight — (a) dispatch racing relay
   re-key second (backlog), (b) handlers now off-loop (#87 fixed the big one). Re-verify send
   works end-to-end on device after list fix.
3. Lane P `fix/p1-repo-match` — DONE, PR #89 open (tests green; needs sim gate before
   merge). ⚠️ worktree is NESTED at .worktrees/fix-router-async/.worktrees/fix-orphan-turns/
   .worktrees/p1-repo-match (cd bug); clean up all three nested worktrees after merging.
4. Tap agent session → open conversation DIRECTLY (kill "Continue in Lancer" screen) — owner
   explicitly annoyed. Not laned yet.
5. Stale-approval class fix: drop pending approvals whose run is dead (same startup
   reconciliation as #88 turns). Not laned yet.
6. Transcript view slowness re-check post-#87.
7. APNs lock-screen co-test NEVER RUN — owner was mid-session; ask for "closed" signal, fire
   gated action, trace daemon→conduit-push logs (`gcloud logging read` project
   roshan-agent-f1c2466d service conduit-push).

**Landed tonight:** #80 keepalive · #81 stable identity · #82 model-argv · #83 git-wedge ·
#84 picker/haiku · #85 markdown+pacer · #86 Agents section · #87 handlers off messageLoop ·
#88 orphan-turn reconciliation. Sim-gate evidence: docs/test-runs/2026-07-11-sim-live-loop-gate/.

**Open PRs awaiting sim gate (all tests green, ui risk):** #89 repo-match · #90 proof reel ·
#91 flight recorder. Gate each with a real haiku run (receipt needed for #90), merge, then
ONE device build to owner. s27-deep-integration branch: S27-0 committed; NEXT S27-2a
Live-Activity restore. Cleanup: remove merged worktrees fix-router-async + fix-orphan-turns
+ nested p1-repo-match (3-deep nesting bug), fix-git-timeout, fix-model-argv, p2-* after
merge. Background procs: all stopped (test daemon /tmp/lth killed; monitors expired).

**Operational gotchas:** cursor headless dies on big ~/.cursor/mcp.json → `mv` to
.headless-hold during dispatch, ALWAYS restore · daemon redeploy = stop→mv→bootstrap, NEVER
cp; restarts kill in-flight runs (now reconciled honestly, still avoid during owner runs) ·
single relay slot: sim gates borrow via backup/restore of ~/.lancer/relay-pairing.json
(phone auto-reconnects) · `lancerd pair` codes expire ~15min unconfirmed · TCC: owner may
grant lancerd Full Disk Access; codesign lancerd queued for launch prep.

**Feature queue (after punch list):** plan-limits collector (lfg study:
docs/product/2026-07-11-lfg-study-and-usage-limits.md, MIT) → account switcher/hotswap →
in-app messaging + bug reports (needs owner scope confirm) → S27 lane → cross-device proof.

**Updated:** 2026-07-11 PM (update after every merge or blocker; this file is compaction insurance)
**Phase:** 1 — dogfood MVP. Phase 0 CLOSED: PR #69 merged (`fd7b56d5`); stashes + checkpoint/backup refs dropped; w0a branch deleted.

## FRONTEND REVERSAL (owner, 2026-07-11 PM) — read before touching UI

Owner supplied the Cursor Design reference set → the frontend is the **Codex Workspaces
shell** (`b472ffd3` line), NOT W0.A. PR #75 restores it. W0.A retired; PRs #72/73/74 closed
as superseded. Re-queue lanes against the restored shell:
- Tool-call cards re-port (pairing/presentation logic from closed #72 is shell-agnostic)
- Siri warning cleanup (redo of #73)
- LancerUITests rewrite (current suite targets the retired W0.A shell; kept only so
  xcodegen resolves)
- Known fidelity gaps from the Codex session: light-mode header-chip chrome subtler than
  reference; avatar orb oversized. Device dogfood items M2/M3/M4 unproven live.
- **Failure lesson (recorded):** the 07-10 purge docs said "W0.A KEPT / wipe abandoned" —
  the docs were wrong about which shell the owner meant. When a directive names a branch,
  attach a screenshot of what it looks like before acting on delete/keep decisions.

## Wave 3+4 COMPLETE on master (2026-07-11 ~20:00): #82–#86 · device build ready, phone offline

#86 Agents section merged (observed sessions list/transcript/continue; gate screenshot shows
3 REAL sessions incl. the orchestrator itself). Final device build from `027e6ef4` SUCCEEDED;
**install monitor armed — phone `unavailable`, installs+launches automatically on reconnect,
then ping owner.** Owner review list: Model chip (Haiku default) · markdown on algebra prompt
· streaming fluidity · Agents section listing Mac sessions. All lane worktrees cleaned.

## Dogfood wave 3 MERGED (2026-07-11 ~19:30): PRs #82–#85 — awaiting phone reconnect to install

#82 model-argv (latent: ANY explicit-model dispatch instant-exited — picker exposed it) ·
#83 relay-wedge (hung git on messageLoop; goroutine dump preserved; 10s CommandContext +
async receipt snapshot) · #84 model picker Haiku default + cloud chip removed · #85 markdown
HTML-conversion/block-boundaries + streaming pacer. Sim gate evidence:
docs/test-runs/2026-07-11-sim-live-loop-gate/ (both addenda). Daemon deployed at 36dc6ac9-era
tip on owner code 208937. **Device build SUCCEEDED but phone went unavailable at install time
— install + launch it the moment the phone reconnects, then ping owner (review moment:
Model chip → Haiku, algebra prompt markdown, streaming fluidity).**
Backlog logged: dispatch-vs-repair race orphaning a running turn; pairing-sheet expiry UX.
Feature queue: plan-limits collector (lfg MIT, docs/product/2026-07-11-lfg-study-and-usage-limits.md)
· account switcher/hotswap (Orca) · in-app agent messaging + bug reports (needs owner spec
confirm) · S27 lane (S27-0 done on branch) · cross-device continuation proof.

## Pairing friction SOLVED (2026-07-11 night): PRs #80 + #81 merged, prod-relay-proven

Root causes (backend-log-verified): (a) daemon sat on relay-reaped sockets forever (no read
deadline; x/net/websocket has no control-frame ping) — #80 adds 90s read deadline + bounded
expired-code giveUp; daemon REDEPLOYED. (b) E2ERelayClient minted a new keypair per instance
→ backend key-pin rejected every retry/reinstall as hijack — #81 adds Keychain-persisted
stable device identity (dev.lancer.relay, AfterFirstUnlockThisDeviceOnly, survives reinstall)
+ launch auto-restore + fail-closed corruption wipe. Sim gate vs PROD relay: pair PASS,
relaunch-no-code auto-reconnect PASS ("phone connected (paired)"). Owner pairs ONCE more
(final code 853535), then never again. Ops note: `lancerd pair` codes expire unconfirmed
~15min — generate immediately before pairing.

## S27 lane (owner top priority): iOS 27 SDK ALREADY INSTALLED — all packages CAN START NOW

Branch feat/s27-deep-integration: plan committed (docs/plans/2026-07-11-s27-deep-integration-Plan.md),
S27-0 target raise DONE on branch (cb7f3196, swift+app-target gates green). Next: S27-2a
Live-Activity widget restore (deleted in wipe — prereq for the Siri-dispatch headline),
S27-1 tests, S27-2 LongRunningIntent (sensitive), S27-3 Spotlight, S27-4 FM copilot
(iOS26+, parallel-safe), S27-5 verify-then-build. Queued: cross-device continuation proof.

## Dogfood round 2: PR #79 MERGED (2026-07-11 late) — streaming/timeout/transcript

Owner findings → fixes, all sim-gate-proven (evidence `docs/test-runs/2026-07-11-sim-live-loop-gate/`):
streaming mid-run PASS · false 90s timeout removed (LivePollPolicy) · follow-up round-trip
PASS · full-transcript bug (follow-ups wiped prior turns) found BY the new gate, fixed.
New build installed+launched on phone from `e7619069`; owner re-pairs with code 221157.
**Open:** artifacts surface lane (LiveThreadView freed up) · streamed-markdown newline
cosmetic · **notifications = device-only, owner co-test pending (APNs diagnosis prepped
next)** · SiriRelevanceCoordinator warnings redo.

## Dogfood round 1: ALL THREE FINDINGS FIXED AND MERGED (2026-07-11 night)

PR #76 (composer onSend required, repo-scoped send) · #77 (chat/PR polish to reference) ·
#78 (real data everywhere; +app-target access-level hotfix 65ba058c — swift build on macOS
missed an iOS-gated public-init/internal-type error, CI build_sim caught it). Dogfood
candidate installed+launched on phone from master 36d81be6. ~/.cursor/mcp.json RESTORED.
Reinstall wipes pairing — owner must re-pair (`lancerd pair` for a fresh code).

## Dogfood round 1 (owner, 2026-07-11 evening) — pairing WORKED; 3 findings → lanes

1. **P0 composer bug** (root-caused by Fable): `NewChatComposerView.send()` = `onSend?();dismiss()`;
   ThreadListView:86 + ThreadDetailView:83 pass NO onSend → silent dismiss. Lane F
   (`fix/p1-composer-onsend`, Grok) makes onSend required + repo-scoped cwd.
2. **Chat UI "looks horrible"** → Lane H (`feat/p1-chat-polish`, Grok): LiveThreadView/
   ThreadDetail/PRDetail to cursor-reference quality, native AttributedString markdown.
3. **Mock data everywhere** → Lane G spec ready (scratchpad/laneG-SPEC.md): real repos from
   chatRepo + AddRepo persistence, real threads, honest empty states, kill placeholderCwd.
   Dispatch AFTER F merges (shared files: WorkspacesView, ThreadList, Composer).

**Cursor CLI MCP-limit gotcha (recurring):** headless `agent -p` dies with "Too many MCP tools"
since ~/.cursor/mcp.json grew. Project-level empty .cursor/mcp.json does NOT override. Current
workaround: `mv ~/.cursor/mcp.json ~/.cursor/mcp.json.headless-hold` during dispatches —
**RESTORE IT after lanes finish** (owner's IDE loses MCP servers while held).

## Phase 1 lanes (dispatched 2026-07-11, Grok 4.5 xhigh via cursor-agent)

| Lane | Branch / worktree | Scope | Write-set | Status |
|---|---|---|---|---|
| A | **PR #72 open — OWNER GATE (ui)** | Tool-call cards + indicator enum; rebased on master; swift gates green, 22 new tests; Orca attribution present | CursorStyle + tests | awaiting owner batched eyeball |
| C | `feat/p1-question-card` (stacked on A) / `.worktrees/p1-question-card` | Question card on W0.A shell + RelayQuestionIngest reconcile w/ 30a28e26 | Bridge/RelayQuestionIngest, CursorShellLiveBridge, CursorWorkThreadView, new CursorQuestionCard | dispatched (Grok) |
| E | `chore/p1-siri-warnings` / `.worktrees/p1-siri-warnings` | 25-warning mechanical cleanup | Lancer/SiriRelevanceCoordinator.swift | dispatched (Composer) |
| B | **MERGED** PR #70 (`eeaa6134`) | 81-case permission matrix + **real fail-open bug found & fixed**: `policy/match.go` corrupt ExpiresAt (effect-aware fail-closed after Opus CI correction) | — | done; worktree removed |
| D | **MERGED** PR #71 (`57bf761d`) | Ordering already existed (C1–C2); +8 ordering tests, force-unwrap removed | — | done; worktree removed |
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
