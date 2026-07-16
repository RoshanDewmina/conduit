# Chat UI port map — Orca / Happier / Omnara → Lancer

Date: 2026-07-09. **Last updated: 2026-07-15.**
Companion plan `docs/plans/2026-07-09-chat-interface-parity-plan.md` is missing from the tree
(git history only). Sources studied read-only in `research-repos/{orca,happier,omnara}`; all
competitor paths below are relative to those clone roots.

> **Frontend targets (historical, pre-`6b97da65`):** paths under
> `Packages/LancerKit/Sources/AppFeature/CursorStyle/` (`CursorWorkThreadView.swift`,
> `CursorTranscriptMapper.swift`, `CursorThreadTranscriptModel.swift`,
> `CursorShellLiveBridge.swift`) were removed with the CursorStyle shell. **Port intents in this
> doc remain valid** — re-home them onto the current Workspaces / chat surfaces
> (`AppFeature/Workspaces/`, related SessionFeature/LancerCore chat types) when implementing.
> Models in `Sources/LancerCore/ChatConversation.swift` (`ChatTurn`/`ChatEvent`/`ChatArtifact`)
> and GRDB mirror in `Sources/PersistenceKit/ChatConversationRepository.swift` are still current.

**Licenses.** Orca: MIT — patterns and code portable with attribution. Omnara: Apache-2.0 —
portable with attribution + NOTICE (note its README marks the codebase deprecated; the code is
still a complete reference). Happier: the task briefing said "no license," but the clone contains
a root `LICENCE` (MIT, "Happy Coder Contributors") and `apps/ui/LICENSE` (MIT). We treat Happier
conservatively anyway: port **patterns/state machines**, re-verify the license file before any
verbatim reuse. All three are React/React Native — UI code is never copied; schemas, state
machines, thresholds, and buffering algorithms are what we port.

**Architecture context that colors everything:** Orca is a PTY-scraping harness — its "chat" is a
reconstruction of the vendor CLI's own JSONL transcript file (`docs/native-chat-codex-tui-parity.md:27-37`);
Happier is a real E2E-encrypted seq-ordered event-log sync client (closest analog to Lancer);
Omnara is a thin client over a server-authoritative Postgres message table with SSE push.
Happier is the primary donor for most gaps.

---

## 1. Streaming text rendering + smooth appearance

**Orca** — `src/shared/native-chat-streaming.ts:1-62`, `src/renderer/src/components/native-chat/native-chat-incremental-assembler.ts:1-100`.
No animation at all; a data-shape trick. A synthetic assistant bubble (`id: "streaming"`) shows the
live preview only while it is *longer than* the last persisted message and hasn't landed in the
transcript — preventing flicker when the persisted row catches up. Appends are tail-spliced
(O(k log k)) instead of re-sorting the whole list.

**Happier** — `apps/ui/sources/components/sessions/transcript/streaming/useStreamingTextSmoothing.ts` (103 lines),
`useThrottledStreamingMarkdownText.ts` (69 lines), plus `components/markdown/streaming/*`
(`createMarkdownBlockParseCache.ts`, `repairStreamingMarkdownAsync.ts`). Two independent throttles:
(a) raw text deltas are coalesced to one commit per animation frame (`requestAnimationFrame`, i.e.
one paint per frame no matter how many chunks arrive); (b) markdown re-parse runs on a separate
min-interval throttle with trailing flush, and an `isStreaming` flag only flips off after a
`settleDelayMs` quiet window, deferring expensive parsing/highlighting until the stream settles.
Markdown is parsed incrementally per block with a cache, and unterminated fences are "repaired"
mid-stream so a half-open ```` ``` ```` never renders raw.

**Omnara** — none. Whole-message SSE push; only a CSS `animate-fade-in` on web
(`apps/web/src/components/dashboard/chat/ChatMessage.tsx:117`). Nothing to port.

**Port to Lancer:** Happier's dual-throttle is the pattern. In `CursorThreadTranscriptModel`, keep
the raw `activeThreadResponse` firehose off the view: coalesce updates via a display-link-paced
task (CADisplayLink or a ~30–60 Hz `AsyncTimerSequence`) that commits at most one string per frame,
and gate the (future) markdown re-parse behind a 250–400 ms settle timer. Combine with Orca's
synthetic-overlay-vs-persisted-row rule — our `LiveOverlay` in `CursorTranscriptMapper.swift:16-19`
already exists; add the "overlay only wins while longer than persisted `assistantText`" guard to
kill the visible swap-flicker on turn completion. Visual reveal itself uses SwiftUI
`.contentTransition(.interpolate)` / TextRenderer per the parity plan (Apple guidance, not a port).

## 2. Markdown + code blocks

**Orca** — `react-markdown` v10 + `remark-gfm`/`remark-breaks`/`rehype-raw`/`rehype-sanitize`;
chat call site `src/renderer/src/components/native-chat/NativeChatMessageList.tsx:220-227`, shared
renderer `src/renderer/src/components/sidebar/CommentMarkdown.tsx:1-249`. Chat code fences are a
plain styled `<pre>` (`comment-markdown-element-renderers.tsx:203-210`) — **no highlighting, no
per-block copy button** in chat (whole-message copy only, `NativeChatCopyButton.tsx`).

**Happier** — hand-rolled incremental block/span parser (`components/markdown/parseMarkdown.ts`,
`parseMarkdownBlock.ts`) built to be streamed. Highlighting is two-tier: Shiki on web only
(`components/ui/code/highlighting/shiki/shikiTokenize.web.ts`), lightweight regex highlighter
(`SimpleSyntaxHighlighter`) on native — explicitly to avoid main-thread cost on mobile. Per-block
copy button with check-icon feedback: `components/ui/code/blocks/CodeBlockViewFrame.tsx:41,66-81`.
Diff/patch fences get a rendered-diff ↔ raw toggle with a byte-size budget gate
(`MarkdownCodeBlock.tsx:19-22,101-148`).

**Omnara** — mobile: `react-native-markdown-display` with a style dictionary
(`apps/mobile/src/components/chat/ChatMessage.tsx:41-136`), no highlighter, long-press copies whole
message. Web: `react-markdown` + custom heuristic diff renderer and a `preprocessMarkdown()` that
normalizes unicode bullets and wraps Codex `*** Begin Patch` blocks in ` ```diff ` fences
(`apps/web/src/components/dashboard/markdownConfig.tsx:11-25,58-115`).

**Port to Lancer:** adopt **swift-markdown-ui (MarkdownUI)** via SPM as planned; render
`section.assistantText` through it in `CursorWorkThreadView.assistantBody` (lines 231-256), themed
from `CursorColors`/`CursorType`. Port three *configs*, not code: (1) Happier's two-tier
highlighting decision — start with MarkdownUI's plain mono code style (Orca ships no chat
highlighting either; it's not table stakes), add a lightweight highlighter later; (2) Happier's
per-code-block copy button with a 1.5 s check-icon state (we already have `CursorCopiedToast`);
(3) Omnara's `preprocessMarkdown` normalizations (unicode bullets, wrap vendor patch output in
diff fences) as a pure `String -> String` pass before render — directly reusable logic, Apache-2.0.

## 3. Inline tool-call cards / structured output

**Orca** — no lifecycle events: state is derived from block type (`tool-call` vs `tool-result`,
`isError` on result) in `src/shared/native-chat-types.ts`. `foldToolMessages`
(`native-chat-tool-fold.ts:28-39`) merges tool-only messages under the preceding assistant message;
collapsed one-line summary "3× Bash git status · Edit app.tsx" built by `summarizeToolRun`
(`native-chat-tool-summary.ts:41-59`); per-run expand + a global expand-all signal
(`NativeChatToolRun.tsx:1-144`); results capped at `MAX_TOOL_RESULT_CHARS = 4000`.

**Happier** — the best schema. Per-tool Zod input/output schemas wrapped in a passthrough envelope
for forward-compat (`packages/protocol/src/tools/v2/schemas.ts`, 462 lines). Pairing:
`tool_use {id,name,input}` matched to `tool_result {tool_use_id,content,is_error}`
(`packages/protocol/src/sessionMessages/transcriptRawRecordV1.ts:38-56`), with normalization of
hyphenated Codex/Gemini variants (`tool-call`/`tool-call-result`, lines 74-122). Client state
machine `apps/ui/sources/sync/reducer/phases/toolCalls.ts` (235 lines) keys tool calls by id and
**buffers orphan results that arrive before their `tool_use`**
(`drainAndApplyOrphanToolResultsToMessage`, line 212). `ToolCall.state:
'running'|'completed'|'error'|'unavailable'` (`messageTypes.ts:9`); presentation folds in
permission status → `permission_blocked|permission_pending|running|completed|error`
(`resolveToolStatusIndicatorKind.ts`). Auto-expand policy: a group expands only if small
(`resolveToolCallsGroupAutoExpandPolicy.ts`, threshold `max(previewCount*2, 6)`).

**Omnara** — none; `content.includes('Using tool:')` string sniffing
(`apps/web/.../ChatMessage.tsx:66`). Anti-pattern; skip.

**Port to Lancer:** our `ChatArtifact` (kind `.tool`, status `.running/.done/.failed`) already
matches Happier's state machine — the missing pieces are wire + persistence + card. Daemon: persist
`lancerE2EToolStart`/end as ledger events (kind `"tool"`, `payloadJSON` = `{name, input-summary,
isError}`) so `ChatEvent` mirrors carry them; adopt Happier's pairing rule (result keyed by
tool-call id, orphan-result buffer — we already normalize ID case at Swift↔Go boundaries, same
lesson). iOS: a `ToolCallCardView` in CursorStyle rendered from `artifactView(for:)`
(`CursorWorkThreadView.swift:511-544` `default: EmptyView()` branch), with Orca's collapsed
one-line multi-tool summary per turn and Happier's auto-expand-only-small-groups policy. Cap stored
result payloads at ~4 KB (Orca's number). Permission-pending as an overlay state maps 1:1 onto our
approval flow.

## 4. Thinking / loading indicators

**Orca** — five session statuses `loading|ready|working|empty|error`
(`src/shared/native-chat-types.ts:81-89`). `working` asserts immediately and only clears once the
transcript's last message is a fresh assistant reply (`native-chat-live-status.ts:26-77`). Bouncing
three-dot `TypingIndicatorRow` shows only when working AND no streaming bubble exists
(`NativeChatMessageList.tsx:101-120,274-275`) — dots and preview text never coexist.

**Happier** — three orthogonal signals: (a) ephemeral session-level `activity {active, thinking?}`
presence event (`docs/protocol.md`), not persisted; (b) a persisted `thinking` content block
rendered as a collapsible row with pulse animation while it's the open/most-recent one
(`transcript/thinking/ThinkingTimelineRow.tsx`, `resolveActiveThinkingMessageId.ts`); (c) per-tool
running spinner from gap 3. No unified "queued" state.

**Omnara** — status enum `ACTIVE|AWAITING_INPUT|PAUSED|COMPLETED|FAILED|KILLED`
(`apps/web/src/types/dashboard.ts:1-8`) plus a client-computed **offline** state from
`last_heartbeat_at` vs a 60 s TTL (`ChatWorkingIndicator.tsx:13,22-29`) — liveness is derived,
never trusted from the DB status.

**Port to Lancer:** replace the static "Working…" `logLine` (`CursorWorkThreadView.swift:238-241,258-268`)
with a state-driven indicator enum: `starting / thinking / toolRunning(name) / streaming`, derived
exactly as Orca does — mutually exclusive with visible streamed text. Tool-start events (gap 3)
supply the ticker text ("Running swift build…"). Adopt Omnara's derived-offline rule: our
`ConnectionStateStore` heartbeat already exists; if the host hasn't been heard from in N seconds,
show "host unreachable" instead of an eternal spinner — fail-visible, matches our fail-closed
posture. Vendor `thinking` blocks can later map to a collapsible row à la Happier once the daemon
forwards them.

## 5. Image / attachment display + upload

**Orca** — no HTTP upload: pasted image → local temp file → path pasted into the PTY as the CLI's
own bracketed-paste token (`native-chat-image-paste.ts:14-40`); for SSH-remote worktrees the file
is first uploaded to `${worktree}/.orca/drops` over its IPC (`native-chat-attachment-upload.ts:80-105`).
Transcript shows a filename chip only, no thumbnail (`NativeChatMessageList.tsx:40-68`).

**Happier** — full pipeline: local draft store that survives restart
(`attachments/attachmentDraftModel.ts`, `recoverableAttachmentDrafts.ts`), per-draft
`uploading → uploaded|error` machine with byte-level progress + SHA-256
(`uploadAttachmentDraftsToSession.ts:117-129`), drafts keyed by `messageLocalId` (bound to the
optimistic outgoing message before a server id exists), inline image rows + full-screen preview
(`attachments/messages/AttachmentsInlineImages.tsx`, `preview/AttachmentImagePreviewModal.tsx`),
and a text fallback wrapping paths in `[attachments]…[/attachments]` for models that can't see
files (lines 163-174).

**Omnara** — not implemented at all.

**Port to Lancer:** Orca's transport is the cheap Wave-1 win: we already run the vendor CLI on the
host, so "upload" = ship bytes over the relay to a daemon drop dir (`~/.lancer/drops/<conv>/`) and
paste the *path* into the prompt — no new artifact kind needed to start. Happier's draft state
machine is the model for the composer: persist drafts in GRDB keyed by our existing
`clientTurnID` (mirrors their `messageLocalId`), states `staged → uploading(progress) →
uploaded|failed`, and never auto-send (our ChatDraft non-negotiable already forbids it). Render
side: an `image` artifact kind + thumbnail row can land independently for receipt screenshots.

## 6. Context / session info view

**Orca** — none in-chat; aggregate usage screens scan the CLI's own local usage logs
(`src/main/claude-usage/store.ts`, `src/renderer/src/components/stats/ClaudeUsagePane.tsx`).

**Happier** — the pattern to copy: an in-composer **context-window fullness badge**, not a cost
ticker. `agentInput/contextWarning.ts` (91 lines) computes `usedRatio` + 3-tier severity
(warning ≤10 % remaining, critical ≤5 %); rendered by `AgentInputContextUsageBadge.tsx` and a
circular `TokenUsageRing.tsx`. Cost/token history lives in a settings-level `UsagePanel.tsx`
(292 lines: period selector, totals, per-model bars). Wire: ephemeral `usage {tokens, cost}` event
per session (`docs/protocol.md`). Machine + cwd chosen via a `ContextBar.tsx` picker at session
setup, not a live transcript header.

**Omnara** — frontend types declare `total_cost_usd`/`model_name` but the backend never persists
them (`src/shared/database/models.py:131-190` has no such columns) — dead placeholders; skip.

**Port to Lancer:** we already persist more than any of them: `ChatConversation.model/cwd/budgetUSD`
and per-turn receipts with usage/cost. Build a context sheet off the thread overflow menu
(`CursorWorkThreadView.swift:378-404`): model chip, cwd chip, cumulative cost summed from receipt
artifacts, files-touched list. Port Happier's two numeric thresholds verbatim (warn ≤10 %,
critical ≤5 % of context remaining) as a composer badge once the daemon forwards context-window
usage; wire cost against `budgetUSD` for a budget-fullness ring — that's a governance
differentiator none of the three ship.

## 7. Stop / cancel; regenerate

**Orca** — stop = send `ESC` down the PTY (`use-native-chat-interactive-send.ts:11-12,83-87`);
send button swaps to a Stop square while working (`NativeChatComposerActions.tsx:103-119`).
**No regenerate** (can't replay a PTY).

**Happier** — the gold pattern: a 3-tier graceful-degradation ladder in
`sync/ops/sessionStopStrategy.ts` (221 lines): (1) machine-daemon RPC `STOP_SESSION` (real kill) →
(2) session-scoped `killSession` RPC → (3) best-effort `session-end` event so the server at least
marks it inactive ("server will also eventually time out stale sessions", lines 156-159). Fallback
driven by typed RPC-method-unavailable error classification (`sync/runtime/rpcErrors.ts`).
Regenerate: no confirmed in-place regenerate; only re-send-selection.

**Omnara** — no interrupt; only `PUT …/status → COMPLETED` ("End Session",
`src/backend/api/agents.py:412-430`). No regenerate.

**Port to Lancer:** wire `RelayRunControl` to a Stop affordance: composer send-button swaps to a
stop square while `activeThreadIsWorking` (Orca's UI rule), backed by Happier's ladder — (1)
daemon `agent.run.stop` RPC kills the process; (2) on unreachable-host, locally mark the turn
failed("stopped") and let the ledger reconcile on reconnect. Always leave the UI in a stopped
state even when the kill is unconfirmed. Regenerate: none of the three ship it; implement as
re-send-last-prompt (our `handleRetry`, `CursorWorkThreadView.swift:291-300`, is already 90 % of
it) rather than true in-place regeneration — new turn, honest history.

## 8. Scroll behavior

**Orca** — the cleanest portable logic: pure tested geometry in `native-chat-autoscroll.ts:1-44` —
`isNearBottom` (48 px threshold), `shouldShowJumpToLatest` (detached AND content below).
`stuckToBottom` mirrored in state + ref to avoid effect self-loops
(`NativeChatMessageList.tsx:257-261`); re-pin before paint in a layout effect; "Jump to latest"
pill (391-401); prepend-preservation: capture scrollHeight/top before loading older messages, then
shift scrollTop by the growth delta (277-297, 322-331); `ResizeObserver` re-runs the decision when
the composer resizes.

**Happier** — heaviest machinery: an explicit bottom-follow **state machine**
(`transcript/scroll/transcriptBottomFollowMode.ts`, `transcriptAutoFollowGate.ts:1-23` — follow
only if pinned AND following AND not mid-jump, explicit user jump always wins), FlashList-based,
`JumpToBottomButton.tsx` (89 lines) with **unread-count badge**, prepend-transactions
(`viewport/prepend/prependTransaction.ts`) and viewport restore on re-entry
(`viewport/entryRestore/entryRestoreTransaction.ts`).

**Omnara** — same idea, simpler: auto-scroll only if within 20 px of bottom
(`apps/mobile/src/components/chat/ChatInterface.tsx:174-227`), RN
`maintainVisibleContentPosition` + manual height-delta restore for prepends (268-289), 800 ms
pagination cooldown. **No scroll-to-bottom pill.**

**Port to Lancer:** our `.onChange(rows) → scrollTo(last)` (`CursorWorkThreadView.swift:102-107`)
scrolls unconditionally — the bug all three solve. Port Orca's pure functions verbatim (MIT):
a `TranscriptAutoScrollPolicy` enum in CursorStyle with `isNearBottom(offset:contentH:viewportH:) `
(48 pt) and `shouldShowJumpToLatest`, unit-tested like theirs. Track nearness via a scroll-geometry
preference key (or `ScrollPosition` on iOS 18+), auto-scroll only when near-bottom, and add a
jump-to-latest pill with Happier's unread-count badge fed by rows appended while detached.
Prepend-preservation waits until we paginate history (we currently load whole conversations).

## 9. Message persistence / sync

**Orca** — none of its own: the vendor CLI's JSONL transcript *is* the store. Worth stealing
anyway: the tail-follower in `src/main/native-chat/transcript-watch.ts:1-255` — byte-offset
incremental reads, complete-lines-only decode (partial trailing line retried, never dropped),
40 ms debounce, truncation→offset-reset; windowed reads (300 turns) in `transcript-reader.ts`.

**Happier** — closest to us and validates our design: a **per-user monotonically sequenced event
log** (`docs/protocol.md`: persistent `update {id, seq, body}` vs `ephemeral` events; "apply
updates in order and you are consistent"), optimistic sends reconciled by client-generated
`localId`, optimistic concurrency via `expectedVersion` (server replies `version-mismatch`),
client reducer replays raw provider records into normalized state (`sync/reducer/`), MMKV only for
local-only state, E2E envelope `{t:'encrypted'|'plain'}` so the server stores ciphertext
(`docs/encryption.md`). Postgres + Redis + Socket.IO backend (`docs/backend-architecture.md`).

**Omnara** — server-authoritative message table, no client cache (re-fetch on every mount);
realtime = Postgres LISTEN/NOTIFY → per-client SSE, where NOTIFY only signals "changed" and the
row is **re-read from the DB before emitting** (`src/backend/api/agents.py:260-409`) — avoids
stale/partial payloads; 30 s SSE heartbeat; `last_read_message_id` read cursor
(`src/shared/database/models.py:157-166`).

**Port to Lancer:** our host-ledger (`conversation_events.seq`, `lastHostSeq`, `clientTurnID`
idempotency, `SyncState.conflict` on stale `baseSeq`) is already Happier's architecture — seq-log
+ localId reconciliation + version-conflict — independently arrived at; no rework needed. Three
refinements to steal: (1) Happier's persistent-vs-**ephemeral** event split — typing/thinking/
usage ticks should be relay-ephemeral, never ledger rows (keeps gap-4 ticker cheap); (2) Omnara's
notify-then-re-read rule for our 5 s poll → push upgrade: a push means "fetch since seq," never
"trust the push payload"; (3) Orca's partial-line/truncation handling if the daemon ever tails
vendor JSONL transcripts directly (it will, for tool events).

---

## Docs worth citing

- Orca `docs/native-chat-codex-tui-parity.md` — PTY-harness limits + 3-tier protocol-ownership roadmap.
- Orca `docs/reference/agent-session-resume-cli-evidence.md` — per-CLI `session_id`/`transcript_path` semantics (feeds our `vendorSessionID`).
- Happier `docs/protocol.md` — the sync bible: update/ephemeral taxonomy, seq ordering, `expectedVersion`.
- Happier `docs/encryption.md` + `apps/ui/CLAUDE.md` "Sync boundaries" — E2E envelope + sync layering.
- Omnara `CLAUDE.md` + `docs/guides/architecture-diagram.md` — unified `messages` table rationale; read/write API split.

## Ranked steal list

| # | Port | From | Effort | License note |
|---|---|---|---|---|
| 1 | **Streaming dual-throttle + synthetic-overlay rule** — frame-paced text commit, settle-gated markdown re-parse, overlay-wins-only-while-longer | Happier `useStreamingTextSmoothing.ts` + Orca `native-chat-streaming.ts` | **M** | Pattern from Happier (MIT in clone; re-verify before verbatim); Orca MIT — logic portable with attribution |
| 2 | **Auto-scroll policy + jump-to-latest pill** — 48 pt near-bottom threshold, follow-only-when-near, unread badge | Orca `native-chat-autoscroll.ts` (+ Happier badge) | **S** | Orca MIT — pure functions portable verbatim with attribution |
| 3 | **Tool-call card state machine** — id-paired start/result, orphan-result buffer, running/completed/error(+permission overlay), collapse-unless-small policy, 4 KB result cap | Happier `reducer/phases/toolCalls.ts` + Orca fold/summary | **L** (daemon ledger events + iOS card) | Patterns only from Happier; Orca summary logic MIT |
| 4 | **Markdown preprocessing + code-block copy** — MarkdownUI SPM dep, Omnara's bullet/patch-fence normalizer as a pure String pass, per-block copy w/ check state | Omnara `markdownConfig.tsx:11-25` + Happier `CodeBlockViewFrame.tsx` | **S** (on top of the planned MarkdownUI adoption) | Omnara Apache-2.0 — logic portable with attribution/NOTICE |
| 5 | **Stop ladder + derived-offline indicator** — kill-RPC → best-effort mark-stopped fallback; heartbeat-TTL "host unreachable" instead of eternal spinner | Happier `sessionStopStrategy.ts` + Omnara `ChatWorkingIndicator.tsx:22-29` | **M** | Patterns only (Happier); Omnara Apache-2.0 |

Non-port validation worth recording: our host-ledger seq/`clientTurnID`/conflict design is
architecturally identical to Happier's shipped sync protocol — build on it with confidence;
adopt only the ephemeral-event split and notify-then-re-read refinements (gap 9).
