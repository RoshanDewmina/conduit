# Chat surface — device test checklist

> Run this on a **real iPhone** (the simulator can't fire SwiftUI taps reliably and can't receive
> APNs). Build/install the `Lancer` scheme from Xcode (needs the Apple PLA + signing resolved
> first). Tick each box; note anything off. Covers the P0+P1 chat work shipped on `rebrand/lancer`.

## 0. Setup
- [ ] App installed on device, opened, notifications allowed on first launch.
- [ ] Paired with a machine (relay code via `lancerd pair`, or SSH host). Settings → Connection
      shows relay connected.
- [ ] At least one agent shows in the composer's agent chip (e.g. "Claude · mac-studio").

## 1. Composer (inline, ChatGPT/Claude style)
- [ ] New Chat shows a **bottom-pinned composer** (not a button that opens a drawer).
- [ ] Typing grows the field; placeholder reads "Message, or type / for commands…".
- [ ] Agent·host chip is tappable → agent picker opens.
- [ ] The slider/options button opens the drawer (model, budget, project).
- [ ] Send button is disabled until there's text + a non-offline agent.

## 2. `/` command autocomplete
- [ ] Typing `/` shows a floating palette **above** the composer.
- [ ] Two sections: **LANCER** (app commands: /new, /clear, /model, /budget, /agent, /workspace)
      and **AGENT** (your machine's real commands + skills + built-ins).
- [ ] Agent section reflects **your** `.claude/commands` + skills (e.g. project commands you have).
- [ ] Filtering: `/re` narrows to matching commands.
- [ ] Tap a **Lancer** command → runs its action (e.g. /agent opens the picker).
- [ ] Tap an **Agent** command → inserts `/name ` into the prompt to keep typing.
- [ ] Works over **relay** (not just SSH) — agent commands still populate on a relay-paired host.

## 3. Send + markdown rendering (the big visual upgrade)
- [ ] Send a prompt; a user bubble appears (right, accent) and a working indicator shows.
- [ ] Assistant reply renders **markdown**: **bold**, *italic*, inline `code`, bullet/numbered lists,
      headings — not raw asterisks/hashes.
- [ ] Fenced code renders as a **dark code card** with a language label.
- [ ] Code card **Copy** button copies the code (paste elsewhere to confirm); **wrap** toggle works.
- [ ] **Syntax highlighting** in code cards (keywords/strings/comments tinted). _(P2)_
- [ ] Copy-message button under an assistant reply copies the full text.
- [ ] Streaming: text appears incrementally without flicker; indicator morphs into the reply.

## 4. Run controls + follow-up
- [ ] Stop button cancels a running agent.
- [ ] Follow-up bar sends a continuation; a new turn appends and streams.
- [ ] Budget cap (options) is respected (blocked message if exceeded).
- [ ] **Regenerate** re-runs the last prompt as a fresh turn. _(P2)_

## 5. History (resume)
- [ ] Open a past conversation from **Workspaces** (thread list for a repo or All Repos).
- [ ] Persisted turns render (prose + any terminal/error cards + artifacts).
- [ ] A **follow-up bar** is present (conversation is resumable, not read-only).
- [ ] Sending a follow-up **continues the run** (new turn streams live) and persists.
- [ ] Offline host → a clear "couldn't continue" alert (no silent failure).

## 6. Conversation management (Cursor shell)
- [ ] Open the **Search** sheet (toolbar) and filter chats live as you type (FTS).
- [ ] Long-press a thread → context menu with **Rename** and **Delete**.
- [ ] Rename → title updates immediately in the list.
- [ ] Delete → confirm dialog → row disappears; gone after relaunch.
- [ ] **Share/export** a transcript from the header. _(P2)_

## 7. The governed loop (the product promise — P0 launch gate)
- [ ] Background/close the app; trigger an `ask` on the host.
- [ ] Lock-screen / Dynamic Island notification fires with Approve/Reject.
- [ ] Tapping **Approve** on the lock screen unblocks the agent **without** foregrounding the app.
      (Full steps: `docs/LIVE_LOOP_RUNBOOK.md` Phase 5c.)

## Simulator pre-verification (done 2026-06-22, before device pass)

What was verified on the iPhone 17 Pro simulator before the device pass, so the device pass can focus on
real taps + the live loop:

- **Builds/tests:** `swift build` + app-target `build_sim` SUCCEEDED; **419 LancerKit tests / 68
  suites + 8 HostServiceClient + all Go daemon tests pass.**
- **Rendered + screenshotted (dark + forced-light):** markdown reply with bold/inline-code/ordered
  list; `swift` code card with syntax highlighting (keyword/string/comment tints) + Copy + wrap;
  `/` autocomplete (LANCER + AGENT sections, filtered by `/re`); `@` file mention (filtered by
  `@App`); inline composer; Cursor shell (Search sheet, Workspaces thread list, connection banner).
  Route `chat-overlays[-light|-dark]` added as the fixture.
- **Accessibility tree audited** (real interaction proof, since sim HID taps don't fire SwiftUI
  actions here): composer — Send correctly **disabled when empty**, agent chip / options / shell
  controls all labeled; `/` + `@` rows are enabled AXButtons with combined labels + badges; code card Copy /
  wrap present; Workspaces thread rows (rename/pin/delete context menus) present + labeled.

**Not verifiable on the simulator — must be the device pass (§1–§7 below):** firing button actions
(tap-and-observe), long-press context menus (rename/delete/pin/edit-resend) actually opening, live
streaming/resume/regenerate against a real daemon, and APNs (§7). These are exactly what the device
checklist covers.

## Report
Note pass/fail per section + any screenshot. Failures in §3–§6 are chat-experience regressions;
§7 is the V1 launch gate. Update `docs/product/chat-parity-checklist.md` if a feature's real-device
behavior differs from its scored status.
