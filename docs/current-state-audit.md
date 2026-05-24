# Current State Audit

Updated: 2026-05-23T17:05:35Z

## Executive Summary

Conduit is now a credible M0/M1 foundation, not yet a finished mobile developer environment. The scaffold builds, tests pass, and the iOS app launches on simulator. The immediate direction is correct: keep the first production slice SSH-first, secure, and small before adding cmux-style daemon features, previews, files, approvals, or richer AI workflows.

The previous output overstated the target platform and completion level. The code deploys to iOS 17.0+ and was verified locally with Xcode 26.4.1 against the iOS 26.4 simulator runtime. It should not claim iOS 26.5+ as a hard requirement unless the app intentionally adopts APIs that require it.

## Verified In This Pass

- `swift build` succeeds for `Packages/ConduitKit`.
- `swift test` passes 20 tests across 6 suites; the Keychain public-key test remains skipped because it needs an entitlement-backed Keychain context.
- `xcodegen` generates `Conduit.xcodeproj` in the repo root.
- XcodeBuildMCP simulator build succeeds for scheme `Conduit`, simulator `iPhone 17 Pro`, with zero warnings.
- XcodeBuildMCP build-run succeeds and launches `dev.conduit.mobile`.
- Runtime smoke reached the onboarding screen. The simulator log only showed a CoreSimulator/WebKit accessibility duplicate-class warning and no app crash.

## Implemented Corrections

- Replaced the placeholder empty-password connection path with a real credential decision path:
  - password hosts show a password prompt at connect time;
  - Ed25519 hosts load the selected private key from `KeyStore`;
  - agent auth now fails clearly because it is not implemented.
- Added host editor authentication selection so a host can be saved as password or Ed25519 key auth.
- Changed generated SSH key tags to UUID strings so they round-trip through `Host.AuthMethod.ed25519(keyID:)` and `HostRepository`.
- Replaced Citadel `.acceptAnything()` with a TOFU host-key validator backed by `HostKeyStore`.
- Fixed block command exit handling so non-zero remote exits use Citadel's `SSHClient.CommandFailed.exitCode` instead of running `echo $?` in a new exec channel.
- Fixed iOS-only compile issues in `RawTerminalView`, WebKit scheme handler signatures, and Swift 6 `any Error` existential syntax.
- Moved root sheets and connection alerts onto the whole ready app state so onboarding and Workspaces share one presentation path.

## Local Source Review

### `~/warp-mobile`

Useful direction retained:

- Block-first terminal model.
- Citadel actor wrapper for SSH sessions.
- AI failure explanation as a terminal-adjacent workflow.
- Modular SwiftPM package layout.

What should not be copied blindly:

- A scaffold that passes macOS SwiftPM tests is not proof the iOS target builds.
- Block mode is useful for ordinary commands, but it cannot replace a raw PTY for `vim`, `tmux`, `htop`, shell prompts, or full-screen TUIs.

### `~/Documents/ios` Helm

Useful direction retained or targeted:

- SwiftTerm bridge for real terminal mode.
- Citadel live session with `withPTY`, byte forwarding, resize propagation, and TOFU host-key validation.
- SFTP manager and URL-scheme preview proxy patterns.
- Pairing/security primitives that are worth reusing conceptually.

Immediate gap vs Helm:

- Conduit still uses exec-style command blocks. It does not yet have Helm's live `withPTY` session as the primary interactive terminal.
- Conduit does not yet expose SFTP-backed file browsing.
- Conduit does not yet confirm first-use host keys in UI; it records automatically, which is safer than accepting anything but weaker than a user-confirmed TOFU flow.

### `~/Documents/mobile-coding` / cmux Research

Useful direction retained for later milestones:

- Remote daemon over stdio as the right long-term answer for resilient mobile workflows.
- Proxy-stream RPC for previews, WebSockets, and port forwarding.
- SHA-256 verified daemon upload/update flow.
- HMAC relay and smallest-screen-wins resize strategy.

What should wait:

- Do not make the daemon a dependency for M1. First prove direct SSH connect, host-key safety, key/password auth, and command execution from the iOS app.
- Do not build preview/WebSocket tunneling before raw terminal and reconnect semantics are stable.

## Product Direction Check

The current direction is mostly right, with one important correction: Conduit should not try to be Warp-on-a-phone. Warp's block model is a strong fit for command review, AI explanation, history, and structured output, but mobile developers still need a real terminal escape hatch immediately. The correct order is:

1. Secure first SSH connect.
2. Live PTY terminal with SwiftTerm.
3. Block capture and command UX layered around the terminal.
4. Reconnect/session survival.
5. Files, diffs, previews, and approvals.
6. cmux-style daemon for resilient previews, stream RPC, and richer remote control.

Termius/Blink-style basics are table stakes: host management, key management, password prompts, known-host safety, terminal keyboard affordances, copy/paste, and reconnect. Warp/cmux-style features become differentiators only after those basics are solid.

## External Reference Check

- Termius remains the baseline iOS SSH client to beat: the current App Store listing advertises SSH, Mosh, Telnet, port forwarding, SFTP, biometric protection, and iOS 17.0+ support. Its own support docs also confirm the core iOS constraint for this product class: background terminal work is sharply limited by iOS/iPadOS, so durable server-side `tmux`/`screen` style survival still matters.
- Warp's current agent direction reinforces Conduit's AI-control-plane thesis: Warp documents terminal-native agents, attaching terminal blocks as context, and launching/tracking cloud agents from app/web/phone surfaces. Conduit should copy the control and context ideas, not the desktop layout.
- cmux has moved toward a Ghostty-based macOS terminal with vertical tabs, notifications, saved Claude Code/Codex sessions, and remote-daemon work. Conduit's cmux lesson is still daemon/proxy/session resilience, but it should come after direct SSH works.
- Ghostty is relevant as terminal-engine architecture research. Official docs describe `libghostty` as the shared terminal emulation/rendering core, but also say it is not yet a stable standalone API. Conduit should stay on SwiftTerm for the M1/M2 iOS terminal path and revisit Ghostty/libghostty only after the core product loop is proven.

Sources checked: [Termius App Store listing](https://apps.apple.com/us/app/termius-terminal-ssh-client/id549039908), [Termius background-session support](https://support.termius.com/hc/en-us/articles/900006226306-Keep-your-Termius-sessions-alive-in-the-background), [Warp Agents](https://docs.warp.dev/agents), [Warp Agent Mode](https://docs.warp.dev/agents/warp-ai/agent-mode), [`manaflow-ai/cmux`](https://github.com/manaflow-ai/cmux), and [Ghostty docs](https://ghostty.org/docs/about).

## Remaining Gaps Before M1 Is Done

- Test against a real SSH host with password auth.
- Test against a real SSH host with generated Ed25519 key auth.
- Add UI confirmation for first-use host keys instead of automatic TOFU recording.
- Persist and display known-host fingerprints per host.
- Replace command-block-only execution with a live PTY path for real terminal use.
- Add a focused first-connect demo script with exact remote setup steps.
- Add integration tests or a local SSH test harness so host-key mismatch and auth failure behavior do not regress.

## Next Implementation Priority

Continue with M1 using a real remote host:

1. Add a known-host confirmation sheet.
2. Add a live PTY session path using Citadel `withPTY` and SwiftTerm.
3. Validate password auth and Ed25519 auth against the real host.
4. Record failure modes in `docs/demos/M1-first-connect.md`.
5. Only then move to reconnect/session survival.
