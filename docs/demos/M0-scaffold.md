# M0 — Scaffold

Closed: 2026-05-23
Re-verified: 2026-05-23T17:05:35Z

## What's in M0

The first milestone produces a SwiftPM workspace that compiles cleanly and a
suite of engine modules with passing tests. There is no working UI in M0;
the iOS app target builds but only shows the onboarding screen and an
empty Workspaces tab. M1 turns this into a real "first connect."

## Acceptance

Run from the package root:

```bash
cd Packages/ConduitKit
swift package clean
swift build                # full clean build of all 19 modules
swift test                 # 20 tests, 6 suites pass
```

Expected:

```
Build complete!
Test run with 20 tests in 6 suites passed
```

Verified locally on:

- Xcode 26.4.1 (build 17E202)
- iOS Simulator runtime 26.4
- Swift 6.0 toolchain
- SwiftPM resolution: Citadel 0.12, SwiftTerm 1.13, GRDB 6.29

## Modules

Engines (build on macOS + iOS, no UIKit imports):

- `ConduitCore`      — typed IDs, value types, error enum
- `SecurityKit`      — Keychain wrapper, Ed25519 KeyStore, HostKeyStore, PairingCrypto
- `SSHTransport`     — Citadel actor + SessionPool + ReconnectController
- `TerminalEngine`   — AnsiSGRParser, BlockRenderer, TUI escalation detector
- `AgentKit`         — AIClient protocol + Anthropic + OpenAI + Mock + RiskScorer
- `PersistenceKit`   — GRDB stack, HostRepository, BlockRepository
- `NotificationsKit` — UNUserNotificationCenter wrapper
- `DiffKit`          — unified diff parser

Features (compile only for iOS; engines remain macOS-testable for CI):

- `WorkspacesFeature` · `SessionFeature` · `InboxFeature` · `OnboardingFeature`
- `SettingsFeature`   · `KeysFeature`    · `DiffFeature`  · `PreviewFeature`
- `FilesFeature`      · `AppFeature` (root composition)

Special:

- `TerminalEngine.RawTerminalView` wraps SwiftTerm via UIViewRepresentable
  (gated `#if canImport(UIKit) && canImport(SwiftTerm)`).
- `PreviewKit.SSHProxyURLSchemeHandler` curl-over-SSH proxy for live remote
  previews (gated `#if canImport(WebKit)`).

## Known gaps for M0

- App's onboarding and Workspaces add-host flows share the same host editor.
- Password hosts prompt at connect time; Ed25519 hosts load keys from Keychain.
- `HostKeyStore` is now wired through a TOFU host-key validator. M1 still
  needs an explicit first-use fingerprint confirmation UI.
- `ContentUnavailableView` requires iOS 17 / macOS 14. Confirmed working
  on the iOS 26.4 simulator.
- `conduitd` (remote daemon) is documented in ARCHITECTURE.md §6 but is
  not yet implemented; first appears in M5.

## Next: M1 — First connect

Demo script for M1 will live at `docs/demos/M1-first-connect.md` and must
include:

1. Generate Ed25519 key in app → copy public key to remote `authorized_keys`.
2. Add host with key auth in the iOS app.
3. Tap host → terminal opens → `ls -la` runs → blocks render with colors.
4. `ls /nonexistent` → red `2` exit chip → long-press → "Explain with AI".
5. Backgrounding → reopen → session reconnects cleanly.
