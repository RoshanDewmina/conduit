# UX_OPPORTUNITIES.md — Conduit UX Opportunities

> Mapped to existing codebase locations. Sequenced by the staged roadmap in ROADMAP.md.
> "Already built" items are noted — do not rebuild them.

---

## 1. Lead Differentiator: Native Notifications + Live Activity + Dynamic Island + Apple Watch

**Why this is #1:** The universal complaint across HN, Reddit, app-store reviews, and the dev.to mobile-dev thread (https://dev.to/jagafarm/stop-losing-claude-code-sessions-a-tmux-primer-for-mobile-devs-2p48) is "I missed the moment the agent needed me." Rivals:
- Happy (github.com/slopus/happy, 21.6k★) — "vibe-coded… long chats take minutes to render" (GitHub issues)
- Omnara (omnara.com) — Android reportedly doesn't raise real system notifications

Conduit already has the scaffolding. Stage 2 work is deepening, not greenfield.

**Why rivals structurally can't copy this:** Live Activities, Dynamic Island, and Apple Watch Inbox are Apple-exclusive APIs. Web-based, Electron, and Android-first rivals cannot match native quality regardless of engineering investment.

---

### 1.1 Live Activity (Lock Screen)

**What to build:**
- Real-time agent state display on the lock screen: `thinking` / `streaming` / `waiting-approval` / `done` / `error`
- Approval action directly from the lock screen — Allow / Deny without unlocking
- Agent name + current task summary in the compact line
- Progress indicator for long-running operations

**Codebase map:**
- `SessionFeature/LiveActivityManager.swift` — existing scaffold
- `ConduitLiveActivityWidget/` — existing widget extension
- `ConduitCore/Approval.swift` — approval model (extend with structured fields from 2.1a)

**Stage:** 2

---

### 1.2 Dynamic Island

**What to build:**
- **Compact view:** PixelBox animation (existing `DesignSystem/Components/PixelBox.swift`) + agent state pill (thinking/streaming/waiting)
- **Expanded view:** Tool name + brief input context (e.g. "Write: `src/auth.swift`") + Allow / Reject buttons with haptic confirmation
- **Minimal view:** Unread approval count badge when another app is in foreground

**Codebase map:**
- `ConduitLiveActivityWidget/` — existing extension; add expanded view
- `DesignSystem/Components/PixelBox.swift` — reuse existing animation
- Blocked on 2.1a (structured tool_use) for tool name + context in expanded view

**Stage:** 2 (scaffold now; deepen after 2.1a for structured content)

---

### 1.3 Apple Watch — Approval Queue Drainable from Wrist

**What to build:**
- **Inbox tab:** Pending approvals list, each with tool name, truncated context, Allow / Deny action
- **Haptic on new approval:** Crown buzz + notification sound
- **Complication:** Pending approval count (updates via ActivityKit or WatchConnectivity)
- **Quick-approve flow:** Raise wrist → see pending count → tap → Allow / Deny in ≤3 taps

**Codebase map:**
- `ConduitWatch/` — multi-tab watchOS app already exists with Inbox tab
- `InboxFeature/InboxViewModel.swift` — LiveInboxViewModel; extend for Watch data relay
- WatchConnectivity bridge needed for live approval count

**Stage:** 2

---

### 1.4 Notification Filtering

**What to build:**
- Filter notifications by risk level: low / medium / high / critical (RiskScorer bands already exist)
- Per-agent notification toggle (silence a specific agent without muting all)
- Quiet-hours schedule (no interruptions between configurable hours)
- "Only critical" mode for focus sessions

**Codebase map:**
- `NotificationsKit/Notifications.swift:23` — notification registration; add filtering logic here
- `PersistenceKit/` — persist user preferences per-agent and globally
- `SettingsFeature/` — UI surface for filtering configuration

**Stage:** 2

---

## 2. Approval Hero Surface (Beats Happy's Raw-JSON Yes/No)

The current approval card in `InboxView.swift:181-183` shows a truncated 500-char string because `conduit-hook.sh` flattens `tool_input`. After 2.1a (structured wire protocol), the card can become a genuine decision surface.

### 2.1 Four Actions Per Approval

| Action | Description | Requires |
|---|---|---|
| **Allow once** | Permit this specific tool call | Already wired |
| **Allow always** | Persist a rule for this tool + pattern | WS-C + WS-D (2.1b) |
| **Edit & run** | Modify the tool input before permitting | WS-C + WS-D (2.1b) |
| **Deny** | Block the tool call, return error to agent | Already wired |

### 2.2 Structured Tool Card (Not a 500-Char Truncated String)

**What to build (after 2.1a):**

- **Card header:** Tool name in bold — `Write`, `Bash`, `Edit`, `Read`, etc.
- **Structured input panel:**
  - For `Write` → file path + collapsible content preview (first N lines)
  - For `Bash` → command in monospace, working directory
  - For `Edit` → file path + inline diff hunk (DiffKit already exists — `DiffKit/DiffView.swift`)
  - For `Read` → file path only (low-risk; consider auto-allow)
- **Risk badge:** low / medium / high / critical from `AgentKit/RiskScorer.swift` — already computed
- **Expandable diff hunk:** for `Write`/`Edit` tools, tap to expand full diff before deciding
- **Agent context:** which agent session, git branch if available

**Codebase map:**
- `InboxFeature/InboxView.swift:181-183` — card render site
- `ConduitCore/Approval.swift` — extend with `toolName`, `toolUseID`, structured `input` (after 2.1a)
- `DiffKit/DiffView.swift` — ready to use; just needs real data from 2.1a
- `SSHTransport/DaemonChannel.swift` — approval decision relay (fix `.approvedAlways` collapse at line 52 in 2.1b)

**Source inspiration:** cmux Feed approval cards (github.com/manaflow-ai/cmux); Warp inline actions rendered in-block

**Stage:** 3

---

## 3. Agent Cards, Not Log Walls (cmux-Inspired)

### 3.1 Session Rows in SessionsHomeView

**What to build:**
- **Per-agent status pill:** `running` / `idle` / `needsInput` (needsInput should pulse or animate)
- **Metadata line:** git branch + PR status + current working directory + latest notification text
- **Unread badge:** fixed-width slot using `ZStack(alignment: .trailing) { ... }.frame(width: 20, alignment: .trailing)` — the CLAUDE.md invariant; the animated PixelBox must not shift horizontally between rows
- **PixelBox state animation** per row — already available from `DesignSystem/Components/PixelBox.swift`

**Codebase map:**
- `AppFeature/SessionsHomeView.swift` — session row render site
- `AgentKit/GitMetadataProbe.swift` — new file needed; probes git branch, PR status, cwd via SSH
- `ConduitCore/SessionSummary` — extend with git metadata fields

**Stage:** 4 (fleet prerequisite; can partially land in Stage 2 for single-session case)

### 3.2 Jump-to-Unread

**What to build:**
- Badge tap on any agent in the home list → jumps to that agent's first unread approval or chat message
- Scroll position restored on return
- cmux analog: Cmd-Shift-U

**Codebase map:**
- `InboxFeature/InboxViewModel.swift` — extend with per-agent unread tracking
- `AppFeature/AppRoot.swift` — navigation coordinator; add jump-to-unread routing

**Stage:** 4

---

## 4. Bottom Agent Rail + Fleet (Stage 4)

**What to build:**
- N agent slots in a bottom rail; each slot shows:
  - PixelBox state animation (existing component)
  - Agent name (truncated)
  - Pending approval count badge
- Tap slot → jump to that agent's session view, scrolled to unread
- Fleet-wide Inbox filter: "All agents" shows pending approvals across all active slots
- Session count pip on each slot when multiple worktrees open

**Key architectural change required:** hoist single-session ownership out of `AppRoot.swift:587-691` into a new `FleetStore` that manages N `(DaemonChannel, ApprovalIngest)` pairs independently.

**Codebase map:**
- `AppFeature/FleetStore.swift` — new file; N-slot fleet state management
- `AppFeature/AppRoot.swift` — remove single-session wiring; delegate to FleetStore
- `InboxFeature/InboxViewModel.swift` — extend for fleet-wide aggregation
- `DesignSystem/Components/PixelBox.swift` — reuse in rail slots

**Stage:** 4

---

## 5. Collapsible Blocks (Warp-Inspired)

**What to build:**
- Blocks as first-class objects with a context menu: **Collapse / Copy / Re-run / Share / Attach as agent context**
- Long output (>20 lines) auto-collapsed with a "Show N more lines" tap-to-expand affordance
- **"Re-run with edit"** inline action within the block: tap → edit command in place → re-submit
- **Share block** → copies command + output to clipboard, or shares to AI for analysis
- Collapsed state shows: command summary + exit status + line count

**Codebase map:**
- `SessionFeature/Chat/ToolCardView.swift:295-328` — block render; add collapse/expand state
- `SessionFeature/BlockRenderer.swift` — add `isCollapsed` property to block model
- `SessionFeature/ChatTranscriptView.swift` — handle collapsed height + tap gesture

**Stage:** 3 (partial — collapse/copy); Later (re-run/share/attach)

---

## 6. Session Timeline Scrubber

**What to build:**
- Horizontal scrubber at the bottom of the session view
- Scrub to any block in the session's history (not just live tail)
- Milestone markers on the scrubber track: approvals (orange), errors (red), long-running completions (green)
- Tap a marker → jump to that block

**Codebase map:**
- `SessionFeature/HistoryView` — existing history surface; extend with scrubber
- `PersistenceKit/SessionSnapshotRepository.swift` — block history source
- `PersistenceKit/ApprovalRepository.swift` — approval timestamps for milestone markers

**Stage:** Later (Bucket 3, item 3.3)

---

## 7. SFTP → Prompt Integration

**What to build:**
- Long-press a file in the SFTP browser → context menu: **"Ask agent about this file"**
- Inserts `file path + first N lines of content` into the live prompt input as a quoted excerpt
- Makes it natural to ask the agent to review, refactor, or explain a specific file without typing the path

**Codebase map:**
- `SessionFeature/SFTPFilesView.swift` — add long-press gesture + context menu
- `SessionFeature/KeyCommands.swift` — existing command dispatch; extend for SFTP→prompt injection
- `SessionFeature/LivePromptInputView.swift` — receive and insert the file excerpt

**Stage:** Later (Bucket 3)

---

## 8. Parameterized Workflows (Already Built — Needs Prominence)

**Status: COMPLETE. Do not rebuild.**

The Snippets / Workflow system is fully implemented with `{{arg}}` placeholders (literal, enum, dynamic-shell), a 371-line editor, 235-line palette, and 212-line library view. See APP_AUDIT.md §3.1.

**What remains:**
- Seed a meaningful default library (common agent commands, git workflows, deploy scripts)
- Surface "Workflows" as a distinct section with category headers in the palette (currently flat list)
- Warp-YAML import compatibility (Bucket 3, item 3.1)

**Codebase map:**
- `SessionFeature/SnippetPaletteSheet.swift` — palette UI; add category headers
- `AgentKit/WorkflowEngine.swift` — engine; already handles multi-step composition
- `SettingsFeature/SnippetEditorView.swift` — CRUD editor; already complete

**Stage:** 0+1 (QA + seed default library); Later (YAML import + UI polish)

---

## 9. UX Consistency Invariants (Do Not Regress)

These invariants are documented in CLAUDE.md and must be preserved across all UX work:

1. **Fixed-geometry right columns:** Session rows must allocate a fixed-width slot for the unread badge even when empty. Use `ZStack(alignment: .trailing) { ... }.frame(width: 20, alignment: .trailing)` so the animated PixelBox never shifts horizontally between rows. Reference: `ReviewSessionRow` in `AppFeature/DebugGalleryView.swift`.

2. **Alt-screen renders block-embedded:** vim/htop/tmux render inside their block via the block-embedded SwiftTerm. There is no full-screen overlay swap. The `isRaw`/`activeShell`/`RawTerminalView` escalation path is dormant — do not re-activate it.

3. **Connect-time commands wait for `unifiedIntegrationReady`:** `runStartupCommandIfAny` and `attemptAgentResume` must await `awaitUnifiedShellReady()` to avoid pasting into a launched app's stdin.

4. **The unified PTY is the single byte source:** Never spawn a second `SSHShell` for raw mode. All bytes flow through PTYBridge.

5. **Belt-and-suspenders TUI escalation:** `SessionViewModel.onBlockBytes` must only fire for `.submitted` blocks, never an idle `.promptEditing` prompt — zsh's ZLE trips `TUIDetector`.
