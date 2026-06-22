# Design — Lock-screen approval journey (Live Activity states + reveal flow)

**Date:** 2026-06-19 · **Status:** approved design, pre-implementation-plan
**Scope:** the first frontend cycle for the 2026-06-19 push work — make the push-driven Live Activity
**expressive** (#2) and wire the **post-unlock reveal** of full approval detail (#3). One coherent journey:
glance (redacted, stateful Live Activity) → tap → open in-app → reveal full command/diff.

> Builds on (read first): the V1 reach work — `feat(liveactivity)` (fc26ea8d, push-driven Live Activity +
> APNs payload redaction + cold-decision gate) and `feat(liveactivity): secure activity push-token
> registration` (051875e3). `ARCHITECTURE.md` §0.1. **The redaction lives on the push payload; the reveal
> lives in-app.** These features ride the relay + APNs path, never a phone-held SSH session.

**Follow-on cycles (NOT this spec):** governance/vendor-trust panel, watch glance polish, a standalone
cold-decision feedback surface. Each is its own spec → plan → build.

## 0. Why this first

The push work shipped the *plumbing* (Live Activity updates while the app is closed; command text redacted
off the lock screen; a killed-app Approve reaches lancerd). But two halves have no frontend yet: the Live
Activity distinguishes state only implicitly, and the redacted push has no in-app "reveal the full truth"
counterpart. #2 + #3 close both and are small because the substrate already exists:
- `LancerLiveActivityWidget` already has lock-screen + Dynamic Island (expanded/compact/minimal) scaffolding.
- `InboxApprovalDetail` already renders the full un-redacted command, args, host, cwd, blast-radius, and
  already biometric-gates critical approve/allow-always (`InboxView.swift:206-262`).
- Notification taps already deep-link into the Inbox with `approvalId` in `userInfo`
  (`NotificationsKit/Notifications.swift`), and a MAJOR-6 cold-launch buffer already replays a tapped
  approval action.

## 1. Architecture decision — representing "decision landed ✓"

Three of the four states map onto existing `ContentState` fields (`pendingApprovals`, `isStreaming`, `cost`).
"Decision landed" is a *transient confirmation* with no field today.

**Decision (approved): add a `lastDecision` transient to `ContentState`.**
- `lastDecision: String?` — `"approved"` / `"rejected"` / `nil` — plus reuse of `lastUpdate` as its timestamp.
- The backend pushes it once after a decision resolves; the widget shows a ✓ for ~4s, then the next push (or
  stale-date) returns it to running or ends the activity.
- **Rationale over a client-side-only flash:** the cold path — a killed-app Approve resolves *server-side*,
  and only a **pushed** state can confirm it on the lock screen while the app is asleep. A local `update()`
  flash can't, so it would undercut exactly the cold-decision gate this builds on.
- Low cost: a one-field addition that already round-trips through the Go encoder + the pinned-`Date` test
  built in fc26ea8d.

## 2. The four Live Activity states (#2)

**Precedence — exactly one primary state shows; cost rides along as secondary:**
**Needs-you > Decision-landed > Running > Idle/done.**

| State | Driven by | Lock-screen / DI-expanded | DI compact | DI minimal |
|---|---|---|---|---|
| **Needs you** | `pendingApprovals > 0` | Amber/red accent, **redacted** action summary, Approve / Reject buttons, count if >1 | `bell.badge` + count, tinted | tinted dot |
| **Running** | `isStreaming` && no pending | Calm accent, agent name + current step, streaming pulse, elapsed | pulsing glyph | quiet dot |
| **Decision landed ✓** | `lastDecision != nil` (~4s) | Green ✓ "Approved"/"Rejected", then → Running or `end()` | ✓ glyph | ✓ |
| **Idle / done** | none of the above | "✓ done · exit 0" or quiet; prepare to end | static glyph | — |
| **Cost** *(secondary overlay)* | `cost > 0` | Always-visible cost; **amber ≥80% of budget, red at 100%** | cost in trailing when no pending | — |

**Treatments:**
- **Needs-you is the loudest** — the only reason to glance. Color + buttons carry it. Shows the **redacted**
  summary only; the §3 reveal is where full detail lives.
- **Decision-landed** is the cold-path payoff: a killed-app Approve pushes `lastDecision` → the lock screen
  flips to green ✓ without the app waking. Auto-clears.
- **Cost** is an overlay, not a primary state — visible in the trailing region when there's room; it only
  *escalates* (amber/red) near the budget threshold lancerd already tracks. No budget data invented.

**Implementation surface:** mostly new tint/label/precedence logic in `LancerLiveActivityWidget`, plus the
`lastDecision` field flowing through. The widget stays **pure presentation** — every state is computed from
`ContentState`; no business logic in the widget.

## 3. The reveal flow (#3)

Three pieces; mostly wiring because `InboxApprovalDetail` already renders full detail.

**3.1 Deep-link routing — tap a Live Activity / notification → open Inbox + auto-present the detail sheet
for that `approvalId`.**
- *Warm* (app alive): the tap already posts `approvalId` in `userInfo` → set `InboxView.detailApproval` →
  the existing `.sheet(item: $detailApproval)` opens.
- *Cold* (app killed): extend the existing MAJOR-6 cold-launch buffer (which already replays a tapped
  approval *action*) to also open the **detail sheet** for that approval — not just process the decision.
  Same launch path the cold-decision gate already primes; no new launch plumbing.

**3.2 The reveal = the existing detail sheet, un-redacted.** Redaction is purely a *push-payload* concern
(done in fc26ea8d); in-app, `InboxApprovalDetail` already shows the real command/args/host/blast-radius.
- **Gate (approved): respect the app-lock setting.** App-lock ON → the app already authenticated at launch,
  so the sheet opens instantly; app-lock OFF → opens with no extra prompt. **No new biometric step for
  viewing.** App-lock-at-launch *is* the reveal gate.
- Critical **approve / allow-always** stays biometric-gated (already implemented, `InboxView.swift:247-252,
  234-240`). Viewing ≠ approving; only the action is gated. #3 adds **zero** new gate code.
- *Accepted tradeoff:* an app-lock-OFF user sees full commands in-app with no biometric step — consistent
  with app-lock being THE in-app privacy control.

**3.3 Diff render for patches — the one net-new view.** Today a `kind == .patch` approval shows
`command`/`args` as summarized text. Render an actual **diff view** (reuse `DiffKit` / `DiffFeature`) inside
the detail sheet so "reveal" surfaces the real change. Non-patch approvals are unchanged.

## 4. Boundaries, data flow, testing

**Module boundaries (existing graph respected):**
- `ContentState.lastDecision` added in `SessionFeature/LiveActivityManager.swift`; mirrored in
  `daemon/push-backend/liveactivity.go` (Go `ContentState` struct + the pinned encoder).
- `LancerLiveActivityWidget` stays pure presentation (states computed from `ContentState`).
- Deep-link: `NotificationsKit` posts `approvalId` → `AppFeature`/AppRoot routes to Inbox →
  `InboxFeature` presents the sheet. The one new edge is **`InboxFeature` → `DiffKit`** for 3.3 — established
  lib (`DiffFeature` already consumes `DiffKit`); verify the dependency edge is declared in `Package.swift`.

**Data flow for the cold ✓:** decision resolves server-side → `push-backend` pushes `ContentState` with
`lastDecision` set → ActivityKit updates the lock screen (app asleep) → ~4s later the next push (or
stale-date) clears it to running / `end()`.

**Testing:**
- Unit: extend `LiveActivityContentStateTests` for `lastDecision` encode/decode; extend the Go Date-pin /
  payload test for the new field; widget **state-precedence** test (needs-you > decision-landed > running;
  cost-as-overlay).
- Unit: warm deep-link routing (`approvalId` → `detailApproval` set); patch approval → diff section renders,
  non-patch → unchanged.
- **Device-only (flagged for owner QA):** cold-path ✓ on the lock screen; cold deep-link (killed app → tap →
  detail sheet opens). Simulator can't prove these (same constraint as the fc26ea8d device items;
  see `docs/LIVE_LOOP_RUNBOOK.md`).

**Verification gate (per `lancer-verification-gate`):** LancerKit/widget changes → `swift build` +
XcodeBuildMCP app-target build (catches `#if os(iOS)` strict-concurrency that SPM skips — the same footgun
that hid the `start()` caller break in the V1 merge); push-backend changes → `go test ./...` from
`daemon/push-backend`; device-only paths → real-device test.

## 5. Open questions / risks (resolve at plan time)
1. **`lastDecision` lifecycle** — confirm the clear mechanism: an explicit follow-up push vs. relying on
   stale-date. Prefer an explicit push so the ✓→running transition is deterministic; budget one extra
   ActivityKit push per decision against the frequent-push throttle (§ the fc26ea8d push budget).
2. **`InboxFeature → DiffKit` edge** — confirm it's allowed/declared; if it introduces an undesirable
   dependency, render the diff via a thin `DiffFeature` entry point instead.
3. **Cost budget source** — confirm the widget can read the budget threshold from `ContentState` (or that
   the backend pre-computes the ≥80%/100% escalation and pushes a level), rather than the widget needing
   policy data it shouldn't hold.
4. **Cold deep-link vs cold decision** — the MAJOR-6 buffer currently replays a *decision*; opening the
   *detail sheet* on cold launch is a distinct intent (review, don't auto-decide). Keep them separate:
   tapping the Live Activity *body* opens detail; tapping an Approve/Reject *button* decides. Verify the
   AppIntent vs. notification-tap routing distinguishes these.
