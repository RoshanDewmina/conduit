# CLAUDE.md — Conduit iOS codebase guide

## Build

```bash
cd Packages/ConduitKit && swift build
```

Run after every change. The package builds independently of Xcode; build errors surface immediately with file:line pointers.

## Visual verification process

### What this app is

Conduit is an iOS SSH/agent management app. The UI is in `Packages/ConduitKit/Sources/`. There is no web-based renderer — the only way to see the UI is in the iOS Simulator via Xcode or `xcodebuild`.

### Launching the debug gallery

The gallery harness (`DebugGalleryView`) renders mock UI in the simulator without a real SSH connection. Launch it by setting the environment variable:

```
SIMCTL_CHILD_CONDUIT_GALLERY=<route>
```

Valid routes (see the `switch route` in `DebugGalleryView.swift`): `review` (the default — any unknown value also falls back to it; shows session rows + inbox + before/after strip), `components` (full component catalog), `chat`, `diff`, `filepreview`, `onboarding`, `orb-connecting`, `orb-connected`, `blocks` (static mock block transcript — `ChatTranscriptView`/`ToolCardView` over a fake `BlockRenderer`, no SSH), `session` (the **real** live SSH block pipeline — see "Block terminal" below).

To launch from the CLI:
```bash
# Build and install to a booted simulator
xcodebuild -project Conduit.xcodeproj -scheme Conduit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# The env var must be set in the CALLING shell, NOT passed as a positional arg —
# anything after the bundle id is forwarded to the app as launch arguments, not env.
# simctl strips the SIMCTL_CHILD_ prefix, so the app sees CONDUIT_GALLERY=review
# (read in AppRoot.swift via ProcessInfo.processInfo.environment["CONDUIT_GALLERY"]).
SIMCTL_CHILD_CONDUIT_GALLERY=review xcrun simctl launch booted dev.conduit.mobile
```

### Taking screenshots

```bash
# Wait ~2s after launch before screenshotting to avoid blank/mid-animation frames
xcrun simctl io booted screenshot /tmp/conduit-review.png
open /tmp/conduit-review.png
```

**Common mistakes:**
- Screenshotting immediately after launch → blank frame. Always wait for the first SwiftUI render pass (~1–2 s).
- Screenshotting mid-animation (e.g. PixelBox is animating) → captures an intermediate frame. Wait for animations to settle or test static states first.
- Wrong simulator booted → `xcrun simctl list devices booted` to confirm.

### Verifying component changes

1. Edit the component in `Sources/DesignSystem/Components/`.
2. `cd Packages/ConduitKit && swift build` — confirm zero errors.
3. Re-launch the gallery with `SIMCTL_CHILD_CONDUIT_GALLERY=review xcrun simctl launch booted dev.conduit.mobile`.
4. Screenshot and inspect.
5. Check both light and dark appearances: `xcrun simctl ui booted appearance dark` / `light`.

### Design system reference

- Tokens: `Sources/DesignSystem/Tokens.swift`
- Components: `Sources/DesignSystem/Components/`
  - `DSButton` — primary/accent/secondary/ghost/destructive; use `mono: true` for terminal-context action labels
  - `DSQuoteBlock` — left-bar callout with title, tags, body; tone maps to severity (ok/warn/accent/danger)
  - `DSLink` — underlined accent inline link; requires a real action to be meaningful
  - `DSDiffChips` — "X → Y" status transition chips
  - `PixelBox` — animated grid showing agent state (thinking/streaming/approval/done/error/offline)
  - `PixelAvatar` — deterministic pixel art avatar seeded by a string (host name, etc.)
- Gallery: `Sources/AppFeature/DebugGalleryView.swift` — the canonical visual reference for all components

### Key layout invariant: fixed-geometry right columns

Session rows and similar list rows must allocate a fixed-width slot for the unread badge even when it is empty. Use `ZStack(alignment: .trailing) { ... }.frame(width: 20, alignment: .trailing)` so the animated PixelBox never shifts horizontally between rows. See `ReviewSessionRow` in `DebugGalleryView.swift` for the reference implementation.

## Block terminal (Warp-style blocks + live agents over SSH)

Full design/debugging writeup: **`docs/block-terminal-implementation.md`** (read it before touching the terminal/block code). Architecture rules: `docs/agent-contract.md` §5.

**Pipeline:** one unified PTY → `PTYBridge` (parses/strips OSC 133 A/B/C/D + OSC 7, detects alt-screen) → `SessionViewModel` → `BlockRenderer` (`@Observable` block store + per-block live grid) → `ChatTranscriptView`/`ToolCardView`. Shell commands form Warp-style blocks; alt-screen apps (vim/htop/tmux) auto-escalate to a raw `RawTerminalView` overlay (`\e[?1049h`) and de-escalate on exit; inline Ink TUIs (claude/codex) render **inside their block** via `BlockRenderer.liveBlockHandles`.

**Block card UI** lives in `SessionFeature/Chat/ToolCardView.swift`, built on the design-system `DSBlockCard` language (dark `termSurface`, left state gutter, `DSPromptLine` + `DSExitChip`, three tiers: `RUN › COMMAND` header / `$ command` bar / output panel). The canonical reference card is `DSBlockCard` in `DesignSystem/Components/Composites.swift` — keep `ToolCardView` visually consistent with it.

**Invariants (do not regress):**
- The belt-and-suspenders TUI escalation in `SessionViewModel.onBlockBytes` must only fire for `.submitted` blocks, **never** an idle `.promptEditing` prompt — zsh's ZLE (`\e[?1h`) and the integration's screen-clear (`\e[2J`/`\e[H`) trip `TUIDetector`, and escalating an idle prompt captures the bare `~ %` as output.
- Connect-time commands (`runStartupCommandIfAny`, `attemptAgentResume`) must wait on `unifiedIntegrationReady` (via `awaitUnifiedShellReady()`) so they run at the clean post-injection prompt — otherwise the integration bootstrap/clear gets pasted into a launched app's stdin.
- The unified PTY is the single byte source — never spawn a second `SSHShell` for raw mode (`agent-contract.md` §5).

**Running the live block session in the simulator:**
```bash
xcodebuild -project Conduit.xcodeproj -scheme Conduit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/conduit-dd build
xcrun simctl install booted /tmp/conduit-dd/Build/Products/Debug-iphonesimulator/Conduit.app
xcrun simctl terminate booted dev.conduit.mobile 2>/dev/null; sleep 2
PW="$(security find-generic-password -s conduit-localhost-ssh -w)"
# STANDALONE launch — env prefixed directly; chaining after build/install drops the vars.
env SIMCTL_CHILD_CONDUIT_GALLERY=session \
    SIMCTL_CHILD_CONDUIT_TEST_HOST=127.0.0.1 SIMCTL_CHILD_CONDUIT_TEST_USER="$USER" \
    SIMCTL_CHILD_CONDUIT_TEST_PW="$PW" SIMCTL_CHILD_CONDUIT_TEST_AUTOCMD='claude' \
    xcrun simctl launch booted dev.conduit.mobile
sleep 11; xcrun simctl io booted screenshot /tmp/shot.png
```
Prereqs: macOS Remote Login (sshd) on, and the login password in Keychain (`security add-generic-password -s conduit-localhost-ssh -a "$USER" -w 'PW' -U`). `CONDUIT_TEST_AUTOCMD` auto-runs a command on connect so a block forms without typing. Harnesses auto-trust the first host key (debug only) — **production paths must keep the TOFU prompt**.

**Gotcha:** if a launch lands on the normal "Sessions" home instead of the harness, the `SIMCTL_CHILD_*` env didn't propagate — re-run the launch as a standalone command (not chained after `xcodebuild`/`install`).
