# Codex UI/UX audit - 2026-06-13

## Scope

Branch: `codex/uiux-audit`

Target: Conduit iOS on the iPhone 17 Pro Device Hub runtime, Xcode 27.0 beta (`27A5194q`), iOS 27.0 simulator runtime.

Primary inventory reviewed:

- `docs/design-handoff/PAGES.md`
- `docs/design-handoff/screenshots/`
- `docs/design-handoff/BACKEND_COVERAGE.md`
- `docs/superpowers/specs/2026-06-12-conduit-pixel-perfect-polish-plan.md`

Apple docs checked while judging macOS 27 / Xcode 27 behavior and HIG issues:

- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [Device Hub](https://developer.apple.com/documentation/xcode/device-hub)
- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

The practical HIG constraints applied here were: keep tappable regions at least 44 x 44 pt, preserve Dynamic Type readability, avoid low-contrast disabled states, keep a clear primary action, and make the first-run mental model explicit without adding onboarding bulk.

## Device Hub findings

Tap injection was verified before relying on it:

- Before: `docs/audit/screenshots/2026-06-13/tap-check-before-inbox.png`
- After tapping the Fleet tab: `docs/audit/screenshots/2026-06-13/tap-check-after-fleet.png`

Result: the first MCP tap changed the screen from Inbox to Fleet, so event injection works in at least the cold-start path.

The runtime was still unstable later in the pass:

- `build_run_sim` via XcodeBuildMCP built successfully but timed out around launch state.
- `simctl io booted screenshot` worked but was slow.
- The iPhone 17 Pro runtime shut down during screenshot/install cycles.
- After a reboot, MCP taps sometimes returned success while the screen hash stayed unchanged.
- XCUITest could synthesize taps, but the iOS 27 runner repeatedly terminated with `Test crashed with signal term` / `SBMainWorkspace` request denied while relaunching `dev.conduit.mobile.uitests.xctrunner`.

Because of that, I treated fresh screenshots as evidence only for the affected surfaces and used the existing design-handoff inventory plus source review for the full route pass. I did not fake a full fresh recapture.

## Changes made

### 1. Global button tappable area

Severity: should-fix

Issue: `DSButton` small and medium variants were visually compact and could expose sub-44 pt hit areas. This was already called out by the polish plan as P1-12.

Fix: preserve compact visual height, but wrap every `DSButton` in a minimum 44 x 44 pt tappable frame and content shape. Large buttons now use a 44 pt visual minimum.

Files:

- `Packages/ConduitKit/Sources/DesignSystem/Components/DSButton.swift`

Verification screenshots:

- `docs/audit/screenshots/2026-06-13/after-components-dark.png`
- `docs/audit/screenshots/2026-06-13/after-components-light.png`

### 2. Fleet saved-host reconnect target

Severity: should-fix

Issue: the reconnect icon in saved-host rows was visually aligned but its slot was only 28 pt wide, below the HIG target floor and easy to miss for a first-time user.

Fix: expand the reconnect affordance to a fixed 44 x 44 pt slot without changing the row layout.

Files:

- `Packages/ConduitKit/Sources/AppFeature/FleetView.swift`

Verification screenshots:

- `docs/audit/screenshots/2026-06-13/after-fleet-dark.png`
- `docs/audit/screenshots/2026-06-13/after-fleet-light.png`

### 3. Connect sheet header consistency

Severity: should-fix

Issue: the connect/password prompt used a one-off title row and circular close button. It did not match the BLOCKS detail-header system used elsewhere, and the close target looked visually smaller than surrounding navigation controls. This was the remaining P1-14 item from the polish plan.

Fix: replace the custom row with `DSDetailHeader("connect", onBack:)`.

Files:

- `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`

Verification screenshot:

- `docs/audit/screenshots/2026-06-13/after-connect-sheet-dark.png`

Light-mode after-shot was not captured because the Device Hub tap path started no-oping after a simulator restart. The source change is token-based and shares the same `DSDetailHeader` rendering as the verified dark shot.

### 4. Tap-proof test hardening

Severity: nice-to-have

Issue: `scrollIntoView` could continue swiping even when the target control was above the comfortable viewport, which makes the Face ID toggle case more fragile on beta runtimes.

Fix: only swipe when the target is below the safe bottom threshold; otherwise stop. Also isolated `TapInjectionProofTests` with `@MainActor` and a preconcurrency XCTest import, eliminating the Xcode 27 Swift concurrency warnings in the rerun result bundle.

Files:

- `ConduitUITests/TapInjectionProofTests.swift`

## Page review

| Page / route | Evidence | UX judgment | Result |
| --- | --- | --- | --- |
| 00 onboarding flow | baseline, source review | First-run model is visually strong but the product promise must avoid unverified closed-app/Watch claims until physical APNs is signed off. | No committed copy change in this pass; note remains should-fix for product copy audit. |
| 01 inbox | baseline, live tap-check before | Strong primary approval surface. Dense cards are acceptable for developer context. | No code change. |
| 05 inbox typed/MCP | baseline, source review | MCP permission language is understandable, but allow-always scope should remain explicit wherever shown. | Deferred; broader copy changes exist in the worktree but were not included in this audit commit. |
| 02 fleet | live dark/light screenshots | Saved-host rows are clear; reconnect target was too small. Empty state should explain host/agent relationship. | Fixed reconnect 44 pt slot; empty copy changes in worktree left unstaged. |
| 03 activity | baseline | Timeline hierarchy is clear; no immediate first-user blocker. | No code change. |
| 04 settings | baseline, source review | Settings is dense but structured. Notification filter scope could be clearer. | Deferred; larger settings refactor in worktree left unstaged. |
| 11 billing | baseline | Uses design-system header and CTA structure; no blocking clutter. | No code change. |
| 12 paywall | baseline | CTA hierarchy and gutters appear consistent after prior polish work. | No code change. |
| 13 compare | baseline | Comparison table is scan-friendly; verify Dynamic Type in a dedicated pass. | No code change. |
| 14 library | baseline | Library states read as secondary power-user surfaces, acceptable. | No code change. |
| 15 snippets | baseline | Form-heavy but expected for snippet editing. | No code change. |
| 16 SSH keys | baseline | Security intent is clear; no first-run blocker. | No code change. |
| 17 policy editor | baseline | Dense, but the domain requires detail. Future pass should add progressive disclosure for new users. | Deferred. |
| 18 connect host | live dark screenshot | Header inconsistency was the main visible issue. Disabled connect button reads inactive. | Fixed header. |
| 19 add host | baseline, source review | First-time user needs to understand this is the machine agents control. | Deferred; explanatory copy exists in worktree but was not included in this audit commit. |
| 20 orb connecting | baseline | Clear transient state. | No code change. |
| 21 orb connected | baseline | Clear success state. | No code change. |
| 22 orb failed | baseline | Failure state is visible; next action clarity should be checked with real backend errors later. | Deferred. |
| 23 orb slow | baseline | Slow state communicates waiting without looking broken. | No code change. |
| 30 diff review | baseline | Diff density is appropriate for developer audience. Live terminal/block grids must remain screenshot-verified, not AX-only. | No code change. |
| 31 file preview | baseline | Good information hierarchy. | No code change. |
| 40 blocks | baseline | Terminal surface matches product promise; AX tree is insufficient by design. | No code change. |
| 41 chat | baseline | Approval card actions need minimum target guarantees. | Covered through `DSButton`. |
| 42 live session | baseline | Header and session controls are compact but consistent. | No code change. |
| 50 agent HUD | baseline | HUD communicates state well for a glance surface. | No code change. |
| 51 status header | baseline | Compact status header is understandable after onboarding. | No code change. |
| 52 keyboard rail | baseline | Dense but appropriate for terminal control. | No code change. |
| 53 features | baseline | Marketing-style feature surface is acceptable as gallery/internal route. | No code change. |
| 54 states | baseline | Empty/loading/error states are on-brand. | No code change. |
| 60 component catalog | live dark/light screenshots | Component catalog validates global button hit-area change; layout remains intentionally wide. | Fixed via `DSButton`. |

## Verification

Passed:

- `xcodegen generate`
- `cd Packages/ConduitKit && swift build`
- `xcodebuild -project Conduit.xcodeproj -scheme Conduit -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' -configuration Debug -derivedDataPath /tmp/conduit-dd-codex build`
- `cd Packages/ConduitKit && swift test`
  - 6 XCTest cases passed in `NotificationFilterXCTests`
  - 345 Swift Testing tests passed across 57 suites
- Manual Device Hub tap gate: Inbox -> Fleet changed screen

Partially verified / blocked by beta runtime:

- `xcodebuild test ... -only-testing:ConduitUITests/TapInjectionProofTests`
  - First run: the approval tap and visual attachment paths executed, but the suite failed after the iOS 27 runner restarted and later refused to launch the xctrunner. Result: `/tmp/conduit-tap-proof.xcresult`.
  - Rerun after `@MainActor`: zero warnings in the result bundle, but the first approval test terminated with `Test crashed with signal term`. Result: `/tmp/conduit-tap-proof-rerun.xcresult`.

The Xcode 27 failure mode matches the observed Device Hub instability, not an app assertion failure.

## Deferred items

- Full fresh dark/light screenshot recapture for all 66 baseline screenshots. Device Hub screenshot and launch instability made this impractical in one pass; the route inventory was still reviewed against existing screenshots and source.
- Light-mode after-shot for the connect sheet. The post-reboot tap path no-oped.
- Live `CONDUIT_GALLERY=session` real localhost SSH flow. This needs Remote Login and a valid `conduit-localhost-ssh` keychain entry.
- Physical-device APNs and lock-screen/Watch approval copy. Do not treat lock-screen/Watch claims as verified from this simulator pass.
- Cloud/paid entitlement inner screens. I evaluated locked/baseline states only.

## Summary

Pages reviewed: all pages and gallery routes listed in `docs/design-handoff/PAGES.md`.

Issues fixed: 4

- Global `DSButton` 44 x 44 pt tappable area.
- Fleet saved-host reconnect 44 x 44 pt target.
- Connect sheet BLOCKS detail-header consistency.
- Tap-proof XCUITest scroll and actor-isolation hardening.

Issues deferred: full route recapture, physical-device notification claims, live SSH session, and several broader copy/refactor changes currently present but left outside this focused audit commit.
