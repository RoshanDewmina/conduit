# Fable brief — POST-110 phone dogfood blockers (2026-07-13)

> **Superseded for paste:** use the canonical orchestrator PASTE  
> [`docs/plans/2026-07-13-fable-orchestrator-PASTE.md`](2026-07-13-fable-orchestrator-PASTE.md)  
> (inventory appendix: [`2026-07-13-fable-owner-asks-complete.md`](2026-07-13-fable-owner-asks-complete.md)).

This file keeps the original phone-only slice for diff archaeology. Do not paste this alone —
it omitted APNs, plan-limits, Flight Recorder spam, multi-vendor Pi/Cursor, Live Activities,
relay cost, ledger #24–#31, and under-specified the Claude/Codex screenshot port work.

---

## Explicit ask (phone-only — historical)

Fix the **phone daily-driver blockers** found on POST-110 (`0e0b9eba`) owner-device dogfood today. Do **not** run bare `lancerd pair` (relay **732590** confirmed). Prefer Cursor CLI implementers; Sonnet only for relay/`dispatch.go` sensitive paths. Hard/recurring → **Fable** or **GPT-5.6**, not casual Composer.

## What already fixed in working tree (verify + device rebuild)

1. **Ugly Attach** — `LiveThreadView` separate `Label("Attach")` removed; follow-up composer `+` opens `ContextAttachView` (`ChatThreadChrome.onAddContext`).
2. **Spurious "4 files +442 −11" on new chat** — root cause: `LiveThreadView`/`ThreadDetailView` used **`FixtureReviewDataSource`** (fixture JSON is exactly +442/−11). Switched to `RelayReviewDataSource` stub. **Still owed:** wire live `repo.turnDiff` / `repo.sessionDiff` through E2E (daemon RPCs exist; phone never called them). Owner liked review-sheet UI — keep UI, feed real data.
3. **`<task-notification>` import** — daemon now skips those wrappers in `isObservedWrapperUserText` + `claudeUserMessages`. **Still owed:** hide already-imported ledger rows / optional re-attach; iOS display filter for residual XML.

Evidence + screenshots: `docs/test-runs/2026-07-13-post110-session4-continuity/`.

## Still open — recurring bugs (do these)

### P0 — Stuck "Working…" after New Chat "Hi" + dead Follow up

- **Symptom:** Send "Hi" → spinner Working forever; Follow up bar inert (`03-newchat-working-attach-diff.png`).
- **Evidence:** `~/.lancer/audit.log` `conversation-append-launched` for `Hi` at `2026-07-13T19:31:24Z` — dispatch reached daemon. Relay had `EOF` reconnect ~15:35. UI stayed in `ShellLiveBridge.sendState = .working`.
- **Tried:** REL-1 #110 first-send gate (merged); still fails on device.
- **Done-bar:** New Chat "Hi" on paired phone completes to assistant text **without** Retry; Follow up accepts typed send; force-quit → reopen → first send (R1) also works.

### P0 — Agents "Machine unreachable — no successful update yet" while Trusted Machines Connected

- **Symptom:** `02-home-agents-unreachable.png` — Connected on Trusted Machines; Agents degraded copy.
- **Code:** `RunningAgentsFreshness.statusMessage` when `!hasEverSucceeded` after poll failures (`RunningAgentsMapping.swift`).
- **Done-bar:** With zero running agents and healthy relay, Agents shows **"No agents running"** (not unreachable). Mac desk Claude session appears and opens via observed-continue (desk↔phone continuity).

### P0 — Attachment chip spinner never finishes

- **Symptom:** Photo chip stuck uploading; send disabled (`05-attachment-chip-spinner.png`).
- **Path:** `NewChatComposerView` / `relayPutAttachment` / daemon `attachmentPut`.
- **Done-bar:** Photo attach → chip reaches `.done` → send → Mac agent sees host path in prompt.

### P1 — `<task-notification>` gibberish in long "Fix triple…" thread

- **Symptom:** Raw XML bubbles + "(no reply text)" (`04-….png`).
- **Partial fix:** daemon skip on new imports (this pass).
- **Done-bar:** Re-open "Fix triple…" on phone — no XML task-notification bubbles; real turns remain.

### P1 — Live status pill never shows Thinking / tool / Editing

- **Symptom:** Owner only sees generic Working…. G3 `LiveStatusPill` needs daemon `runStatus` events (`LiveStatusPresentation`); absent → legacy Working….
- **Done-bar:** Edit-file turn on phone shows Thinking… / Calling… / Editing… with elapsed; clears when done.

### P1 — Scroll-↓ polish

- **Symptom:** Arrow works but instant/unpolished (#105 shipped mechanics).
- **Done-bar:** Owner accepts animation/position above keyboard (no mid-screen float).

### P2 — Full terminal (owner ask — do not lose)

- **Session:** `~/.claude/projects/-Users-roshansilva-Documents-command-center/4a407758-e5c4-477f-b007-099b48def762.jsonl`
  - L1403: "orca handles terminal… **i want full terminal support**"
  - L2571: Claude Code desktop + Codex app screenshots of live features (`~/Desktop/Views/Screenshot 2026-07-12 at 2.38.*.png`)
- **Spec already written:** `docs/product/2026-07-12-orca-terminal-port-map.md` (Phase 1 re-wire existing PTY — not started).
- **Related:** Cursor mobile ref [cf9acad8](cf9acad8-7a69-4763-8f2d-cc33c55e31bb) + `Downloads/Cursor Mobile App`.
- **Done-bar (Phase 1):** Phone opens Terminal at paired machine cwd; vim/htop survive background.

### P2 — CloudKit C7

- **Blocked on hardware** — owner has no 2nd Apple device today. Do not mark fixed.

### P2 — Live G1→G2 review wire

- After fixture removal, review sheet will be empty until `RelayReviewDataSource` calls real `repo.*` over E2E.
- **Done-bar:** After a real edit turn, session pill + review sheet show **that turn's** files (not fixtures, not whole dirty tree from unrelated work).

## Out of scope for this brief (see complete brief)

Vendor picker uncommitted slice; pairing-durability worktree merge; Siri Phase 2; billing;
APNs / plan-limits / FR spam / Pi+Cursor vendors / Live Activities / relay cost — all in
`2026-07-13-fable-owner-asks-complete.md`.

## Verify

- `cd daemon/lancerd && go test ./...` for transcript wrapper tests
- `cd Packages/LancerKit && swift build`
- Device rebuild + owner re-dogfood checklist in `docs/plans/phone-test-session4.md` priority order + R1/R2
