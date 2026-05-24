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

| M  | Title           | Status |
|----|-----------------|--------|
| M0 | Scaffolding     | ✅ verified |
| M1 | First connect   | 🚧 credential flow + TOFU started |
| M2 | Real terminal   | ⏳ |
| M3 | Survive         | ⏳ |
| M4 | AI loop         | ⏳ |
| M5 | Inbox + Approvals | ⏳ |
| M6 | Preview         | ⏳ |
| M7 | Diff + Files    | ⏳ |

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) §14 for full roadmap.

Current implementation audit: [`docs/current-state-audit.md`](./docs/current-state-audit.md).

## Heritage

Conduit synthesises learnings from three earlier prototypes plus a
research survey:

- `~/warp-mobile/`              → Block model, Citadel actor pattern
- `~/Documents/ios/` (Helm)    → SwiftTerm bridge, SSH-proxy preview, X25519 pairing
- `~/Documents/mobile-coding/` → React UX prototype + cloned upstreams (cmux, warp, ghostty)
- `~/Downloads/deep-research-report (2).md` → market analysis

None of those repos are imported wholesale; Conduit is a fresh, opinionated
build that takes the *patterns* and leaves the *baggage*.
