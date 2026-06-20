# Conduit

A phone-native cockpit for remote AI coding workspaces.

The phone is the best on-body computer humans have ever owned. The remote
machine is where the toolchain, repo, and agent actually live. Conduit is
the missing client between them.

> Read the full design at [`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Repository layout

```
.
├── ARCHITECTURE.md              ← product + technical spec
├── Conduit/                     ← iOS app target (thin shell over AppFeature)
├── Packages/ConduitKit/         ← all real code: engines + features
│   ├── Package.swift            ← module graph
│   ├── Sources/
│   │   ├── ConduitCore/         ← types, ids, errors (no UIKit)
│   │   ├── SecurityKit/         ← Keychain, Ed25519 KeyStore, pairing crypto
│   │   ├── SSHTransport/        ← Citadel actor, SessionPool, reconnect
│   │   ├── TerminalEngine/      ← ANSI SGR parser, block model, SwiftTerm bridge
│   │   ├── AgentKit/            ← AIClient + Anthropic + OpenAI + risk scorer
│   │   ├── PersistenceKit/      ← GRDB stack + repos
│   │   ├── NotificationsKit/    ← UNUserNotificationCenter wrapper
│   │   ├── DiffKit/             ← unified diff parser
│   │   ├── DesignSystem/        ← shared atoms + theme
│   │   ├── PreviewKit/          ← SSH-proxy URL scheme handler
│   │   └── *Feature/            ← SwiftUI screens
│   └── Tests/
├── docs/                        ← demo scripts, ADRs
├── project.yml                  ← XcodeGen project definition
└── scripts/                     ← reload, fmt, etc.
```

## Quick start

Requirements: Xcode 26.x, Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# 1. Generate the Xcode project
xcodegen

# 2. Build the SwiftPM workspace (sanity check, no UI)
cd Packages/ConduitKit
swift build

# 3. Build & run on simulator (iPhone 17 Pro)
xcodebuild -project Conduit.xcodeproj \
  -scheme Conduit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## Engineering rules

Three rules keep the codebase honest:

1. **Engines never import UIKit/SwiftUI.** They are SwiftPM libraries
   testable on macOS CLI. UI lives in feature modules only.
2. **Features may import engines and DesignSystem, never each other.**
   Cross-feature navigation goes through `AppFeature`'s router.
3. **All `async` APIs are `Sendable` and respect cancellation.** No
   `DispatchQueue` outside the rendering hot path; no detached tasks
   outside scene lifecycle.

## Status

> **Current direction (2026-06-20):** the app home is a **sidebar / Command Home shell**; New Chat and
> durable threads remain a primary action and depth destinations — *not* a tab bar. Read [`ARCHITECTURE.md` §0.1 (current-state snapshot)](./ARCHITECTURE.md)
> and §4.1 for the authoritative picture; the milestone table below is historical milestone history.

| M  | Title             | Status |
|----|-------------------|--------|
| M0 | Scaffolding       | ✅ verified |
| M1 | First connect     | ✅ Ed25519 + biometric gate + TOFU + password-at-connect |
| M2 | Real terminal     | ✅ raw PTY via SwiftTerm, auto block↔raw |
| M3 | Survive           | ✅ tmux auto-attach, auto-reconnect on scene resume |
| M4 | AI loop           | ✅ `#`-prefix NL→cmd, explain-block streaming |
| M5 | Inbox + Approvals | ✅ conduitd daemon + LiveInboxViewModel + Codex hook |
| M6 | Preview           | ✅ WKWebView + SSH-proxy scheme + port auto-detect |
| M7 | Diff + Files      | ✅ SFTPFiles + DiffView + UnifiedDiffParser |
| M8 | Watch + Sync      | ✅ Watch app + CloudKit LWW + widget |
| M9 | Hardware input    | ✅ external keyboard, key commands, snippets |
| M10 | Billing + Store  | ✅ StoreKit + Stripe + Privacy manifest |
| M11 | Temporal wall    | 🚧 Phase 0+1+UX landed 2026-05-27; Phase 2 pending |
| M12 | Live Block I/O   | 🚧 core implementation landed 2026-05-28; real-host TUI validation pending |

Last updated 2026-06-17. See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the product and module
architecture, [`docs/PUBLISH_READINESS_CHECKLIST.md`](./docs/PUBLISH_READINESS_CHECKLIST.md) for
launch gates, and [`docs/KNOWN_ISSUES.md`](./docs/KNOWN_ISSUES.md) for the current audit tracker.

Historical state audits have been archived under [`docs/_archive/`](./docs/_archive/). Do not use
`docs/current-state-audit.md` as source of truth.

## Heritage

Conduit synthesises learnings from three earlier prototypes plus a
research survey:

- `~/warp-mobile/`              → Block model, Citadel actor pattern
- `~/Documents/ios/` (Helm)    → SwiftTerm bridge, SSH-proxy preview, X25519 pairing
- `~/Documents/mobile-coding/` → React UX prototype + cloned upstreams (cmux, warp, ghostty)
- `~/Downloads/deep-research-report (2).md` → market analysis

None of those repos are imported wholesale; Conduit is a fresh, opinionated
build that takes the *patterns* and leaves the *baggage*.
