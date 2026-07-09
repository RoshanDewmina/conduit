# Chat interface parity — gap inventory + build-on-references plan

Date: 2026-07-09 (owner ask after first successful multi-turn phone test). Question:
stop building the chat UI from scratch — what references/libraries do we build on, and
what is the full gap list to a full-fledged agent chat interface?

## What we build on instead of hand-rolling

| Need | Reference / library | Note |
|---|---|---|
| Message/parts data model | **Vercel AI SDK `UIMessage.parts` spec** | Already adopted conceptually in `CursorTranscriptMapper` (turn sections). Use its part taxonomy (text / reasoning / tool / file / error) as the schema target — spec only, no React port. |
| Markdown + code blocks | **swift-markdown-ui (gonzalezreal/MarkdownUI)** | Owner's screenshot shows raw backticks — replies must render markdown. Mature SPM package, theming support. Verify current API via context7 before adopting. |
| Streaming text animation | **Apple Foundation Models / WWDC25-26 streaming-UI patterns** | Apple ships first-party guidance for rendering streamed LLM text in SwiftUI (snapshot streaming, `contentTransition(.interpolate)`, TextRenderer for fade-in-by-word). Query apple-docs MCP before implementing. |
| Chat scaffolding (list, keyboard, attachments) | **ExyteChat (SwiftUI)** | Messenger-style; evaluate — likely we keep our own list but can lift keyboard/attachment/scroll handling patterns. |
| Agent-thread UX reference | `docs/design-reference/cursor-mobile-2026-07-08/` + Mobbin (`mcp__mobbin__*`) flows for Cursor/ChatGPT/Claude mobile | For tool cards, thinking indicator, context chips. |

Rule for implementation lanes: **use context7 / apple-docs MCP to pull current API docs
before writing code** (CLAUDE.md doc-lookup rule) — no training-data-only API usage.

## Gap inventory (state after `e8edcf3c`, 2026-07-09)

Have today: persisted multi-turn transcript · conversationID routing · conflict
auto-recover · error rows with real vendor errors · Retry/Refresh · approval banner →
Review · receipt + question artifact cards · 5s ledger-poll convergence · FTS search.

Missing (owner-named first):

1. **Token-level streaming rendering with smooth appearance** — text arrives in chunks
   but re-renders as a plain `Text` swap; no interpolation/fade-in animation.
2. **Markdown rendering** — replies show raw `` ` `` backticks; need MarkdownUI with
   code-block syntax highlight + copy button.
3. **Inline structured output / tool cards** — tool starts exist on the wire
   (`lancerE2EToolStart`, `agent.artifact`) but the transcript renders no per-tool card
   (running/done/failed, tool name, input summary). Daemon may need to ledger-persist
   tool events (kind "tool") so cards survive reopen.
4. **Image / attachment display** — composer attachments disabled; no image bubbles.
   Requires an attachment pipeline (upload to host, artifact kind "image") — bigger lift,
   Wave 1 item #9 territory; render-side can land first for receipt screenshots.
5. **Thinking / loading indicator** — only a static "Working…" line; need an animated
   indicator + current-activity ticker ("Running tests…", from tool events).
6. **Context manager view** — nothing shows what's in context: cwd, model, files
   touched, token usage/cost. Receipts already carry usage/cost per turn; surface a
   per-thread context sheet (model chip, cwd chip, cumulative cost, files list).

Missing (not named, should be on the list):

7. **Stop button while generating** (RelayRunControl exists — cheap and honest).
8. **Regenerate / edit-and-resend** last user message.
9. Scroll-to-bottom pill + don't auto-scroll while the user is reading history.
10. Per-message actions: copy, share, select text (partial today).
11. Timestamps + per-turn model/cost line (data exists in receipts).
12. Composer: multiline growth, draft persistence per thread, send-while-offline queue
    (fail-closed: explicit "will send when connected" state, never silent).
13. Haptics on send/complete/approval.
14. VoiceOver/accessibility labels for transcript rows.
15. Live Activity for an in-flight run (Wave 1 #2 — same data feed as the ticker).

## Suggested sequencing (post-retest)

- **Slice 1 (highest perceived quality per token):** markdown rendering + streaming
  animation + thinking indicator + stop button. Pure `CursorStyle` + one package dep.
- **Slice 2:** tool cards (daemon tool-event ledger persistence + transcript card) +
  context sheet (receipt-derived).
- **Slice 3:** attachments/images pipeline (needs design; overlaps Wave 1 #9).

Each slice: research-first via context7/apple-docs, exclusive write-sets, app-target
build + on-sim visual verification with screenshots BEFORE any owner phone test.
