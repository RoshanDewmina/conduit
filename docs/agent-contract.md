# Agent Contract

> Rules every contributor — human or AI — follows when changing this repo.

Last updated: 2026-07-06

This document is the canonical short-form for the engineering rules in
`README.md` and the architectural constraints in `ARCHITECTURE.md`. When
something here conflicts with either of those, this file is wrong and should
be corrected.

---

## 1. Module discipline

1. **Engines never import UIKit or SwiftUI.** `LancerCore`, `SSHTransport`,
   `TerminalEngine`, `SecurityKit`, `AgentKit`, `PersistenceKit`,
   `NotificationsKit`, `DiffKit`, `PreviewKit`, and `SyncKit` are SwiftPM
   libraries testable on a macOS CLI. UI belongs in `*Feature` modules.
2. **Features may depend on engines and `DesignSystem`, never on each other.**
   Cross-feature navigation happens through `AppFeature`'s router.
3. **All `async` APIs are `Sendable` and respect cancellation.** No
   `DispatchQueue` outside the rendering hot path; no detached `Task`s
   outside scene lifecycle.

## 2. Platform contract

- Deployment target: **iOS 26.0** (`project.yml` and `Package.swift`).
- Toolchain: Xcode 27.x, Swift 6.2, SwiftPM-first.
- Strict concurrency and existential-any are on by default — do not add
  upcoming-feature flags for them.
- iOS 27-only APIs (`glassEffect`, `@Observable`, new ScrollView/safeArea
  modifiers, `BGContinuedProcessingTask`, Foundation Models, etc.) are
  fast-follow candidates while the deployment target remains iOS 26.0. Gate
  them or keep them out of the shipping path.

## 3. Code change rules

- **Edit existing files first.** Don't create new files when a small edit
  fits an existing module.
- **No comments unless the why is non-obvious.** Don't restate what the code
  already says.
- **No backwards-compatibility shims, dead code, or "removed for X"
  markers.** Delete cleanly.
- **No speculative abstractions.** Three similar lines beats a premature
  helper.
- **Validate at boundaries only.** Trust internal types; don't add
  fallbacks for cases that can't happen.

## 4. UI surface rules

- All glass / chrome surfaces use `View.lancerGlassChrome(...)` from
  `DesignSystem/Atoms.swift`, not raw `.background(.bar)` /
  `.background(.thinMaterial)` / `.glassEffect(...)`. The single helper is
  what we change when Apple revises Liquid Glass.
- Status, loading, and reconnect banners are owned by the feature module
  they belong to — `AppFeature` only routes.
- Bottom safe-area inset chrome (keyboard rails, composers) goes through
  `safeAreaInset(edge: .bottom)` so it composes correctly with the system
  keyboard accessory bar.

## 5. Terminal-engine rules

- The unified PTY shell is the single source of truth for the byte stream.
  Don't spawn a second `SSHShell` for "raw mode" — `PTYBridge` toggles the
  view, the channel stays open.
- OSC 133 / OSC 7 parsing lives in `PTYBridge`. Adding new markers means
  extending `dispatchOSC*`, not sprinkling regexes elsewhere.
- Block-mode rendering must never see raw OSC bytes — `PTYBridge` strips
  them before calling `onBlockBytes`.
- Alt-screen detection (`\e[?1049h/l`) drives raw↔block escalation. Don't
  add heuristics — the escape sequence is authoritative.

## 6. SSH / security rules

- TOFU: unknown host keys must surface a user-confirmation sheet via
  `HostKeyStore`. Never `acceptAnything()`.
- Private keys live in the Keychain via `KeyStore`, gated by
  `BiometricGate`. Never read them from disk or copy them off-device.
- Connection timeouts use the `withThrowingTimeout` task-group pattern
  (see `SSHSession`). No raw `DispatchQueue.asyncAfter`.

## 7. Testing rules

- Engines have `swift test` coverage. Adding behaviour to an engine
  without a test is a defect.
- iOS-only features (anything `#if os(iOS)`) ship without unit tests by
  default; if they have logic worth testing, refactor it into a
  platform-agnostic helper inside an engine module.
- Tests must not require network, real Keychain context, or a real SSH
  host. Skip with a reason if they do.

## 8. Documentation rules

- `ARCHITECTURE.md` is the source of truth for product + technical scope.
- `docs/PUBLISH_READINESS_CHECKLIST.md` is the source of truth for launch
  state ("what works / what's gated") — update it when you ship a milestone,
  not retroactively. (`docs/current-state-audit.md` is archived/stale — do
  not rely on it.)
- `docs/KNOWN_ISSUES.md` is the canonical audit/issue tracker (security,
  perf, dead code, doc drift). Record verified findings there.
- `docs/remaining-work.md` is **superseded** (states a wrong "free Apple
  team" blocker); do not act on it. Track real blockers in the checklist above.
- When code disagrees with a doc, fix one of them in the same commit.
  Don't let drift accumulate.

## 9. Non-goals (don't propose these)

- Local iOS code editor, local language servers, local build tools.
- A custom SSH protocol implementation (Citadel + swift-nio-ssh is the
  answer).
- Re-implementing tmux semantics in-app — integrate, don't replace.
- Real-time multi-cursor collaboration.
- Pure-subscription gating of the client.

See `ARCHITECTURE.md` §1.1 for the full list and reasoning.
