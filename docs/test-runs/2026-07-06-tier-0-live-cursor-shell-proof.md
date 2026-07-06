# Tier 0 Live Cursor Shell — proof run (2026-07-06)

Branch: `codex/tier-0-live-cursor-shell`  
Device: Roshan's iPhone 17 (`557A7877-F729-5031-9606-0E04F2B67822`, iOS 27.0)  
Simulator: iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`)

## Scope

Prove `LANCER_CURSOR_SHELL_LIVE=1` routes through real `AppRoot` state (workspaces,
Settings handoff, live bridge hydration) and that P0 security fixes hold.

Full governed loop (pair → dispatch → approval → continue) on a physical device with
a live `lancerd` relay remains **owner-gated** — see checklist below.

## Verification commands and results

| Gate | Command | Result |
|------|---------|--------|
| BiometricGate P0 | `cd Packages/LancerKit && swift test --filter 'BiometricGate\|ApprovalDecisionAuth'` | **PASS** — 8 tests |
| Daemon emergency stop | `cd daemon/lancerd && go test ./...` | **PASS** |
| Live bridge unit | `xcodebuild test -scheme LancerKitTests -only-testing:LancerKitTests/CursorShellLiveBridgeTests` | **PASS** |
| Live shell UI (sim) | `xcodebuild test -scheme Lancer -destination 'platform=iOS Simulator,id=095F8B3A…' -only-testing:LancerUITests/CursorAppShellExhaustiveTests/testLiveShell_UsesAppRootBridgeForWorkspaceAndSettings` | **PASS** (25s) |
| Device build + install | `xcodebuild build` (signed) + `devicectl device install app` | **PASS** — `dev.lancer.mobile` installed |
| Device live-shell launch | `devicectl device process launch … LANCER_CURSOR_SHELL_LIVE=1` | **PASS** — app launched on device |
| Live shell UI (device) | Same test as sim, physical destination | **FAIL** — `XCTAssertTrue` on workspace hydration (`command-center` label); device has real paired state, not UITest reseed fixtures |
| Relay approval E2E | `scripts/validation/relay-approval-e2e.sh` | **FAIL** — `TapInjectionProofTests.testRelayApprovalUnblocksHostHook` could not find `board.primary` Inbox card (Cursor shell no longer surfaces legacy Inbox tab) |

## Interpretation

- **Tier 0 shell wiring is proven on simulator** with live bridge + real Settings handoff.
- **P0 security fixes are verified** (BiometricGate fail-closed, daemon atomic emergency stop).
- **Physical device** accepts signed builds and launches with `LANCER_CURSOR_SHELL_LIVE=1`.
- **Automated device UI test** needs a device-tolerant assertion path (do not require `command-center` fixture label when real conversation data is present).
- **Relay E2E harness** needs updating for Cursor-shell navigation (approval surface moved from legacy Inbox tab).

## Owner-gated next proof (manual)

1. Ensure resident `lancerd` is running and relay-attached on the Mac.
2. On the physical iPhone (already paired): open Lancer with live shell, send a prompt from composer.
3. Confirm approval arrives → approve/deny → follow-up/continue works.
4. Record evidence in this file or a sibling `docs/test-runs/` entry.

Reference: `docs/LIVE_LOOP_RUNBOOK.md`, `docs/PUBLISH_READINESS_CHECKLIST.md` B10.
