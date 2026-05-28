# Current State Audit

Updated: 2026-05-28

## Executive Summary

Conduit is an iOS 26 / Swift 6.2 app with a working SSH shell pipeline,
session survival via tmux, and automatic reconnection on network changes.
M1 through M10 are complete on `master`. M11 (temporal-wall redesign) is
still partial. M12 (Live Block I/O, from
`docs/block-model-redesign-research.md`) is now in progress: the main
block-lifecycle/input architecture has landed, but final real-host
interactive validation is not complete yet.

**What works now:**
- SSH connection with 15s timeout, password and Ed25519 auth
- Host-key TOFU confirmation with UI sheet
- Block mode (command + output as discrete units) with error indicators
- Raw PTY mode via SwiftTerm (vim, htop, tmux)
- Unified PTY: one long-lived shell channel feeds both block and raw views;
  alt-screen and OSC 133/7 markers drive escalation and CWD/exit tracking
- Manual Terminal/Blocks toggle in toolbar
- tmux auto-attach when configured on host
- Auto-reconnect on scene resume using cached credentials
- Reconnection banner UI with cancel
- "Session suspended" local notification on background expiry
- tmux session name field in host editor
- Keyboard accessory rail with momentary Ctrl, arrows, tmux prefix
- Block-mode TUI emulation (per-block SwiftTerm) for cursor-positioning
  programs that don't take alt-screen
- Terminal-safe UIKit input for shell syntax (`--`, quotes, pipes,
  backslashes, `$VAR`) in the session composer, host/session fields,
  port-forward host field, and snippet body
- Bundled OSC 133 / OSC 7 shell-integration scripts for bash, zsh, and fish
- Active-block prompt/live input: prompt entry is rendered with the active
  block; executing blocks use a live keystroke receiver and Ctrl-C stop
  affordance
- Debug Pro bypass in Debug builds for simulator coverage of gated surfaces
- Watch app, conduitd JSON-RPC, push backend, billing scaffolding (see
  `docs/remaining-work.md` for the full list)

**What's pending:**
- Validation against a real SSH host across all auth methods
- Clean validation of Claude/Codex-style inline interactive TUIs against a
  real shell, including repeated prompt/response cycles and Ctrl-C exit
- Alt-screen rendering still uses the raw SwiftTerm branch rather than a
  fully embedded active-block overlay
- Plug-and-play agent resume/detection is limited to tmux session discovery;
  per-agent process/session labeling is not complete
- M11 Phase 2: full temporal-wall UX (saved-frame thumbnails, pan/zoom
  semantics) — design exists, implementation partial
- BGContinuedProcessingTask adoption for improved background keepalive
  (currently uses the scene-phase observer pattern; iOS 26 API not wired)
- Complete Liquid Glass adoption across non-chrome surfaces (see §
  "Liquid Glass adoption status" below)

## Verified In This Pass (2026-05-28)

- `swift test` on `Packages/ConduitKit`: **106 tests across 24 suites pass**
  in ~3.1s.
- XcodeBuildMCP `build_sim`, scheme `Conduit`, iPhone 17 Pro simulator:
  **BUILD SUCCEEDED**, no warnings.
- XcodeBuildMCP `test_sim`, scheme `ConduitKitTests`, iPhone 17 Pro
  simulator: **116 passed, 0 failed, 0 skipped**.
- XcodeBuildMCP `build_run_sim`, scheme `Conduit`, iPhone 17 Pro simulator:
  app built, installed, and launched successfully.
- Simulator smoke:
  - Workspaces seeded list renders without overlap.
  - Password prompt and TOFU host-key sheet are reachable through quick
    connect.
  - Session shell launched after a temporary localhost SSH server accepted
    auth/TOFU.
  - Keyboard rail rendered on-device; a clipping regression after adding
    Ctrl-C/D/Z was found and fixed with stable button minimum widths.
  - Temporary scripted SSH server was sufficient for negotiation/auth/TOFU
    and basic shell rendering, but not a conclusive real-shell TUI test.
- Test suites: AnsiSGRParser, AutoReconnectEngine, Billing eligibility,
  BlockRenderer, ConduitDProtocol, CredentialResolver, DaemonChannel
  framing, HostKeyStore TOFU logic, KeyStore, PairingCrypto,
  Patch persistence, PortDetector parsing, PromptBuilder, PTYBridge,
  Redactor, RiskScorer, SFTPClient, SnippetRepository,
  SSHSession.loginShellWrap, SyncEngine, UnifiedDiffParser, WorkflowEngine,
  KeyCommands.
- Deployment target verified: `project.yml` declares
  `IPHONEOS_DEPLOYMENT_TARGET: "26.0"`; `Package.swift` declares
  `.iOS(.v26)`. Swift tools version 6.2.
- Liquid Glass primitive: `DesignSystem/Atoms.swift` ships
  `conduitGlassChrome(cornerRadius:interactive:)`, gated on iOS 26 with a
  `.ultraThinMaterial` fallback. Four call sites use it today:
  - `AppFeature/SessionShellView.swift:113,125`
  - `SessionFeature/SessionView.swift:141,325`
- `BGContinuedProcessingTask` is **not referenced** anywhere in
  `Packages/ConduitKit/Sources` (verified by repo-wide grep). Background
  keepalive is the `ScenePhaseObserver` + local-notification path only.

## Liquid Glass adoption status

`conduitGlassChrome` is the project's single glass primitive. As of
2026-05-28 it is fully adopted across primary and secondary chrome —
every translucent surface flows through the same primitive. The
SessionView status bar and block-card chrome use a custom dark-translucent
stack (LinearGradient backdrop + per-block translucent fill + hairline
border) tuned to the Warp-style dark theme; the standard primitive is
used everywhere else.

**Using `conduitGlassChrome`:**
- `AppFeature/SessionShellView.swift` — top + bottom ribbons + shell bar
- `SessionFeature/SessionView.swift` — raw-mode keyboard rail + composer +
  accessory dock
- `OnboardingFeature/OnboardingView.swift` — onboarding footer
- `OnboardingFeature/ProvisioningWizard.swift` — wizard step bar
- `PreviewFeature/PreviewSurface.swift` — preview toolbar
- `SettingsFeature/PaywallSheet.swift` — paywall section card
- `InboxFeature/InboxView.swift` — approval command card

**Custom dark-theme chrome (not using the primitive, by design):**
- `SessionFeature/SessionView.swift` — status bar (transparent over the
  shell wallpaper with a hairline divider) and block-row card
  (dark-translucent fill + 0.5px white-at-8% border). These need fine
  control of border + fill independently, which the primitive doesn't
  expose; using it would lose the per-block separation Warp shows.

## Background-keepalive status

iOS 26 introduced `BGContinuedProcessingTask` for tasks that need to keep
running past the standard ~30s background expiration. It would suit
Conduit's "keep the SSH session alive while the user is briefly out of the
app" use case.

Current behaviour:
- `ScenePhaseObserver` calls `SessionViewModel.handleSceneActive()` on
  resume.
- `handleSceneActive()` checks `sshSession.isConnected` and triggers
  reconnect if the session was dropped.
- `Notifications.postSessionSuspended(hostName:)` fires when the OS
  expires the standard background task.

Not implemented:
- No `BGContinuedProcessingTask` registration, no
  `BGContinuedProcessingTaskRequest.submit(...)`.
- Background runtime is therefore capped at whatever
  `UIApplication.beginBackgroundTask` grants (~30s on iOS 26).

This is a deliberate omission for now: the tmux + auto-reconnect path
covers the common case (the remote shell survives client disconnect; the
client reconnects on scene resume). Adopting `BGContinuedProcessingTask`
would tighten the experience for users who don't run tmux. Tracked in
`docs/remaining-work.md`.

## External Reference Check

- Termius remains the baseline iOS SSH client to beat: SSH, Mosh, Telnet,
  port forwarding, SFTP, biometric protection. Its support docs confirm
  the iOS constraint we already plan around: background terminal work is
  sharply limited by iOS/iPadOS, so durable server-side `tmux`/`screen`
  style survival still matters more than client-side BG juggling.
- Warp's agent direction reinforces Conduit's AI-control-plane thesis:
  terminal-native agents, attaching blocks as context, and launching
  cloud agents from app/web/phone surfaces. We copy the control and
  context ideas, not the desktop layout.
- cmux has moved toward a Ghostty-based macOS terminal with vertical
  tabs, notifications, saved Claude Code/Codex sessions, and
  remote-daemon work. Conduit's cmux lesson is still daemon/proxy/session
  resilience.
- Ghostty/libghostty remains research-only — official docs still say
  `libghostty` is not a stable standalone API. We stay on SwiftTerm.

## Remaining Gaps (cross-reference `docs/remaining-work.md`)

- Validate SSH against a real host (password and Ed25519 auth) for the
  M11 unified-PTY path
- Complete Liquid Glass migration to the 7 remaining secondary-chrome
  surfaces
- Implement BGContinuedProcessingTask for non-tmux background keepalive
- Add Mosh support for UDP-based session resilience (stretch goal)
- M11 Phase 2: temporal-wall thumbnails and pan/zoom UX

## Next Implementation Priority

1. Finish M11 Phase 2 temporal-wall UX (thumbnails + pan/zoom).
2. Migrate the 7 secondary-chrome surfaces to `conduitGlassChrome`.
3. Wire `BGContinuedProcessingTask` for non-tmux sessions.
4. Validate the full connect → blocks → raw → reconnect flow against a
   real host with Ed25519 and password auth.
