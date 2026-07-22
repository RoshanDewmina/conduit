# Lane C2 — Review stack, receipts, repo honesty (candidates 7, 8, 9, 17, 19, 23) — re-run after approval-race fix

Date: 2026-07-16. Sim: Simurgh `lease-191`, `iPhone 17 Pro`, udid
`F9CA019E-E998-4455-8D0B-93FB27694761` (released at end). Daemon: isolated `/tmp/sweep-C2`, freshly
rebuilt binary `/tmp/lancerd-sweep` from worktree tip `4e45dbaa` (`Merge fix/first-send-approval-race:
bounded retry for approval delivery when relay isn't paired at send time`) —
`go build -o /tmp/lancerd-sweep-C2 . && cp /tmp/lancerd-sweep-C2 /tmp/lancerd-sweep`, confirmed via
`git log --oneline -3` on the worktree. Isolation verified: `grep -c "/Users/roshansilva/.lancer"
/tmp/sweep-C2/daemon.log` = 0.

## Headline result: the approval-delivery race Lane C found IS fixed — but a second, deeper bug blocks every candidate anyway

**The specific bug Lane C reproduced (sendApproval silently dropping when the relay wasn't yet
paired) is fixed and I proved it live, twice in one run:**

```
2026/07/16 11:27:10 e2e: paired with phone
2026/07/16 11:27:44 e2e: sent approval 5372267a-97d9-4b6b-a904-990cc31a247d over relay
```
(`/tmp/sweep-C2/daemon.log`) — the send happened 34s after pairing, well inside what used to be a
dead zone, and `sent approval ... over relay` fired on the very first attempt this time (no retry
needed, though the retry path exists per `e2e_router.go:130-197`). The audit log confirms delivery
was actionable:
```json
{"timestamp":"2026-07-16T15:27:44Z","action":"conversation-append-needs-approval","agent":"claudeCode","kind":"dispatch","command":"Run `pwd` with Bash and print the output. Then edit greeting.txt and readme.md: append one line to each, then run git add -A && git commit -m 'sweep edit'.","effect":"ask","rule":"ask-medium","hash":"d2c03bc642eb..."}
{"timestamp":"2026-07-16T15:27:49Z","action":"approve","agent":"claudeCode","kind":"command","command":"[conversation-append] claude --output-format stream-json ... -p Run `pwd` ...","approvalId":"5372267a-97d9-4b6b-a904-990cc31a247d","hash":"2218a4bf..."}
```
(`/tmp/sweep-C2/home/.lancer/audit.log`, full file — only these 2 entries exist for the whole run).
A decision was recorded 5s after the ask — inside my XCUITest's poll loop, which taps
`cursor.approval.approve` whenever it exists/hittable, confirming a live decidable card really was
delivered and tappable (not just logged).

**But this did not unblock the turn.** 4 minutes after the "approve" audit entry, the app was still
showing the exact same terminal error Lane C found:

> **Couldn't get a reply** — "Awaiting your approval — check the Inbox." / **Retry**
> (`docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/LC2-05-couldnt-get-reply-after-approve-run2.png`,
> captured 11:31, vs. the ask at 11:27:44 / approve at 11:27:49)

Ground truth confirms nothing ran: `git -C /tmp/sweep-C2/target-repo log --oneline` still shows only
the initial `633dfe7 init` commit; `greeting.txt`/`readme.md` are byte-identical to what `git init`
wrote. `ps aux | grep target-repo` shows **no `claude` CLI process ever spawned** for this dispatch,
and `/tmp/sweep-C2/daemon.log` has **zero lines** after `11:27:44 sent approval ...` — the daemon
never logged launching anything.

**Root cause, traced in source (`daemon/lancerd/dispatch.go:2604-2631`):** the `conversation-append`
"ask" branch is a dead end by design, not by omission:
```go
case "ask":
    audit(AuditEntry{Action: "conversation-append-needs-approval", ...})
    d.deliverLaunchApproval(event)
    return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
```
`deliverLaunchApproval` fires the async relay card (the thing that now reliably arrives, per the fix
above) — but the function **returns immediately** with `Status: "needsApproval"`, which the client
renders as the terminal, non-recoverable error (`LiveThreadView.swift:985`, per Lane C's trace, still
accurate). There is no pending-continuation map, no channel, nothing that re-invokes the actual CLI
launch when `applyDecision` later resolves the approval — `handleMessage`'s `approvalResponse` case
(`e2e_router.go:292-329`) only calls `r.server.applyDecision(...)` and `applyAllowRule(...)` (if an
`AllowRule` was attached) and sends an ack; it never calls back into `dispatch`/`dispatchConversationAppend`
to actually start the process. Approving the async card only pre-authorizes a **future** matching
call (via the remembered `AllowRule`, if the client sent one) — it does not resume **this** one.

**Consequence for a real user:** the exact "pair then send immediately" workflow — a first-time
user's most natural path — still ends in an unrecoverable dead end. Tapping the delivered approval
card (assuming a user can even find a live surface for it; Lane C already found
`LANCER_DESTINATION=inbox` is a dead deep-link with no reachable destination) does not complete the
blocked turn. The user's only lever is the in-thread **Retry** button, which re-runs
`dispatchConversationAppend` from scratch — re-hitting the same `ask-medium` policy rule (since no
`AllowRule` was attached from my tap) and producing the **identical** terminal error again. This is a
genuine infinite loop for the common case, distinct from and not addressed by the relay-delivery fix
in `4e45dbaa`.

## Candidate verdicts — all BLOCKED, same root cause as Lane C, but for a different, now-precise reason

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 19 | Repo display-name vs dispatch cwd | **BLOCKED** (same as Lane C) | Added repo path `/tmp/sweep-C2/target-repo`, display name `sc2-repo` (different, shorter). No turn ever reached the `pwd` tool call (see above — the CLI process never launched at all), so there is no daemon-side receipt of the transmitted cwd to check. Code-path claim from Lane C (`AddRepoView.swift:83` passes separate `name`/`cwd` params, unchanged in this tip) still holds by inspection but is unverified live. |
| 7 | Review pill → ReviewSheetView | **BLOCKED** | No turn completed (no diff exists) — `session-diff-pill` never appeared. |
| 8 | FileViewerView | **BLOCKED** | Same root cause — no real diff to open a file from. |
| 9 | AddCommentSheet | **BLOCKED** | Same root cause. |
| 17 | Receipt `filesTouched` honesty | **BLOCKED** | No receipt was ever generated (no completed turn). |
| 23 | Flight Recorder timeline | **BLOCKED** | Same root cause — no completed turn's tool-call timeline exists to open. |

## Run details

1. **Own tooling bug found first (not a product bug):** my first attempt used
   `LANE_C2_PAIR_CODE=149265 xcodebuild test-without-building ...` — `xcodebuild` only forwards
   `TEST_RUNNER_`-prefixed shell env vars into the XCUITest runner process; a plain-named var set in
   front of the `xcodebuild` invocation is **not** visible inside the test via `ProcessInfo`. Result:
   `LANCER_RELAY_PAIR_CODE` was never set on `app.launchEnvironment`, the app never auto-paired, and
   it eventually surfaced its own **"Couldn't get a reply — No connected machine. Pair one in
   Settings → Trusted Machines."** error (`screenshots/LC2-04-no-connected-machine-run1.png`) — a
   red herring that looks superficially like the approval bug but is purely a test-harness mistake.
   Fixed by re-invoking with `TEST_RUNNER_LANE_C2_PAIR_CODE=<fresh code>` (matching the convention
   Lane E and Lane A2 already documented, which I should have used the first time). **Flagging this
   loudly for future lanes** since it's an easy trap: a plain env var in front of `xcodebuild` looks
   like it should work and silently doesn't.
2. Second run (fresh pair code `258131`, `TEST_RUNNER_LANE_C2_PAIR_CODE=258131`): pairing succeeded
   (`11:27:10 e2e: paired with phone`), dispatch sent at 11:27:44 (34s after pairing — the literal
   "pair then send immediately" scenario), approval delivered same-attempt, decided 5s later — and
   then stalled forever per the root cause above. Killed the test at ~11:34 after confirming via
   direct screenshot (`xcrun simctl io ... screenshot`, not `mcp__XcodeBuildMCP__screenshot` — that
   tool errored against a stale UDID from another lane's global session default, consistent with
   Lane C/D's documented HARD LESSON #2) that the app was durably stuck, not merely slow.
3. `git init` target repo at `/tmp/sweep-C2/target-repo` (greeting.txt, readme.md, notes.txt — 3
   files, 1 commit, `633dfe7`).

## Simurgh feedback (0 items — no friction)

`acquire --model "iPhone 17 Pro" --json`, `renew lease-191 --json` (used 2x), and the lease teardown
all worked exactly as documented. No CLI friction to report this lane.

## Files

- New test: `LancerUITests/SweepLaneC2Tests.swift` (mirrors Lane C's `SweepLaneCTests.swift`
  structure; added a Flight Recorder step at the end that Lane C's version didn't reach either).
- Screenshots: `screenshots/LC2-04-no-connected-machine-run1.png` (harness-bug red herring),
  `screenshots/LC2-05-couldnt-get-reply-after-approve-run2.png` (the real finding — terminal error
  persists 4 minutes after a server-side "approve" decision was recorded).
- Raw evidence: `/tmp/sweep-C2/daemon.log` (pairing + `sent approval` line, no further activity),
  `/tmp/sweep-C2/home/.lancer/audit.log` (full file, 2 lines — ask then approve, nothing after),
  `/tmp/sweep-C2/target-repo` (git log unchanged at `633dfe7 init`, files untouched).

## Top surprises

1. **The fix genuinely works for what it targeted** — `sendApproval`'s bounded retry closed the
   specific delivery race Lane C reproduced. This is real progress, not a false "fixed" claim.
2. **But it exposed the next layer of the same underlying design gap**: `conversation-append`'s
   "ask" path (`dispatch.go:2623-2631`) returns a synchronous terminal `needsApproval` result no
   matter what happens to the async approval afterward — there is no continuation. Fixing the
   delivery race was necessary but not sufficient; the missing piece is wiring an approved decision
   back into actually launching the CLI (or the client re-driving a "resume" call using the
   `AllowRule`/approval outcome instead of a dumb from-scratch Retry).
3. A plain (non-`TEST_RUNNER_`-prefixed) env var in front of `xcodebuild test-without-building` is a
   silent no-op for the runner process — cost about 10 minutes and one wasted pairing code before I
   caught it via a live screenshot showing "No connected machine" instead of the expected approval
   flow.
4. HID taps (`mcp__ios-simulator__ui_tap`) were not even attempted this lane given 3 prior lanes'
   confirmed-dead findings — went straight to XCUITest, which worked correctly for every interaction
   it got to (Add Repo, composer fill, send).
