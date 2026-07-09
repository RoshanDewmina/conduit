# Chat UI research notes — parts-style transcript for the Cursor work thread

Date: 2026-07-08 (Wave 0.A pre-dispatch). Purpose: ground the thread-view rebuild in the
patterns modern agent chat UIs converge on, adapted to SwiftUI. Not a redesign doc — the
Cursor-shell visual language stays; this is about the *data model driving the screen*.

## Pattern 1 — messages are lists of typed parts, not one mutable string

Vercel AI SDK UI (`UIMessage.parts`) and every serious agent client (Cursor, Claude
mobile, ChatGPT) model a transcript as an ordered list of typed items:

- `user` part (the prompt bubble)
- `assistant text` part (streamed, then frozen)
- `tool` part (a card: name, input summary, status running/done/failed)
- `error` part (a banner row *inside* the transcript — never a replacement for it)
- terminal artifacts (receipt, question card)

Lancer's mirror already has this data: `ChatTurn` (prompt, `assistantText`, `status`,
`errorMessage`) + `ChatEvent` (kind: output/receipt/…) + `ChatArtifact`. The failure on
device was purely that `CursorWorkThreadView` rendered three ephemeral bridge strings
(`activeThreadPrompt` / `activeThreadResponse` / `activeThreadError`) instead of the turn
list. **Mapping:** one transcript row per `ChatTurn` = user bubble + assistant text +
(error row if `status == .failed`), artifacts interleaved by turn, newest at bottom.

## Pattern 2 — history is append-only; errors and streaming are overlays

- An error never clears prior content. It renders as a distinct row appended after the
  turn it belongs to, with inline Retry / Refresh actions (AI SDK: `regenerate` vs
  `retry`; runbook conflict UX: "changed on another device" + Refresh + Resend).
- While a run streams, the *last* row shows live text (from the bridge) — everything
  above it is the persisted mirror. When the run ends, the persisted turn replaces the
  overlay. The bridge fields are legitimate *only* for the currently-active run.
- "Stop while generating" is standard; Lancer has run-control (`RelayRunControl`) — a
  stop affordance on the streaming row is cheap and honest. (P2, not gate.)

## Pattern 3 — navigation identity is the conversation ID

Cursor mobile threads, ChatGPT, Claude: the route/deeplink is the conversation ID; the
title is display-only and mutable. Lancer routes by prompt-title string today
(`CursorRoute.workThread(String)`), which collides ("hi" twice) and can't survive a
rename. Route payload becomes the `conversationID` (optional for the just-dispatched
thread whose ID isn't known until `started` returns — that route binds to the bridge's
`selectedThreadID` as it resolves).

## Pattern 4 — honest empty/degraded states

- "Working…" tied to run status, not sheet lifecycle.
- Vendor failure shows the vendor's message (model_not_found), not "exit code 1".
- A thread with zero turns yet says "Starting…" — never blank, never mock content.

## What we are NOT doing this wave

- No React/AI-SDK port, no markdown renderer rewrite, no plan/todo cards (no real data).
- Proof Reel stays the receipt scrubber. No video capture.
- No tool-call-level parts from the raw stream yet — turn-level granularity (prompt +
  assistant text + artifacts) is what the mirror stores today and is sufficient for the
  dogfood bar. Tool cards become feasible when the daemon ledger emits structured
  tool events (post-Wave-0).
