# In-thread questions M2 — unblock AskUserQuestion + live dogfood: results

**Run date:** 2026-07-10
**Branch/worktree:** `feat/in-thread-questions` @ (M1 `898e24fc` + this session's fixes) in
`/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe`
**Executor:** agent, Simulator + XcodeBuildMCP + local `lancerd` only — no physical-phone time used.

## Result summary

| Claim | Result | Evidence |
|---|---|---|
| `AskUserQuestion` reachable in headless `-p` dispatch | **PASS** | live CLI probes below; `dispatch.go` argv fix |
| Real `agent.question.pending` → relay → `questionPending` round-trip | **PASS** | daemon audit `question-pending` + phone-side card render |
| In-thread question card renders real (not synthetic) data | **PASS** | `s1-question-card-real-data.jpg` |
| Answer submits via the real production path | **PASS** | daemon audit `question-answered`, 1s after `question-pending` |
| Underlying run's output resumes after the hold clears | **PASS** | `s2-post-answer-resumed-output.jpg` |
| `go test ./...` (daemon/lancerd) | **PASS** | `ok lancer/lancerd 41.987s`; `ok lancer/lancerd/policy` |
| `build_sim` (iOS app target) | **PASS** | 0 errors, 0 new warnings throughout |

## Part 1 — Investigation: why AskUserQuestion was unreachable

Live experiments against the installed `claude` CLI (2.1.206) in a scratch directory, no code changes:

1. **Default `-p` dispatch** (no extra flags): `AskUserQuestion` absent from both the built-in tool
   list and the deferred/MCP registry (`ToolSearch` returned "No matching deferred tools found" out
   of 175). `--tools default` and `--allowedTools AskUserQuestion` made no difference — the tool
   simply doesn't exist in this invocation mode.
2. **Root cause (confirmed via `code.claude.com/docs/en/agent-sdk/user-input`):** `AskUserQuestion`
   is an Agent-SDK-only mechanism gated behind a `canUseTool` callback — not a CLI flag combination.
3. **The actual unlock, found live:** `--permission-prompt-tool stdio` (the same hidden flag the
   Agent SDK itself passes under the hood) makes `AskUserQuestion` appear in the tool list and lets
   the model call it with its real structured input (confirmed: `"tools":[...,"AskUserQuestion",...]`
   and a real `tool_use` block with `{"questions":[{"question":"pick a color",...}]}`).
4. **The catch:** with no live bidirectional stdio responder attached (which `lancerd`'s one-shot
   `-p` dispatch doesn't implement — a real Agent-SDK-style responder is out of scope, see
   AGENTS.md's "no daemon feature creep"), the CLI's own protocol auto-denies the call instantly
   (`"stream closed on the tool call"`) and the turn continues past it. This is fine: the daemon's
   *existing*, already-wired `registerAndWaitForQuestion`/`waitForAnswer` hold mechanism
   (`daemon/lancerd/question.go`) was built with exactly this constraint in mind — it pauses this
   run's own downstream output (not the underlying process) until a human answers or a 10-minute
   timeout elapses, which is what "continue" means in this architecture (see Part 3).

**Minimal fix:** add `--permission-prompt-tool stdio` to `agentArgv`/`continueArgv`/`resumeArgv`'s
`claudeCode` case only (`daemon/lancerd/dispatch.go`). Verified live that dispatch.go's *existing*
stream-json parser needs zero changes — `AskUserQuestion`'s `tool_use` streams through the ordinary
`content_block_start`/`delta`/`stop` sequence every other tool already uses, and
`question.go`'s `extractQuestionEvent` already recognizes it by name.

## Part 2 — A second, pre-existing bug found by dogfooding (not introduced by the above)

The first live attempt (see Commands run, S3) showed the question card correctly render **zero
times** despite the daemon logging `sent question ... over relay` successfully. Root-caused via the
daemon's own `lancerd.stderr.log` + iOS os_log capture, comparing against the *working* approval
path:

- `daemon/lancerd/e2e_router.go`'s `sendQuestion` sends relay message `"type": "agentQuestion"` with
  a hand-rolled payload keyed `questionID` (not `id`), matching that function's own doc comment
  ("the relay kind the Lane E proposal names explicitly for this event").
- `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`'s `handleRelayMessage` only ever
  matched `case "questionPending":` and tried to decode straight into `QuestionPendingParams` (the
  **SSH** JSON-RPC shape, keyed `id`) — a message type the daemon's relay path never actually sends.
  The message was silently dropped end-to-end. This bug pre-dates this session entirely — it was
  simply never exercised until today, because nothing ever got a real `AskUserQuestion` call through
  headless dispatch before Part 1's fix, and nothing ever subscribed to the (never-arriving)
  notification before M1.

**Fix (iOS-only, no daemon change):** added `E2ERelayMessage.QuestionData` — a relay-specific wire
type mirroring `ApprovalData`'s established pattern (a dedicated Swift type for the relay's
hand-rolled JSON, distinct from the SSH-path struct) — changed the switch case to `"agentQuestion"`,
and `RelayQuestionIngest.handle` now converts `QuestionData` → `QuestionPendingParams` field-by-field
(same conversion discipline `RelayApprovalIngest.handle` already uses for `ApprovalData` → `Approval`).

## Part 3 — A third bug, in this session's own DEBUG seam (not shipped, caught before commit)

The `LANCER_DEBUG_QUESTION_ANSWER` seam's first version called `questionIngest.toggleOption` inside
an `.onChange(of: pendingQuestion)` handler with no one-shot guard. `toggleOption` mutating
`latestPendingQuestion` re-triggers the same `onChange` (the observed value changed), and toggling
the *same* label a second time deselects it (`toggleOption` is a toggle, not a set) — the seam
live-locked into flipping the selection on/off forever and never reached `submit`. Fixed with a
`hasAutoAnsweredQuestion` one-shot guard (same pattern as the existing `hasSentInitialPrompt`).

## What this proves about "continue"

`s2-post-answer-resumed-output.jpg` shows the assistant's own buffered text appearing *after* the
answer was submitted: *"The question tool call failed with a 'Stream closed' error — the request
didn't go through. Want me to retry it?"* — this is the CLI's own denial message, held back by
`registerAndWaitForQuestion`'s hold and flushed once the hold released. The human's real answer
("Red") is genuinely delivered to and resolved by the daemon (audited, `question-answered`), but it
does **not** reach the *same* turn's live reasoning — there is no stdin/tool-result injection channel
into an already-launched one-shot CLI process (documented in `question.go`'s own pre-existing doc
comment, not something introduced this session). Turning an answer into real conversational
continuation is a follow-up **send** through the existing composer/follow-up-bar mechanism (M3),
not a live tool-result injection — a real product-design fact surfaced by this dogfood, not a defect
in this milestone's write-set.

## Commands run

```bash
# Part 1 investigation (scratch dir, no code changes)
claude -p --output-format json "List the exact names of every tool..." < /dev/null
# → no AskUserQuestion (175 deferred tools searched, 0 matches)
claude -p --tools default --output-format json "..." < /dev/null
# → still no AskUserQuestion
claude --output-format json --permission-prompt-tool stdio -p "List tool names..." < /dev/null
# → "...AskUserQuestion..." present
claude --output-format stream-json --verbose --permission-prompt-tool stdio \
  -p "Call AskUserQuestion right now with one question 'pick a color'..." < /dev/null
# → real tool_use block with structured input; permission_denials shows the
#   auto-deny ("stream closed on the tool call"), terminal_reason=completed (no hang)

# Fix: daemon/lancerd/dispatch.go — added --permission-prompt-tool stdio to
# claudeCode's agentArgv/continueArgv/resumeArgv; updated dispatch_test.go
# (new TestAgentArgv + updated want= slices in TestContinueArgv/TestResumeArgv)
cd daemon/lancerd && go build ./... && go vet ./... && go test ./...
# → ok lancer/lancerd 41.987s ; ok lancer/lancerd/policy

# Installed fixed binary (stop launchd service, mv not cp-in-place, restart):
launchctl stop dev.lancer.lancerd; launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist
mv /tmp/lancerd-new ~/.lancer/bin/lancerd
launchctl load ~/Library/LaunchAgents/dev.lancer.lancerd.plist
~/.lancer/bin/lancerd doctor   # 12 OK / 1 warn / 0 fail

# S1: build_run_sim, pair (LANCER_RELAY_PAIR_CODE seam), launch liveThread with
# a prompt forcing AskUserQuestion + LANCER_DEBUG_APPROVAL_DECISION=approve
# (for the intermediate ToolSearch/command-level hook gate).
# → daemon audit: "sent question ... over relay" logged, but NO card rendered,
#   no phone-side log entry for the question at all — Part 2's bug found here.

# Fix: Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift (new QuestionData),
# E2ERelayBridge.swift (case "agentQuestion", was "questionPending"),
# RelayQuestionIngest.swift (convert QuestionData → QuestionPendingParams)
build_sim → SUCCEEDED
build_run_sim → SUCCEEDED; re-paired; relaunched liveThread with the same prompt
# → REAL card rendered: s1-question-card-real-data.jpg (Question / Complete /
#   "Button color" / "Which color should the button be?" / Red / Blue / free-text / Submit)

# HID tap attempt on "Red" (established simulator limitation, control test):
# no visible change — confirms the well-documented HID-taps-dead finding, not a
# regression in this build.

# Relaunch with LANCER_DEBUG_QUESTION_ANSWER=Red — Part 3's toggle-loop bug
# found here (no question-answered audit entry after 10s).

# Fix: LiveThreadView.swift — hasAutoAnsweredQuestion one-shot guard
build_sim → SUCCEEDED
# Fresh pair + clean single dogfood round (daemon restarted via launchctl
# kickstart to clear the accumulated backlog of never-answered questions from
# earlier debugging attempts, which the daemon's resendPendingQuestions-on-
# reconnect mechanism was re-delivering and racing with the one-shot seam):
launchctl kickstart -k gui/$(id -u)/dev.lancer.lancerd
lancerd pair → fresh code, cleared stale machines (LANCER_DEBUG_REMOVE_ALL_MACHINES seam), re-paired
launch_app_sim env={LANCER_DESTINATION: liveThread, LANCER_LIVETHREAD_PROMPT: "...", 
  LANCER_DEBUG_APPROVAL_DECISION: approve, LANCER_DEBUG_QUESTION_ANSWER: Red}
# → CLEAN single round trip: audit.log question-pending (22:58:02) →
#   question-answered (22:58:03), same approvalId (dfbe3d76-...), 1 second apart.
# → s2-post-answer-resumed-output.jpg: buffered assistant text flushed after
#   the hold cleared, confirming the "continue" mechanism (see Part 3 above).

# Final clean verification before commit:
cd daemon/lancerd && go test ./...   # ok, both packages
build_sim (iOS)                       # SUCCEEDED, 0 errors, 0 new warnings
```

## Screenshots

- `s0-clean-pairing.jpg` — clean single-machine pairing after clearing accumulated debug state
- `s1-question-card-real-data.jpg` — the real in-thread question card, live relay data
- `s2-post-answer-resumed-output.jpg` — buffered output flushed after the answer resolved the hold

## Files changed this session (beyond M1)

| File | Change |
|---|---|
| `daemon/lancerd/dispatch.go` | `--permission-prompt-tool stdio` added to claudeCode's 3 argv builders |
| `daemon/lancerd/dispatch_test.go` | new `TestAgentArgv`; updated `TestContinueArgv`/`TestResumeArgv` want= slices |
| `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift` | new `QuestionData` relay wire type |
| `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift` | case `"questionPending"` → `"agentQuestion"`, decode `QuestionData` |
| `Packages/LancerKit/Sources/AppFeature/Bridge/RelayQuestionIngest.swift` | consume `QuestionData`, convert to `QuestionPendingParams` |
| `Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift` | one-shot guard on the `LANCER_DEBUG_QUESTION_ANSWER` DEBUG seam |
| `Packages/LancerKit/Sources/AppFeature/Settings/TrustedMachinesView.swift` | new `LANCER_DEBUG_REMOVE_ALL_MACHINES` DEBUG seam (frees fleet-cap slots blocked by `.hostOffline`, not `.pairingInvalid`, stale pairings — needed purely to unblock verification given the established HID-tap-dead limitation) |

## Owner-only follow-ups (not gaps in this milestone, product/architecture decisions)

- Whether to invest in a real bidirectional `--permission-prompt-tool stdio` responder in `lancerd`
  (genuine Agent-SDK-style protocol work, not a minimal fix) so an answered question can inject its
  content into the *same* live turn, versus the current, honest "answer resolves the hold + a
  separate follow-up send carries the content forward" model. Not decided here — flagging for the
  owner per this session's brief ("if fundamentally unavailable... propose Plan B" — this landed
  short of that: the round-trip **is** genuinely live end-to-end, just with this one documented
  continuation-semantics caveat, not a fundamental unavailability).
