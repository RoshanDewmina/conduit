# Lancer Relay Chat UX — Research + Design Spec

> **Target:** Best-in-class mobile agent-chat experience on the relay run screen.
> **Aesthetic:** opencode TUI, but for mobile — monospace, terminal-flavored, tasteful motion.
> **Constraint:** Zero new colors or fonts. Every element maps to existing `LancerTokens` / components.

---

## 1. Existing building blocks — summary

### 1.1 SpectrumBar (`DesignSystem/Components/Atomic/SpectrumBar.swift`)

| `SpectrumMode` | Visual | When used |
|---|---|---|
| `.idle` | Static rainbow segments, full opacity | No agent activity, run complete |
| `.loading` | Sweeping white shine left → right (indeterminate) | Command submitted, waiting for first bytes |
| `.working` | Per-segment staggered ease-in-out pulse (1.05 s cycle) | Agent actively executing / thinking |
| `.scan` | Blurred bright bar tracking across | Connecting / establishing link |

Animations reset on mode change (`onChange(of: mode) { start = Date() }`). Height defaults 6 pt, gap 1.5. Uses `LancerTokens.spectrumColors` (7-segment famicom palette).

### 1.2 AgentState + AgentStateContext (`DesignSystem/Components/AgentState.swift`)

```swift
AgentState: thinking | streaming | approval | done | error | offline
```

Each has `.label`, `.systemImage`, `.color(tokens:)`. The `.from(isExecuting:status:)` factory derives from session lifecycle:
- `connecting` → `.thinking`
- `connected + executing` → `.streaming`
- `connected + !executing` → `.done`
- `disconnected/suspended` → `.offline`
- `failed` → `.error`

`AgentStateContext` adds `BlockedReason?` + timestamps. `DSBlockedReasonRow` renders blocked reason with severity-appropriate color (`text3` / `warn` / `danger`) and 2 pt left bar.

### 1.3 PixelBox (`DesignSystem/Components/PixelBox.swift`)

3×3 animated grid. Per-state behaviors:

| AgentState | `CellBehavior` | Visual |
|---|---|---|
| `.thinking` | `.evolving` | Warm gradient (ember → gold → coral → magenta) sweeping diagonally, breathing opacity 0.68–1 |
| `.streaming` | `.flowing` | Brightness wave traveling along diagonal, blue → blueLit |
| `.approval` | `.breathing(RGB.amber)` | Calm synchronized swell |
| `.error` | `.glitching` | Stutter at 13 Hz, dead pixels, corruption spikes, horizontal tearing |
| `.done` | `.still(RGB.green)` | Static green, 92% opacity |
| `.offline` | `.still(RGB.offline)` | Static dim, 90% opacity |

Also supports `subdivisions` for "pixels made of pixels" self-similar shimmer. `TickBars` variant for state-driven audio-meter bars.

### 1.4 DotMatrixView (`DesignSystem/Components/Atomic/DotMatrixView.swift`)

Alternative animated indicator. States: `idle`, `connecting`, `thinking`, `working`, `error`, `done`. Each has unique Canvas-driven motion. Not used in current chat — candidate for compact footer / nav-dot.

### 1.5 DSBlockCard (`DesignSystem/Components/Composites.swift`)

Warp-style block card shell:
- 3-pt left gutter bar (state-colored: `termAccent`/`termOk`/`termErr`/`termText3`)
- Header row: caller-provided view + `DSExitChip` + duration + star
- Command line: `DSPromptLine` (host: cwd $) with `dsMonoPt(14)`
- Output area
- Footer with COPY / RERUN ghost buttons
- `DSBlockState` enum: `editing / submitted / executing / doneOk / doneErr / starred`

### 1.6 ToolCardView (`SessionFeature/Chat/ToolCardView.swift`)

Existing production card. Maps `Block` → chat tool card:
- **Left gutter** — 3 pt, color-mapped from `ToolCardState` (`idle`/`queued` → `termText3`, `running` → `termAccent`, `success` → `termOk`, `error` → `termErr`)
- **Tier 1** — `RUN › COMMAND` kind label (mono uppercase, tracked) + meta cluster (snippet icon, duration, `DSExitChip`, `ProgressView` when running, star, collapse chevron)
- **Tier 2** — `DSPromptLine` (host: cwd $) + command text, on `termSurface2` sunken surface
- **Tier 3** — Output panel on `termBg`: SGR-rendered `AttributedString` (`dsMonoPt(termFontSize)`, `termText`), or `RawTerminalView` for inline TUI, or blinking caret + "Running…" placeholder
- Truncation affordance: "⚠ N earlier lines dropped"
- Context menu: re-run, star, copy command, copy output, search output, explain error
- Search bar: inline TextField with match count, highlights in AttributedString

### 1.7 ChatTranscriptView (`SessionFeature/Chat/ChatTranscriptView.swift`)

ScrollView + LazyVStack rendering `blocks.blocks` as `ToolCardView`s. Auto-scrolls to `#bottom` on block count change or last block chunk count change. Supports load-older via `Color.clear.onAppear`. Double-tap → Tab. Long-press + drag → cursor keys (block-mode cursor pan).

### 1.8 ChatInputBar (`SessionFeature/Chat/ChatInputBar.swift`)

Pill-shaped input bar:
- Contextual prompt ($ or # indicator)
- `TerminalSafeTextField` (disabled when executing)
- "Running — tap to type" button + `LivePromptInputView` when executing
- Approval banner (amber, DENY/APPROVE capsules) when `pendingApprovalCount > 0`
- Action buttons: attachment (photo/files), mic, snippet, send
- Send disabled when text empty
- ⌘↵ hint shown when not executing

### 1.9 RunDetailView (`AppFeature/RunDetailView.swift`)

Current relay control surface:
- Header: title + subtitle + status pill (working/paused/stopped/budgetExceeded)
- Control bar (safe area bottom): Stop + Pause/Resume + Budget
- Bare follow-up bar (safe area bottom, above controls): plain `TextField` + send button
- Budget sheet (`.detents([.height(260)])`)

### 1.10 Tokens — key palette references

| Token | Dark value | Role |
|---|---|---|
| `t.termBg` | #0a0b0d | Terminal output background |
| `t.termSurface` | #0e0f12 | Block card body |
| `t.termSurface2` | #15171c | Sunken command bar |
| `t.termBorder` | #23262d | Hairlines within cards |
| `t.termText` | #e9e9e2 | Primary terminal text |
| `t.termText2` | #8a8d96 | Dim meta text |
| `t.termText3` | #565963 | Faint tertiary |
| `t.termAccent` | #f0a93b | Amber-gold accent (running) |
| `t.termOk` | #36c26b | Green success |
| `t.termErr` | #e0533f | Red error |
| `t.termPrompt` | #2f43ff | Electric blue prompt host |
| `t.termCwd` | #565963 | Prompt CWD |
| `t.accent` | #2f43ff | Electric blue brand accent |
| `t.text` / `t.text2` / `t.text3` / `t.text4` | Scheme-adaptive text tiers |
| `t.surf0` / `t.surf1` / `t.surf2` | Scheme-adaptive surfaces |
| `t.r4` | 0 | Block card radius (square — BLOCKS identity) |
| `t.pill` | 999 | Pill shape |
| `t.spectrum` | 7-color famicom palette | SpectrumBar + DotMatrix |

---

## 2. Competitor design analysis

### 2.1 Claude Code Mobile (mobile agent chat)

1. **Message-turn layout with subtle sender indicators** — User prompts appear right-aligned with a compact "You" badge; assistant turns are left-aligned with a model avatar. Clear turn separation prevents confusion over who said what, especially in tool-call-heavy conversations.
2. **Streaming indicator in the status bar** — A subtle pulsing dot + "model working…" in the navigation bar while tokens are arriving. No loading spinner per-message; the bar-level indicator is sufficient.
3. **Tool-call collapse** — Each tool call is a collapsed block showing just the tool name + duration. Tap to expand the full output. Reduces scroll noise when the model uses 8–12 tools per turn.
4. **Sticky "New message" input** — The input bar remains pinned above the keyboard via `safeAreaInset`, with a faint shadow line separating it from the transcript. Never scrolled away.
5. **Haptic on every incoming message** — A light tap when a new user-facing message lands (not per-token — too aggressive). Makes the app feel responsive without the user looking at it.

### 2.2 opencode TUI (terminal agent UI)

1. **Block/section framing with left gutter** — Every tool call is a clearly delimited card with a 3-pixel left border whose color signals state (amber = running, green = success, red = error). The gutter makes state scannable without reading text.
2. **Monospace everything** — No proportional fonts in the agent area. Commands, output, status labels all use a single monospace face. Creates visual coherence and reinforces the terminal identity.
3. **Sticky status line that collapses** — A 1-line persistent footer showing: agent name, current state, token count, elapsed time. Collapses to a compact dot-matrix indicator during streaming so the user gets maximum transcript width.
4. **Section separators with timestamp** — Between unrelated agent turns, a subtle `───── 2:34 PM ─────` divider creates temporal landmarks. Helps when re-reading long sessions.
5. **Exit code chip on every block** — Every completed block shows a small `✓ exit 0` or `✗ exit 1` chip. Zero is green + faint, non-zero is red + bold. Scannable without reading output.

### 2.3 Omnara (mobile agent monitoring)

1. **Hierarchical agent status** — A top-level "agent fleet" bar showing running/done/error counts, then per-agent expandable sections. Good pattern for multi-agent runs.
2. **Time-budget progress ring** — A small ring around the status indicator showing remaining budget as a fraction of total. Visual urgency cue without taking extra space.
3. **Approval queue as a horizontal pill counter** — Pending tool approvals shown as a tappable badge ("3 → REVIEW") that opens a bottom sheet. Keeps approval separate from the transcript flow.
4. **Cold-start skeleton** — While the agent is initializing, a pulsing skeleton of 3–4 fake "block" shapes previews the layout. Reduces perceived latency vs a blank screen.
5. **Swipe-to-dismiss blocks** — Swipe left on a completed block reveals "Re-run" / "Copy output" / "Star". Faster than long-press context menus.

---

## 3. SPEC: Lancer relay-chat screen

### 3.1 Screen layout (top → bottom)

```
┌──────────────────────────────────────┐
│ NavigationBar ("run")                │
├──────────────────────────────────────┤
│ HUD Strip (always-dark)              │
│  [PixelBox] AgentState  ·  elapsed   │
│  [DSBlockedReasonRow?]               │
├──────────────────────────────────────┤
│ SpectrumBar (full-width, 6 pt)       │
├──────────────────────────────────────┤
│                                      │
│  ChatTranscriptView                  │
│  ┌─ Blocks as ToolCardView ───────┐  │
│  │  RUN › TOOL     ✓ exit 0  0.3s │  │
│  │  host:cwd $ tool --arg          │  │
│  │  ┌ output ───────────────────┐ │  │
│  │  │  monospace terminal text  │ │  │
│  │  └──────────────────────────┘ │  │
│  └────────────────────────────────┘  │
│                                      │
│  ───── Divider (t.divider) ─────     │
│                                      │
│  User follow-up bubble (future)      │
│                                      │
├──────────────────────────────────────┤
│ Approval banner (amber, conditional) │
├──────────────────────────────────────┤
│ Follow-up input bar (refined)        │
│  $| command...                  [↗]  │
├──────────────────────────────────────┤
│ Control bar                          │
│  [Stop]  [Pause/Resume]  [Budget]   │
└──────────────────────────────────────┘
```

#### Files to change:
- `AppFeature/RunDetailView.swift` — primary target (rewrite body to house the stack)
- `SessionFeature/Chat/ChatTranscriptView.swift` — minor refinements (user turn support)
- `SessionFeature/Chat/ToolCardView.swift` — potential streaming polish
- `SessionFeature/Chat/ChatInputBar.swift` — reuse as-is for follow-up

#### New files:
- `SessionFeature/Chat/RunChatView.swift` — extracted from RunDetailView if body grows too large
- `SessionFeature/Chat/RelayChatViewModel.swift` — observable that bridges BlockRenderer + RunControlStore

---

### 3.2 Header / Status — HUD Strip + SpectrumBar

#### HUD Strip (always-dark, exactly like AgentIsland)

```
┌──────────────────────────────────────┐
│ ▣ Thinking  ─── 12.3s  $0.04 ◇      │
└──────────────────────────────────────┘
```

Left cluster:
- `PixelBox(state: agentState, size: 12, subdivisions: 2)` — 24×24 pt total
- `AgentState.label` in `t.hudText` at `dsMonoPt(12, .semibold)`
- Elapsed timer: `dsMonoPt(11)` in `t.hudText.opacity(0.7)`
- (optional) Budget burn: "$0.04" in `t.accent` at `dsMonoPt(11)`

Right cluster:
- `DotMatrixView(state: matrixState, cols: 10, rows: 3, cell: 5, dot: 2.5)` — compact activity field

Bottom row (conditional):
- `DSBlockedReasonRow(context: agentStateContext)` when blocked (approval / budget / error)

Background: `t.hudBg` (#0e0f12). Border bottom: `t.hudBorder` 1 pt.

#### SpectrumBar — mode mapping

| Run / agent condition | `SpectrumMode` | Rationale |
|---|---|---|
| Connecting / establishing tunnel | `.scan` | Blurred bar tracking = "searching / linking" |
| Executing, thinking before first token | `.loading` | Shine sweep = indeterminate "warm-up" |
| Actively streaming tokens | `.working` | Staggered per-segment pulse = "processing live data" |
| Awaiting approval (blocked) | `.working` | Still active, just paused on approval gate |
| Paused by user | `.idle` | Static = suspended |
| Run complete (all blocks done) | `.idle` | Static = settled |
| Error / disconnected | `.scan` (slow) | Decaying scan = "link lost" — sweep period doubled |

Implementation — `RunDetailView` observes two sources:
1. `RunControlStore.status` for pause/stop signals
2. `BlockRenderer.blocks.last?.state` for execution state
3. daemon connection state (`connecting` / `connected` / `disconnected`)

```swift
func spectrumMode(
    runStatus: RunControlStatus,
    agentState: AgentState,
    blocks: [Block]
) -> SpectrumMode {
    switch runStatus {
    case .stopped, .budgetExceeded: return .idle
    case .paused: return .idle
    case .running:
        switch agentState {
        case .thinking: return .loading     // waiting for model
        case .streaming: return .working    // actively streaming
        case .approval: return .working     // active, blocked on approval
        case .done: return .idle            // connected, nothing running
        case .error: return .scan           // link error
        case .offline: return .scan         // disconnected
        }
    }
}
```

---

### 3.3 Transcript — turn layout

#### User prompts

User messages appear as **right-aligned bubbles** above the block they triggered. This is a new affordance not in the current `ChatTranscriptView`.

Structure:
```
┌─ 12:34 PM ───────────────────────────┐
│                                      │
│           ┌────────────────────┐      │
│           │ fix the n+1 bug   │      │ ← "You" bubble
│           │ in websocket re-  │      │
│           │ connect           │      │
│           └────────────────────┘      │
│                                      │
│  ┌─ Block 1 RUN › bash ──────────┐   │
│  │  ...                           │   │
│  └────────────────────────────────┘   │
│  ┌─ Block 2 RUN › write_file ────┐   │
│  │  ...                           │   │
│  └────────────────────────────────┘   │
└──────────────────────────────────────┘
```

- User bubble: `t.surface2` background, `t.text` foreground, `dsMonoPt(14)`, right-aligned, max 75% width
- No avatar — "You" label in `t.text3` `dsMonoPt(10)` above the bubble
- Timestamp divider: `DSDivider(.soft)` with `dsMonoPt(10)` `t.text4` time label at center (e.g. "─ 12:34 PM ─")
- The `BlockRenderer` model already has all user commands in `block.command` and `block.prompt` — no new data model needed

#### Turn grouping (future P2)

When multiple user turns precede agent output (follow-ups mid-execution), group them as a timeline: `DSTimeline` with states `active/pending/done`.

---

### 3.4 Streaming — token-level animation

#### Data model

The daemon streams token-level JSON lines via `claude -p --output-format stream-json`. Each line:
```json
{"type": "content_block_delta", "index": 0, "delta": {"text": " fixing"}}
```

These arrive at high frequency (10–60 updates/sec). The `SessionViewModel` (or `RelayChatViewModel`) coalesces them and appends `BlockChunk`s to `BlockRenderer`.

#### SwiftUI rendering strategy

**Rule: do NOT use per-character views.** A `Text("...")` with a single `.animation()` is exponentially cheaper than `ForEach(text.indices)` with `Text(String(char))`.

**Recommended approach — opacity fade on appended runs:**

1. `BlockRenderer` maintains a `streamingChunkCounter: [BlockID: Int]` that increments on each new chunk.
2. `ToolCardView` reads the counter via `onChange(of: block.chunks.count)`.
3. New chunks appear with a **0.12 s opacity fade** (not slide — moving text on mobile is disorienting):

```swift
Text(chunk.text)
    .transition(.opacity.animation(.easeIn(duration: 0.12)))
```

4. **Throttled coalescing:** incoming token deltas are accumulated in a buffer and flushed to the model at ~20 Hz (50 ms interval). This prevents SwiftUI from re-rendering 60 times per second.

```swift
// In RelayChatViewModel:
private let coalesceInterval: Duration = .milliseconds(50)
private var pendingText = ""
private var flushTask: Task<Void, Never>?

func enqueueDelta(_ text: String) {
    pendingText += text
    guard flushTask == nil else { return }
    flushTask = Task { [weak self] in
        try? await Task.sleep(for: coalesceInterval)
        await MainActor.run {
            guard let self else { return }
            if !pendingText.isEmpty {
                appendCoalesced(pendingText)
                pendingText = ""
            }
            flushTask = nil
        }
    }
}
```

5. **Performance budget:** The `LazyVStack` in `ChatTranscriptView` already means only visible blocks pay rendering cost. Test with 10+ streaming blocks visible simultaneously — if frame drops occur, further throttle to 10 Hz.

#### Visual streaming indicator

During active streaming (agent is `.streaming` but no new chunk has arrived in >1.5 s), show a **subtle pulsing caret** in the output area of the last block:
```
 ▪ flickering amber 2×14 pt rectangle
```
Reuse the existing `runningPhase` animation pattern from `ToolCardView` (lines 164–179).

---

### 3.5 "Cool Loader" — pre-first-token states

#### Phase 1: Connecting (SpectrumBar.scan + HUD strip)

```
SpectrumBar: scan (bright bar tracking ~1.2 s cycle)
HUD: PixelBox(.thinking) + "Connecting…"
```

#### Phase 2: Submitted, awaiting model (SpectrumBar.loading + thinking PixelBox)

```
SpectrumBar: loading (white shine sweeping ~1.4 s cycle)
HUD: PixelBox(.thinking) with evolving palette → replaced by DotMatrixView(.connecting)
Blocks area: A single inline "placeholder block":
  ┌─ RUN › agent                        ┐
  │  host:cwd $ claude                   │
  │  ┌ output ────────────────────────┐  │
  │  │ ◌    (large DotMatrixView       │  │
  │  │      .thinking, centered,       │  │
  │  │      12 cols × 4 rows)          │  │
  │  └─────────────────────────────────┘  │
  └───────────────────────────────────────┘
```

- The placeholder block uses `DSBlockCard(state: .executing, ...)` with a centered `DotMatrixView(state: .thinking)` as the output content
- Replaced by the real `ToolCardView` when the first chunk arrives (cross-fade: 0.2 s)

#### Phase 3: First token arrives → seamless transition

First chunk lands → `DotMatrixView` fades out (0.15 s), real text content fades in (0.12 s).
`SpectrumBar` transitions `.loading → .working` on the mode change (auto-resets `start` timer per `SpectrumBar.onChange`).

---

### 3.6 Follow-up input bar

Refine the current `RunDetailView.followUpBar` to **exactly match `ChatInputBar`'s pill field styling**:

```swift
// RunDetailView follow-up replacement:
HStack(spacing: 8) {
    Image(systemName: "circle.fill")  // green dot when executing
        .font(.system(size: 7))
        .foregroundStyle(t.ok)
        .padding(.leading, 4)
    TextField("follow-up", text: $followUpText, axis: .vertical)
        .font(.dsMonoPt(15))
        .foregroundStyle(t.text)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    Button { submitFollowUp() } label: {
        Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundStyle(textEmpty ? t.text4 : t.accent)
    }
    .disabled(textEmpty)
}
.padding(.horizontal, 8)
.padding(.vertical, 9)
.background(t.surf2)
.clipShape(RoundedRectangle(cornerRadius: t.radiusPill, style: .continuous))
```

Key differences from the current bar:
- Remove raw `.stroke` border — use `t.surf2` fill (matches ChatInputBar pill field)
- Add `$` prompt prefix (matches `ChatInputBar.pillField`)
- Add multiline support (`.axis(.vertical)`) for long follow-ups
- Hold in a `safeAreaInset` at the bottom, above the control bar, using the same `.background(.bar)` overlay

Approval banner integration:
- When `pendingApprovalCount > 0`, replicate `ChatInputBar.approvalBanner` above the follow-up bar
- Same amber pill, same DENY/APPROVE capsules, same spring animation

---

### 3.7 Empty / Done / Error states

#### Empty state (first launch, no run started yet)

```
┌──────────────────────────────────────┐
│                                      │
│         (centered column)            │
│                                      │
│          ┌──────────────┐            │
│          │  PixelBox    │            │
│          │  (.offline)  │            │
│          │  size: 64    │            │
│          └──────────────┘            │
│                                      │
│     No active run                    │
│     ────────────────                 │
│     Deploy an agent task from        │
│     the dashboard to get started     │
│                                      │
│     [Start new run]                  │
│                                      │
└──────────────────────────────────────┘
```

- `PixelBox(state: .offline, size: 64)`
- Text: `t.text3`, `dsMonoPt(14)` body
- CTA: `DSButton("Start new run", variant: .primary)`
- Haptic: `.selection()` on appear

#### Done state (all blocks completed)

```
SpectrumBar → .idle (static rainbow)
HUD → PixelBox(.done) + AgentStatus("Connected")
```

- Final block shows `DSExitChip(code: 0)` for each success
- If any block errored: `DSBlockedReasonRow` with `.critical` severity at the top of the transcript
- A summary line at the bottom: `── 3 blocks · 12.4s · $0.08 ──`
- No special celebration — the aesthetic is calm and professional

#### Error state (disconnected / failed)

```
SpectrumBar → .scan (slow, double period)
HUD → PixelBox(.error) + "Disconnected"
DSBlockedReasonRow: critical severity
```

- Show `DSTypedErrorCard` (already exists in `DesignSystem/Components/States/`) for categorized errors
- Follow-up bar disabled with "Reconnect" button replacing the send button
- Haptic `.warning()` on transition to error

#### Haptic feedback map

| Event | Haptic |
|---|---|
| First token arrives | `.light()` |
| Block completes successfully | `.selection()` |
| Block errors | `.warning()` |
| User message sent | `.light()` |
| Run stops | `.medium()` |
| Approval needed | `.selection()` |
| Scroll to bottom triggered | (none — silent) |

---

### 3.8 Scroll-to-bottom behavior

1. **Auto-scroll** — `ChatTranscriptView` already scrolls on `blocks.blocks.count` and `blocks.blocks.last?.chunks.count` changes (lines 83–90). Preserve this.
2. **Override condition** — When user has scrolled up more than 100 pt from bottom, suppress auto-scroll. Show a **floating "↓ latest" badge** at the bottom-right of the transcript area:
   - `t.surface2` background, `dsMonoPt(11)` label, pill shape
   - Tap scrolls to bottom and re-enables auto-scroll
3. **Keyboard show** — When the follow-up bar becomes first responder, always scroll to bottom (with 0.15 s delay to let the keyboard animation settle).

---

## 4. Concrete build checklist

### P0 — Core chat surface (shippable alone)

| # | Task | Files to change | Effort |
|---|---|---|---|
| 0.1 | Replace empty RunDetailView body with the full stack: HUD strip + SpectrumBar + ChatTranscriptView + follow-up bar + control bar | `RunDetailView.swift`, new `RelayChatViewModel.swift` | M |
| 0.2 | Wire `RunControlStore.status` + `BlockRenderer.blocks` into HUD strip: PixelBox, AgentState label, timer | `RelayChatViewModel.swift`, `RunDetailView.swift` | S |
| 0.3 | Implement `spectrumMode()` mapping table (3.2) — drive `SpectrumBar.mode` reactively | `RelayChatViewModel.swift` | S |
| 0.4 | Refine follow-up bar to match ChatInputBar pill styling (`.surf2` fill, `$` prefix, multiline) | `RunDetailView.swift` | S |
| 0.5 | Approval banner above follow-up bar (reuse ChatInputBar.approvalBanner) | `RunDetailView.swift` | S |
| 0.6 | Block placeholder while awaiting first token (DotMatrixView.thinking in block card) | `ToolCardView.swift` or new `BlockPlaceholder.swift` | M |
| 0.7 | Opacity-fade on new chunks (`.transition(.opacity).animation(.easeIn(duration: 0.12)))` | `ToolCardView.swift` | S |
| 0.8 | Stream coalescing buffer (50 ms flush) | `RelayChatViewModel.swift` | S |

### P1 — Polished streaming + UX

| # | Task | Files to change | Effort |
|---|---|---|---|
| 1.1 | Blinking output caret when block is `.executing` but no chunk arrived in 1.5 s | `ToolCardView.swift` | S |
| 1.2 | User prompt bubbles (right-aligned, `t.surface2`, with voice label) | `ChatTranscriptView.swift` | M |
| 1.3 | Timestamp dividers between user turns | `ChatTranscriptView.swift` | S |
| 1.4 | "↓ latest" floating badge when user scrolls up during streaming | `ChatTranscriptView.swift` | M |
| 1.5 | Empty state (PixelBox.offline + text + CTA) | `RunDetailView.swift` | S |
| 1.6 | Error state (DSTypedErrorCard, "Reconnect" button) | `RunDetailView.swift` | S |
| 1.7 | Haptic map (light on first token, selection on block done, warning on error, medium on stop) | `RelayChatViewModel.swift` | S |

### P2 — Advanced

| # | Task | Files to change | Effort |
|---|---|---|---|
| 2.1 | Swipe-left on blocks → re-run / copy / star toolbar (replace context-menu-only) | `ToolCardView.swift` | M |
| 2.2 | Turn grouping timeline (DSTimeline) for mid-execution follow-ups | `ChatTranscriptView.swift`, new `TurnGroupView.swift` | L |
| 2.3 | "Explain with AI" inline explanation sheet for errored blocks | `ToolCardView.swift`, new `ExplainSheet.swift` | M |
| 2.4 | Budget burn display in HUD strip (`$0.04`) | `RelayChatViewModel.swift`, `RunDetailView.swift` | S |
| 2.5 | Run summary line on completion (`── 3 blocks · 12.4s · $0.08 ──`) | `RunDetailView.swift` | S |
| 2.6 | Keyboard toolbar rail (DSKeyboardRail) for quick context keys when live input active | `RunDetailView.swift` | M |
| 2.7 | Force Touch / long-press on send → context menu (paste, attach, snippet) | `RunDetailView.swift` | M |

---

## 5. Risk items

1. **Token-level streaming + SwiftUI performance:** The coalescing buffer at 50 ms is a starting point. Profile on iPhone 14+ with 50+ blocks in the transcript. If `LazyVStack` reallocation costs dominate, switch to `UICollectionView` via `UIViewRepresentable` for the transcript (P2 fallback).
2. **`SpectrumBar` mode transitions reset the animation timer.** The `onChange(of: mode)` resets to `Date()`, which causes a visible "jump" if the old in-progress animation is mid-cycle. Add a 0.3 s crossfade overlay when transitioning between non-idle modes so the reset isn't jarring.
3. **Per-block SwiftTerm handles for inline TUI:** If the user runs `vim` inside a relay session, `RawTerminalView` within `ToolCardView` handles it. The `inlineTerminalHeight` screen fraction (0.55) works on iPhones but may feel cramped on SE. Clamp minimum to 300 pt for SE.
4. **Approval bar + follow-up bar stacking:** When both bars are visible (pending approvals + user wants to type a follow-up), the dual-safe-area-inset bottom stack is ~140 pt. Ensure the transcript's bottom padding accounts for this. Use `GeometryReader` in the scroll view to compute `safeAreaInsets.bottom` dynamically.
