# In-thread agent Question cards — Implementation Plan

**Goal:** Render an in-thread agent Question card (answer / multi-choice) on `LiveThreadView`, wired to
the real relay/daemon question path — mirroring the M4 approval-ingest discipline from
`docs/plans/2026-07-10-frontend-rebuild-Plan.md`: register real origins, no cosmetic-only UI, call
production decide/answer paths even when driven by a DEBUG seam.

**Base:** `master` @ `77488c11` (frontend rebuild M1–M4 + sim dogfood D0–D8, all PASS — see
`docs/STATUS_LEDGER.md` Current priority).
**Branch:** `feat/in-thread-questions`.
**Worktree:** `/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe`.

**Owner priorities (2026-07-10):** push physical-device testing as far back as possible; keep shipping
features verifiable on Simulator + a real local `lancerd`/relay, same pattern as
`docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/`.

---

## Why this is next

`docs/plans/2026-07-10-frontend-rebuild-Status.md`'s closing note flagged this explicitly:

> `SessionFeature/Chat/QuestionCardModel.swift`/`AnswerQuestionResolver.swift` ... look like they'd
> support an in-thread *question* card (distinct from the approval card M4 just built) — the Plan's
> M1–M4 scope never included this ... Worth a future milestone if the owner wants it.

Explored (read-only) before writing this plan, and found the exact same class of gap M4 found for
approvals:

- `E2ERelayBridge.handleRelayMessage`'s `"questionPending"` case (`E2ERelayBridge.swift:840`) already
  decodes a `QuestionPendingParams` and posts a `lancerE2EQuestionPending` `NotificationCenter`
  notification with `["questionParams": ..., "machineID": ...]` — confirmed via `grep -rn
  "lancerE2EQuestionPending"` that **nothing subscribes to it**. Posted into the void, same shape as
  the approval gap M4 closed.
- Unlike `E2ERelayMessage.ApprovalData` (which carries no `runId`), **`QuestionPendingParams` does
  carry an optional `runId`** (`LancerDProtocol.swift:535`) — a relay-delivered question *can* be
  correlated to the specific conversation/run it belongs to, not just "which machine it arrived from."
  This milestone still keys the live published-card state by machine (matching `RelayApprovalIngest`'s
  established pattern, and `LiveThreadView` only ever has one active machine at a time), but uses the
  `runId` to persist a real `.question` `ChatArtifact` when the run is known locally, so the answered
  state survives relaunch — a strictly better outcome than the approval card gets today.
- All the model/decision logic already exists and is fully unit-tested, pre-wipe-surviving,
  non-UI: `QuestionCardModel` (decode / toggleOption / setFreeText / isReadyToAnswer / buildAnswer /
  mergeAnswer — `SessionFeature/Chat/QuestionCardModel.swift`) and `AnswerQuestionResolver` (Siri
  voice-answer only, not touched by this plan). `CommandGateway.answerQuestion` and
  `E2ERelayBridge.sendQuestionAnswer` are also already real and wired for the Siri/AppIntent path — this
  plan does not touch either, it adds the missing **relay-ingest → in-thread-render → in-thread-submit**
  leg for the live chat surface, calling the *same* wire method (`bridge.sendQuestionAnswer`) directly
  against the originating machine's bridge (mirroring `RelayApprovalIngest`'s direct-bridge-call
  pattern, not `CommandGateway`'s AppIntent-oriented "any connected machine" fallback).

## Goal (restated, concrete)

A question that a host-side agent asks mid-run (`agent.question.pending` → relay →
`questionPending` → this app) renders as an interactive card in `LiveThreadView`, orthogonal to
`SendState` (same rule M4 established for the approval card — a pending question can appear
regardless of whether the turn is `.working` or `.completed`). Selecting options / entering free text
and submitting sends a real `QuestionAnswerParams` back over the same relay bridge the question
arrived from, and (when the question's `runId` matches a locally known turn) persists the answered
state to GRDB so it's visible after relaunch.

## Non-goals

- Physical device / APNs / Live Activity for questions.
- Away Mode.
- Markdown polish or any rendering mega-pass.
- Rewriting `ThreadDetailView` (Section 7's static mockup) — this plan only touches the **live**
  `LiveThreadView` surface, same boundary M3/M4 already drew.
- Siri voice-answer (`AnswerQuestionResolver`, `AnswerQuestionIntent`) — untouched, already shipped,
  out of scope.
- Multi-question queueing UI (more than one pending question shown at once) — `latestPendingQuestion`
  is single-slot per machine, same simplification `RelayApprovalIngest` made for approvals.
- Reconciling the SSH-only path (`ChatRunPersistenceSink.handleQuestionPending`,
  `ApprovalIngest.swift`) — this app has no SSH fleet (same M4 finding, still true); not touched.

## Milestones

### M1 — Thin card + relay ingest + answer path (implement now)

**Intent:** Close the exact `lancerE2EQuestionPending` gap identified above, end to end, for the single
live-thread surface.

**Write-set:**
- `Packages/LancerKit/Sources/AppFeature/Bridge/RelayQuestionIngest.swift` (new) — `@MainActor
  @Observable` class mirroring `RelayApprovalIngest`:
  - `start()`: subscribes to `Notification.Name("lancerE2EQuestionPending")`, idempotent like
    `RelayApprovalIngest.start()`.
  - On receipt: decodes `QuestionPendingParams` + `RelayMachineID` from `userInfo`. If `runId` is
    present and non-empty, tries `chatRepo.turnByRunID(runId)` and — on a hit — upserts a real
    `.question` `ChatArtifact` (same shape `ChatRunPersistenceSink.handleQuestionPending` already
    builds for the SSH path: `id: "question:\(params.id)"`, `payloadJSON` = encoded
    `QuestionArtifactPayload(event: params)`, `status: .running`). Builds a
    `QuestionCardModel.PresentationState` via `QuestionCardModel.decode(from:)` against that same
    (persisted-or-synthetic) artifact either way, so decode logic is never duplicated.
  - Publishes `private(set) var latestPendingQuestion: [RelayMachineID: QuestionCardModel.PresentationState]`.
  - `toggleOption(machineID:itemIndex:label:)` / `setFreeText(machineID:itemIndex:text:)`: mutate the
    published dict's entry in place via `QuestionCardModel`'s static mutators (view calls these instead
    of holding parallel local state).
  - `submit(machineID:relayFleetStore:)`: builds `QuestionAnswerParams` via
    `QuestionCardModel.buildAnswer`, resolves `relayFleetStore.machine(machineID)?.bridge`, calls
    `await bridge.sendQuestionAnswer(answer)`. On success (or best-effort regardless, matching
    `CommandGateway.persistAnsweredQuestion`'s "daemon already has it, local mirror is best-effort"
    reasoning), merges the answer into the persisted artifact if one exists
    (`QuestionCardModel.mergeAnswer` + `chatRepo.upsertArtifact`) and clears
    `latestPendingQuestion[machineID]`.
- `Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift` — add `@Environment(RelayQuestionIngest.self)`,
  a `pendingQuestion` computed property (same shape as `pendingApproval`), and a `questionCard(_:)`
  view: one section per `ItemState` (question text, options as toggleable buttons or a free-text
  field per `QuestionCardModel`'s existing rules), a Submit button gated on
  `QuestionCardModel.isReadyToAnswer`. Rendered as its own card, independent of the approval card (both
  can theoretically be present; render both, stacked, same as how `replyState` and `approvalCard` are
  already independent of each other).
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — construct `RelayQuestionIngest(database:,
  relayFleetStore:)` alongside `relayApprovalIngest`, `.start()` in the same `.task`, inject via
  `.environment(_:)` at the same point `relayApprovalIngest` is injected.
- DEBUG-only seam (mirroring `LANCER_DEBUG_APPROVAL_DECISION`): an env-var-gated `.onChange` in
  `LiveThreadView` that drives the *same* `RelayQuestionIngest.submit` call the Submit button calls —
  needed because Simulator HID taps are dead in this environment (established finding, `docs/test-runs/
  2026-07-02-device-hub-matrix-simulator-pass.md` + the 2026-07-10 dogfood README). Not a bypass of
  the real answer/persist/send flow, same discipline as every other DEBUG seam in this codebase.

**Acceptance:**
- [ ] `RelayQuestionIngest` compiles and subscribes to the real notification (no new notification name
      invented — reuses `lancerE2EQuestionPending`, which `E2ERelayBridge` already posts).
- [ ] `LiveThreadView` renders a question card when `latestPendingQuestion[activeMachineID]` is non-nil.
- [ ] Submitting calls `bridge.sendQuestionAnswer` on the **originating** machine's bridge (not
      "any connected machine" — mirrors M4's registerRelayOrigin discipline for approvals).
- [ ] `build_sim` green.

**Verify:**
```bash
# XcodeBuildMCP: session_show_defaults → build_sim (scheme Lancer)
# If a local lancerd is up (check `~/.lancer/bin/lancerd doctor`): sim dogfood a real question
# round-trip using the same LANCER_DESTINATION=liveThread seam + a prompt that provokes a host-side
# question (mirrors the 2026-07-10 dogfood session's approval round-trip, D6/D7).
# If no question-provoking daemon flow is available this session: document the failure/idle path
# (no pending question → no card, no crash) as evidence instead, same fallback the Plan allows.
```

**Stop:** implement this milestone only, verify, commit on `feat/in-thread-questions`, update Status,
**stop for owner OK** before any further milestone.

### M2 — Dogfood round-trip proof + polish (not started; owner OK required)

Once a real host-side question-provoking flow is confirmed (or built minimally on the daemon side if
genuinely blocking — constrained by AGENTS.md's "no daemon feature creep unless a blocker bug is
found"), prove the full round-trip live (question appears → answer submitted → daemon receives it),
same rigor as the 2026-07-10 approval dogfood (D6/D7). Possible polish: multi-item question layout,
free-text keyboard-avoidance, confidence caption display (`QuestionCardModel.confidenceCaption`).

### M3+ — Not scoped yet

Anything else (queueing multiple pending questions, Inbox-surface parity with the approval card,
Live Activity) is out of scope until M1/M2 are owner-reviewed.

## Decision log

- 2026-07-10: keyed `latestPendingQuestion` by machine (not run), matching `RelayApprovalIngest`'s
  established simplification — `LiveThreadView` only ever shows one active machine's thread at a time,
  so machine-scoped is sufficient for this UI even though the wire data would support run-level
  precision.
- 2026-07-10: persist a real `.question` `ChatArtifact` when `runId` is known (question wire data
  supports it, approval wire data does't) — strictly better durability than the approval card, cheap to
  add since `QuestionCardModel`/`ChatRunPersistenceSink` already define the exact shape.
- 2026-07-10: reuse `bridge.sendQuestionAnswer` directly against the resolved machine (mirrors
  `RelayApprovalIngest`'s direct-bridge-call pattern), not `CommandGateway.answerQuestion`
  (AppIntent-oriented "any connected machine" fallback, wrong transport-resolution semantics for a
  live thread that already knows its exact machine).

## Related docs

- Rebuild Plan/Status: `docs/plans/2026-07-10-frontend-rebuild-Plan.md`, `-Status.md`
- Sim dogfood proof pattern: `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md`
- Status: `docs/plans/2026-07-10-in-thread-questions-Status.md`
