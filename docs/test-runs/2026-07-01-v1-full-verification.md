# Lancer V1 full verification run

Date: 2026-07-01
Runner: Codex in `/Users/roshansilva/Documents/command-center`
Result: **BLOCKED for V1 live loop**. Local code/build/UI gates passed, but the production Cloud Run relay/backend is currently unavailable and prevents relay approval, APNs, Live Activity, and multi-machine live verification.

## Scope

This run covered the current working tree, including the committed multi-machine relay feature (`ffc99368`, report `ebaccafb`) and the later uncommitted approval/Live Activity reliability changes:

- `RelayMachineID`, `RelayMachineRecord`, `RelayFleetStore`
- `E2ERelayBridge`, `ApprovalRelay`
- `approvalResponseAck`, `approvalResolved`
- `LancerLiveActivityManager`
- `lancerd` relay routing
- production backend `https://conduit-push-y4wpy6zeva-ts.a.run.app`

Initial dirty-tree snapshot:

```text
 M Packages/LancerKit/Sources/AppFeature/AppRoot.swift
 M Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift
 M Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift
 M Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift
 M Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift
 M Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift
 M Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift
 M daemon/lancerd/daemon_test.go
 M daemon/lancerd/e2e_router.go
 M daemon/lancerd/e2e_router_test.go
 M daemon/lancerd/server.go
 M docs/lancer-ui-prototype/app/page.tsx
 M docs/lancer-ui-prototype/components/variant-nav.tsx
?? .claude/launch.json
?? docs/lancer-ui-prototype/app/live-activity/
?? docs/lancer-ui-prototype/app/siri-readiness/
?? docs/lancer-ui-prototype/components/conduit/
?? docs/lancer-ui-prototype/components/dynamic-island-frame.tsx
?? docs/lancer-ui-prototype/components/lock-screen-frame.tsx
?? docs/lancer-ui-prototype/components/siri-snippet-frame.tsx
```

## Automated gates

| Gate | Command | Result |
| --- | --- | --- |
| `lancerd` build + tests | `cd daemon/lancerd && go build -o lancerd . && go test ./...` | PASS: `lancer/lancerd` ok in 23.263s, `lancer/lancerd/policy` cached |
| LancerKit build + tests | `cd Packages/LancerKit && swift build && swift test` | PASS: build complete; 8 XCTest tests, 471 Swift Testing tests, and 13 HostServiceClient tests passed; 0 failures |
| push-backend tests | `cd daemon/push-backend && go test ./...` | PASS: `lancer/push-backend` ok in 1.152s |
| Xcode app-target build | XcodeBuildMCP `build_sim` with project `Lancer.xcodeproj`, scheme `Lancer`, sim `iPhone 17 Pro` | PASS: SUCCEEDED in 27.890s, 0 warnings, 0 errors |
| Xcode app-target build/run | XcodeBuildMCP `build_run_sim` | PASS: SUCCEEDED in 19.645s, installed and launched `dev.lancer.mobile`, 0 warnings, 0 errors |

XcodeBuildMCP evidence:

- Build log: `/Users/roshansilva/Library/Developer/XcodeBuildMCP/workspaces/command-center-c3ef378ca557/logs/build_sim_2026-07-02T00-12-29-290Z_pid68621_f276b70c.log`
- Build/run log: `/Users/roshansilva/Library/Developer/XcodeBuildMCP/workspaces/command-center-c3ef378ca557/logs/build_run_sim_2026-07-02T00-13-02-027Z_pid68621_a632b6c2.log`
- Runtime log: `/Users/roshansilva/Library/Developer/XcodeBuildMCP/workspaces/command-center-c3ef378ca557/logs/dev.lancer.mobile_2026-07-02T00-13-18-869Z_helperpid27543_ownerpid68621_d3d62a3a.log`
- OS log: `/Users/roshansilva/Library/Developer/XcodeBuildMCP/workspaces/command-center-c3ef378ca557/logs/dev.lancer.mobile_oslog_2026-07-02T00-13-21-656Z_helperpid27624_ownerpid68621_4690a190.log`

Log scan for `crash|fatal|EXC_BAD|uncaught|assertion failed|terminating app due`: no matches in the app launch logs or debug-seam launch logs.

## Simulator UI screenshots

Stored under `docs/test-runs/2026-07-01-v1-full-verification/`.

| Surface | Screenshot | Result |
| --- | --- | --- |
| Home, no paired relay machine | `01-home-empty.jpg` | PASS: renders "All clear tonight" and "Connect a machine" empty state |
| Home, fake relay host seam | `02-home-relay-host.jpg` | PASS: renders `Hermes-MacBook-Pro` as a green live relay machine row |
| Settings landing | `03-settings.jpg` | PASS: settings landing renders without crash |
| Machines / Fleet | `04-machines.jpg` | PASS for existing SSH-host rendering; relay card remains visually unverified because the existing fake-relay seam feeds Home only |

## Targeted regressions

### Home relay-host UI test

Command:

```bash
xcodebuild test -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LancerUITests/HomeButtonTapTests/testRelayHostShowsOnHome
```

Result: PASS. One UI test executed, 0 failures, 8.558s.

Result bundle:

```text
/Users/roshansilva/Library/Developer/Xcode/DerivedData/Lancer-ecglbxlaauasnnazkhdmviuidudl/Logs/Test/Test-Lancer-2026.07.01_20-19-35--0400.xcresult
```

### Relay approval E2E simulator proof

Command:

```bash
./scripts/validation/relay-approval-e2e.sh
```

Result: FAIL.

Evidence:

- Script log dir: `/tmp/lancer-relay-e2e/`
- XCUITest rc: `65`
- Hook rc: `0`, but **not because of a human approval**
- XCUITest failure:

```text
TapInjectionProofTests.testRelayApprovalUnblocksHostHook()
XCTAssertTrue failed - A relay-delivered escalation should surface an Approve button in the Inbox
```

- Daemon relay log repeatedly showed:

```text
e2e: connect failed: websocket dial:
wss://conduit-push-y4wpy6zeva-ts.a.run.app/ws/relay?role=daemon&code=314159&publicKey=...
bad status
```

- Audit tail showed the hook unblocked via no-client fallback, not relay approval:

```json
{"action":"escalate","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","effect":"ask","rule":"default:ask","approvalId":"bba698f6-a422-4a96-9c37-95ddaa3eab48"}
{"action":"auto-allow-no-client","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","effect":"ask","rule":"default:ask","approvalId":"bba698f6-a422-4a96-9c37-95ddaa3eab48"}
```

Assessment: the relay proof did not prove phone tap -> relay -> daemon. It proved the harness correctly fails when no relay approval reaches the app, but the host-side hook still exits 0 via `auto-allow-no-client`.

## Production backend / APNs readiness

Backend probes:

```bash
curl -i --max-time 20 https://conduit-push-y4wpy6zeva-ts.a.run.app/health
curl -i --max-time 20 https://conduit-push-y4wpy6zeva-ts.a.run.app/register
curl -i --max-time 20 'https://conduit-push-y4wpy6zeva-ts.a.run.app/decisions?sessionId=probe'
```

Result: FAIL. All three returned HTTP 503 from Google Frontend:

```text
Error: Server Error
The service you requested is not available yet. Please try again in 30 seconds.
```

Read-only Cloud Run inspection:

- Project: `roshan-agent-f1c2466d`
- Service: `conduit-push`
- Region: `australia-southeast1`
- URL: `https://conduit-push-y4wpy6zeva-ts.a.run.app`
- Latest ready revision: `conduit-push-00011-jgk`
- Traffic: 100% latest revision
- Service status: Ready=True
- Max scale annotation on template: `autoscaling.knative.dev/maxScale: '1'`

Secret/env refs are present on the service:

```text
APNS_KEY_PATH=/secrets/apns.p8
APNS_BUNDLE_ID=dev.lancer.mobile
APPROVAL_RELAY_SECRET secret ref
APNS_KEY_ID secret ref
APNS_TEAM_ID secret ref
APNS_KEY mounted as /secrets/apns.p8
```

Recent Cloud Run logs identify the platform blocker:

```text
The request failed because billing is disabled for this project.
GET 500 https://conduit-push-y4wpy6zeva-ts.a.run.app/ws/relay?role=phone&code=444591&publicKey=...
```

Assessment: APNs env wiring appears present, but cannot be considered verified because the live backend is unavailable and Cloud Run reports billing disabled for the project.

## Physical device and V1 live loop

Device visibility:

- `xcrun devicectl list devices` sees `Roshan's iPhone` as `available (paired)`.
- `xcodebuild -showdestinations` lists compatible iOS device id `00008150-0001653C26F8401C`.
- `xcrun xctrace list devices` reported physical iPhones offline.

Result: BLOCKED. I did not install to the physical iPhone because the production relay/backend is returning 503; installation would not allow the APNs or relay loop to pass. The physical-device checks remain unproven:

- closed/backgrounded-app APNs approval
- lock-screen Approve/Reject action
- Live Activity push updates
- two-machine real relay pairing and routing

## Multi-machine relay live matrix

Result: BLOCKED by the production backend outage.

Not proven in this run:

- pair machine A and machine B from Settings -> Paired Machines
- approve A and verify only A unblocks
- reject B and verify only B records reject
- simultaneous A/B approvals with no cross-machine routing
- unpair/kill A and verify B remains usable
- 3-machine cap and fourth-pairing cap UI
- visual relay card inside Machines/Fleet with a real active relay machine
- APNs token registration fan-out across active relay machines

What is covered by local tests:

- relay machine ID/record codability
- relay fleet cap helpers
- legacy single-pairing migration paths
- fail-closed approval routing unit tests
- `approvalResponseAck` and `approvalResolved` daemon tests

## Blockers

1. **P0: production Cloud Run backend unavailable.**
   - Public endpoints return HTTP 503.
   - Cloud Run logs show: `The request failed because billing is disabled for this project.`
   - This blocks relay pairing, APNs, lock-screen actions, Live Activity pushes, and live multi-machine routing.

2. **Relay E2E harness can end with hook rc 0 without proving relay approval.**
   - The script correctly failed overall because XCUITest rc was 65.
   - The host hook still returned 0 via `auto-allow-no-client`, so future reports must key success on XCUITest rc plus audit `approve`, not hook rc alone.

3. **Machines/Fleet relay card visual proof is still missing.**
   - Existing debug seam proves Home relay row only.
   - FleetView relay cards need a real relay pairing or an explicit test seam.

## Conclusion

Local source health is good: daemon, push-backend, LancerKit, app-target build/run, and the focused Home relay-host UI test all pass. The full V1 promise is **not verified** in this run because the production Cloud Run relay/backend is unavailable. The next required action is to restore Cloud Run billing/service availability, then rerun `./scripts/validation/relay-approval-e2e.sh` before attempting physical APNs and multi-machine live tests.

## Follow-up: SSH hermes-box real-phone setup

Context: the production backend was intentionally turned off because of cost. The current real-phone test target is the direct SSH path to `hermes-box`, not the production relay/APNs path.

Actions completed:

- Built the current working-tree `lancerd` for Linux ARM64:
  - `cd daemon/lancerd && GOOS=linux GOARCH=arm64 go build -o /tmp/lancerd_linux_arm64 .`
- Copied it to `hermes-box` and installed it at `/home/silvapulle/.lancer/bin/lancerd`.
- Ran `~/.lancer/bin/lancerd install` on `hermes-box`.
- Enabled and started the user systemd service:
  - `systemctl --user enable --now lancerd.service`
- Fixed the state directory mode:
  - `chmod 700 ~/.lancer`
- Put the Lancer shim directory first in new Bash shells by adding it to `~/.bashrc`.
- Installed and launched the signed physical-device app build on `Roshan's iPhone`:
  - `xcrun devicectl device install app --device 00008150-0001653C26F8401C .../Debug-iphoneos/Lancer.app`
  - `xcrun devicectl device process launch --device 00008150-0001653C26F8401C --terminate-existing dev.lancer.mobile`

Host verification:

```text
systemctl --user is-active lancerd.service
active

test -S ~/.lancer/lancerd.sock && echo socket_ok
socket_ok

bash -lc 'type -a claude | sed -n "1,3p"'
claude is /home/silvapulle/.lancer/bin/claude
claude is /home/silvapulle/.local/bin/claude
```

`lancerd doctor` result on `hermes-box`:

```text
Summary: 11 OK, 2 warnings, 0 failures
```

Remaining warnings are expected for the SSH-only setup:

- `policy.yaml absent (default-ask only)` keeps approval testing conservative.
- `relay-pairing.json absent` is expected while the production relay/APNs backend is off.

Current next manual test:

- On the iPhone, add/connect to machine `hermes-box` over SSH as user `silvapulle`.
- Start a Lancer-run Claude session from the app, or open a new shell on `hermes-box` and confirm `claude` resolves to `/home/silvapulle/.lancer/bin/claude` before starting Claude.
- Trigger a mutating tool request and verify the phone receives the approval prompt and the host audit records the decision.

## Follow-up (2026-07-01, evening): relay decision return path fixed — E2E proof now PASSES

Context: after the Cloud Run relay was re-enabled, a debugging session fixed 5 bugs in the
relay approval loop (see `docs/handoff-2026-07-01-relay-decision-return-path.md`) but one
remained: the phone's approve decision never rode back to the daemon — the host hook denied
fail-closed at exactly +120s on every run (`xcodebuild test rc: 0`, `agent-hook rc: 1`,
audit `escalate` → `deny`), 100% reproducible.

### Root cause: approval-ID case mismatch in the phone-side origin-routing map

lancerd generates approval IDs **lowercase** (`newUUID()` → `hex.EncodeToString`,
`daemon/lancerd/hook.go`) and sends that string to the phone, which registers it verbatim as
the key of `ApprovalRelay.approvalMachineMap` (the multi-machine routing map added by
`ffc99368`, via `registerRelayOrigin` in `AppRoot.swift`). But every iOS decision path
forwards `UUID.uuidString`, which Foundation renders **UPPERCASE**. The case-sensitive
dictionary lookup at step 0 of `ApprovalRelay.forwardDecisionOnly` therefore missed on every
decision, so:

1. `E2ERelayBridge.sendDecision` was **never called** (the handoff's leading
   `connectionState` hypothesis is refuted — live logs show `connection=connected
   pairing=paired` at send time once the route matches).
2. The SSH fallback is nil in a relay-only pairing.
3. `postDecisionToBackend` got **HTTP 401** (no valid relay token exists for the isolated
   test daemon — the handoff's suspected second dying path, confirmed live).
4. The queued redelivery entry was tagged `machineID: nil` (the *same* case-miss lookup), so
   `machineBridgeReconnected` could never retry it. The decision was parked forever and the
   daemon's independent 120s fail-closed timeout denied the gate.

The daemon already fixed this exact bug class for its own store (`normID` in
`daemon/lancerd/approval.go` + `approval_case_test.go`, which documents "iOS sends UPPERCASE
`uuidString`"); the phone-side routing map re-introduced it one layer up.

Live evidence (pre-fix, instrumented run; sim os_log, `category == "ApprovalRelay"`):

```text
forwardDecisionOnly: approvalID=F8C34D42-095B-4B9F-9250-19379D681976 decision=approved
  registeredOrigins=[f8c34d42-095b-4b9f-9250-19379d681976] bridges=4
forwardDecisionOnly: NO relay origin registered for approvalID=F8C34D42-… — falling through
postDecisionToBackend: HTTP 401 for approvalID=F8C34D42-…
forwardDecisionOnly: QUEUED approvalID=F8C34D42-… for redelivery (originTag=nil)
```

### Fix

`Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift`: added
`normalizeApprovalID` (trim + lowercase, mirroring Go's `normID`) and applied it at
`registerRelayOrigin`, the `forwardDecisionOnly` routing lookup/removal, the redelivery
queue's origin tag, and `machineBridgeReconnected`'s post-retry cleanup. Also added
permanent `os_log` instrumentation (`ApprovalRelay` + `E2ERelayBridge` categories) covering
every fallback step of the decision path, which previously had none past pairing.

Regression test:
`Packages/LancerKit/Tests/LancerKitTests/ApprovalRelayMultiMachineTests.swift`
(`relayOriginLookupIsCaseInsensitive`) mirrors the daemon's `approval_case_test.go`.

Post-fix live log of the same path (decision delivered in ~425 ms, daemon ack round trip):

```text
forwardDecisionOnly: approvalID=3DF51CFD-… registeredOrigins=[3df51cfd-…] bridges=4
sendDecision: approvalID=3DF51CFD-… decision=approve connection=connected pairing=paired
sendDecision: ack for approvalID=3DF51CFD-… → ok
forwardDecisionOnly: bridge DELIVERED approvalID=3DF51CFD-… to machine=161D7729-…
```

### Verification (all green)

- `cd Packages/LancerKit && swift build && swift test` — 471 tests in 83 suites + 13 tests
  in 2 suites, 0 failures.
- `cd daemon/lancerd && go build -o lancerd . && go vet ./... && go test ./...` — `ok`.
- `./scripts/validation/relay-approval-e2e.sh` — **PASS twice consecutively** (was 100%
  FAIL before the fix). Run 1:

```text
================= RESULT =================
xcodebuild test rc : 0  (0 = APPROVE tapped + card cleared)
agent-hook rc      : 0 (0 = host hook UNBLOCKED via relay approve)
--- audit tail ---
{"timestamp":"2026-07-02T02:58:22Z","action":"escalate","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","effect":"ask","rule":"default:ask","approvalId":"3df51cfd-5c6c-457d-94ae-3bb91d6b4758",…}
{"timestamp":"2026-07-02T02:58:27Z","action":"approve","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","rule":"default:ask","approvalId":"3df51cfd-5c6c-457d-94ae-3bb91d6b4758",…}
>>> PASS: relay approval round-trip proven (phone tap → relay → host unblock).
```

Run 2:

```text
================= RESULT =================
xcodebuild test rc : 0  (0 = APPROVE tapped + card cleared)
agent-hook rc      : 0 (0 = host hook UNBLOCKED via relay approve)
--- audit tail ---
{"timestamp":"2026-07-02T02:59:39Z","action":"escalate","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","effect":"ask","rule":"default:ask","approvalId":"1b4eb355-3c72-4d92-be85-8b3d60000ad6",…}
{"timestamp":"2026-07-02T02:59:44Z","action":"approve","agent":"claudeCode","kind":"fileWrite","command":"/tmp/lancer-relay-e2e/approve-marker.txt","rule":"default:ask","approvalId":"1b4eb355-3c72-4d92-be85-8b3d60000ad6",…}
>>> PASS: relay approval round-trip proven (phone tap → relay → host unblock).
```

The approve now lands ~5 s after escalation (human tap latency), not a +120 s timeout deny.
The "Relay approval E2E simulator proof" FAIL earlier in this report is superseded: the full
phone-tap → relay → daemon → hook-unblock loop is proven in the simulator against the
production Cloud Run relay.

## Follow-up (2026-07-02, morning): first physical-device pairing pass — 2 real bugs found + fixed

Runner: Claude Sonnet 5, physical device (`Roshan's iPhone`, iOS 27.0), against the production
GCP relay (`conduit-push-y4wpy6zeva-ts.a.run.app`, billing re-enabled by the owner).

### Bug 1 — a leftover self-hosted relay was silently absorbing pairing attempts

`hermes-box`'s `conduit-relay.service` (systemd user unit, from Codex's 2026-07-01 pivot testing,
§"Follow-up: SSH hermes-box real-phone setup" above) was still `enabled` and `active`, 15+ hours
after that investigation ended. Separately, the physical device's app had a **Debug-only persisted
relay-URL override** (`Packages/LancerKit/Sources/SSHTransport/RelaySettings.swift`,
`lancer.debug.relayURL` in `UserDefaults`) left over from that same pivot — every normal Home
Screen launch on this device was silently dialing `hermes-box`, not GCP, while the resident
`lancerd` daemon only ever listened on GCP. hermes-box's own log confirmed the phone hitting it
repeatedly (`relay: phone connected with code 332193/851548 ...`) — proof the pairing attempts
were reaching a dead end, not GCP.

**Fix:** `ssh hermes-box 'systemctl --user stop conduit-relay.service && systemctl --user disable
conduit-relay.service'` (service decommissioned; `~/.conduit` data/APNs key left in place,
untouched). Relaunched the app once with `LANCER_RELAY_URL` forced to the GCP URL via
XcodeBuildMCP's `launch_app_device(env:)`, which overwrites the persisted debug key going forward.
Confirmed via `lancerd.stderr.log`: `paired with phone (code: 033519)`.

### Bug 2 — Keychain-persisted machine index survives uninstall, silently hits the 3-machine cap

See `docs/KNOWN_ISSUES.md` §6 for the full writeup (root cause, both symptom screens, and the
code fix in `FleetView.swift` + `E2ERelayPairingView.swift`). Short version: repeated pairing
attempts during this same session (each hitting expired/stale codes before the hermes-box bug was
found) persisted 3 dead `RelayMachineRecord`s to the iOS Keychain — surviving even a full app
uninstall/reinstall — silently maxing out `relayFleetMaxMachines` while the Machines tab rendered
as if nothing were paired at all (active-only empty-state check). Fixed the misleading copy on
both surfaces; the underlying fix for the user was simply removing the 3 stale entries from
Settings → Paired Machines.

### Result: clean pairing achieved

After both fixes, a fresh pairing on the physical device succeeded and stayed stable:

```text
2026/07/02 08:12:14 e2e: connected to relay as daemon (code: 967943)
2026/07/02 08:13:00 e2e: paired with phone (code: 967943)
```

No disconnects since. Next steps on this device: send a prompt, trigger a gated approval, then
the closed/backgrounded-app APNs + lock-screen checks per `lancer-onboarding-smoke`.
