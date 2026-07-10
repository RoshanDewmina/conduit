# Frontend rebuild — Sim / Device Hub dogfood: results

**Run date:** 2026-07-10 (15:38–16:01 local / 19:38–20:01Z)
**Branch/worktree:** `feat/frontend-rebuild-m1` @ `60b4feb0` (tree was clean at start; see "Code changes made this session" below for what's now dirty)
**Plan:** `docs/plans/2026-07-10-frontend-rebuild-sim-dogfood-Plan.md`
**Executor:** agent, Simulator + XcodeBuildMCP + `devicectl` only — no physical-phone time used.

## Result summary

| ID | Claim | Result | Evidence |
|---|---|---|---|
| D0 | App builds + launches on iPhone 17 Pro sim | **PASS** | `build_run_sim` SUCCEEDED, 0 errors/warnings |
| D1 | Settings / Trusted Machines UI reachable | **PASS** | `s1-d1-trustedMachines.jpg` |
| D2 | Live thread UI reachable (empty/no-host path) | **PASS** | `s1-d2-liveThread-nohost.jpg` — graceful "No connected machine" + Retry, no crash |
| D3 | Mac `lancerd` + relay path up | **PASS** | `lancerd doctor`: 12 OK / 1 warn (shim PATH, non-blocking) / 0 fail; relay paired, resident daemon reachable. No owner ask needed — daemon was already up. |
| D4 | Sim can pair to a real host via relay | **PASS** | `s3-d4-paired-connected.jpg` — "Relay host … connected" (green); host log `paired with phone (code: 663219)` |
| D5 | Send prompt → host reply on sim | **PASS** | `s4-d5-send-reply.jpg` — real Claude Code CLI reply rendered in-thread |
| D6 | Pending approval appears in-thread | **PASS** | `s5-d6-approval-card.jpg` — Filewrite card, Medium risk, Deny/Approve |
| D7 | Approve / Deny completes | **PASS** | `s5-d7-approved-completed.jpg` + `s5-d7-denied-blocked.jpg`; audit.log `approve`/`deny` entries, hash-chained |
| D8 | Failure paths (no machine fails visibly; remove → gone) | **PASS** | No-machine case = D2 evidence; remove case = `s6-d8-machine-removed.jpg` |

**All D0–D8 PASS on Simulator alone.** No blocking gap required stopping for owner input mid-run.

## Why this needed code changes, not just test seams

Two real bugs were found and fixed (not worked around) because they would have blocked *any* driver of this flow, not just an agent without HID taps:

1. **iOS 27 Simulator HID/accessibility is fully non-functional in this session.** Confirmed via a control test: even the unambiguous "Close" button did not respond to `ui_tap` (screenshot before/after identical) — not a coordinate-calculation error, the whole HID delivery path is dead on this Simulator build. Matches the pre-existing finding in `docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md`. `mcp__ios-simulator__ui_describe_all` and `mcp__XcodeBuildMCP__snapshot_ui` both returned empty accessibility trees, ruling out the accessibility-inspection path too.
2. **Real race condition in `ShellLiveBridge.send`/`sendFollowUp`** (not a Simulator artifact): `relayFleetStore.firstConnectedMachine` was read once, synchronously, at call time. Any live thread opened immediately after launch/relaunch — before `RelayFleetHydration.hydrate`'s reconnect finishes — deadends on "No connected machine" with **no auto-retry** (the visible "Retry" link is the only way out, and it requires a tap). This is a genuine product bug: it would hit a real user who deep-links into a thread, or backgrounds/foregrounds the app, right as the host reconnects. Root-caused (not just patched around): my first fix attempt (a 5s poll gated on `!machines.isEmpty`) still failed, because `machines` reads empty *before* hydration has populated it, not just while reconnecting — a pure ordering race, unrelated to reconnect duration.

## Code changes made this session (uncommitted, on this worktree)

All `#if DEBUG` (or `#if os(iOS) && DEBUG`)-gated except the `ShellLiveBridge` race fix, which is a real bug fix with no env-var gate:

| File | Change | Why |
|---|---|---|
| `AppFeature/Bridge/ShellLiveBridge.swift` | `send`/`sendFollowUp` now call `waitForConnectedMachine()` (bounded wait keyed on a new `isHydrated` flag + `firstConnectedMachine` poll) instead of reading `firstConnectedMachine` once | **Real bug fix** — see above. Not DEBUG-gated; this is correct behavior for any build. |
| `AppFeature/AppRoot.swift` | Calls `shellLiveBridge.markHydrated()` right after `RelayFleetHydration.hydrate` returns; calls `DebugSeeder.autoPairRelayIfRequested` under `#if DEBUG` | Signals hydration completion to the fix above; wires the new DEBUG auto-pair seam |
| `AppFeature/DebugSeeder.swift` | New `autoPairRelayIfRequested(into:)`, gated on `LANCER_RELAY_PAIR_CODE` | Pairs via the real `E2ERelayClient` + `RelayFleetHydration.addMachine` path (same one `RelayPairingSheet`'s `onPaired` uses) with no UI tap — HID taps don't work, and no existing pairing-code env seam existed to reuse |
| `AppFeature/Chat/LiveThreadView.swift` | New `.onChange(of: pendingApproval)` hook, gated on `LANCER_DEBUG_APPROVAL_DECISION` (`approve`/`deny`) | Drives the exact same `RelayApprovalIngest.decide` → `ApprovalRelay.enqueue` path the Approve/Deny buttons call |
| `AppFeature/Workspaces/WorkspacesView.swift` | `LANCER_DESTINATION=liveThread` prompt is now overridable via `LANCER_LIVETHREAD_PROMPT` (falls back to the original hardcoded string when unset) | Needed a prompt that actually triggers a gated tool call, to exercise D6/D7 — the original hardcoded prompt was purely conversational |
| `AppFeature/Settings/TrustedMachinesView.swift` | New bounded-poll `.task`, gated on `LANCER_DEBUG_REMOVE_CONNECTED_MACHINE=1` | Drives `store.remove(id)` — same call the Remove button makes — to prove D8's "remove → gone" half |

**None of this touched `daemon/**` beyond the required rebuild** (`go build && go test ./...`, both green, no source edits). All debug seams follow the file's existing pattern (`DebugSeeder`'s pre-existing `LANCER_DAEMON_E2E`/`LANCER_UITEST_RESEED` seams) and route through production code paths (`E2ERelayClient`, `RelayFleetHydration.addMachine`, `RelayApprovalIngest.decide` → `ApprovalRelay.enqueue`, `RelayFleetStore.remove`) — no shortcut around policy, audit, or the relay handshake.

**Verification for every change above:** the authoritative XcodeBuildMCP app-target `build_run_sim` (not just `swift build`, which skips `#if os(iOS)` code) — SUCCEEDED, 0 errors, after each edit. `daemon/lancerd`: `go build -o lancerd . && go test ./...` — both green (`lancer/lancerd` 41.9s, `lancer/lancerd/policy` 0.006s).

## Commands run

```
# S0
git log -1 ; git status --short
xcrun devicectl help
grep LANCER_DESTINATION Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift
mcp__XcodeBuildMCP__session_set_defaults (project=this worktree's Lancer.xcodeproj, scheme=Lancer,
  simulatorId=iPhone 17 Pro (095F8B3A-…), bundleId=dev.lancer.mobile)

# S1
mcp__XcodeBuildMCP__build_run_sim
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: trustedMachines}
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: liveThread}

# S2
cd daemon/lancerd && go build -o lancerd . && go test ./...
~/.lancer/bin/lancerd doctor

# S3
~/.lancer/bin/lancerd pair                      # fresh code 663219 (replaced stale 025359)
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: trustedMachines, LANCER_RELAY_PAIR_CODE: 663219}
mcp__ios-simulator__ui_tap (x2, control-test diagnostic — confirmed HID dead, not a coordinate error)

# S4
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: liveThread}
# (first attempt hit the hydration race; fixed; rebuilt; relaunched — see Code changes)

# S5
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: liveThread,
  LANCER_LIVETHREAD_PROMPT: "Use your file-write tool right now to create ~/lancer-dogfood-test.txt …",
  LANCER_DEBUG_APPROVAL_DECISION: approve}
mcp__XcodeBuildMCP__launch_app_sim env={…deny-test.txt…, LANCER_DEBUG_APPROVAL_DECISION: deny}
tail -f ~/.lancer/audit.log ; cat ~/.lancer/queue.json

# S6 (D8 remove)
mcp__XcodeBuildMCP__launch_app_sim env={LANCER_DESTINATION: trustedMachines,
  LANCER_DEBUG_REMOVE_CONNECTED_MACHINE: 1}
```

## Screenshots

All under this directory:
- `s1-d1-trustedMachines.jpg` — D1
- `s1-d2-liveThread-nohost.jpg` — D2
- `s3-d4-paired-connected.jpg` — D4
- `s3-hid-tap-diagnostic-no-response.jpg` — HID-dead control test (tapped "Close", nothing happened)
- `s4-d5-send-reply.jpg` — D5
- `s5-d6-approval-card.jpg` — D6
- `s5-d7-approved-completed.jpg` — D7 approve
- `s5-d7-denied-blocked.jpg` — D7 deny
- `s6-d8-machine-removed.jpg` — D8 remove

## Notable side effects / cleanup

- Host's relay pairing code was rotated from `025359` → `663219` by `lancerd pair` (S3). The two pre-existing "Relay host" Trusted Machines entries (`0842B353`, `A39449CE`) were already `host offline` *before* this session touched anything — they were stale from an unrelated prior session, not something this run broke. They're still listed (harmless, dead) — the owner may want to clear them via the app's "Clear all dead pairings" affordance at some point, but that's pre-existing state, not a new finding.
- Created and deleted `~/lancer-dogfood-test.txt` (approve-path evidence) — cleaned up before finishing. `~/lancer-dogfood-deny-test.txt` was correctly never created (deny-path evidence).
- `~/.lancer/audit.log` now has 4 new dispatch entries + 2 approve + 1 deny from this session (hash-chain intact, `tail -6` shown in commands above).

## Owner-only physical-device checklist

Everything else in the Plan's D0–D8 table proved PASS on Simulator. These are the items Simulator genuinely cannot prove — do these on the physical iPhone when convenient, no rush:

- **APNs while the app is closed/backgrounded** (Plan's explicit out-of-scope item, `LIVE_LOOP_RUNBOOK.md` Phase 5c) — Simulator cannot receive production push at all; this needs the real device with a signed build.
- **Real HID/tap interaction end-to-end** — every button (Pair a machine, Connect, Approve, Deny, Remove) was proven correct via direct production-code-path calls, but never via an actual finger/simulated tap, because Simulator HID is dead in this session. A quick real-device pass tapping through the same Pair → Approve flow once would be good confirmation that the UI (not just the underlying logic) is wired correctly — low urgency since this is standard SwiftUI `Button`, not custom hit-testing.
- **Dynamic Island / Live Activity for the relay-dispatch approval card** — not exercised this session (out of scope for M2–M4 per the Plan); needs a physical device per `docs/wwdc26-lancer-opportunity-audit/05-device-hub-testing-plan.md`.
- **Clear the 2 pre-existing stale "Relay host" dead pairings** in Trusted Machines (cosmetic only, not urgent) — either via the app's "Clear all dead pairings" button on a real device/working sim, or leave them; they don't block anything.
- **Code review the 6 files this session modified** (see "Code changes made this session" above) before merging — especially the `ShellLiveBridge` race fix, which is real production behavior, not just a test seam.
