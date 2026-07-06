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
| Relay approval E2E | `scripts/validation/relay-approval-e2e.sh` | **PASS** (2026-07-06, see below) — was FAIL: `TapInjectionProofTests.testRelayApprovalUnblocksHostHook` timed out waiting for the Workspaces `approval-banner` |
| Cursor shell regression suite | `xcodebuild test … -only-testing:LancerUITests/CursorAppShellExhaustiveTests` | **PASS** — 22/22 (21 original + 1 uncommitted addition already in the tree) |

## Interpretation

- **Tier 0 shell wiring is proven on simulator** with live bridge + real Settings handoff.
- **P0 security fixes are verified** (BiometricGate fail-closed, daemon atomic emergency stop).
- **Physical device** accepts signed builds and launches with `LANCER_CURSOR_SHELL_LIVE=1`.
- **Automated device UI test** needs a device-tolerant assertion path (do not require `command-center` fixture label when real conversation data is present).
- **Relay E2E harness now passes** through the live Cursor shell — see fix below.

## Relay E2E fix (2026-07-06, follow-up)

**Symptom:** `relay-approval-e2e.sh` failed with the daemon log showing `paired with phone` and
an `escalate` audit entry, but the phone never rendered the Workspaces `approval-banner` —
`TapInjectionProofTests.testRelayApprovalUnblocksHostHook` timed out after 120s waiting for it.

**Root cause:** not a Cursor-shell routing bug. `RelayFleetStore` caps paired machines at
`relayFleetMaxMachines` (3), and `isFull`/`add()` counted **every** hydrated machine record
toward that cap — including ones whose persisted pairing had permanently failed to restore
(`pairingUsable: false`, i.e. `ConnectionStateStore` state `.pairingInvalid`, which can never
reconnect without a fresh re-pair). The iOS Simulator's Keychain survives `xcrun simctl
uninstall` even though `UserDefaults` does not, so each harness run (or any real device that's
been reinstalled a few times while reusing the same relay code) left one more permanently-dead
machine record in the Keychain-backed index. After ~3 such runs the cap was permanently full of
unusable ghosts, so `addRelayMachine` rejected every *new*, real pairing right after it completed
its handshake (`AppRoot.swift`'s `guard relayFleetStore.add(...) else { …; client.disconnect();
return }` — the bridge was never started, so the `approvalPending` relay message had nowhere to
land). Confirmed live via temporary instrumentation + `log stream`: the fresh client reached
`peer_joined`/session-key-derived (hence the daemon's "paired with phone"), then was immediately
disconnected with `addRelayMachine: fleet at cap`.

**Fix:** `RelayFleetStore.isFull` now excludes machines whose `ConnectionStateStore` state is
`.pairingInvalid` from the cap count (`Packages/LancerKit/Sources/AppFeature/RelayFleetStore.swift`).
A permanently-unrestorable ghost pairing still shows up in the fleet list (existing behavior,
unchanged) but no longer consumes a slot that a real pairing needs.

**Verification (2026-07-06):**

```
cd /Users/roshansilva/Documents/command-center
LANCER_SIM_UDID=095F8B3A-FEA3-4031-A2A5-561755740730 bash scripts/validation/relay-approval-e2e.sh
```

Ran twice consecutively — both **PASS**:

```
xcodebuild test rc : 0  (0 = APPROVE tapped + card cleared)
agent-hook rc      : 0 (0 = host hook UNBLOCKED via relay approve)
--- audit tail ---
{"action":"escalate", ..., "approvalId":"...",...}
{"action":"approve", ..., "approvalId":"...",...}
>>> PASS: relay approval round-trip proven (phone tap → relay → host unblock).
```

`xcodebuild test -only-testing:LancerUITests/CursorAppShellExhaustiveTests` stayed green after
the fix: 22/22 passed (356.9s).

Known side note (not fixed here, out of scope): the harness's hardcoded relay code (314159)
means the Keychain-persisted ghost index keeps growing by one entry per run (5 at last count).
The cap fix makes this harmless for pairing, but a long-lived dev simulator will eventually want
a "clear all relay pairings" debug action if the growing list becomes visible clutter in Settings.

## Owner-gated next proof (manual)

1. Ensure resident `lancerd` is running and relay-attached on the Mac.
2. On the physical iPhone (already paired): open Lancer with live shell, send a prompt from composer.
3. Confirm approval arrives → approve/deny → follow-up/continue works.
4. Record evidence in this file or a sibling `docs/test-runs/` entry.

Reference: `docs/LIVE_LOOP_RUNBOOK.md`, `docs/PUBLISH_READINESS_CHECKLIST.md` B10.
