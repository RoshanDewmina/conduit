# In-thread agent Question cards — Status

**Updated:** 2026-07-10 (M1 implemented + verified)
**Plan:** `docs/plans/2026-07-10-in-thread-questions-Plan.md`
**Branch / worktree:** `feat/in-thread-questions` @ `77488c11` (cut from `master`) in
`/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe`

## Done

- Read `docs/plans/2026-07-10-frontend-rebuild-Plan.md` / `-Status.md`, the sim-dogfood README, and
  `AGENTS.md`/`AGENT_READ_FIRST.md`.
- Updated `docs/STATUS_LEDGER.md` Current priority to reflect the scorched wipe + rebuild + sim
  dogfood D0–D8 PASS on `master` @ `77488c11`; marked physical-device/APNs re-proof DEFERRED by owner;
  removed Wave 0 / old `CursorStyle` as active work.
- Explored (read-only) the real question-path APIs before writing the Plan:
  - `QuestionCardModel.swift` / `AnswerQuestionResolver.swift` — pure, pre-wipe-surviving, fully unit
    testable, unused by any UI today.
  - `CommandGateway.answerQuestion` — real, already wired for the Siri/AppIntent path via
    `channel.sendQuestionAnswer` (SSH) or `firstConnectedBridge().sendQuestionAnswer` (relay,
    "any connected machine" fallback).
  - `E2ERelayBridge.handleRelayMessage`'s `"questionPending"` case — already decodes
    `QuestionPendingParams` and posts `lancerE2EQuestionPending`; confirmed via grep that **nothing
    subscribes to it** — the exact same class of gap M4 found and closed for approvals
    (`lancerE2EApprovalReceived` → `RelayApprovalIngest`).
  - `QuestionPendingParams` carries an optional `runId` (unlike `E2ERelayMessage.ApprovalData`,
    which carries none) — a relay question can be correlated to a specific local turn.
  - `ChatRunPersistenceSink.handleQuestionPending` (SSH-only path, `ApprovalIngest.swift`) already
    defines the exact `.question` `ChatArtifact` shape to persist — reused, not reinvented.
- Wrote `docs/plans/2026-07-10-in-thread-questions-Plan.md` with Goal / Non-goals / M1–M3 milestones
  and verify commands.
- Wrote this Status file.

## M1 — thin card + relay ingest + answer path (2026-07-10)

- **Implemented:** `Packages/LancerKit/Sources/AppFeature/Bridge/RelayQuestionIngest.swift` (new,
  `@MainActor @Observable`) — subscribes to the real `lancerE2EQuestionPending` notification (already
  posted by `E2ERelayBridge.handleRelayMessage`'s `"questionPending"` case, confirmed keys match:
  `"questionParams"` / `"machineID"`), decodes `QuestionPendingParams`, tries `chatRepo.turnByRunID`
  when `runId` is present, persists a real `.question` `ChatArtifact` on a hit (same shape
  `ChatRunPersistenceSink.handleQuestionPending` already defines for the SSH path), and always builds
  a `QuestionCardModel.PresentationState` via `QuestionCardModel.decode(from:)` — reusing the existing
  decode/mutate/build-answer/merge-answer logic verbatim, adding zero new question-model code.
  `toggleOption`/`setFreeText` mutate the published per-machine dict in place; `submit` builds the
  wire answer, resolves the *originating* machine's bridge from `RelayFleetStore` (not "any connected
  machine" — mirrors `RelayApprovalIngest.decide`'s direct-bridge-call discipline), calls
  `bridge.sendQuestionAnswer`, best-effort persists the merged answer, and clears the card.
- `Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift` — added `@Environment(RelayQuestionIngest.self)`
  + `@Environment(RelayFleetStore.self)`, a `pendingQuestion` computed property (same shape as
  `pendingApproval`), and a `questionCard`/`questionItem` view: per-item question text, tappable
  option rows (checkmark-circle toggle), a free-text field when `item.options.isEmpty ||
  question.allowFreeText`, and a Submit button gated on `QuestionCardModel.isReadyToAnswer`. Rendered
  independently of the approval card and `replyState`, matching M4's "orthogonal UI state" rule. Added
  `import SessionFeature` (was missing; `QuestionCardModel` lives there).
  Also added a `LANCER_DEBUG_QUESTION_ANSWER` DEBUG seam (mirrors `LANCER_DEBUG_APPROVAL_DECISION`
  exactly): fuzzy-matches the env value against each item's options via
  `QuestionCardModel.fuzzyMatchOption` (the same helper `AnswerQuestionResolver`'s Siri path uses),
  falling back to free text, then calls the real `RelayQuestionIngest.submit` — no bypass of the
  production answer/send/persist path.
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — constructs `RelayQuestionIngest(chatRepo:
  env.chatRepo)` alongside `relayApprovalIngest`, calls `.start()` in the same `.task`, injects via
  `.environment(_:)` at the composition root.
- `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift` — added
  `@Environment(RelayQuestionIngest.self)`, re-injected `.environment(relayQuestionIngest)` +
  `.environment(relayFleetStore)` at the `LiveThreadView` sheet boundary (sheets don't auto-inherit
  custom environment values — same explicit-re-injection discipline M2/M3/M4 established), and updated
  the `#Preview` provider to construct/inject a `RelayQuestionIngest` for consistency.

### Verification

- `build_sim` (XcodeBuildMCP, scheme `Lancer`, iPhone 17 Pro): **SUCCEEDED**, 5.8s (incremental),
  0 errors, 0 new warnings. Earlier full `build_run_sim` after the first fix (missing `import
  SessionFeature`) also SUCCEEDED, 24.0s, 0 errors, same 25 pre-existing `SiriRelevanceCoordinator.swift`
  warnings as every prior rebuild session, 0 new.
- **Sim dogfood attempted against real local `lancerd` + relay** (same pattern as
  `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/`):
  1. `lancerd doctor`: 12 OK / 1 warn (shim PATH, non-blocking) / 0 fail — daemon already up, relay
     paired, no owner ask needed.
  2. `lancerd pair` → fresh code `527904`. Launched sim with `LANCER_DESTINATION=trustedMachines
     LANCER_RELAY_PAIR_CODE=527904` — paired successfully, screenshot confirmed machine `C0FE8DBE`
     "connected" (two older stale "host offline" pairings from prior sessions still present, left
     alone per existing precedent).
  3. Launched `LANCER_DESTINATION=liveThread` with a prompt asking the host's Claude Code CLI to call
     `AskUserQuestion`. The **approval card rendered correctly** for an intermediate `ToolSearch` tool
     call (screenshot evidence) — confirms M4's approval path still works end-to-end post-this-change.
  4. Relaunched with `LANCER_DEBUG_APPROVAL_DECISION=approve` set from launch so any intermediate
     tool-call approval auto-resolves (approved twice in `audit.log`, both for `ToolSearch`).
  5. **Definitive result, screenshot evidence:** the host-side Claude Code CLI itself replied *"There's
     no `AskUserQuestion` tool available to me in this environment — it's not in my tool list or the
     deferred/MCP tool registry I can search. I can't invoke a tool that doesn't exist."* — the
     headless `stream-json` dispatch mode `lancerd` uses to launch Claude Code CLI does not expose
     `AskUserQuestion` to the model, so `agent.question.pending` / `questionPending` is never emitted
     by the daemon in this session's environment. This is a **host-CLI-availability constraint**, not
     a bug in the new ingest/UI code — `RelayQuestionIngest`'s subscribe/decode/render/answer logic is
     unreachable-but-correct by inspection (same class of "failure path proven, happy path
     architecturally sound but not exercised" gap M3/M4 already carried forward for send/reply and
     approve/deny before *those* were dogfooded).
- **Not verified this session:** an actual `questionPending` round-trip end-to-end. Blocked on
  `AskUserQuestion` tool availability in the daemon's headless CLI dispatch mode — a daemon/CLI-launch
  configuration question, not something this milestone's write-set (iOS-only) can fix, and out of
  scope per AGENTS.md's "no daemon feature creep unless a blocker bug is found." Whether this is
  fixable (e.g. a different `claude` CLI invocation flag) is worth a follow-up investigation, not
  assumed to be a real gap yet.

## Remaining

- M2+ (dogfood round-trip proof once `AskUserQuestion` availability is resolved on the daemon side;
  polish) — **not started, needs owner OK** before starting (see Plan). Specifically worth raising to
  the owner: is `AskUserQuestion` expected to work through `lancerd`'s current headless dispatch mode
  at all, or does question-asking need a different CLI invocation shape?

## Commands run

```bash
git checkout -b feat/in-thread-questions   # from master @ 77488c11

# XcodeBuildMCP: session_set_defaults(project=this worktree's Lancer.xcodeproj, scheme=Lancer,
#   simulator=iPhone 17 Pro, bundleId=dev.lancer.mobile) → build_sim
# First attempt FAILED: cannot find type 'QuestionCardModel' in scope (LiveThreadView.swift missing
#   `import SessionFeature`) → fixed → build_sim SUCCEEDED, 13.4s, 0 errors, 0 new warnings

cd daemon/lancerd 2>/dev/null; cd -    # (not touched — iOS-only milestone)
~/.lancer/bin/lancerd doctor           # 12 OK / 1 warn / 0 fail, daemon+relay already up
~/.lancer/bin/lancerd pair             # fresh code 527904

# XcodeBuildMCP: build_run_sim → SUCCEEDED, 24.0s
# stop_app_sim → launch_app_sim env={LANCER_DESTINATION: trustedMachines, LANCER_RELAY_PAIR_CODE: 527904}
#   → screenshot: machine C0FE8DBE "connected"
# stop_app_sim → launch_app_sim env={LANCER_DESTINATION: liveThread,
#   LANCER_LIVETHREAD_PROMPT: "Use your AskUserQuestion tool right now to ask me: ..."}
#   → screenshot: real approval card rendered for an intermediate ToolSearch call (M4 still works)
# stop_app_sim → launch_app_sim env={..., LANCER_DEBUG_APPROVAL_DECISION: approve}
#   → audit.log: 2 ToolSearch approvals auto-resolved; host Claude Code CLI then replied in-thread
#     that AskUserQuestion is not available to it in this environment — screenshot captured.

# Final verification before commit:
git status --short   # exactly the intended 6-file write-set (3 modified app files, 1 new Swift
                      #   file, 1 modified STATUS_LEDGER.md, 2 new plan/status docs)
# XcodeBuildMCP: build_sim → SUCCEEDED, 5.8s (incremental), 0 errors, 0 new warnings
```
