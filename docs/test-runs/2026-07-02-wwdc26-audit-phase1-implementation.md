# Session report — WWDC26 audit Phase 1 implementation + live device verification

Date: 2026-07-02
Runner: Claude Sonnet 5, working directly with the owner on parallel implementation + physical-device testing
Branch: `master` (all changes committed directly, no feature branch)
Precedes: `docs/wwdc26-lancer-opportunity-audit/` (the 11-file research/audit report this session implements against)
Follows: `docs/test-runs/2026-07-02-relay-siri-liveactivity-session-report.md` (same-day, earlier session)

## Executive summary

This session took the WWDC26 opportunity audit's Phase 1 roadmap (four items: approval
content-hash binding, risk-tiered fail-closed no-client policy, E2E relay replay resistance, and
the Live Activity background-lifecycle fix) from report to merged, tested, and **live-verified on
a physical device**. Two parallel implementation lanes ran in isolated git worktrees, were
carefully reconciled against a moving `master`, and merged. A code-review pass before merging
caught a P0 integration gap (the phone's actual approve/deny UI never echoed the new content
hash) that would have silently broken every real-device approval; a dedicated worktree completed
that gap. All of this was then pushed to a real paired iPhone and a real Mac-side daemon for live
testing — which is where the session earned its keep: **four additional, previously-unknown, real
production bugs were found and fixed**, none of which any amount of unit testing or code review
would have caught, because none of them were about logic correctness in isolation — they were
about cross-process message routing, UI wiring gaps, and a genuine concurrency race.

**Sixteen commits landed on `master`, all reviewed, tested, and (for the daemon/app pieces)
live-verified against a real device.** No feature branch was used; every commit was merged
directly, matching this repo's established workflow for same-day iterative work.

The single most significant fix is the last one (`e61a365e`) — a data race in the E2E relay's
message-sending code that silently reordered and dropped chat-dispatch output frames under
concurrent load, causing the exact "app hangs forever waiting for a response" symptom the owner
hit live. It was invisible to every prior test in this session (including the approval-flow
live test, which only ever sends one message at a time) and was found only because the owner
tried an actual multi-chunk streaming chat on a real device.

---

## Part 1 — What was planned (recap)

`docs/wwdc26-lancer-opportunity-audit/09-recommended-roadmap.md`'s "Phase 1 — foundational
platform work" specified four items, in this order:

1. **Approval content-hash binding** — bind an approval decision to a hash of the exact
   command/diff/tool-input the user reviewed, so a stale or substituted approval can't execute.
2. **Risk-tiered fail-closed no-client policy** — stop the blanket 8-second
   auto-approve-when-unreachable behavior for high/critical-risk actions.
3. **E2E relay replay resistance** — add a sequence number so a captured/replayed encrypted frame
   can't re-trigger a dispatch or decision.
4. **Live Activity lifecycle fix** — stop ending every Live Activity on app background, register
   Live Activity push tokens over the relay-only path, add a backend push-to-start sender, and add
   a risk-level field to the content state.

These were the top four items of `08-feature-opportunity-ranking.md`'s 25-item ranked table,
chosen because none of them depend on any Apple API version gate and all four close either the
largest confirmed security gap or the largest confirmed doc/code mismatch found by the audit.

## Part 2 — Parallel implementation (Lane A + Lane B)

Per this repo's `lancer-parallel-handoff` skill, work was split into two isolated worktree lanes
rather than four fully-independent ones, because three of the four items all touch
`daemon/lancerd/server.go` (a documented hot file) and item 3 was explicitly designed to bind into
the same authenticated envelope as item 1 — a real dependency, not just a file collision.

### Lane A — daemon trust-boundary hardening (items 1–3)

Worktree branch `worktree-agent-ac868f62b898a9bd9`, 3 commits:

- **`7032dc09` — content-hash binding.** `computeContentHash` (Go `approval.go` / Swift
  `Approval.computeContentHash`) is a plain SHA-256 over
  `command\x1fpatch\x1fcwd\x1ftoolInput` — deliberately **not** an HMAC keyed to the E2E session
  key, because `push-backend` (the REST-fallback decision path) never holds that key, and all
  three delivery paths (SSH RPC, E2E relay, REST poll) must verify identically.
  `approvalStore.resolve` now takes a `contentHash` param and rejects (without consuming the
  pending approval) on mismatch, logging it as a security event.
- **`6c273a57` — risk-tiered fail-closed no-client policy.** Added
  `policy.PermitsNoClientGrace(risk int)`, reusing the existing `riskOrder`/`RiskLabel`
  classification. In `handleHookWithNotify`, the no-client fast-path condition gained
  `&& policy.PermitsNoClientGrace(event.Risk)` — high/critical-risk events with no reachable
  client now fall through to the same indefinite-wait path a reachable client gets, instead of
  auto-approving after 8 seconds.
- **`60fcf7a4` — E2E replay resistance.** A per-direction monotonic sequence is wrapped around
  the plaintext *before* encryption (`SeqFrame`/`wrapSeq`/`unwrapSeq` in Go, `SeqFrame` in Swift)
  — authenticated by the AEAD but never relay-visible. A `replaySequencer`/`ReplaySequencer`
  rejects non-strictly-increasing sequences, reset on every new pairing generation (mirroring the
  existing `connectGeneration` idiom from an earlier session's stale-socket fix).

New tests: `TestComputeContentHashDeterministicAndFieldSensitive`,
`TestApprovalResolveRejectsContentHashMismatch`, `TestDecisionPollerThreadsContentHash`,
`TestHookHighRiskNoClientDoesNotAutoApprove`, `TestE2EReplayedFrameRejected` (Go);
`ApprovalContentHashTests`, `E2EReplayResistanceTests` (Swift, including a cross-language hash
vector verified against the live Go output).

### Lane B — Live Activity lifecycle fix (item 4)

Worktree branch `worktree-agent-a7bcc240610c17f7b`, 4 commits:

- **`888c3d73` — stop ending Live Activities on app background.** Removed the
  `scenePhase == .background` handler in `AppRoot.swift` that called
  `LancerLiveActivityManager.shared.endAll()` — this directly contradicted
  `ARCHITECTURE.md`'s own claim of push-driven Live Activity updates while the app is closed.
- **`48c419a7` — relay-only Live Activity token registration.** New `activityTokenRegister`
  `E2ERelayMessage` case + `ActivityTokenRegisterData` struct, sent from
  `E2ERelayBridge.swift`, mirroring the existing `deviceRegister`/`deviceRegistered` pattern.
- **`2d297497` — risk level in Live Activity content state.** Added a risk field to
  `LancerSessionAttributes.ContentState`, with redaction above a threshold in
  `LancerLiveActivityWidget.swift`, plus new risk-tiered `#Preview` states.
- **`50dc3e44` — push-backend push-to-start sender.** An `event: "start"` APNs payload path in
  `daemon/push-backend/liveactivity.go`, so a Live Activity can originate purely from a server
  push while the app is fully closed.

New tests: `liveactivity_test.go` (Go, 147 new lines), `LiveActivityContentStateTests`,
`LiveActivityPresentationTests` (Swift).

### Reconciliation and merge

Both worktrees had branched from an earlier commit (`f51a4217`) than the eventual merge target
(`31d8f528`, itself several commits ahead — including the reachable-client-never-times-out fix and
the `connectGeneration` stale-socket fix from the prior same-day session). Merging required
resolving four textual conflicts (`server.go` ×2, `e2e_router.go`, `daemon_test.go`,
`E2ERelayClient.swift`) — all confirmed non-substantive on inspection (either doc-comment-only
conflicts, or two independent additions at the same insertion point) and reconciled by hand
(`e6a2afb8`). A follow-up merge (`2db23d23`) combined Lane A and Lane B, which auto-merged cleanly
since their only shared file (`E2ERelayMessage.swift`) was touched in disjoint, additive regions.
The combined result was merged to `master` as `47f86639`, verified via `go build/vet/test` (both
Go modules), `swift build`/`swift test` (488 tests/87 suites + 13/2 passing), and a real
`XcodeBuildMCP` app-target `build_sim` (SUCCEEDED, 0 errors, 0 warnings).

**A process note for future sessions:** `Agent(isolation: "worktree")` calls in this session
consistently branched from a stale, pre-session base commit rather than current `master` HEAD,
twice in a row for the P0 follow-up task below. The workaround was creating the worktree manually
(`git worktree add --detach <path> <current-HEAD-sha>`) and dispatching a plain `Agent` call with
explicit "cd into this exact directory" instructions instead of relying on `isolation`. Worth
flagging if this tool's worktree-base behavior needs a fix upstream.

## Part 3 — The P0 gap: content-hash threading (found during merge review, not by any test)

Before declaring the merge safe, a direct trace of the actual phone-side "tap Approve" code path
(`ApprovalRelay.forwardDecisionOnly` → `E2ERelayBridge.sendDecision` /
`DaemonChannel.respond` / `postDecisionToBackend`) found that **none of the five real
approve/deny entry points actually sent the new content hash** — every real device decision would
have been rejected by Lane A's own new daemon-side check. This was not caught by any unit test,
because the tests exercised the wire types and the resolve-logic in isolation, never the actual
UI-to-wire call chain.

A dedicated pass (after two failed dispatch attempts due to the worktree-base issue noted above,
finally run in a manually-created worktree) threaded the hash through all five entry points:

1. Base Inbox UI (`InboxViewModel.decide` → `decisionSink`)
2. Live/relay-attached Inbox (`LiveInboxViewModel.decide` → `onDecision`)
3. Watch decisions (no in-memory `Approval` in scope — added
   `ApprovalRepository.find(id:)` to read the persisted row's hash back after `decide()` commits it)
4. Siri/CommandGateway (`ApprovalRelay.enqueue` — same `find(id:)` pattern)
5. Fleet-slot direct SSH channel (`DaemonChannel.respond`, both the primary send and the
   queued-redelivery/drain paths)

Plus two prerequisite gaps found and fixed along the way, both required for correctness, not scope
creep: `contentHash` wasn't a persisted GRDB column (added migration `v11`), and the SSH-path wire
struct (`ApprovalPendingParams`) had no `contentHash` field at all, so SSH-received approvals could
never populate it regardless of any sender-side fix.

Commit `68215211` (implementation, 15 files, 301 insertions) + `5ea05c36` (merge into `master`).
Verified via a genuinely clean rebuild (`rm -rf .build` — an earlier fast/cached `swift build` had
silently missed a real compile error caused by a missing `import InboxFeature`, a lesson repeated
later in the session), 488/87 + 13/2 tests, and an app-target `build_sim`.

## Part 4 — Live device verification (where the real bugs surfaced)

With all four Phase 1 items merged and unit-verified, the session moved to a real paired iPhone
and the owner's real Mac-side daemon — the actual "prove it on Device Hub" ask. This is where four
additional, previously-unknown production bugs were found. None were hypothetical; all were
observed directly, diagnosed from first evidence (daemon logs, audit trail, or direct code trace),
fixed, and re-verified live.

### Finding 1 — deployed daemon binary was 9 hours stale

Before any live test could mean anything, the actually-running production `lancerd` (PID 63558,
launchd-managed, binary dated `Jul 2 08:39`) predated every commit in this session. Rebuilt from
current `master` and redeployed via the safe stop→backup→move→start sequence (never `cp` onto a
running binary in place — this repo's own established gotcha). Also discovered, via `lsof`, two
orphaned isolated test-daemon instances from an earlier same-day session
(`~/.lancer-simtest`, `~/.lancer-machine2`) — confirmed harmless (separate state dirs/sockets) and
left untouched.

### Finding 2 — Home screen's approval review sheet silently no-oped for relay-only approvals

**Symptom:** tapping Approve/Deny/Choose on the Home screen's "N agents need you" review sheet did
nothing — no daemon log line, no audit entry, the card just stayed.

**Root cause:** `LancerHomeView.approvalReviewSheet` resolved the inbox VM to act on via
`fleetStore.slot(forApprovalID:)?.inboxVM` — bare optional chaining. A `FleetStore.Slot` is
created *only* in `AppRoot`'s legacy SSH-connect flow. A relay-only pairing — the actual
V1-primary transport per `ARCHITECTURE.md`, no SSH session ever held — never creates a slot, so
the lookup always returned `nil` and the entire `decide()` call silently vanished. This is the
app's single most prominent approval surface, non-functional for the primary architecture. **This
bug predates this session entirely** — confirmed by grep, `LancerHomeView.swift` was untouched by
every prior commit today.

**Fix (`c4cc1412`):** threaded the same `activeInboxViewModel` fallback `AppRoot` already uses
elsewhere (`selectedFleetSlot?.inboxVM ?? liveInboxVM ?? inboxVM`) into `LancerHomeView` as a new
required `defaultInboxVM` init param; falls back to it before calling `decide()`.

**Verified:** live, end-to-end, on the physical device — a real Claude Code `fileWrite` escalated
through the daemon, showed on the Home review sheet, tapping Approve was confirmed in the daemon
audit log (`action: "approve"`, no hash-mismatch rejection) and the gated write actually executed
(`cat`'d the resulting file, contents matched exactly).

### Finding 3 — the daemon silently dropped `activityTokenRegister`

**Symptom:** discovered via a `e2e: unhandled message type: activityTokenRegister` log line while
investigating why the Live Activity wasn't appearing.

**Root cause:** Lane B's Swift side correctly sends this new message; Lane B's Go side correctly
implements `postActivityTokenRegistration` (POSTs to push-backend's already-built
`/register-activity-token`, right auth, right body shape) — but nothing in `e2e_router.go`'s
`handleMessage` switch ever routed the incoming message to that function. It fell through to the
generic `default` case and was discarded every time.

**Fix (`3faaf404`):** added the missing `case "activityTokenRegister":` arm, mirroring the
adjacent `deviceRegister` case's structure.

**Verified:** `go build/vet/test` clean; deployed; confirmed via a follow-up simulator test that
pairing no longer logs the "unhandled" line for this message type.

### Finding 4 — Live Activity ended after the first response, not "while the chat is active"

**Symptom:** the owner reported the Dynamic Island appeared, then disappeared within seconds of
the first response finishing — even though the chat thread was still open.

**Root cause:** `runIsTerminal` (`currentRun?.isTerminal`) is `status == "exited" || status ==
"failed"` on the **current turn's** underlying process — every individual response finishing
flips this true, since each follow-up mints its own new `runId`/process. The
`.onChange(of: runIsTerminal)` handler called `.end(activityKey:)` immediately on that flip, with
no distinction between "this turn is done" and "the user is done with this chat." **This is also
pre-existing behavior**, not something the background-`.endAll()` fix (Finding in Lane B) touched
— that fix was specifically about *backgrounding*, not about *turn-completion*.

**Fix (`74f880e0`):** defer the end behind a 90-second grace window (`endActivityTask`, a new
`@State private var` cancellable `Task`), cancelled if `sendFollowUp` successfully starts a new
turn before it fires — which already correctly calls `.update()` on the same `liveActivityKey`,
so a genuine multi-turn conversation now stays one continuous Live Activity as originally intended.

**Verified:** live on the physical device after redeploy — confirmed by the owner ("Live
activitis are working awsome!").

### Finding 5 — the most significant fix: a real concurrency race in `sendMessage`

**Symptom:** the owner sent a chat message; the composer showed an infinite spinner with no
response ever streaming back. The daemon's own audit log showed the dispatch had actually launched
successfully (`action: "dispatch-launched"`, `effect: "allow"`) — so the failure was specifically
in the daemon-to-phone direction, not the dispatch itself. This was the opposite direction from
every prior live test in this session (approval decisions flow phone→daemon; those all worked).

**Root cause:** `e2eRelayClient.sendMessage` (Go) assigned the new replay-resistance sequence
number under one `c.mu.Lock()`/`Unlock()` pair, then did variable-time work (sequence-wrap,
AEAD-encrypt, JSON-marshal) **unlocked**, before re-acquiring the lock only for the final
`websocket.Message.Send`. Two concurrent `sendMessage` calls — exactly what happens during chat
streaming, where many rapid `agentRunOutput`/`agentRunStatus` notifications fire from concurrent
callback contexts — could race in that unlocked window: whichever finished encryption first won
the wire, independent of which one had been assigned the lower sequence number. An out-of-order
arrival is precisely what the phone's `ReplaySequencer` (added by this session's own Lane A work)
is designed to reject, since `accept()` requires strictly increasing sequence numbers. A reordered
frame carrying output the UI was waiting on was silently dropped, and the composer hung forever
with no error — because from the daemon's perspective, the send had "succeeded" (no error
returned; the frame reached the relay, just out of order relative to another frame).

This is a genuine, non-hypothetical logical-ordering race that Go's `-race` detector does **not**
catch by itself (every individual field access was correctly mutex-protected in isolation; the bug
was in the *ordering guarantee* across two separate critical sections, not in raw memory safety) —
found only by observing real behavior on a real device under real concurrent load, exactly the
kind of bug this session's live-testing phase existed to catch.

**Fix (`e61a365e`):** hold `c.mu` for the entire seq-assign → wrap → encrypt → send sequence
(single `Lock()`/`defer Unlock()`), removing the second lock acquisition entirely. This is the
semantically correct design regardless of performance — the whole point of a sequence number is a
wire-order guarantee, so assignment and actual transmission order must be atomic relative to each
other, not just individually thread-safe.

**Verified:** `go build/vet` clean; `go test ./... -race -count=1` clean (no data races, 32.4s);
deployed to the production daemon; confirmed live by the owner immediately after.

## Part 5 — Full commit list (chronological, all on `master`)

| Commit | Summary |
|---|---|
| `888c3d73` | Stop ending Live Activities on app background |
| `2d297497` | Add risk level to Live Activity content state |
| `48c419a7` | Forward Live Activity tokens over the relay-only path |
| `50dc3e44` | Add push-to-start sender for closed-app Live Activities |
| `7032dc09` | Bind approvals to a content hash of what the user reviewed |
| `6c273a57` | Fail closed on high/critical-risk no-client escalations |
| `60fcf7a4` | Add replay resistance via per-direction sequence numbers |
| `e6a2afb8` | Merge: reconcile Lane A trust-boundary hardening onto current master |
| `2db23d23` | Merge: combine Lane A with Lane B |
| `47f86639` | Merge: land trust-boundary hardening + Live Activity lifecycle fix (Phase 1, items 1-4) |
| `68215211` | Thread contentHash through every phone-side decide path |
| `5ea05c36` | Merge: thread contentHash through phone-side approve/deny UI paths |
| `c4cc1412` | Fix: Home screen's approval review sheet silently no-ops for relay-only approvals |
| `3faaf404` | Fix: wire the activityTokenRegister message to its already-built handler |
| `74f880e0` | Fix: don't end the activity just because one turn's process exited |
| `e61a365e` | Fix: serialize sendMessage's seq-assign through wire-send as one critical section |

16 commits, 47 files changed, +1656/−148 lines (daemon Go + Swift app/widget + tests). All on
`master`, none pushed to any remote (no push was requested or performed).

## Part 6 — What is verified vs. not yet fully verified

**Verified with strong, direct evidence (logs, audit trail, or live device confirmation):**
- All four Phase 1 items — code-verified via `go test`/`swift test`/app-target build at merge
  time; the content-hash binding and Live Activity lifecycle specifically re-verified live on a
  physical device via Findings 2–5 above (the trust-boundary work's actual end-to-end proof came
  from watching a real approval round-trip correctly, not just from unit tests).
- The `sendMessage` race fix — confirmed live: the exact "chat hangs forever" symptom stopped
  reproducing immediately after redeploy.
- The Live Activity backgrounding + grace-period fix — confirmed live by the owner after the
  final redeploy ("Live activitis are working awsome!").
- The Home-screen approval bug fix — confirmed via a full live round-trip (daemon audit log
  showing `action: "approve"`, and the gated file write actually executing with the expected
  content).

**Not yet fully, independently verified — flagged honestly, not glossed over:**
- **Push-to-start while the app is fully closed** (not just backgrounded) — the
  `activityTokenRegister` wiring fix (Finding 3) should make this work now that the token
  actually reaches push-backend, but the full closed-app → server push → Live Activity starts
  cold flow was not tested live this session. This is the one remaining item from the original
  Phase 1 scope.
- **Replay resistance and risk-tiered fail-closed policy** — verified via unit/integration tests
  and via the race-detector-clean rebuild, but not separately exercised live with an actual
  replayed frame or an actual high-risk no-client scenario on the physical device (both are
  adversarial/synthetic scenarios, harder to trigger via normal live usage than the other items).
- Whether any *other* concurrency races exist in the E2E relay code beyond the one found in
  `sendMessage` — the fix was scoped to the specific function implicated by live evidence; a
  broader audit of the relay client/router for similar lock-then-unlock-then-relock patterns was
  not performed this session.

## Part 7 — What's next

Per `docs/wwdc26-lancer-opportunity-audit/09-recommended-roadmap.md`, the original Phase 1 plan is
now functionally complete and live-verified (modulo the closed-app push-to-start gap above). Two
paths forward, not mutually exclusive:

**Close out Phase 1 fully:**
- Live-test push-to-start while the app is fully force-quit (owner-gated — needs the physical
  device again, not something verifiable from a dev machine alone).
- Consider a targeted audit of `e2e_client.go`/`e2e_router.go` for other instances of the same
  "lock, release, do variable-time work, relock" pattern that produced Finding 5 — this was found
  reactively, not via a systematic sweep.

**Move to Phase 2** (`09-recommended-roadmap.md`'s next section):
- Resolve the iOS 26.0-vs-27.0 deployment-target drift (`02-current-codebase-state.md`) — cheap,
  and the actual blocker for `AppIntentsTesting` and Core Spotlight semantic indexing.
- `AppEntity`/`AppIntentsTesting` adoption — the exact bug class that shipped twice in production
  before this session (Siri phrase registration, dual-target execution crash, both from the
  *earlier* same-day session) has zero regression coverage; this framework would have caught both.
- Device Hub regression matrix formalization (`05-device-hub-testing-plan.md`) — turn today's
  live-testing discipline into a standing, repeatable pre-release checklist rather than
  one-off reactive debugging.

**Phase 3 (prototype-tier, further out):** the Approval Copilot (Foundation Models,
evidence-retrieval-first per `06-ai-and-approval-copilot.md`) and Core Spotlight semantic search
(`03-app-intents-and-siri.md`) — both real differentiators per the original audit, but
appropriately sequenced after the trust-boundary and lifecycle work this session completed, per
the audit's own stated priority ("harden the approval trust boundary... before exposing
entity-backed attention surfaces").

## Part 8 — Process notes for future sessions

- **`Agent(isolation: "worktree")` branched from a stale pre-session base commit, twice.** Worked
  around by manually creating the worktree (`git worktree add --detach`) at the correct HEAD and
  dispatching a plain (non-isolated) `Agent` call with explicit directory instructions. Worth a
  bug report if this recurs.
- **A "fast" `swift build` can be a stale-cache false positive, not a real clean-compile
  confirmation.** Hit this twice this session — once during Lane A merge review, once during the
  content-hash P0 fix — both times a suspiciously-fast build (under 5s) masked a real compile
  error that only surfaced on `rm -rf .build && swift build`. When verification stakes are high
  (pre-merge, pre-device-deploy), always force a clean rebuild rather than trust an incremental
  one's speed as a correctness signal.
- **Unit tests did not, and structurally could not, catch three of the four live-discovered
  bugs** (Findings 2, 3, 5) — they were about cross-module UI wiring, cross-process message
  routing, and a concurrency ordering guarantee, none of which a unit test in isolation
  exercises. This is the concrete case for why "code-verified" and "live-verified" are tracked as
  separate confidence levels in this report, matching the convention established in the prior
  same-day session's own report.
- **Never `cp` onto a running `~/.lancer/bin/lancerd` in place.** Followed the established
  stop-service → backup → `mv` → start-service sequence for every one of this session's four
  daemon redeploys; no incidents.
