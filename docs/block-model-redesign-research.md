# Conduit — Block-Mode Redesign: Research & Plan

Date: 2026-05-28 (rev 5 — implementation started)
Status: **Implementation in progress. Core code paths landed; full real-host/TUI validation still pending.**
Owner: Codex

> **Rev 2 changes.** A parallel real-device pass surfaced bugs my code-trace
> couldn't catch — most importantly, **iOS smart-punctuation rewrites `--` to
> `—` in the composer**, so `claude --version` runs as `claude —version` and
> falls into interactive Claude. That's the *proximate* cause of the symptom;
> the block-model architecture is the *root* cause. This revision splits the
> plan: a new **Phase 0** (real-device quick wins, no architecture) lands
> first, then the six architectural phases that follow. See §7.
>
> **Rev 3 changes.** A reuse-mapping pass against Warp and cmux identified
> what to vendor instead of reinventing. The new §6 ("Reuse matrix") lists
> 17 features by portability rating (DIRECT / ADAPT / PATTERN / KEEP).
> Headline: cmux gives us ~8 files of Swift we can port near-1:1 (agent
> registry, session keying, input queue, persistence schema, keyboard
> chord map, etc.); Warp gives us a portable workflow YAML schema and an
> AI context envelope (`BlockContext`). §6.4 lists the new files Phase 1+
> creates by vendoring rather than designing.
>
> **Rev 4 changes.** Added Ghostty (`/Users/roshansilva/Downloads/ghostty-main`)
> as a third reference. Ghostty is MIT overall, but its bash + zsh
> shell-integration scripts are **GPLv3** (derived from Kitty) — we cannot
> bundle them in Conduit's proprietary target. Useful as architectural
> reference and for the fish script (no GPL header). Also added §6.6
> "What this delivers — and what it doesn't" — an honest scope statement
> answering "will the terminal just work after these phases?"
>
> **Rev 5 changes.** The plan is no longer research-only: implementation has
> started. Landed work includes terminal-safe UIKit input, bundled shell
> integration resources, OSC 133 A/B callbacks, block lifecycle state,
> active-block prompt/live input, direct keystroke forwarding, debug Pro
> bypass, tmux-session discovery UI, cursor-positioning fallback detection,
> and expanded keyboard rail controls. Remaining proof needed: clean
> real-host interactive validation for Claude/Codex-style inline TUIs,
> alt-screen-in-block polish, and plug-and-play agent resume.

---

## TL;DR

The block-mode terminal is broken for interactive TUI programs (Claude Code, Codex, top, vim without alt-screen) for two stacked reasons:

1. **Proximate (cheap to fix):** the composer `TextField` has autocorrect/autocapitalize disabled, but **smart dashes, smart quotes, and smart insert** are not — so `--`, `'`, `"`, and other shell syntax silently mutates as the user types. One UIViewRepresentable fix.
2. **Root cause (the redesign):** we built the model as request–response — every `submit()` mints a new block, the composer is the only input path, and OSC 133 prompt-start/end markers we already parse are ignored. Even with a fixed input field, a running Claude Code can't be interacted with because keystrokes have no path to the PTY in block mode.

The architectural fix mirrors Warp: **one PTY per session, blocks are display slices bounded by OSC 133, input always flows directly to the PTY**. cmux's lesson is the opposite extreme — zero composer, zero intermediate queue, NSEvent → `ghostty_surface_key()` direct. We want Warp's structure with cmux's input-latency discipline, in a phone-shaped UI.

This doc is exhaustive on purpose because the user asked for a thorough investigation. The actual implementation plan is §6; everything before that is the evidence base.

---

## 0. How this doc is structured

1. **What we have today** — Conduit's full feature inventory and the broken paths, with code citations.
2. **What Warp does** — architecture + the specific path that fixes our bug.
3. **What cmux does** — architecture + the patterns we should steal (and the ones we shouldn't).
4. **Side-by-side comparison matrix** — feature-by-feature, all three apps + Termius for SSH-client baseline.
5. **Recommended redesign** — the model + concrete changes by file.
6. **Reuse matrix** — for each Conduit feature, whether to copy from cmux/Warp or keep building. Don't reinvent the wheel.
7. **Implementation plan** — phased, each phase shippable on its own.
8. **Open decisions** — questions for the user before coding starts.
9. **Appendix** — code citations across all three codebases.

---

## 1. Conduit today

### 1.1 Feature inventory (verified from source)

**Engines** — pure SwiftPM, no UIKit:
- `ConduitCore` — IDs, errors, base types
- `SecurityKit` — Keychain, Ed25519 KeyStore, biometric gate, TOFU `HostKeyStore`, pairing crypto
- `SSHTransport` — Citadel actor (`SSHSession`), `SSHShell`, `SessionPool`, `AutoReconnectEngine`, `TmuxClient`, `LocalPortForward`, `PortForwardTunnel`, `SFTPClient`
- `TerminalEngine` — `AnsiSGRParser`, `BlockRenderer` (per-block SwiftTerm), `PTYBridge` (OSC 133/7), `RawTerminalView` (SwiftTerm UIView)
- `AgentKit` — `AIClient` protocol, `AnthropicClient`, `OpenAIClient`, `MockAIClient`, `PromptBuilder`, `RiskScorer`, `Redactor`
- `PersistenceKit` — GRDB stack, repos for hosts/blocks/snippets/approvals/patches
- `NotificationsKit`, `DiffKit`, `DesignSystem`, `PreviewKit`, `SyncKit`

**Features** — SwiftUI:
- `SessionFeature` — `SessionView` (block + raw modes), `SessionViewModel`, `KeyboardAccessoryRail`, `KeyCommands`, `HardwareInputHandler`, `DictationEngine`, `SnippetPaletteSheet`, `ExplainSheet`, `PortForwardView`, `ScenePhaseObserver`
- `AppFeature` — `AppRoot`, `SessionShellView` with 5-surface picker (Terminal/Preview/Files/Diff/Inbox), `AdaptiveRoot`, biometric `BiometricGate`
- `OnboardingFeature` — host wizard, `ProvisioningWizard`, Lightsail/Orbstack/Fly provisioners
- `WorkspacesFeature` — host list with live status dots
- `InboxFeature` — approval cards, `LiveInboxViewModel`, conduitd `DaemonChannel`, `ApprovalIngest`
- `PreviewFeature` — `SmartPreviewView` + WKWebView + `SSHProxyURLSchemeHandler` + auto `PortDetector`
- `FilesFeature` — `SFTPFilesView`, text preview
- `DiffFeature` — `DiffView` + `UnifiedDiffParser`
- `KeysFeature` — Ed25519 key management
- `SettingsFeature` — `PaywallSheet`, `TerminalSettingsView`, `BillingView`

**Watch app** — multi-tab (Inbox/Activity/Session/Snippets), widget, app group.

**Backend** — `daemon/conduitd` (Go, JSON-RPC over SSH), `daemon/push-backend` (Stripe + APNs).

### 1.2 The terminal architecture as it stands

There are **two display modes**:

- **Block mode** (`SessionView.blockScroll` — `SessionView.swift:242–274`)
  - A scrolling list of `Block` objects rendered as cards
  - User input is the `composer` `TextField` at the bottom (`SessionView.swift:278–329`)
  - `vm.submit()` → `vm.run(command:)` sends a whole command + `\n`
- **Raw mode** (`SessionView.rawTerminalContent` — `SessionView.swift:108–154`)
  - `RawTerminalView` (SwiftTerm `UIViewRepresentable`)
  - Software keyboard becomes first-responder; bytes flow direct to PTY via `onUserBytes` (`SessionView.swift:114–119`)
  - `KeyboardAccessoryRail` sits in the bottom safe-area inset

There is **one persistent SSH shell** per session — the "unified PTY":
- `SessionViewModel.unifiedShell: SSHShell?` (`SessionViewModel.swift:58`)
- Opened on connect (`SessionViewModel.openUnifiedShell()` — `SessionViewModel.swift:250–375`)
- Wrapped in a `PTYBridge` actor that pumps bytes into both a `RawTerminalView` *and* a block-mode byte stream
- Shell integration script is auto-injected on connect (`SessionViewModel.swift:231–246`) so the remote shell emits OSC 133 A/B/C/D and OSC 7 markers

`PTYBridge` (`PTYBridge.swift:39–348`) parses two protocols out of the byte stream:
- **Alt-screen** sequences `\e[?1049h` / `\e[?1049l` → fires `onAltScreenEnter` / `onAltScreenExit`
- **OSC 133**:
  - `A` (prompt_start) — `case "A": break` — **NO-OP**
  - `B` (prompt_end) — `case "B": break` — **NO-OP**
  - `C` (preexec) — fires `onCommandStart`
  - `D;N` (postcmd) — fires `onCommandDone(exitCode)`
- **OSC 7** — `\e]7;file://host/path\a` → fires `onCWDUpdate`

`onAltScreenEnter` (`SessionViewModel.swift:314–326`) flips `isRaw = true` and the UI switches from blocks to `RawTerminalView`. On exit it flips back.

### 1.3 The full input flow today

**Block mode submit path** (`SessionViewModel.run(command:)` — line 440–447):

```swift
private func run(command: String) async {
    commandHistory.append(command)
    guard let shell = unifiedShell else { return }
    let prompt = Block.PromptInfo(cwd: cwd, hostName: host.name)
    let blockID = blocks.begin(sessionID: sessionID, command: command, prompt: prompt)
    unifiedBlockID = blockID
    try? await shell.send(Array((command + "\n").utf8))
}
```

**Raw mode** input path (`SessionView.swift:113–119`):

```swift
onUserBytes: { bytes in
    let typedBytes = Array(bytes)
    Task { @MainActor in
        let outgoing = consumeRawCtrlLatch(typedBytes)
        try? await vm.activeShell?.send(outgoing)
    }
}
```

`vm.activeShell` is non-nil **only** in raw mode (`SessionViewModel.swift:323` and `:393`).

Notice the asymmetry: in raw mode, every keystroke is one PTY write. In block mode, the only way bytes reach the PTY is via `run(command:)`, which always mints a fresh block before sending.

### 1.4 Why Claude Code breaks (the bug, narrated)

> The story has two layers — first the proximate cause that triggers the
> failure, then the architectural cause that prevents recovery.

#### Layer A: proximate — smart punctuation mutates the command

The composer `TextField` (`SessionView.swift:283–294`) sets:

```swift
.textInputAutocapitalization(.never)
.autocorrectionDisabled()
```

but it does **not** set `smartDashesType = .no`, `smartQuotesType = .no`, or `smartInsertDeleteType = .no`. The SwiftTerm raw-mode view does set them (`RawTerminalView.swift:210–212`), but the SwiftUI composer doesn't have direct modifiers for them — they only exist on `UITextInputTraits`. So when a user types `claude --version`:

- iOS rewrites `--` to em-dash `—`
- The shell receives `claude —version`
- That parses as `claude` (an unknown argument), shell runs `claude` interactively
- The user lands inside Claude Code, expecting a one-shot version check

This is the bug a tester hits first. Fixing it is one `UIViewRepresentable` wrapping `UITextField` with the right `UITextInputTraits`, plus matching `.disableAutocorrection(true)` and `.textContentType(.username)` (which suggests plain text to iOS). The smart-punctuation fix alone unblocks the `--version` case and similar one-shot commands.

But the user *also* wants to interact with Claude when they intentionally launch it. That's where Layer B kicks in.

#### Layer B: architectural — block model can't handle live programs

The user is connected, sitting at the block-mode view. They type `claude` (no flags) in the composer and tap send.

1. `vm.submit()` → `vm.run(command: "claude")`
2. `blocks.begin(...)` creates **block A**; `unifiedBlockID = A`
3. `shell.send("claude\n")` — shell launches Claude Code
4. Shell hook fires `\e]133;C\a` → `PTYBridge.onCommandStart` → `isExecutingUnified = true`
5. Claude Code starts outputting cursor-positioning sequences (`\e[H`, `\e[2J`, `\e[?25l`, inline rewrites)
6. `PTYBridge.start()` pumps these to `onBlockBytes` (because no alt-screen)
7. `BlockRenderer.append` (`BlockRenderer.swift:54–75`) sees `\e[H` etc. → flips `hasCursorMovement` on for block A → engages per-block SwiftTerm
8. Claude Code's UI renders inside block A. So far so good.

Now the user wants to talk to Claude. They type "tell me about this repo" in the composer and tap send.

9. `vm.submit()` → `vm.run(command: "tell me about this repo")`
10. `blocks.begin(...)` creates **block B**; `unifiedBlockID = B` ← **DAMAGE STARTS HERE**
11. `shell.send("tell me about this repo\n")` — bytes go to the PTY. The shell isn't at a prompt; Claude Code is the foreground process owning the PTY, so Claude receives "tell me about this repo\n" as stdin
12. No OSC 133 C fires (Claude isn't the shell). `isExecutingUnified` is still `true` from step 4.
13. Claude responds with cursor-positioning + text. Bytes flow through `onBlockBytes` → routed to `unifiedBlockID` = **block B**.
14. **Block A is now frozen** showing Claude's pre-input state.
15. **Block B accumulates Claude's response** but doesn't have the rest of Claude's UI context. It looks garbled because cursor sequences relative to Claude's full screen make no sense in an empty block.
16. The user sees: original Claude block frozen, new gibberish block, no working input.

This is the unresponsiveness. The byte stream is going through; the block model is what's broken.

A secondary failure: even if we fix the block creation problem, the composer model means the user can't type a single character into Claude — they have to type a full string + submit, which round-trips through the composer's `TextField`. There's no way to press Tab, Esc, arrow keys, Ctrl-C, or any other interactive control while in block mode.

### 1.5 What about the auto-escalation?

`PTYBridge.scanAltScreen` (`PTYBridge.swift:205–221`) only looks for `\e[?1049h`. Claude Code uses inline cursor positioning, not alt-screen — so `escalationDetected` never flips and `onAltScreenEnter` never fires. The block-to-raw switch never happens.

This is intentional in Warp's model too: alt-screen is for vim/htop/tmux; everything else stays in the block. The difference is Warp's blocks accept live input, ours don't.

---

## 2. How Warp handles this

(Full source citations in the appendix; this section summarises the model that's relevant to our fix.)

**Warp's terminal is one PTY per session.** All input goes through one event channel:

```
NSEvent → typed_characters_on_terminal()
       → should_write_typed_chars_to_pty()
         ├── YES (active block has started) → write_user_bytes_to_pty() → PTY
         └── NO  (active block not started) → input box buffer (local edit)
```

The decision is **`active_block().started()`** — once the block has received its first byte of output, every keystroke flows straight to the PTY. No "interactive mode" detection, no heuristics; the block stays in `Executing` state for the entire foreground program's lifetime.

**Blocks are a *display* concept.** They are slices of the PTY's output, bounded by OSC 133 markers:
- `133;A` (prompt_start) — start of prompt; the user can edit
- `133;B` (prompt_end) — prompt complete; user pressed enter
- `133;C` (preexec) — command started; block transitions to `Executing`
- `133;D;N` (postcmd) — command done with exit code N; new block created

Pre-`133;A` text + edit buffer is the "input box". From `133;C` onward, the active block is *the* output container, and every keystroke is forwarded to stdin.

**Alt-screen is a rendering switch, not a mode change.** When `\e[?1049h` appears, Warp renders from an `AltScreenElement` overlay (a separate grid) instead of the block's output grid. Input still goes to the same PTY. When the program exits, alt-screen disappears and the block reappears with whatever scrollback the program left behind.

**No raw mode, no block mode toggle.** There's one architecture; alt-screen is a special render path within it.

Key Warp source citations (verified by background-agent exploration of `/Users/roshansilva/Downloads/warp-master`):
- Block state machine + `is_active_and_long_running`: `app/src/terminal/model/block.rs:610–634, 1719–1753`
- Input gate `should_write_typed_chars_to_pty`: `app/src/terminal/view.rs:8298–8320`
- Single PTY per session: `app/src/terminal/local_tty/unix.rs:51+`
- OSC 133 parser: `crates/warp_terminal/src/model/ansi/control_sequence_parameters.rs:620–681`
- Alt-screen overlay: `app/src/terminal/alt_screen/alt_screen_element.rs:55–195`
- `LONG_RUNNING_COMMAND_DURATION_MS = 50`: `app/src/terminal/model/block.rs:68`

---

## 3. How cmux handles this

cmux is interesting as a *counter-example*: it does **no** block segmentation at all.

- One Ghostty PTY per `TerminalSurface`
- Workspace > Panels > TerminalSurface hierarchy
- Input path: `NSEvent → GhosttyNSView.keyDown → ghosttyKeyEvent() → ghostty_surface_key(surface, keyEvent)` — direct C call, zero intermediate layer
- No composer, no command-line draft buffer, no OSC 133 parsing in app layer (Ghostty handles ANSI internally, doesn't expose semantic markers)
- Agent attention is signalled out-of-band: `cmux notify --workspace ID --surface ID "Title|Subtitle|Body"` is a socket command, not a terminal escape
- Session "persistence" = layout + scrollback metadata; live agent state requires hooks (`cmux hooks setup claude`) that record session IDs the agent CLI can resume

What cmux teaches us:
1. **Latency is sacred.** cmux's `CLAUDE.md` explicitly warns against adding work outside the `isPointerEvent` guard in `WindowTerminalHostView.hitTest` — keyboard latency must be zero. They use SwiftUI `Equatable` conformance to skip body re-evaluation while typing.
2. **Direct PTY input wins.** No queue, no buffer, no decision logic for keystrokes. The only queueing is for socket-API input (1 MB cap).
3. **Remote sessions need their own daemon.** cmux's WebSocket daemon (`cmuxd-remote/ws_pty.go`) holds a 24h-idle PTY session; reconnect = re-attach to the same session. This is exactly our "phone reattaches to remote tmux/agent" use case, just shaped differently.
4. **Agent resume is opt-in and explicit.** They don't try to magically reattach; they ask the user to install hooks, then resume via the agent's own `--continue` flag.

What cmux teaches us **not** to do:
1. Don't drop block segmentation entirely. On a phone, scrollback is hard to navigate without blocks — Warp's model gives us copy-block, re-run-block, explain-block, all of which we want.
2. Don't rely on a separate notification protocol when OSC 133 + tmux already give us the signals we need.

cmux source citations:
- Workspace/Panel/TerminalSurface: `Sources/Workspace.swift:142`, `Sources/Panels/TerminalPanel.swift:34`, `Sources/GhosttyTerminalView.swift:5093`
- Input path: `Sources/GhosttyTerminalView.swift:9280` (`sendGhosttyKey` → `ghostty_surface_key`)
- Socket input queue (only queued path): `Sources/GhosttyTerminalView.swift:5233–5235`
- Remote PTY daemon: `daemon/remote/cmd/cmuxd-remote/ws_pty.go:29–195, 1306+`
- Session persistence: `Sources/SessionPersistence.swift`, `Sources/RestorableAgentSession.swift`
- Notification socket command: `Sources/TerminalController.swift:17477–17513`

---

## 4. Side-by-side feature matrix

Columns: **Conduit** (what we have today), **Warp** (desktop ref.), **cmux** (macOS native), **Termius** (mobile baseline). A `~` means partial.

### 4.1 Terminal model

| Feature | Conduit | Warp | cmux | Termius |
|---|---|---|---|---|
| Block-segmented PTY output | ✅ | ✅ | ❌ | ❌ |
| Block segmentation signal | OSC 133 markers (we have them but only use C/D) | OSC 133 A/B/C/D fully used | n/a (continuous) | n/a |
| Single PTY per session | ✅ (unified shell) | ✅ | ✅ | ✅ |
| Input always direct to PTY | ❌ (composer in block mode) | ✅ (when block started) | ✅ (always) | ✅ |
| Composer/draft input | ✅ (only path in block mode) | ✅ (only before block starts) | ❌ | ❌ |
| Interactive-program in-block | ❌ broken | ✅ | n/a | n/a |
| Alt-screen TUI handling | Mode switch to raw view | Overlay render in same view | Direct (Ghostty handles it) | Direct |
| Per-block re-render via VTE | ✅ SwiftTerm per block | ✅ output grid per block | n/a | n/a |
| Block actions (copy/star/explain/rerun) | ✅ | ✅ | n/a | n/a |
| Block collapse | ✅ | ✅ | n/a | n/a |
| Block failure indicator | ✅ red sidebar | ✅ | n/a | n/a |
| Search across blocks/buffer | ❌ | ✅ | ✅ (Ghostty) | ✅ |
| Bracketed paste detection | ✅ | ✅ | ✅ | ✅ |
| Pinch-to-zoom font (mobile) | ✅ (raw only) | n/a | n/a | ✅ |

### 4.2 SSH / connection

| Feature | Conduit | Warp | cmux | Termius |
|---|---|---|---|---|
| SSH password auth | ✅ | ~ (delegate to OS) | ~ | ✅ |
| Ed25519 keys + Keychain | ✅ + biometric | ~ | ~ | ✅ |
| TOFU host-key confirmation | ✅ | ✅ | ✅ | ✅ |
| Connection timeout | ✅ 15s | ✅ | ✅ | ✅ |
| Auto-reconnect on network change | ✅ | n/a (local) | n/a (local) | ✅ |
| tmux auto-attach | ✅ | ❌ | ~ (manual `cmux ssh`) | ✅ |
| Mosh support | ❌ | ❌ | ❌ | ✅ |
| Local port forwarding | ✅ | n/a | n/a | ✅ |
| SFTP file browser | ✅ | n/a | n/a | ✅ |
| Background keep-alive | ~ (scene-phase only) | n/a | n/a | ~ (limited) |

### 4.3 AI / agent

| Feature | Conduit | Warp | cmux | Termius |
|---|---|---|---|---|
| NL → command synthesis | ✅ (`#` prefix) | ✅ | n/a | ✅ |
| Explain command/output | ✅ streaming | ✅ | n/a | ✅ |
| AI Agent inbox + approvals | ✅ (conduitd) | ✅ Agent Mode | ✅ (notifications) | ❌ |
| Multi-agent (Claude+OpenAI) | ✅ | ✅ | ✅ (Claude, Codex, Grok, OpenCode…) | ✅ |
| Risk-scored commands | ✅ | ✅ | ❌ | ❌ |
| Agent attention signal | Push + inbox card | In-block + agent mode | Bell + socket `cmux notify` | n/a |
| Agent session resume | ~ (tmux reattach) | n/a | ✅ (hooks per-agent) | n/a |

### 4.4 UX / surfaces

| Feature | Conduit | Warp | cmux | Termius |
|---|---|---|---|---|
| Multi-surface (term/preview/files/diff/inbox) | ✅ | ~ | ~ (browser pane) | ~ (split tabs) |
| Dev-server preview (in-app browser) | ✅ WKWebView | ❌ | ✅ browser panel | ❌ |
| Unified diff review | ✅ | ✅ | ❌ | ❌ |
| Split-pane layout | ❌ (phone) | ✅ | ✅ Bonsplit | ✅ desktop |
| Workspaces / projects | ✅ | ✅ Drives | ✅ workspaces | ✅ groups |
| Snippets/workflows | ✅ palette | ✅ Workflows | ❌ | ✅ |
| Hardware-keyboard mappings | ✅ `HardwareInputHandler` | ✅ | ✅ | ✅ |
| Voice dictation | ✅ | ❌ | ❌ | ❌ |
| Watch companion + widget | ✅ | ❌ | ❌ | ❌ |
| CloudKit sync (hosts/snippets) | ✅ | n/a | n/a | ✅ |
| Push notifications (approvals/suspend) | ✅ | n/a | ✅ macOS | ✅ |
| Biometric app gate | ✅ | n/a | n/a | ✅ |

### 4.5 Plug-and-play targets (the user's goal)

| Promise | Conduit today | After redesign | Warp | cmux |
|---|---|---|---|---|
| Open a host → terminal works | ✅ | ✅ | ✅ | ✅ |
| Resume tmux session on connect | ✅ if `host.tmuxSessionName` set | ✅ + auto-detect existing sessions | ❌ | manual |
| Continue a running Claude Code from another machine | ❌ broken | ✅ via tmux + working interactive block | n/a | ✅ via hooks + tmux |
| Type into a running agent | ❌ broken | ✅ direct keystroke flow | ✅ | ✅ |
| Approve agent action without opening terminal | ✅ inbox | ✅ | ~ (socket notify) | n/a |

---

## 5. Recommended redesign

### 5.1 Single mental model

**Drop the "block mode vs raw mode" toggle.** There is one mode: a session with one persistent PTY, displayed as a vertical stack of blocks, with input that always flows to the PTY.

```
                                 Conduit (post-redesign)
        ┌─────────────────────────────────────────────────────────┐
        │  status bar (host, status dot, CWD)                     │
        ├─────────────────────────────────────────────────────────┤
        │                                                         │
        │  ┌─── Block N-1 (finished, collapsed by default) ───┐   │
        │  │  $ ls                                            │   │
        │  │  README.md  package.json  src/                   │   │
        │  └──────────────────────────────────────────────────┘   │
        │                                                         │
        │  ┌─── Block N-1 (finished, exit 0) ─────────────────┐   │
        │  │  $ git status                                    │   │
        │  │  ...                                             │   │
        │  └──────────────────────────────────────────────────┘   │
        │                                                         │
        │  ┌─── Block N (active / executing) ─────────────────┐   │
        │  │  $ claude                                        │   │
        │  │  ╭──────────────────────────────────────╮        │   │
        │  │  │  Claude Code live UI renders here    │        │   │
        │  │  │  (cursor pos / inline rewrites)      │        │   │
        │  │  ╰──────────────────────────────────────╯        │   │
        │  └──────────────────────────────────────────────────┘   │
        │                                                         │
        ├─────────────────────────────────────────────────────────┤
        │  [Esc][Tab][Ctrl][Tmux][↑↓←→][|][;][/][$]              │  ← always on when connected
        ├─────────────────────────────────────────────────────────┤
        │  $ _                                                    │  ← prompt edit field
        │  [mic] [snippets] [send/abort]                          │
        └─────────────────────────────────────────────────────────┘
```

- **Active block** = the last block in the list, the one that hasn't received OSC 133 D yet.
- **Prompt edit field** = a `UIKeyInput`-conformant view that captures keystrokes. State machine:
  - *Prompt state* (after `133;A`, before `133;C`): visible as a text field, characters are buffered; Send sends `\n`. (Just like today's composer, but living *inside* the active block.)
  - *Executing state* (after `133;C`, before `133;D`): the field renders as a thin "live input" caret. Every keystroke is forwarded to PTY immediately. The `KeyboardAccessoryRail` is the visible affordance.
- **Alt-screen** (vim/htop/tmux): the active block expands to fill, rendered by SwiftTerm overlay. Input still flows to PTY through the same path. When alt-screen exits, the block collapses back to its "regular" shape with the program's final scrollback. No mode toggle.

This is **Warp's model, shaped for a phone**: instead of clicking the input box, the active block "owns" the input field at its bottom edge; instead of having a desktop-sized chrome, the bottom inset carries the accessory rail.

### 5.2 The state machine

```
                            ┌──── PTY bytes ─────┐
                            ▼                    │
        ┌───────────┐  133;A   ┌─────────┐  133;C  ┌──────────┐  133;D
        │ idle/boot ├─────────►│ prompt  ├────────►│ executing├──────► (new block)
        └───────────┘          └─────────┘         └──────────┘
                                    │                   │
                                    │                   ├─ alt-screen on/off (overlay)
                                    │                   ├─ keystrokes → PTY direct
                                    ▼                   ▼
                              keystrokes:           keystrokes:
                              edit buffer locally   PTY direct
                              \n → send to PTY      every char → PTY
```

State variables we already have on `SessionViewModel`:
- `unifiedBlockID` — change semantics: this is now the **active** block ID, lifecycle owned by OSC 133 markers, not by `submit()`.
- `isExecutingUnified` — kept as-is, drives the input state machine.

New state variable:
- `promptDraft: String` — buffer for the input field. Reset on `133;C` (it was just sent) and on `133;A` (new prompt cycle).

### 5.3 File-by-file change list (no code yet — sizes and intents)

These are the files that need to change. I'm **not** writing the code in this doc; that comes after you approve.

**Phase 0 (quick wins, no architecture):**

0a. **New file `TerminalSafeTextField.swift`** in `DesignSystem` — a `UIViewRepresentable` wrapping `UITextField` with `smartDashesType = .no`, `smartQuotesType = .no`, `smartInsertDeleteType = .no`, `autocorrectionType = .no`, `autocapitalizationType = .none`, `spellCheckingType = .no`. Replace the SwiftUI `TextField` in `SessionView.swift:283–294`. Also use this for the host editor's hostname/command fields and the snippet editor body.

0b. **New folder `Packages/ConduitKit/Sources/TerminalEngine/Resources/`** — extract the inline shell-integration script (`SessionViewModel.swift:231–246`) into three bundled files: `conduit-init.bash`, `conduit-init.zsh`, `conduit-init.fish`. Loaded via `Bundle.module.url(forResource:withExtension:)`. Easier to update, easier to inspect, easier to test against fixtures.

0c. **`PurchaseManager.swift` + `BillingEligibility.swift`** — add a debug bypass:
```swift
#if DEBUG
public var debugProBypass: Bool {
  UserDefaults.standard.bool(forKey: "conduitDebugProBypass")
}
#endif
```
…and a Settings toggle "Unlock all features (debug)". Production builds ignore the toggle. This unblocks the testing of Preview/Files/Diff/Inbox surfaces in simulator without touching StoreKit.

0d. **Audit duplicate keyboard rails.** Right now `KeyboardAccessoryRail` lives in `SessionView.rawTerminalContent`'s `safeAreaInset(edge: .bottom)`. Verify whether `RawTerminalView`'s internal SwiftTerm `TerminalView` also sets `inputAccessoryView`. If so, kill one — only one rail should be visible at a time.

0e. **Status-bar overlap.** `SessionView` uses `.background(.thinMaterial)` on the status bar (line 207). On iOS 26 this can compose unexpectedly with `Liquid Glass` chrome below. Verify visually and adjust the safe-area insets or `.zIndex` ordering as needed.

**Phase 1+ (architectural — the redesign):**

1. **`PTYBridge.swift`** — extend the OSC 133 dispatch to fire on `A` and `B`:
   - `case "A":` → `onPromptStart?()`
   - `case "B":` → `onPromptEnd?()`
   - Add the two new callbacks to `configure(...)`.
   - Lines affected: roughly 81–94 (configure signature), 310–322 (dispatchOSC133).

2. **`SessionViewModel.swift`** — the biggest change. Approximate diff shape:
   - Remove `run(command:)`'s `blocks.begin(...)` call. Block lifecycle is now owned by the new OSC 133 A handler in the bridge configure.
   - Add `onPromptStart` callback: if there's an active block in `executing` state without a 133;D, finalize it as `interrupted`; otherwise, create a new block with `state = .promptEditing`.
   - Add `onPromptEnd` callback: capture the prompt text, transition the active block to `state = .submitted` (waiting for 133;C).
   - In `onCommandStart` (133;C): transition active block to `state = .executing`.
   - In `onCommandDone` (133;D): transition active block to `state = .done(exit)`, persist, and emit a "ready for new prompt" signal so the next 133;A creates the next block.
   - Add `sendKeystrokes(_ bytes: [UInt8])` — direct PTY write, used by the active block's input field when executing.
   - Change `submit()` to: append `promptDraft + "\n"` to PTY (no block creation here), clear `promptDraft`.
   - Remove `escalateToRaw()` and `deescalate()` as user-facing toggles (alt-screen drives it automatically; we can keep them as private helpers if any callers remain).

3. **`BlockRenderer.swift`** — minor:
   - Add `BlockState` enum: `.promptEditing | .submitted | .executing | .done(exit)`. Replace today's `exitStatus`-based "is it finished?" check with this.
   - `clearChunks(id:)` stays (used on alt-screen overlay swap).

4. **`Block.swift`** (`ConduitCore`) — model change:
   - Add `state: BlockState`. Migrate `exitStatus` to be a derived value of `state`.
   - `command` becomes mutable while in `.promptEditing` so the input field can update it before submit; freezes once `.submitted`.

5. **`SessionView.swift`** — UI rewrite of `blockScroll` + the composer:
   - Block rows render differently based on `block.state`. The active block (`.promptEditing` / `.submitted` / `.executing`) renders an input field at its bottom.
   - Composer at the bottom of the screen goes away. The active block IS the composer.
   - `rawTerminalContent` collapses into the active-block rendering — when `vm.isInAltScreen`, the active block becomes a SwiftTerm host filling the available space.
   - `KeyboardAccessoryRail` is always visible (with `.connected` status), not just in raw mode.

6. **`RawTerminalView.swift`** — stays. It's reused as the alt-screen overlay inside the active block. We may move it from `SessionFeature` to an embeddable surface inside `BlockRow`.

7. **New file: `LivePromptInputView.swift`** — a `UIKeyInput`-conformant wrapper that:
   - Captures every keystroke directly (no `TextField` middleware)
   - When `block.state == .promptEditing`, buffers chars and shows them as a cursor-positioned line
   - When `block.state == .executing`, forwards each keystroke immediately to PTY
   - This is the iOS equivalent of `ghostty_surface_key` — bytes go through with no intermediate buffer

8. **`Notifications.swift` / `Inbox` paths** — unchanged.

9. **Tests** — add to `PTYBridgeTests.swift`:
   - `133;A` fires `onPromptStart`
   - `133;B` fires `onPromptEnd`
   - Full A→B→C→D sequence drives the block state machine in `SessionViewModel` (this one is a new VM test file — `SessionViewModelTests.swift`)
   - Simulated Claude Code byte stream (no alt-screen, cursor-positioning, awaiting input) routes follow-up keystrokes directly to PTY, not to a new block

### 5.4 Plug-and-play (the user's stated goal)

The "start on phone, continue from laptop, continue from phone" loop requires three things:

1. **A running session that survives client disconnect.** We already have tmux auto-attach if `host.tmuxSessionName` is set (`SessionViewModel.swift:155–161`). The redesign keeps this. After the block-model fix, a tmux session containing Claude Code becomes a *live agent session you can drive from the phone*.

2. **Auto-detect existing sessions.** Today the host editor has a tmux session field. We should also:
   - On connect, run `tmux ls 2>/dev/null` and offer "Attach to <session-name>" if any exist.
   - On connect, scan for foreground agent processes (`pgrep -f 'claude|codex|grok' 2>/dev/null`) inside detected tmux sessions and surface them as "Resume Claude Code in tmux session work".
   - This is a small SSH `executeCollected` chain in `SessionViewModel.connect()`.

3. **Reattach semantics that survive everything.** Network drop → tmux session keeps running, agent keeps running. Phone reconnects → re-attaches to tmux → the active block re-renders the agent's current screen. Works because the PTY is the tmux session's, not the phone's.

This loop is achievable as a follow-up phase *after* the block-model redesign lands. It doesn't require new infrastructure — just three SSH calls and one UI surface on the connect screen.

---

## 6. Reuse matrix — what to vendor from cmux and Warp

> Two parallel deep-dives mapped each Conduit feature against its closest
> counterpart in Warp and cmux, with file:line citations and a portability
> rating. This section is the synthesis: **what we can copy outright, what
> we adapt, what we keep building ourselves.** The rule is "don't reinvent
> the wheel when professionals already shipped a working version."

### 6.1 Portability levels

- **DIRECT** — copy with light renames. For cmux, this is Swift-to-Swift verbatim. For Warp, this is Rust→Swift port of an algorithm that has no idiomatic gap (parsers, state machines, palette indices).
- **ADAPT** — the design transfers, the API surface differs. Their structure → our types; their AppKit → our UIKit; their Rust regex → our Swift Regex.
- **PATTERN** — only the architectural idea transfers. We re-implement because their source is proprietary, dynamic, or fundamentally different.
- **KEEP** — we already have it, no equivalent exists, or ours is better-shaped for our environment.

### 6.2 What to vendor — by feature

The table merges both reference reports. **C-cmux** column shows cmux's rating; **C-Warp** shows Warp's. The **Action** column is what we should actually do.

| Feature | C-cmux | C-Warp | Action |
|---|---|---|---|
| ANSI SGR parser | — | DIRECT | We already have `AnsiSGRParser.swift`; cross-check the flag set against Warp's `cell.rs:39–63` to catch missing attrs (DOUBLE_UNDERLINE, STRIKEOUT). |
| OSC 133 / OSC 7 dispatch | — | ADAPT | Mirror Warp's `PromptMarker` enum shape in our `PTYBridge`. We already wire A/B as no-ops; the Phase 2 work moves to Warp's enum-driven dispatch. |
| Per-block grid cell (fg/bg/flags) | — | DIRECT | Warp's `cell.rs` `Flags` bitfield is 1:1 with what we need from SwiftTerm. Verify our `makeContainer` covers all flags (double-underline, strikeout, wide-char spacer). |
| Bracketed paste mode (2004) | — | DIRECT | Already detected in `PTYBridge.scanAltScreen`. Just confirm mode-number dispatch shape matches Warp's `Mode::BracketedPaste`. |
| Terminal theme system | ADAPT | DIRECT | Adopt Warp's palette-index scheme (0–7 standard, 8–15 bright, named constants in `control_sequence_parameters.rs:711–741`). Ship 2–3 themes as JSON resources in `DesignSystem`. |
| Workflows / snippets schema | — | DIRECT | **Adopt Warp's YAML workflow format directly** (`test_workflow.yaml`): `name`, `command`, `description`, `arguments`, `tags`, `source_url`, `{{param}}` substitution. Our existing `SnippetRepository` becomes a thin storage layer over this schema. |
| Block persistence schema | — | ADAPT | Extend our `BlockRepository` row to mirror Warp's `Block` fields (`persistence/src/model.rs:699–763`): keep `stylized_command` and `stylized_output` raw (don't strip ANSI on save), add `prompt_snapshot` JSON cache, `ai_metadata` JSON, `pwd`, `git_branch`, `start_ts`/`completed_ts`. |
| Login-shell wrap | — | ADAPT | Keep our `loginShellWrap` but confirm `$SHELL` detection drives it (Warp's ShellType enum pattern). Test against bash/zsh/fish bundled scripts (Phase 0 work). |
| **Agent registry** | **DIRECT** | — | **Copy `CmuxVaultAgentRegistration` struct + sub-enums verbatim** (`VaultAgentRegistry.swift`). Schema: `id, name, iconAssetName, detect, sessionIdSource, resumeCommand, cwd, sessionDirectory`. This is the foundation for "auto-detect Claude Code running in tmux on connect". |
| **Agent session resume** | PATTERN | — | Adopt cmux's `AgentResumeCommandBuilder.resumeShellCommand(kind:sessionId:launchCommand:workingDirectory:)` shape (`RestorableAgentSession.swift:35–75`). Store session IDs in our `PersistenceKit` instead of hook files. |
| **Per-agent hook JSON schema** | ADAPT | — | Copy the `AgentHookDef` schema from `CMUXCLI+AgentHookDefinitions.swift:1–150`. Drop shell-format variants we don't need; keep nested/flat/JSON formats. Use to drive Conduit's "what hooks does this agent need installed remotely" UI. |
| **Notification protocol** | ADAPT | — | Use cmux's JSON shape `{title, subtitle, body, workspace, surface}` for daemon→phone notifications. Wire into our existing `Notifications.shared` path. |
| **PTY session keying** | DIRECT | — | Copy cmux's two-tier `wsPTYSessionKey` scheme (`ws_pty.go:124–143`): persistent (sessionID only) + anonymous (sessionID + counter). Use sessionID-only-derived keys for resume across machines. |
| **Idle TTL with pin** | DIRECT | — | Copy cmux's 24h default + a "pinned" override that bypasses reap (`ws_pty.go:1154–1186`). Wire to a per-session `pinned: Bool` flag. |
| **Input queue draining + caps** | DIRECT | — | Copy cmux's constants and pattern (`ws_pty.go:80–90`, `GhosttyTerminalView.swift:7108–7135`): `inputQueueCap = 256` frames, `inputChunkBytes = 16 KB`, `scrollbackCap = 1 MB`. Drain on main queue at display refresh. **Use these for Phase 4 `LivePromptInputView`'s back-pressure semantics.** |
| **Hardware keyboard chord map** | DIRECT | — | Copy cmux's `modsFromFlags` bitwise mapping (`GhosttyTerminalView.swift:9436–9455`). Translate from `NSEvent.ModifierFlags` to `UIPress.modifierFlags` — same shape, different enum names. Update our `HardwareInputHandler` to match cmux's encoding so Ctrl-C/D/Z send the correct PTY bytes. |
| **Workspace/Panel snapshot Codables** | DIRECT | — | Copy `SessionWorkspaceSnapshot`, `SessionPanelSnapshot` (`SessionPersistence.swift:225–280`). Drop view-specific fields. Used for iPad split-pane future and "remember last tmux session per host" (Phase 6). |
| **Session persistence policy limits** | DIRECT | — | Adopt cmux's caps (`SessionPersistence.swift:15–49`): max 12 windows, 128 workspaces/window, 512 panels/workspace, 4000 scrollback lines. Even if our hierarchy is shallower, these tell us where to put limits. |
| NL → command synthesis | — | PATTERN | Copy Warp's `BlockContext` field set (`block_context.rs:10–59`): `command, output, exit_code, pwd, shell, git_branch, username, hostname, os, session_id`. Use as our AI request schema. Prompt template stays ours. |
| Output redaction | — | ADAPT | Adopt Warp's multi-pattern regex engine shape (`secret_redaction.rs:13–83`). Pattern list is Warp-proprietary — keep our `Redactor.swift` patterns; learn from the engine design only. |
| Unified-diff parser | — | KEEP | Warp doesn't expose one. Our `UnifiedDiffParser` stands. |
| Risk scorer | — | KEEP | Warp doesn't expose it. Our `RiskScorer.swift` stands. |
| Port detector | — | KEEP | Warp doesn't expose it. Our `PortDetector.swift` stands. |
| tmux client (SSH wire) | KEEP | KEEP | Warp's tmux integration uses tmux control mode internally — not exposed. Our `TmuxClient` stands. |
| WebSocket PTY protocol | PATTERN | — | We use JSON-RPC over SSH (`conduitd`). cmux uses WS framing with `attachment_id` for tab-switching across reconnects. Worth considering for v2; not for the current redesign. |
| Smart input traits (iOS-specific) | N/A | N/A | Phase 0 — our problem to solve. Neither codebase needs it. |
| SFTP browser | — | — | Neither has it. Ours stands. |
| WKWebView dev-server preview | — | — | Neither has it. Ours stands. |
| Watch app + widget | — | — | Neither has it. Ours stands. |

### 6.3 Recommended vendor strategy

**Five things to do, ranked by leverage:**

1. **Vendor cmux's agent infrastructure** (highest leverage). Copy `CmuxVaultAgentRegistration`, `AgentResumeCommandBuilder`, `AgentHookDef` schemas as `Packages/ConduitKit/Sources/AgentKit/AgentRegistry.swift` and friends. Strip macOS-specific bits. This **is** the foundation for the user's "continue from another machine" goal — auto-detect Claude Code running on a remote host, resume from phone, resume back on laptop.

2. **Vendor cmux's PTY/session primitives**. Session keying (two-tier), idle TTL (24h + pin), input queue (256 frames / 16KB / 1MB), keyboard chord mapping, queue-drain pattern. These become the building blocks for the architectural Phase 1–4 work. Approx 200 lines of Swift we don't have to design.

3. **Adopt Warp's workflow YAML schema as our snippet format**. Our `SnippetRepository` keeps the database, but the file format users import/export and the in-app schema become Warp-compatible. Users can paste Warp workflow YAML and it imports cleanly. Adopt `{{param}}` substitution as-is.

4. **Extend our `Block` schema with Warp's fields** before persisting more data. `prompt_snapshot`, `ai_metadata`, `git_branch`, `start_ts/completed_ts` are useful for the AI loop and free if we add them now (vs migrating later).

5. **Use Warp's `BlockContext` shape as our AI request schema**. Our `PromptBuilder` aggregates the same fields they do; matching the schema means we can swap AI backends without re-thinking the context envelope.

### 6.4 New file structure after vendoring

Phase 0 + vendoring would add these files to `Packages/ConduitKit/`:

```
Sources/AgentKit/
    AgentRegistry.swift           ← from cmux VaultAgentRegistry
    AgentResumeBuilder.swift      ← from cmux RestorableAgentSession
    AgentHookDef.swift            ← from cmux CMUXCLI+AgentHookDefinitions
    BlockContext.swift            ← from Warp ai/block_context.rs (Swift port)
Sources/SSHTransport/
    PTYSessionKey.swift           ← from cmux ws_pty.go (Swift port)
    PTYInputQueue.swift           ← from cmux ws_pty.go input queue
Sources/PersistenceKit/
    SessionSnapshot.swift         ← from cmux SessionPersistence.swift
    SnippetWorkflow.swift         ← from Warp test_workflow.yaml schema
Sources/DesignSystem/
    TerminalSafeTextField.swift   ← Phase 0 fix (no external source)
    TerminalTheme+Palette.swift   ← from Warp control_sequence_parameters.rs constants
Sources/TerminalEngine/Resources/
    conduit-init.bash             ← Phase 0 work
    conduit-init.zsh              ← Phase 0 work
    conduit-init.fish             ← Phase 0 work
```

Roughly **8 new files**, most under 200 lines, all anchored to a specific upstream source for future updates. Existing files (`PTYBridge`, `BlockRenderer`, `SessionViewModel`, etc.) only get updated to use the new types — they don't get rewritten.

### 6.5 What this changes about the implementation plan

The big shift: **Phase 1 (tests-first) and Phase 2 (OSC 133 wiring) become much smaller because the data shapes are already designed.** Phase 3 (block state machine) lands cleanly because `BlockContext` and `SessionSnapshot` give us the persistence story for free. Phase 4 (direct keystroke flow) gets concrete numbers (256/16KB/1MB) from cmux instead of guesswork.

The plan in §7 below stays the same in structure but each phase now references the vendored primitive instead of "design from scratch".

### 6.6 What this delivers — and what it doesn't (honest scope)

A direct answer to "will the terminal just work, with no issues, like Warp?"

**After Phase 4 (architectural core lands), these specifically work:**
- ✅ `claude --version` → no smart-punctuation mutation, runs as a one-shot.
- ✅ Launch `claude` interactively → block shows Claude's live UI; type messages in the active block's input field; Claude responds; type again; Ctrl-C exits. Same loop as Warp/cmux.
- ✅ `codex` and any other Ink/non-alt-screen TUI agent — same path as Claude, no code changes per-agent.
- ✅ `htop`, `top`, `vim`, `tmux` (alt-screen TUIs) — render inside the active block via SwiftTerm overlay; exit returns to block view with their scrollback intact.
- ✅ `git status`, `ls`, `npm run dev` (linear commands) — render as discrete blocks with copy/star/explain/rerun actions.
- ✅ Pipes, quotes, backslashes, `$VAR`, `&&`, `|`, multi-line paste — preserved verbatim through `TerminalSafeTextField`.
- ✅ Ctrl-C / Ctrl-D / Ctrl-Z / Tab / Esc / arrow keys — routed to PTY via `LivePromptInputView` (no composer middleware swallowing them).
- ✅ Network drop → tmux session keeps running → reconnect re-attaches → Claude's live UI re-renders on the phone.

**After Phase 7 (polish + fallbacks land), additionally:**
- ✅ Shells without OSC 133 (broken/legacy `.bashrc`s, exotic prompts) degrade cleanly to a blockless live PTY rather than freezing.
- ✅ Visual polish: live-block caret animation, transition smoothness, glass chrome consistency across all surfaces.
- ✅ Plug-and-play: pick a host, hit attach, tmux session auto-detected, Claude Code's screen appears.

**What I cannot promise (and you shouldn't expect):**
- ⚠️ **Zero bugs.** Real-world testing always surfaces new edge cases. What the plan eliminates is the *architectural class* of bug ("can't type into a running TUI"). It does not eliminate the possibility that a specific user's `.zshrc` or a specific TUI program will misbehave on first contact.
- ⚠️ **Every exotic TUI works on day one.** lazygit, ipython, mosh-server, replit-cli, neovim with 50 plugins — these will *probably* work because the byte-pattern detection is binary-name-agnostic, but some may need specific fixes after testing.
- ⚠️ **macOS-grade background behaviour.** iOS will still kill backgrounded apps. tmux + auto-reconnect makes this invisible for the common case, but the experience won't match a desktop terminal that stays running while you switch windows.
- ⚠️ **Performance under extreme output.** `find / -type f` or `cat /var/log/large.log` may cause UI hitches if the per-block SwiftTerm gets overwhelmed. Caps are tuned for typical use; pathological cases need testing.
- ⚠️ **All Bluetooth keyboards.** Some BT keyboards on iOS drop modifier-release events. We patch around what we can; chord reliability depends on the hardware.

**The honest bottom line:**

The bugs you described (Claude Code unresponsive, em-dash mutation, can't interact with a running program) are an *architectural class* of bug. The plan removes that class entirely. The terminal will work for the cases you listed (Claude, htop, top) and for the broad set of "interactive programs run inside a real shell over SSH". Whether the resulting app is "100% polished, no issues" is a question only real-device testing can answer — and that testing is what Phase 6's plug-and-play UX and Phase 7's polish work are designed to surface and fix. Software ships in increments, not in one perfect release.

### 6.7 Ghostty as an additional reference (license-aware)

Ghostty (`/Users/roshansilva/Downloads/ghostty-main`, cloned 2026-05-28) is the macOS-native terminal emulator that cmux uses for rendering. It's overall MIT-licensed, but **its bash and zsh shell-integration scripts are GPLv3** (derived from Kitty). This creates a license constraint:

| File | License | Action |
|---|---|---|
| `src/shell-integration/bash/ghostty.bash` (269 lines) | **GPLv3** | ❌ **Cannot bundle** in Conduit's proprietary target. Use as **architectural reference only** — see what hooks they install, mirror the *structure* in our own MIT-clean rewrite. |
| `src/shell-integration/bash/bash-preexec.sh` (vendored) | GPLv3 (via Kitty) | Same — reference only. |
| `src/shell-integration/zsh/ghostty-integration` (395 lines) | **GPLv3** | Same — reference only. |
| `src/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish` (178 lines) | MIT (no Kitty derivation) | ✅ **Can bundle with attribution.** Copy with `// Adapted from Ghostty (MIT)` comment. |
| `src/shell-integration/nushell/`, `elvish/` | MIT | Available if we ever support those shells. |

**Practical implication for Phase 0.3:**

We write our own bash/zsh integration scripts from scratch, based on:
1. The OSC 133 spec (public, no license issue)
2. The OSC 7 spec (public)
3. Warp's `BlockContext` field set as inspiration for what to emit
4. Ghostty's bash/zsh as **architectural reference** — what hooks to install, how to handle re-entrancy, how to play nicely with oh-my-zsh / starship / powerlevel10k

We can copy Ghostty's fish script with MIT attribution.

**Other Ghostty assets worth referencing (not copying):**
- `src/terminal/` — Zig terminal emulator. Useful for cross-checking our SGR/OSC parsing against a high-quality implementation, but architectural-reference only (different language, different scope).
- `src/config/` — config schema. Useful for thinking about how Conduit settings should be structured for power users.
- `src/font/` — font subsystem. Out of scope.

**Bottom line on Ghostty:** confirms the OSC 133 + cursor-positioning architecture is the right answer (Ghostty's shell integration emits the same markers Warp does). Our own scripts will be smaller (we don't need Ghostty's full feature set — just block boundaries and CWD), MIT-clean, and architecturally aligned with both Warp and Ghostty.

---

## 7. Implementation plan

**Seven phases. Each is shippable on its own. Each gets a test.**

**Phase 0 ships independently of the rest** — the smart-punctuation and paywall fixes are bug-fix commits with no architectural dependency. They can land in a single PR and unblock real-device testing immediately.

### Phase 0 — Real-device quick wins, no architecture (1 session)

Bugs surfaced by the parallel real-device pass. Ship in one PR before any of Phase 1+ starts.

- **0.1 Terminal-safe input field.** New `TerminalSafeTextField` (`UIViewRepresentable` wrapping `UITextField` with `smartDashesType=.no`, `smartQuotesType=.no`, `smartInsertDeleteType=.no`, `autocorrectionType=.no`, `autocapitalizationType=.none`, `spellCheckingType=.no`). Replace the composer's `TextField` and any other text input that takes shell syntax (host editor command fields, snippet body, port-forward host).
- **0.2 Tests for shell-syntax preservation.** Round-trip tests asserting that typing `--`, `'`, `"`, `\`, `$VAR`, `cmd | grep foo`, and multi-line paste does *not* mutate. These tests live in `SessionViewModelTests` (new file) and `TerminalSafeTextFieldTests` and protect the fix from regression.
- **0.3 Bundled shell-integration scripts.** Move the inline script in `SessionViewModel.swift:231–246` into `Packages/ConduitKit/Sources/TerminalEngine/Resources/conduit-init.{bash,zsh,fish}`. Load via `Bundle.module`. License posture: write bash/zsh from scratch against the OSC 133 + OSC 7 specs (no Ghostty/Kitty derivation, since those are GPLv3); use Ghostty's bash/zsh as **architectural reference only**. The fish script can be adapted from Ghostty's MIT-licensed `vendor_conf.d/ghostty-shell-integration.fish` with attribution. All scripts emit the same markers we already parse: 133;A/B/C/D and 7;file://host/path. Test fixtures load these files via `Bundle.module`. See §6.7 for the full license analysis.
- **0.4 Debug paywall bypass.** `PurchaseManager.debugProBypass` flag honoured only in `#if DEBUG` builds; a Settings toggle "Unlock all features (debug)" controls it. Production builds ignore the flag entirely. Unblocks simulator testing of Preview/Files/Diff/Inbox.
- **0.5 Duplicate keyboard rail audit.** Verify only one accessory bar is visible at a time. Kill the dup. (Likely candidate: `SwiftTerm`'s built-in `inputAccessoryView` colliding with our `KeyboardAccessoryRail` in `safeAreaInset`.)
- **0.6 Toolbar/status-bar overlap audit.** Snapshot tests for `SessionView` at iPhone 17 Pro and iPad Air dimensions; fix any safe-area or zIndex issues.

User-visible after Phase 0: `claude --version` works. `git commit -m "fix: --foo"` works. Quotes round-trip. Preview/Files/Diff/Inbox open in simulator. **Block-mode interactivity is still broken — that's Phase 1+.**

### Phase 1 — Tests-first for the architectural redesign (1 session)
- Write failing tests:
  - `PTYBridgeTests`: 133;A fires `onPromptStart`; 133;B fires `onPromptEnd`
  - `SessionViewModelTests`: full A→B→C→D state machine
  - `SessionViewModelTests`: Claude Code byte stream (no alt-screen, cursor pos, follow-up keystrokes) — input must reach PTY directly without creating a new block
- Tests fail. That's the gate for Phase 2+.

### Phase 2 — OSC 133 A/B wiring (1 session)
- Extend `PTYBridge.configure(...)` and `dispatchOSC133` to fire on A and B
- Phase 1 bridge tests go green
- No user-visible change yet

### Phase 3 — Block state machine in the VM (2 sessions)
- Add `BlockState` enum to `ConduitCore/Block.swift`
- Move block lifecycle from `run(command:)` to the OSC 133 A/B/C/D callbacks in `openUnifiedShell()`
- `submit()` becomes: send `promptDraft + "\n"`; do not call `blocks.begin`
- Phase 1 VM tests go green
- User-visible: blocks now appear when the *shell* says they do, not when the user submits. Output framing is correct for the first time.

### Phase 4 — Direct keystroke flow (2 sessions)
- Add `sendKeystrokes(_:)` to `SessionViewModel`
- New `LivePromptInputView` (UIKit `UIView` + `UIKeyInput` conformance) — captures every key and forwards to PTY
- In `SessionView`, when the active block is `.executing`, render `LivePromptInputView` instead of the composer
- Keyboard accessory rail is now always visible when connected, wired to `sendKeystrokes`
- User-visible: **Claude Code is now interactive on the phone.** Type a message, watch Claude respond live, type again. Tab/Esc/Ctrl-C work.

### Phase 5 — Kill the mode toggle (1 session)
- Remove the Terminal/Blocks toolbar button (`SessionView.swift:43–58`)
- Alt-screen entry no longer flips a `isRaw` flag — instead, the active block expands to host a `SwiftTerm` overlay
- `rawTerminalContent` is folded into the active block's rendering
- `RawTerminalView` is reused but lives as a child of `BlockRow` when `block.altScreenActive` is true
- User-visible: vim/htop/tmux work *inside* the block stream. Exiting them returns to the block list with the alt-screen scrollback visible.

### Phase 6 — Plug-and-play UX (2 sessions)
- On connect, run `tmux ls 2>/dev/null` via `SSHSession.executeCollected`
- If sessions exist, show a small sheet: "Attach to <session>?" with options
- Optional: run `pgrep -f 'claude|codex'` and label the session "Claude Code running here"
- Wire the existing `enableTmux(sessionName:)` to the chosen session
- Persist the last-attached session per host so the next connect goes straight there (absorbs Codex's "durable workspace/session records" point — no new schema, just a `tmuxLastSession` field on `Host`)
- User-visible: open the app, pick a host, hit attach — Claude Code's live UI appears. From laptop or from phone, same screen.

### Phase 7 — Polish + telemetry + fallbacks (1 session)
- Block state transitions log to `os.signpost` so we can spot bugs in TestFlight
- Visual polish on the active block (subtle "live" indicator, animated caret)
- Migrate the 7 secondary-chrome `.background(.bar)` sites to `conduitGlassChrome` (the work paused from earlier)
- **OSC 133 missing-marker fallback** (per Q2 in §7): if no OSC 133 marker is received within ~5s of connect, degrade to a blockless live PTY view. Re-engage block segmentation if a marker arrives later.
- **Belt-and-suspenders interactive-CLI hint** (NOT primary mechanism): if cursor-positioning sequences arrive while we're still in `.promptEditing` (i.e. before any 133;C), assume an interactive program slipped through and flip to executing state on the active block. This catches edge cases where shell integration is broken AND the user runs `claude` directly. The hint uses *byte patterns* (`\e[H`, `\e[2J`, `\e[?25l`) not binary names — works for any TUI.
- Doc updates: `ARCHITECTURE.md`, `docs/_archive/current-state-audit.md`, README milestone row

**Estimated total**: ~10 working sessions. Phase 0 is independent and ships first. Phases 2–5 are the core architectural fix. Phases 6–7 close out the user's plug-and-play wedge.

### Why not hardcoded CLI detection as the primary mechanism

A separate review proposed detecting `claude`, `codex`, and other known agent CLIs by name *before* execution and flipping to raw mode preemptively. We're *not* doing that as the primary mechanism, for three reasons:

1. **Denylists rot.** New agents ship every quarter (Grok, OpenCode, Cursor CLI, Aider, …). Anything based on `pgrep` patterns or command-string sniffing needs updates with each new entrant.
2. **Misses non-agent TUIs.** `top`, `htop` without alt-screen, `node`, `ipython`, `lazygit`, custom Python REPLs, `mosh`, interactive `npm init` — none of these are agents but all need the same input flow.
3. **Wrong abstraction.** The signal we actually want is "the foreground process is interactive". OSC 133 + cursor-positioning byte patterns *are* that signal. Binary names are a proxy that's strictly less reliable.

The byte-pattern hint in Phase 7 is the belt-and-suspenders version: it catches programs that don't honour shell integration but still emit cursor sequences. No binary-name list anywhere in the code.

---

## 8. Open decisions — please review before I start coding

I have an opinionated answer for each but want to confirm.

### Q1. The "prompt edit field" — fully replaces the composer, or sits alongside it?

**My recommendation: fully replaces.** The composer-at-bottom is a phone idiom but it's the root of the bug. The active block carries the input field at its bottom edge. The current bottom-of-screen text field disappears.

Alternative: keep the bottom composer as a quick-draft buffer for users who don't want to scroll to the active block. This is what Termius does. It's an option, but it brings the asymmetry back.

### Q2. When OSC 133 markers are absent (some shells don't honour the integration script), what happens?

**My recommendation: graceful degradation + a byte-pattern hint.** Two-layer fallback (implemented in Phase 7):

1. If we go more than ~5 s without ever seeing an OSC 133 marker after connect, fall back to a "blockless live PTY" mode — everything's in one giant scrollback (cmux's model). Re-engage block mode automatically when a marker appears.
2. If cursor-positioning sequences (`\e[H`, `\e[2J`, `\e[?25l`) arrive while the active block is still in `.promptEditing` state — i.e. no 133;C ever fired — flip that block to `.executing` so direct-keystroke input activates anyway. This catches `claude` launched in a shell with broken integration.

This protects fish (we now ship a fish integration script), edge-case shells, and any TUI that bypasses the shell hooks entirely. Critically, this is **byte-pattern driven**, not binary-name driven, so it works for any new TUI without code updates.

### Q3. Block actions (copy, rerun, explain, star) on the active block — allowed?

**My recommendation: copy + star yes; rerun + explain no until `.done`.** A running block's command isn't finished, so rerun is meaningless and explain has no exit code to interpret. Greying these out in the context menu is enough.

### Q4. Hardware keyboard chord — should Ctrl-C / Ctrl-D in `LivePromptInputView` send SIGINT/EOF to the active block's foreground process?

**My recommendation: yes, always.** That's what every terminal does. The byte path is already correct (Ctrl-C = 0x03 to PTY); we just need the `LivePromptInputView` to call `sendKeystrokes` instead of swallowing the chord.

### Q5. The current per-block SwiftTerm in `BlockRenderer` — keep it, replace it, or merge with the unified PTY's terminal?

**My recommendation: keep per-block, but only for cursor-positioning programs that don't take alt-screen (Claude Code, Codex, Ink-based apps).** The unified PTY's terminal stays the source of truth for raw bytes; the per-block terminal exists to render an OSC-stripped, cursor-positioned view of just that block's slice. This is exactly what Warp does (per-block output grid).

### Q6. Should the redesign land in M11 (Temporal Wall) or as its own milestone M12?

**My recommendation: its own milestone.** Temporal wall is about *navigating* history; this is about *fixing the live model*. Conflating them muddles both. Call it **M12 — Live Block I/O**.

### Q7. Anything in cmux's macOS native chrome (Bonsplit-style splits, multi-pane workspaces) worth porting to iPad?

**My recommendation: not now.** iPhone is the primary target and the bug is universal. iPad split-pane is a stretch goal for a later milestone.

---

## 9. Appendix — code citations

**Conduit (this repo):**
- `SessionViewModel.swift:440–447` — the broken `run(command:)`
- `SessionViewModel.swift:250–375` — `openUnifiedShell` with OSC 133/7 callbacks
- `SessionViewModel.swift:314–326` — alt-screen entry flips `isRaw`
- `SessionViewModel.swift:391–403` — `escalateToRaw` / `deescalate`
- `PTYBridge.swift:310–322` — `dispatchOSC133` (A and B are no-ops)
- `BlockRenderer.swift:54–75` — `append` with cursor-movement detection
- `BlockRenderer.swift:155–232` — per-block SwiftTerm rendering
- `SessionView.swift:108–154` — raw terminal content (the mode-toggle UI)
- `SessionView.swift:242–274` — block scroll
- `SessionView.swift:278–329` — composer

**Warp** (`/Users/roshansilva/Downloads/warp-master`):
- `app/src/terminal/view.rs:8298–8320` — `should_write_typed_chars_to_pty`
- `app/src/terminal/view.rs:8324–8354` — `typed_characters_on_terminal`
- `app/src/terminal/view.rs:8390–8395` — `write_to_pty`
- `app/src/terminal/model/block.rs:610–634` — `BlockState`
- `app/src/terminal/model/block.rs:1719–1753` — `is_active_and_long_running`
- `app/src/terminal/model/blocks.rs:840–849` — `active_block_index`
- `app/src/terminal/model/blocks.rs:2614–2740` — `create_new_block`
- `crates/warp_terminal/src/model/ansi/control_sequence_parameters.rs:620–681` — `PromptMarker` parsing
- `app/src/terminal/alt_screen/alt_screen_element.rs:55–195` — alt-screen overlay
- `app/src/terminal/writeable_pty/pty_controller.rs:39–262` — `PtyWrite` variants

**cmux** (`/Users/roshansilva/Downloads/cmux-main`):
- `Sources/Workspace.swift:142` — Workspace
- `Sources/Panels/TerminalPanel.swift:34` — TerminalPanel
- `Sources/GhosttyTerminalView.swift:5093` — TerminalSurface
- `Sources/GhosttyTerminalView.swift:9280` — `sendGhosttyKey` direct PTY call
- `Sources/GhosttyTerminalView.swift:5233` — socket-input queue (the only queue)
- `Sources/Panels/Panel.swift:285` — notification flash ring
- `Sources/RestorableAgentSession.swift` — agent resume hook
- `daemon/remote/cmd/cmuxd-remote/ws_pty.go:29–195` — remote PTY hub
- `daemon/remote/cmd/cmuxd-remote/ws_pty.go:1306` — `writeInputLoop`
- `Sources/SessionPersistence.swift` — layout-only persistence
- `CLAUDE.md:227–231` — typing-latency pitfalls
