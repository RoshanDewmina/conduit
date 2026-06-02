# CLAUDE.md — Conduit iOS codebase guide

## MCP tooling — prefer these over raw shell for Apple-platform work

Five MCP servers are configured for this project in the checked-in [`.mcp.json`](.mcp.json) (project scope — it overrides any same-named user/global server, and teammates inherit it; approve the servers when Claude Code prompts on first launch). **Reach for them before raw `xcodebuild` / `xcrun` / shell** when one fits: they return structured JSON (precise error `file:line`, per-test results, view hierarchies) instead of logs you have to grep, and they don't depend on shell env-var propagation quirks. They also cover Swift/iOS/Xcode work generally — not just this app.

| Server | Tool prefix | Reach for it when |
|---|---|---|
| **XcodeBuildMCP** (headless — no Xcode running) | `mcp__XcodeBuildMCP__*` | Build / run / test the **Xcode app** target; simulator lifecycle (`boot_sim`, `list_sims`, `open_sim`); `install_app_sim` / `launch_app_sim`; `screenshot`; UI automation (`snapshot_ui`); code coverage (`get_coverage_report`). **Physical-device** build/test/install/launch and **LLDB debugging** (attach, breakpoints, stack/variable inspection) are enabled too — see workflows below. |
| **xcode** (mcpbridge — needs Xcode.app open) | `mcp__xcode__*` | Live diagnostics (`XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`); SwiftUI `RenderPreview`; `ExecuteSnippet` (Swift REPL); `DocumentationSearch`; `GetTestList` / `RunSomeTests`. |
| **apple-docs** | `mcp__apple-docs__*` | Apple framework/API questions — `search_apple_docs`, `search_framework_symbols`, `get_apple_doc_content`, WWDC sessions & `get_sample_code`. Use **before guessing** any SwiftUI/UIKit/Foundation/Swift-concurrency API. |
| **context7** | `mcp__context7__*` | Docs for **third-party** libraries/SDKs (SwiftNIO, swift-crypto, Citadel/SSH, etc.). `resolve-library-id` → `query-docs`. Don't guess third-party APIs from memory. |
| **ios-simulator** | `mcp__ios-simulator__*` | Simulator UI automation by accessibility tree: `ui_describe_all`, `ui_find_element`, `ui_tap` / `ui_type` / `ui_swipe`, `ui_view`, `screenshot`. Better than eyeballing a PNG when you need tap coordinates or to assert on-screen state. |

### Rules
- **Build & test the app target** via `mcp__XcodeBuildMCP__build_sim` / `test_sim` (or `mcp__xcode__BuildProject` / `RunSomeTests` when Xcode is open) rather than parsing `xcodebuild` output. The SPM inner loop `cd Packages/ConduitKit && swift build` (see [Build](#build)) **stays** — it's fastest for ConduitKit-only changes. Switch to the MCP **app** build when you need the full Xcode target, which catches the strict-concurrency breaks SPM tests miss (a known footgun — see memory `project_ws10_qa`).
- **First build/run/test of a session:** call `mcp__XcodeBuildMCP__session_show_defaults` **once** to confirm project + scheme + simulator; set them with `session_set_defaults` if missing. Then `build_run_sim` can be called with empty args.
- **Don't guess APIs.** Apple symbols → `apple-docs`. Third-party libraries → `context7`. These reflect current docs; training data may be stale.
- **UI inspection** (what's on screen, tap targets, hierarchy) → `ios-simulator` `ui_describe_all` / `ui_find_element`, not a bare screenshot.
- **Enabled XcodeBuildMCP workflows** (set in [`.mcp.json`](.mcp.json) via `XCODEBUILDMCP_ENABLED_WORKFLOWS`, a full-replacement comma list): `simulator`, `simulator-management`, `session-management`, `project-discovery`, `device`, `debugging`, `ui-automation`, `coverage`, `swift-package`, `macos`, `utilities`, `doctor`. The Xcode IDE bridge is intentionally **not** enabled here — use the dedicated `xcode` server for that. To add/remove a workflow, edit that list and restart Claude Code. Tools for newly-enabled workflows surface on demand via ToolSearch (`mcp__XcodeBuildMCP__*`), so they cost no context until used.
- **Physical-device builds:** with the `device` + `debugging` workflows enabled, prefer the XcodeBuildMCP device tools (list/build/test/install/launch + LLDB) over the bash `xcodebuild` device flow in memory `project_device_build`. Code signing / DeviceTesting entitlements still apply (that memory's caveats hold — sim-only bugs hide on device, iCloud gated by `CONDUIT_ICLOUD_ENABLED`); the MCP just replaces the build/run plumbing.

### Driving the gallery / live-SSH harness with these tools
The harness launches in [Visual verification](#visual-verification-process) and [Block terminal](#block-terminal-warp-style-blocks--live-agents-over-ssh) rely on `SIMCTL_CHILD_*` env vars. `mcp__XcodeBuildMCP__launch_app_sim` takes an `env` map and **adds the `SIMCTL_CHILD_` prefix itself**, so it sidesteps the documented "env didn't propagate → re-run standalone" gotcha. Flow: `build_sim` → `install_app_sim` → `launch_app_sim` with e.g. `env: { CONDUIT_GALLERY: "review" }` (for the live session, add the `CONDUIT_TEST_*` vars + the password fetched via Bash `security find-generic-password`), then `mcp__XcodeBuildMCP__screenshot`. The `xcrun simctl` bash blocks documented below remain a valid, already-verified fallback — use them if a launch lands on the wrong screen.

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

**Pipeline:** one unified PTY → `PTYBridge` (parses/strips OSC 133 A/B/C/D + OSC 7, detects alt-screen) → `SessionViewModel` → `BlockRenderer` (`@Observable` block store + per-block live grid) → `ChatTranscriptView`/`ToolCardView`. Shell commands form Warp-style blocks; alt-screen apps (vim/htop/tmux) render **inside their block** via a block-embedded SwiftTerm that handles `\e[?1049h` natively — there is **no** full-screen overlay swap (Phase 5: "no user-facing escalation"). On alt-screen enter, `SessionViewModel.onAltScreenEnter` just clears the block's text-snapshot chunks so the TUI starts on a clean canvas; on exit the block finalizes (e.g. `✓ exit 0`) and a fresh prompt appears. The legacy `isRaw`/`activeShell`/`RawTerminalView` full-screen escalation path still exists in code but is **dormant** — nothing drives a user-facing escalation. Inline Ink TUIs (claude/codex) likewise render **inside their block** via `BlockRenderer.liveBlockHandles`.

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

**Known limitations:**
- Powerline separator glyphs in some TUI status lines (e.g. vim's airline/lightline bar) render as `[?]` tofu because the bundled terminal mono font lacks those glyphs. Cosmetic only, low priority.
