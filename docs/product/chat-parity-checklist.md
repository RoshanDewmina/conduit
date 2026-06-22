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
| Markdown rendering | ✅ | ✅ | ⬜ P0 | P0 | plain `Text` today → `MarkdownText` (Phase 1) |
| Fenced code blocks (lang + mono) | ✅ | ✅ | ⬜ P0 | P0 | `DarkCodeCard` (Phase 1) |
| Copy code / copy message | ✅ | ✅ | 🟡 | P0 | text-select only; add copy buttons (Phase 1) |
| Syntax highlighting | ✅ | ✅ | ⬜ | P2 | nice-to-have after code cards land |
| Terminal/command output cards | 🟡 | ✅ | ✅ | — | `DarkTerminalBlockCard` |
| Run artifacts (files/diffs) | 🟡 | ✅ | 🟡 | P1 | `ChatArtifactCard` exists; widen coverage |
| Typing/working indicator | ✅ | ✅ | ✅ | — | `DarkTypingIndicator` |
| Edit & resend a message | ✅ | ✅ | ⬜ | P2 | |
| Regenerate / retry | ✅ | ✅ | ⬜ | P2 | |
| Stop generation | ✅ | ✅ | ✅ | — | `RunControlBar` / `controlStore.stop` |

## Input & composer

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| `/` command autocomplete | ✅ | ✅ | ⬜ P0 | P0 | both Lancer + live agent cmds (Phase 2) |
| Always-visible composer | ✅ | ✅ | 🟡 | P1 | behind a drawer tap; inline option (Phase 4) |
| Multi-line growing input | ✅ | ✅ | ✅ | — | `axis: .vertical`, `lineLimit(4...12)` |
| Model picker | ✅ | ✅ | 🟡 | P1 | hardcoded list → real source (Phase 4) |
| @-file / context mentions | ✅ | ✅ | ⬜ | P2 | could reuse `agent.fs.ls` |
| Attachments / images in | ✅ | 🟡 | ⛔ | — | n/a: phone steers headless agents, not a vision chat |
| Voice input | ✅ | ⬜ | ⛔ | — | n/a for a control plane |
| Budget / cost cap on send | ⬜ | ⬜ | ✅ | — | Lancer-specific governance edge |

## Conversations & history

| Feature | Claude mobile | Codex | Lancer | Pri | Note |
|---|---|---|---|---|---|
| Persistent history | ✅ | ✅ | ✅ | — | `ChatConversationRepository` (GRDB) |
| Resume / continue a past chat | ✅ | ✅ | ⬜ P0 | P0 | read-only today → live (Phase 3) |
| Search conversations | ✅ | ✅ | 🟡 | P1 | sidebar search field unwired (Phase 3) |
| Rename | ✅ | ✅ | ⬜ | P1 | Phase 3 |
| Delete | ✅ | ✅ | 🟡 | P1 | repo supports it; wire swipe (Phase 3) |
| Pin / star | ✅ | ⬜ | ⬜ | P2 | optional |
| Share / export transcript | ✅ | ✅ | ⬜ | P2 | |
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
- **P0 (this round):** markdown + code blocks + copy, `/` autocomplete, resume from history.
- **P1 (next):** inline composer, real model picker, search/rename/delete, wider artifacts.
- **P2 (later):** syntax highlight, edit/resend, regenerate, pin, share/export, @-mentions.
