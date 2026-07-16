# Block Terminal — Implementation & Debugging Notes

> How the Warp-style "block" terminal renders agents (claude/codex) and shell
> commands over SSH, the bugs we hit getting it working end-to-end, what fixed
> them, and what didn't. Read alongside `agent-contract.md` §5 (terminal-engine
> rules) and `block-model-redesign-research.md`.

Last updated: 2026-07-15.

---

## 1. Goal

Render a remote shell as a transcript of **blocks** (Warp-style): each command
becomes a card with a state gutter, a `RUN › COMMAND` header, a `$ command` bar,
and an output panel. Interactive agents (Claude Code, Codex) should render
**inside their own block** via a live grid — not take over the whole screen —
matching how Warp shows them.

## 2. Architecture as-built

One unified PTY is the single source of truth (never spawn a second shell for
"raw mode" — see `agent-contract.md` §5):

```
SSHShell (one PTY)
   │  bytes
   ▼
PTYBridge (TerminalEngine/PTYBridge.swift)
   │  • parses + strips OSC 133 A/B/C/D and OSC 7
   │  • detects alt-screen enter/exit (\e[?1049h / \e[?1049l)
   │  • emits OSC-stripped bytes via onBlockBytes
   ▼
SessionViewModel (SessionFeature/SessionViewModel.swift)
   │  • onPromptStart (133;A) → beginPrompt() → new promptEditing block
   │  • onCommandStart (133;C) → block .executing
   │  • onCommandDone (133;D) → block .done(exitCode)
   │  • onCWDUpdate (OSC 7) → block prompt cwd
   │  • appends output to the active block while isExecutingUnified
   ▼
BlockRenderer (TerminalEngine/BlockRenderer.swift)   — @Observable block store
   │  • per-block SGR/AttributedString rendering for linear output
   │  • per-block SwiftTerm emulator + liveBlockHandles for inline TUIs
   ▼
ChatTranscriptView → ToolCardView (SessionFeature/Chat/)   — the visible cards
```

Two rendering modes off the **same** PTY:
- **Block mode** (default): OSC-133-bounded command/output blocks.
- **Raw escalation**: when an alt-screen app starts (`\e[?1049h`), `isRaw = true`
  and a full-screen `RawTerminalView` overlays; on exit (`\e[?1049l`) it
  de-escalates back to blocks. Driven by the escape sequence, not heuristics.
- **Inline TUI** (the in-between): Ink-based apps (claude/codex) that use cursor
  positioning but NOT alt-screen render inside the block via
  `BlockRenderer.liveBlockHandles` (a `RawTerminalView(feedHandle:)` embedded in
  the card's output panel — Warp's "active block hosts the live grid" model).

Shell integration (the OSC 133 emitters) is injected at runtime as an **embedded
script** (`ShellIntegrationScript.bootstrapForPOSIXShells()` / `.script(for:)`),
sent over the PTY after connect. It is NOT a bundled file dependency, so it works
on any localhost shell. A 6s probe timeout (`integrationProbeTimeout`) falls back
to "blockless live PTY" (raw) if no `133;A` ever arrives (Phase 7).

Agent **approvals** (the `patch`/Approve/Deny tool cards in the design) are a
separate, structured path via `lancerd` (remote daemon) → `ApprovalIngest` /
`DaemonChannel` → Inbox + `RiskScorer`. That is not part of the shell-block
pipeline above; it is the future "Phase 3" layer.

## 3. Symptoms we hit, root causes, and fixes

### 3.1 Claude Code rendered jumbled / wrapped mid-word (raw harness)
- **Symptom:** in the raw `LiveTerminalView` harness, Claude Code's banner wrapped
  mid-word and overflowed the right edge.
- **Wrong first guess:** "phone is too narrow." It is not — Warp renders the same
  TUI fine at small sizes.
- **Root cause:** the PTY opened at a hardcoded **80×24**; SwiftTerm reported the
  real ~48-col size via `sizeChanged` ~50 ms later, but the SSH handshake takes
  ~1.5 s, so at that moment `shell` was still `nil` and `resize()`'s
  `guard let shell` **silently dropped** the real size. PTY stayed 80 wide while
  the view showed ~48 → remote drew 80-wide lines, SwiftTerm wrapped them at 48.
- **Fix (`LiveTerminalView.swift`):** store the latest reported size
  (`lastCols/lastRows`) even when no shell exists, open the PTY at that size, and
  re-apply it the moment the shell connects. Verified with a `tput cols` probe:
  `COLS=48` after the fix (was 80).

### 3.2 `~ %` zsh prompt captured as block output
- **Symptom:** blocks showed stray `~ %` lines (the zsh prompt) as if they were
  command output; the session got stuck showing "Running".
- **Root cause:** the "belt-and-suspenders" TUI escalation in
  `SessionViewModel.onBlockBytes` flipped an **idle `.promptEditing` block** to
  `.executing` because `TUIDetector.shouldEscalate` matches `\e[?1h` (zsh ZLE
  enables application-cursor-key mode at every prompt) and `\e[2J`/`\e[H` (the
  integration's own screen-clear). Once "executing", the bare prompt bytes were
  appended as output.
- **Fix (`SessionViewModel.swift`):** restrict the belt-and-suspenders escalation
  to `.submitted` blocks only — never an idle `.promptEditing` prompt. Idle
  prompt bytes are then dropped by the `guard self.isExecutingUnified` gate, so
  no `~ %` noise and no false "Running" state.

### 3.3 Integration bootstrap pasted into claude's stdin
- **Symptom:** launching `claude` showed `printf '\033]133;Z;%s\007' "$FISH_VERSION"
  [Pasted text +19 lines] printf '\033[2J\033[H'` **inside claude's input box**.
- **Root cause:** the shell-integration injection runs in a detached `Task` with
  sleeps (~1.1 s). `connect()` called `runStartupCommandIfAny()` immediately after
  `openUnifiedShell()` returned, so `claude` launched *before* the integration
  bytes were sent — and the trailing probe/bootstrap/clear landed in the running
  app's stdin.
- **First fix attempt (insufficient):** gate the startup command on the first
  `133;A`. Too early — the integration's `printf '\033[2J\033[H'` clear is sent
  ~300 ms *after* the bootstrap's `133;A`, so it still raced and got pasted in.
- **Fix that worked (`SessionViewModel.swift`):** signal `unifiedIntegrationReady`
  only **after the entire injection completes** (probe → bootstrap → clear →
  500 ms settle). `awaitUnifiedShellReady()` waits on that flag (5 s timeout
  backstop) before any connect-time command runs. After this, claude shows its
  real `Try "..."` placeholder — no leaked bytes.

### 3.4 Auto-run / startup commands rendered with no command label
- **Root cause:** `runStartupCommandIfAny()` sends bytes via `shell.send` directly,
  bypassing `submit()` which sets the block command and `.submitted` state.
- **Fix:** `runStartupCommandIfAny()` now mirrors `submit()` — calls
  `blocks.setCommand(raw, …)` and `blocks.setState(.submitted, …)` on the active
  block before sending, so the block shows e.g. `$ claude` and can escalate to the
  live grid.

### 3.5 Idle composer ballooned into a giant pill, hiding the transcript
- **Symptom:** on a connected idle session, the input composer expanded to fill
  ~70% of the screen, squeezing the block transcript to zero height.
- **Root cause:** `TerminalSafeTextField` (a `UIViewRepresentable` over
  `UITextField`) had no vertical content-hugging, so SwiftUI let it stretch to
  fill slack vertical space when the transcript was empty.
- **Fix (`DesignSystem/TerminalSafeTextField.swift`):**
  `setContentHuggingPriority(.required, for: .vertical)` +
  `setContentCompressionResistancePriority(.required, for: .vertical)`. Composer
  is now single-line; the transcript renders normally.

### 3.6 ToolCardView visual inconsistency with the design system
- The session's `ToolCardView` was a light-surface, hand-rolled card that diverged
  from the canonical `DSBlockCard` (dark terminal surface, left gutter, etc.).
- **Fix (`SessionFeature/Chat/ToolCardView.swift`):** rebuilt on the `DSBlockCard`
  language — dark `termSurface`, left state gutter, reuses `DSPromptLine` +
  `DSExitChip`, three tiers: `RUN › COMMAND` header + meta / `$ command` bar
  (`termSurface2`) / output panel (`termBg`). No new components — pure reuse.

## 4. What did NOT work / dead ends (so we don't retry them)

- **Swapping the POSIX bootstrap for the zsh-specific `lancer-init.zsh`.** They
  are functionally identical (both use `add-zsh-hook precmd/preexec`, emit A/C/D,
  no B). The `~ %` noise was the escalation bug (§3.2), not the script. No swap
  needed; `bootstrapForPOSIXShells()`'s `ZSH_VERSION` branch is correct.
- **Adding OSC 133 B (prompt-end) delimiting.** Not necessary — the
  `isExecutingUnified` gate already drops prompt bytes once §3.2 is fixed. Adding
  B would require modifying the user's `PROMPT`/`PS1`, which is riskier.
- **Gating the startup command on the first `133;A`** (see §3.3) — too early.

## 5. How to test (manual, in the simulator)

There is no web renderer; the only way to see the UI is the iOS Simulator.

```bash
# prerequisites
xcrun simctl list devices booted                      # need a booted sim
nc -z 127.0.0.1 22 && echo "sshd up"                  # macOS Remote Login on
security find-generic-password -s lancer-localhost-ssh -w   # password present

# build + install
cd /Users/roshansilva/Documents/command-center
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/lancer-dd build
xcrun simctl install booted /tmp/lancer-dd/Build/Products/Debug-iphonesimulator/Lancer.app

# launch the LIVE block session (real SSH) — run as a STANDALONE command
xcrun simctl terminate booted dev.lancer.mobile 2>/dev/null; sleep 2
PW="$(security find-generic-password -s lancer-localhost-ssh -w)"
env SIMCTL_CHILD_LANCER_DAEMON_E2E=1 \
    SIMCTL_CHILD_LANCER_DESTINATION=review \
    SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 \
    SIMCTL_CHILD_LANCER_TEST_USER="$USER" \
    SIMCTL_CHILD_LANCER_TEST_PW="$PW" \
    SIMCTL_CHILD_LANCER_TEST_PORT=22 \
    xcrun simctl launch booted dev.lancer.mobile

sleep 11; xcrun simctl io booted screenshot /tmp/shot.png   # then view it
```

### Debug entry points
- `LANCER_DAEMON_E2E=1` + `LANCER_DESTINATION=review` — Workspaces approval / review surface
  (matches `scripts/relay-regression.sh`). Primary DEBUG path for governed-loop work.
- `LANCER_DESTINATION=inbox` — inbox deep-link (historical SSH harness notes may still mention
  this; sidebar/Command Home shell deleted 2026-07-06).
- `LANCER_TERMINAL_TEST=1` → `DebugTerminalHarness` → raw-only `LiveTerminalView`
  (routed in `Lancer/LancerApp.swift`, not `AppRoot`).
>
> **Historical (pre-2026-07-11):** `LANCER_CURSOR_SHELL_LIVE=1` targeted the removed CursorStyle
> shell — do not use.

### Env vars the harnesses read
- `LANCER_TEST_HOST` (default `127.0.0.1`), `LANCER_TEST_PORT` (`22`),
  `LANCER_TEST_USER` (`roshansilva`), `LANCER_TEST_PW`.
- `LANCER_DESTINATION=review` — Cursor shell approval surface; `inbox` for legacy SSH harness.

### Gotchas
- **Env-var propagation:** launch as a STANDALONE command with `env VAR=… xcrun
  simctl launch`. Chaining the launch after `xcodebuild`/`install` in one shell
  line intermittently drops the `SIMCTL_CHILD_*` vars and you boot into the normal
  Sessions home instead of the harness. If that happens, re-run the launch alone.
- **Host-key TOFU:** harnesses auto-trust the first host key (in-memory store,
  fresh per launch) so the test is plug-and-play. `LiveTerminalView`'s
  `autoTrustHostKey` defaults `false`; `DebugSessionHarness` uses the public
  `SessionViewModel.trustHostKey()`. **Production paths must still prompt** —
  never let auto-trust leak out of the debug harnesses.
- **Screenshots:** wait ~8 s after launch (11–12 s for agents) — connect + shell
  integration + first render take time. A foreground `sleep` may be blocked in
  some harnesses; run the sleep+screenshot as a background command.

## 6. Verified working (2026-05-29)
- `ls`, idle prompts → clean blocks, correct `✓ exit 0` / `✗ exit 1`, no `~ %`
  noise, **no echoed command in output**, ANSI colours intact, "Done"/idle state,
  compact composer.
- `claude` → renders inside its own block (live grid), command labeled `$ claude`,
  no leaked integration bytes.

### Round 2 fixes (post test-report, 2026-05-29)
- **Command echo / `%` leak (Bug #1):** `PTYBridge` now flushes OSC-stripped clean
  bytes to `onBlockBytes` *interleaved* with the 133 callbacks (`emitCleanBytes`),
  so prompt + echo bytes ahead of `133;C` reach the VM in the prompt phase and are
  dropped. (The test report's "move onBlockBytes before await" fix was a no-op —
  the `onCommandStart` task is enqueued during parse, so ordering was unchanged;
  the real fix is interleaved flushing.) Plus `PROMPT_EOL_MARK=''` in the zsh
  integration suppresses the partial-line `%`.
- **tmux CSI `\e[…t` leak (Bug #2):** `emitCleanBytes` now buffers CSI sequences
  and drops only `t`-terminated window-manipulation reports, re-emitting all other
  CSI (SGR `m`, cursor, erase) verbatim so colours/positioning survive. Verified
  colours still render (ANSI-coloured `ls` output).

## 7. Open / not-yet-done
- **Bug #3 — font glyphs (low severity):** vim/tmux status-bar box-drawing /
  powerline glyphs render as `?` in the AttributedString text path (the SwiftUI
  monospaced system font lacks them). Fix = register a glyph-complete mono font or
  route those blocks through the live `RawTerminalView` handle. Not yet done.
- **Codex** not visually verified end-to-end (account near weekly quota); same
  Ink/inline path as claude, expected identical.
- The integration **clear** setup block (empty command, `exit 0`) at the top of a
  fresh session is harmless (Warp shows `clear` blocks too) but could be suppressed.
- **Resize / block interactions** (collapse, star, search, long-press) verified by
  code review only — need manual simulator interaction to confirm visually.
- **Agent approval cards** (lancerd `patch`/Approve/Deny, `RiskScorer`, Inbox) —
  the structured Phase 3 layer — not started.

## 8. Key files
| Concern | File |
|---|---|
| Block lifecycle, OSC 133 wiring, escalation gate | `SessionFeature/SessionViewModel.swift` |
| Block store + per-block live grid | `TerminalEngine/BlockRenderer.swift` |
| OSC 133 / alt-screen parsing | `TerminalEngine/PTYBridge.swift` |
| TUI heuristic | `TerminalEngine/AnsiSGRParser.swift` (`TUIDetector`) |
| Integration scripts | `TerminalEngine/ShellIntegrationScript.swift`, `Resources/lancer-init.*` |
| Block card UI | `SessionFeature/Chat/ToolCardView.swift`, `ChatTranscriptView.swift` |
| Composer | `SessionFeature/Chat/ChatInputBar.swift`, `DesignSystem/TerminalSafeTextField.swift` |
| Canonical block card (design system) | `DesignSystem/Components/Composites.swift` (`DSBlockCard`) |
| Debug harnesses | `DebugTerminalHarness.swift`; live session coverage uses `LANCER_DAEMON_E2E=1` + `LANCER_DESTINATION=review` (Workspaces; retired `LANCER_CURSOR_SHELL_LIVE` removed 2026-07-11) |
| Raw terminal view + model | `SessionFeature/LiveTerminalView.swift`, `TerminalEngine/RawTerminalView.swift` |
