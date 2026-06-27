---
paths:
  - "Packages/LancerKit/Sources/SessionFeature/**"
  - "Packages/LancerKit/Sources/TerminalEngine/**"
---
# Block terminal (Warp-style blocks + live agents over SSH)

Read `docs/block-terminal-implementation.md` before touching this code; architecture rules in
`docs/agent-contract.md` §5.

**Pipeline:** one unified PTY → `PTYBridge` (parses/strips OSC 133 A/B/C/D + OSC 7, detects
alt-screen) → `SessionViewModel` → `BlockRenderer` (`@Observable` block store + per-block live
grid) → `ChatTranscriptView` / `ToolCardView`. Shell commands form Warp-style blocks; alt-screen
apps (vim/htop/tmux) render **inside their block** via a block-embedded SwiftTerm (handles
`\e[?1049h` natively) — there is no full-screen overlay swap. The legacy `isRaw` / `RawTerminalView`
escalation path still exists but is **dormant**. Block card UI lives in
`SessionFeature/Chat/ToolCardView.swift`, built on `DSBlockCard`
(`DesignSystem/Components/Composites.swift`) — keep them visually consistent.

**Invariants (do not regress):**

- The TUI escalation in `SessionViewModel.onBlockBytes` fires **only** for `.submitted` blocks,
  never an idle `.promptEditing` prompt — zsh's ZLE (`\e[?1h`) and the integration's screen-clear
  (`\e[2J`/`\e[H`) trip `TUIDetector`, and escalating an idle prompt captures the bare `~ %`.
- Connect-time commands (`runStartupCommandIfAny`, `attemptAgentResume`) must await
  `unifiedIntegrationReady` (via `awaitUnifiedShellReady()`) so they run at the clean
  post-injection prompt — otherwise bootstrap/clear gets pasted into a launched app's stdin.
- The unified PTY is the single byte source — **never spawn a second `SSHShell`** for raw mode
  (`agent-contract.md` §5).

**Run the live SSH session in the simulator** (needs macOS Remote Login on + the login password in
Keychain `lancer-localhost-ssh`). The old `LANCER_GALLERY=session` route is gone; the live session
is now reached by seeding a localhost host (`LANCER_DAEMON_E2E=1`) and driving the real connect flow:

```bash
xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/lancer-dd build
xcrun simctl install booted /tmp/lancer-dd/Build/Products/Debug-iphonesimulator/Lancer.app
xcrun simctl terminate booted dev.lancer.mobile 2>/dev/null; sleep 2
PW="$(security find-generic-password -s lancer-localhost-ssh -w)"
# STANDALONE launch — env prefixed directly; chaining after build/install drops the vars.
env SIMCTL_CHILD_LANCER_DAEMON_E2E=1 SIMCTL_CHILD_LANCER_DESTINATION=sessions \
    SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 SIMCTL_CHILD_LANCER_TEST_USER="$USER" \
    SIMCTL_CHILD_LANCER_TEST_PW="$PW" SIMCTL_CHILD_LANCER_TEST_PORT=22 \
    xcrun simctl launch booted dev.lancer.mobile
sleep 11; xcrun simctl io booted screenshot /tmp/shot.png
```

`LANCER_DAEMON_E2E=1` seeds a "This Mac (e2e)" localhost host (`DebugSeeder.seedDaemonE2EHostIfRequested`)
and prefills the SSH password from `LANCER_TEST_PW`; tap it to connect over SSH to 127.0.0.1:22.
If a launch lands on the normal home with no seeded host, the `SIMCTL_CHILD_*` env didn't propagate —
re-run as a standalone command. The harness auto-trusts the first host key (debug only) —
**production paths must keep the TOFU prompt**. Powerline glyphs rendering as `[?]` tofu in some
TUI status bars is a known cosmetic limitation (bundled mono font lacks the glyphs).
