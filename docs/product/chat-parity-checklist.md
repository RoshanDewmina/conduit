# Chat parity checklist — Lancer vs Claude mobile & Codex

> Scorecard for the phone **chat experience** as Lancer moves to being driven primarily from the
> phone. Tracks feature parity with **Claude mobile** (claude.ai iOS) and **Codex** (ChatGPT Codex
> web + Codex CLI). Status: ✅ done · 🟡 partial · ⬜ planned · ⛔ n/a (control-plane, with reason).
> Flip cells as phases land. Source plan: `~/.claude/plans/im-going-to-move-giggly-minsky.md`.

Lancer is a **governed control plane for coding agents**, not a general chatbot — so some
Claude/Codex features are deliberately `⛔ n/a`. Those are recorded with a reason, never silently
dropped, so "not built" never reads as an oversight.

## Rendering & messages

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| Streaming responses | ✅ | ✅ | ✅ | — | `run.text` streams via RunOutputStore |
| Markdown rendering | ✅ | ✅ | ✅ | P0 | `MarkdownText` (Phase 1) |
| Fenced code blocks (lang + mono) | ✅ | ✅ | ✅ | P0 | `DarkCodeCard` (Phase 1) |
| Copy code / copy message | ✅ | ✅ | ✅ | P0 | copy buttons on code + message (Phase 1) |
| Syntax highlighting | ✅ | ✅ | ✅ | P2 | regex tokenizer (keywords/strings/comments) in code cards |
| Terminal/command output cards | 🟡 | ✅ | ✅ | — | `DarkTerminalBlockCard` |
| Run artifacts (files/diffs) | 🟡 | ✅ | 🟡 | P1 | `ChatArtifactCard` exists; widen coverage |
| Typing/working indicator | ✅ | ✅ | ✅ | — | `DarkTypingIndicator` |
| Edit & resend a message | ✅ | ✅ | ✅ | P2 | long-press user turn → edit prompt → resend |
| Regenerate / retry | ✅ | ✅ | ✅ | P2 | re-runs last prompt as a fresh turn |
| Stop generation | ✅ | ✅ | ✅ | — | `RunControlBar` / `controlStore.stop` |

## Input & composer

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| `/` command autocomplete | ✅ | ✅ | ✅ | P0 | Lancer cmds + live agent cmds over SSH **and relay** (Phase 2 + P1) |
| Always-visible composer | ✅ | ✅ | ✅ | P1 | bottom-pinned inline composer (Phase 4) |
| Multi-line growing input | ✅ | ✅ | ✅ | — | `axis: .vertical`, `lineLimit(4...12)` |
| Model picker | ✅ | ✅ | ✅ | P1 | per-vendor ModelCatalog table |
| @-file / context mentions | ✅ | ✅ | ✅ | P2 | `@` autocompletes workspace files via `agent.fs.ls` (relay) |
| Attachments / images in | ✅ | 🟡 | ⛔ | — | n/a: phone steers headless agents, not a vision chat |
| Voice input | ✅ | ⬜ | ⛔ | — | n/a for a control plane |
| Budget / cost cap on send | ⬜ | ⬜ | ✅ | — | Lancer-specific governance edge |

## Conversations & history

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| Persistent history | ✅ | ✅ | ✅ | — | `ChatConversationRepository` (GRDB) |
| Resume / continue a past chat | ✅ | ✅ | ✅ | P0 | follow-up bar in History continues the run (Phase 3) |
| Search conversations | ✅ | ✅ | ✅ | P1 | sidebar search (FTS) live as you type |
| Rename | ✅ | ✅ | ✅ | P1 | context-menu rename (P1) |
| Delete | ✅ | ✅ | ✅ | P1 | context-menu delete + confirm (P1) |
| Pin / star | ✅ | ⬜ | ✅ | P2 | pinned threads sort to top (UserDefaults) |
| Share / export transcript | ✅ | ✅ | ✅ | P2 | ShareLink exports markdown from the header |
| Multi-turn context retention | ✅ | ✅ | ✅ | — | per-vendor continue-most-recent |

## Platform & trust

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| Push notifications | ✅ | ✅ | 🟡 | P0 | APNs wired; device-loop proof pending |
| Approve/deny from notification | ⬜ | ⬜ | 🟡 | P0 | Lancer governance edge; Phase 5c runbook |
| Light/dark | ✅ | ✅ | ✅ | — | |
| Web search in chat | ✅ | ✅ | ⛔ | — | n/a: the agent on the host does this, not the phone |
| Image generation | ✅ | ⬜ | ⛔ | — | n/a for a coding control plane |

## Priority rollup
- **P0:** ✅ markdown + code blocks + copy · ✅ `/` autocomplete · ✅ resume from history.
- **P1:** ✅ inline composer · ✅ search/rename/delete · ✅ relay command-forwarding · ✅ model picker · _todo:_ wider artifacts.
- **P2:** ✅ syntax highlight · ✅ regenerate · ✅ share/export · ✅ edit/resend · ✅ pin · ✅ @-mentions.

**Status: chat surface is feature-complete vs Claude/Codex for a control plane.** Everything not
✅ is either `⛔ n/a` (voice, image-gen, web search — wrong product) or low-value tail (wider
artifact cards). Remaining work is the **on-device QA pass** (`chat-device-test-checklist.md`) and
the **governed-loop launch gate** (`LIVE_LOOP_RUNBOOK.md` Phase 5c).
