# Handoff: V1 relay approval loop — decision return path never unblocks the host hook

## Where this fits

This is a live debugging session started from `docs/test-runs/2026-07-01-v1-full-verification.md`
(a Codex-run V1 verification pass) plus a Claude Code follow-on session that has now found and
fixed **5 real bugs** blocking the V1 governed-approval live loop. **One bug remains** — this
document is everything needed to find and fix it, and to verify the fix is real (not just
"looks plausible").

Read `AGENTS.md` + `CLAUDE.md` first for repo conventions (verification gates, MCP tooling,
skills). This repo's rule: **evidence before "done"** — every claim below is backed by an exact
log line, file:line, or command output. Do the same for your fix.

## What's already fixed today (do not re-investigate these — verified green)

All in the current working tree, uncommitted, on `master`:

1. **iOS double-connect self-own-goal** (`Packages/LancerKit/Sources/AppFeature/AppRoot.swift`,
   `addRelayMachine`): it unconditionally called `client.connect()` again immediately after ANY
   client live-paired (debug seam + 3 real pairing-UI callbacks), because the client's own
   just-persisted credentials made `E2ERelayClient.hasStoredPairing(machineID:)` return `true`
   instantly — tearing down every fresh pairing seconds after it succeeded. **Fixed**: moved that
   reconnect-if-stored-pairing check to only fire from `hydrateRelayFleetStore` (the disk-restore
   path, the only caller that legitimately needs it).
2. **Go daemon reconnect race** (`daemon/lancerd/e2e_client.go`): `stop()` didn't wait for
   `connectLoop()`/`keepaliveLoop()` goroutines to exit before a caller started a new client, and
   `connectLoop()` had zero backoff after a natural `messageLoop()` return (only backed off on
   `connect()` dial failure) — causing a reconnect burst that raced the relay's
   `hub.pairs[code].DaemonConn` pointer. **Fixed**: added `sync.Once` + `sync.WaitGroup` so
   `stop()` blocks until both goroutines exit, plus a 1s backoff after any non-`stop()`
   `messageLoop()` return.
3. **Missing accessibility identifier + wrong test flow**: the Inbox's real row component is
   `InboxBoardCard` (private struct in `Packages/LancerKit/Sources/InboxFeature/InboxView.swift`,
   NOT `InboxApprovalCard` in DesignSystem, which is only used by a chat-transcript inline card
   elsewhere) — it had zero accessibility identifiers. For a medium-risk `fileWrite` escalation
   (what the E2E harness fires), `InboxView.pendingCard`'s `requiresFullReview` logic makes the
   board card's primary button say **"Review"** (not "Approve"), and tapping it opens the detail
   sheet — where the real `approval.approve` identifier lives
   (`Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift`, added earlier
   today). **Fixed**: added `.accessibilityIdentifier("board.primary")` /
   `"board.secondary"` to `InboxBoardCard`'s buttons, and updated
   `LancerUITests/TapInjectionProofTests.swift`'s `testRelayApprovalUnblocksHostHook` to wait for
   `board.primary`, tap it, THEN wait for `approval.approve` inside the opened sheet.
4. **Test harness env gap**: `scripts/validation/relay-approval-e2e.sh`'s isolated test daemon
   didn't inherit `APPROVAL_RELAY_SECRET` (the real launchd-managed daemon at
   `~/.lancer/bin/lancerd` already has it — confirmed via
   `launchctl print gui/$(id -u)/dev.lancer.lancerd`). Without it, the daemon's own
   `postApprovalPush`/token-registration calls to push-backend got HTTP 401. **Fixed**: script
   now does `APPROVAL_RELAY_SECRET="${APPROVAL_RELAY_SECRET:-}" "$LANCERD" daemon ...` — export
   the real secret in your shell before running the script (see Repro below).
5. **Test harness timing**: the script's post-XCUITest hook-wait loop was `seq 1 30` (30s) —
   too short; bumped to `seq 1 150` (150s, past the daemon's own 120s fail-closed timeout) so the
   script always resolves to a definitive PASS or a real `deny`, never "(still blocking)".

With all 5 fixes: `swift build && swift test` (471+13 tests) and
`cd daemon/lancerd && go build -o lancerd . && go vet ./... && go test ./...` are green. The
**forward path is fully proven**: daemon fires escalation → phone receives it → renders the
Inbox board card → XCUITest taps `board.primary` → sheet opens → taps `approval.approve` → local
UI clears the pending card. `xcodebuild test rc: 0` (test PASSES) on every recent run. Pairing is
now clean — exactly **one** `"paired with phone"` log line per run (previously 2-3 rapid
reconnects), confirming fixes #1/#2 actually work.

## The one remaining bug

Despite the phone-side test passing, **the decision never reaches the daemon**. Every run:

```
{"timestamp":"...T02:27:01Z","action":"escalate", ...}
{"timestamp":"...T02:29:01Z","action":"deny", ...}     ← exactly +120s later (fail-closed timeout)
```

`agent-hook rc: 1` (should be `0`). This is reproducible 100% of the time, not flaky — confirmed
across 3 separate runs with the hook-wait extended to 100s and 150s (ruling out "just needs more
time").

### What's been traced so far (read before re-deriving)

The decision-forwarding chokepoint is `ApprovalRelay.forwardDecisionOnly`
(`Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift:176-229`):

```swift
public func forwardDecisionOnly(approvalID: String, decision: Approval.Decision, editedToolInput: String?) async {
    deliveryTracker.recordPost(approvalID: approvalID, decision: decision)
    // 0. Multi-machine relay routing
    if let originMachineID = approvalMachineMap[approvalID],
       let bridge = relayBridges[originMachineID],
       await bridge.sendDecision(approvalID: approvalID, decision: ..., editedToolInput: editedToolInput) {
        approvalMachineMap.removeValue(forKey: approvalID)
        deliveryTracker.recordAcknowledgement(approvalID: approvalID)
        return
    }
    // 2. Fall back to live SSH channel (nil in this relay-only scenario)
    // 3. Fall back to postDecisionToBackend (REST POST to push-backend)
    // 4. Queue for redelivery (terminal state if both above fail — decision is lost until
    //    a reconnect happens, which never occurs before the daemon's own 120s timeout)
}
```

I traced the whole chain and it all looks *structurally* correct:

- `approvalMachineMap[approvalID]` gets populated correctly: `AppRoot.swift:447-463`'s
  `lancerE2EApprovalReceived` notification handler calls
  `ApprovalRelay.shared.registerRelayOrigin(approvalID:machineID:)`, and the notification is
  posted with the right `machineID` key from `E2ERelayBridge.swift:337-341` when an
  `"approvalPending"` message arrives (and we KNOW this arrives — it's how the board card
  renders). `relayBridges[record.id]` is populated in `AppRoot.swift`'s `addRelayMachine`
  (`ApprovalRelay.shared.relayBridges[record.id] = bridge`), using the same ID
  (`client.machineID`) as everywhere else. This routing lookup should succeed.
- `E2ERelayBridge.sendDecision` (`E2ERelayBridge.swift:80-110`) calls
  `try await relayClient.send(type: "approvalResponse", payload: decisionData)`, then waits up to
  5s on a `CheckedContinuation` keyed by `pendingDecisionAcks[approvalID]`, returning `false` if
  no ack arrives in time (or if `send` throws).
- The Go daemon's `handleMessage` for `"approvalResponse"`
  (`daemon/lancerd/e2e_router.go:118-150`) unmarshals the decision, calls
  `r.server.applyDecision(...)`, and **unconditionally** sends back an `"approvalResponseAck"`
  message via `r.client.sendMessage("approvalResponseAck", ackData)` — this looks complete and
  correct, no early-return path that would skip the ack.
- The Swift side's incoming-message case for `"approvalResponseAck"`
  (`E2ERelayBridge.swift:363-368`) decodes it and resolves the pending continuation — this
  handler exists and looks correctly wired (I was worried it might be missing entirely; it's not).
- **Wire-format check** (the thing I was most suspicious of — a double-wrap mismatch): Go's
  `sendMessage(msgType string, payload []byte)` (`daemon/lancerd/e2e_client.go:297-331`)
  **completely ignores its own `msgType` parameter** — it just encrypts whatever `payload` bytes
  it's given and wraps THAT as `{"type":"message","target":"phone","payload":<encrypted>}`. Since
  the caller (`e2e_router.go:136-148`) already pre-marshals `ackMsg = {"type":
  "approvalResponseAck", "payload": {...}}` into `ackData` and passes THAT as the `payload` param,
  the actual encrypted plaintext the daemon sends IS `{"type":"approvalResponseAck","payload":
  {"approvalID":...,"ok":...}}`. On the Swift side, `E2ERelayClient.handleMessage`'s `case
  "message":` (`E2ERelayClient.swift:441-451`) decrypts the frame, decodes
  `E2EInnerMessageDecoded` to extract `inner.type`, and yields
  `ReceivedMessage(type: inner.type, payload: plaintext)` where **`payload` is the FULL
  plaintext** (not re-sliced) — i.e. still the whole `{"type":...,"payload":{...}}` blob. This
  matches what `E2ERelayBridge`'s cases expect to decode via `RelayInnerEnvelope<T>` (see the
  comment at `E2ERelayBridge.swift:328-332`: "message.payload is the FULL inner plaintext
  {type, payload:{…}} — every case must unwrap RelayInnerEnvelope<T>"). **This same shape is used
  by `"approvalPending"` too, which we KNOW works** (the board card renders). So structurally the
  ack's wire format looks consistent with a working case, not an obvious bug — but I have NOT
  proven this with an actual live decrypted payload dump; only static reading.

### My leading (unverified) hypothesis — start here

`E2ERelayClient.swift` has **two separate state properties** that both get set during
`doConnect()`/pairing but are read independently:

- `pairingState` (line ~19-ish area, `.disconnected → .connecting → .waitingForPeer → .paired`
  or `.pairingFailed`) — used by the UI and by `AppRoot`'s debug-seam `for await state in
  client.$pairingState.values` loop.
- `connectionState` (`@Published public private(set) var connectionState: ConnectionState =
  .disconnected`, line 19) — set to `.connected` at `doConnect():361` right after
  `webSocketTask?.resume()`, reset to `.disconnected` in `handleDisconnect()` (line ~469) and in
  at least one other place (line ~303, ~349).

**Critically, `send(type:payload:)` (line 309-331) gates on `connectionState == .connected`**
(line 313: `guard let ws = webSocketTask, connectionState == .connected else { throw
E2EError.notConnected }`) — **not** on `pairingState == .paired`. If anything resets
`connectionState` to `.disconnected` (or a `.reconnecting(...)` case) between the moment pairing
completes and the moment the user taps Approve — e.g. a spurious `handleDisconnect()` firing on a
brief network blip, OR (given today's other reconnect-churn bugs) some now-fixed-but-maybe-not-
fully-fixed reconnect edge case still flipping this flag — then `send()` throws
`E2EError.notConnected` immediately, `E2ERelayBridge.sendDecision`'s `do { try await
relayClient.send(...) } catch { return false }` returns `false` **without ever reaching the 5s
ack-wait**, `forwardDecisionOnly` falls through to the SSH channel (nil, relay-only setup) then
`postDecisionToBackend` (a REST POST — check `ApprovalRelay.swift:358` `postDecisionToBackend`;
this may ALSO be failing, e.g. needing an account bearer token that doesn't exist in this
debug/relay-only test scenario — you should check this function too, it's a plausible SECOND
place the decision could be silently dying), and finally queues the decision for a redelivery
that never happens before the daemon's independent 120s timeout fires.

**I did not get to verify this hypothesis live** (ran out of investigation time) — you need to:

1. Add temporary (or permanent, if useful) logging right at `E2ERelayBridge.sendDecision`'s
   `do { try await relayClient.send(...) }` — log the thrown error if any, and log
   `relayClient.connectionState` / `relayClient.pairingState` at the moment `sendDecision` is
   called. Also log inside `postDecisionToBackend` whether it's even reached, and what HTTP
   status/error it gets if so.
2. Re-run the live repro (below) and read the phone's `os_log` output — `E2ERelayBridge`/
   `ApprovalRelay` currently have almost NO logging (I could only find `E2ERelayClient` category
   logs in `os_log`; this whole subsystem needs eyes-on instrumentation to see past the point
   where pairing succeeds). Consider adding `Logger(subsystem: "dev.lancer.mobile", category:
   "ApprovalRelay")` (or `"E2ERelayBridge"`) calls at each fallback step in
   `forwardDecisionOnly` and in `sendDecision`, mirroring the existing `E2ERelayClient` logger
   pattern (`E2ERelayClient.swift` uses `Self.logger.info(...)`/`.error(...)` throughout — copy
   that style).
3. If `connectionState` is confirmed stuck/reset at the wrong time: find WHY (what sets it back
   to `.disconnected` between pairing and tap — grep every assignment site, listed above,
   and check whether any of them can fire spuriously post-pairing, e.g. a keepalive ping timeout
   miscounted, or the reconnect-state-machine at line ~481 flipping it even when the connection
   is actually still fine). Fix should very likely be: either (a) make `send()` gate on
   `pairingState == .paired` instead of / in addition to `connectionState == .connected` (since
   pairing is the more meaningful "can I actually send" signal and is already proven reliable), or
   (b) find and fix whatever incorrectly resets `connectionState`.
4. If `connectionState` is NOT the issue (i.e. it's genuinely `.connected` at send time): the bug
   is elsewhere in the ack round trip — add the logging from step 1/2 regardless and follow the
   actual evidence rather than my hypothesis. Also directly check `postDecisionToBackend`
   (`ApprovalRelay.swift:358`+) as an independent fallback path that might also need fixing
   (search for `guard !relayToken.isEmpty` mentioned in a comment at line 329 — if this guard
   fails silently in a relay-only/offline debug scenario, that's the REST fallback's own bug,
   separate from but compounding the primary send-path issue).

## Live reproduction (exact commands — this is how every finding above was produced)

All commands run from `/Users/roshansilva/Documents/command-center`. This hits the REAL
production Cloud Run relay (`wss://conduit-push-y4wpy6zeva-ts.a.run.app`) — that's intentional
and already billing-enabled/running (the user re-enabled it today specifically for this work);
no infra changes needed.

```bash
# One-time per shell: load the real APPROVAL_RELAY_SECRET the launchd daemon already has,
# so the isolated test daemon can authenticate to push-backend the same way.
export APPROVAL_RELAY_SECRET=$(launchctl print gui/$(id -u)/dev.lancer.lancerd 2>&1 | grep "APPROVAL_RELAY_SECRET =>" | awk '{print $3}')
echo "secret loaded: ${#APPROVAL_RELAY_SECRET} chars"   # sanity check, don't print the value

# Full automated E2E (build lancerd, start isolated daemon, run XCUITest, fire escalation,
# wait for hook, print PASS/FAIL with exact evidence):
rm -rf /tmp/lancer-relay-e2e
xcrun simctl uninstall <SIM_UDID> dev.lancer.mobile 2>/dev/null || true   # get UDID: xcrun simctl list devices booted
./scripts/validation/relay-approval-e2e.sh
# Look at the final RESULT block: "xcodebuild test rc" and "agent-hook rc" must BOTH be 0,
# and the audit tail must show an "approve" action (not "deny"), for this to be a real PASS.
```

For deeper live inspection while a run is in flight (or manually, without the XCUITest harness —
useful for iterating on Swift-side logging without a full rebuild+test cycle each time):

```bash
# Manual daemon + relay-attach (same as the script's own setup, standalone):
rm -rf /tmp/lancer-relay-e2e/home && mkdir -p /tmp/lancer-relay-e2e/home/.lancer
cd daemon/lancerd
HOME=/tmp/lancer-relay-e2e/home LANCER_RELAY_URL="wss://conduit-push-y4wpy6zeva-ts.a.run.app" APPROVAL_RELAY_SECRET="$APPROVAL_RELAY_SECRET" ./lancerd daemon > /tmp/lancer-relay-e2e/daemon.log 2>&1 &
sleep 2
HOME=/tmp/lancer-relay-e2e/home LANCER_RELAY_URL="wss://conduit-push-y4wpy6zeva-ts.a.run.app" ./lancerd relay-attach 314159 >/dev/null 2>&1
# wait for "connected to relay as daemon" then "paired with phone" in daemon.log

# Launch the app directly (build once via XcodeBuildMCP build_sim, install, then):
# via XcodeBuildMCP launch_app_sim tool with env:
#   LANCER_RELAY_CODE=314159, LANCER_RELAY_URL=wss://conduit-push-y4wpy6zeva-ts.a.run.app,
#   LANCER_PUSH_BACKEND_URL=https://conduit-push-y4wpy6zeva-ts.a.run.app, LANCER_DESTINATION=inbox
# Dismiss the notification permission alert (tap "Allow") if it appears — it can otherwise sit on
# top of the Inbox and block subsequent taps/screenshots from reflecting real content.

# Fire the escalation manually (from the SAME daemon, a second terminal/call):
HOME=/tmp/lancer-relay-e2e/home ./lancerd agent-hook --agent claudeCode --kind fileWrite \
  --command "/tmp/lancer-relay-e2e/approve-marker.txt" --cwd "/tmp/lancer-relay-e2e" --risk medium &

# Watch the phone's os_log live for whatever new logging you add:
xcrun simctl spawn <SIM_UDID> log stream --predicate 'subsystem == "dev.lancer.mobile"' --style compact --debug --info
# (or `log show --start "<time>" --end "<time>" ...` after the fact, like this session did)

# Check the isolated daemon's audit trail directly:
cat /tmp/lancer-relay-e2e/home/.lancer/audit.log   # "escalate" then either "approve" (fixed!) or "deny" (+120s, still broken)

# Cloud Run relay logs (read-only, already authenticated) — useful to confirm the relay's own
# view of connect/pair/disconnect events, independent of local logs:
gcloud logging read 'resource.type="cloud_run_revision" resource.labels.service_name="conduit-push" AND textPayload:"relay"' \
  --project roshan-agent-f1c2466d --limit 30 --format="value(timestamp,textPayload)" --freshness=15m
```

**Always clean up between attempts** (stale processes/state cause misleading results — this bit
us hard earlier in the session):

```bash
pkill -f "lancer-relay-e2e" 2>/dev/null
rm -rf /tmp/lancer-relay-e2e
xcrun simctl uninstall <SIM_UDID> dev.lancer.mobile 2>/dev/null || true
```

## Verification bar for your fix

1. `cd Packages/LancerKit && swift build && swift test` — must stay green (471+13 tests, 0
   failures/regressions).
2. `cd daemon/lancerd && go build -o lancerd . && go vet ./... && go test ./...` — must stay
   green.
3. **The real test**: run `./scripts/validation/relay-approval-e2e.sh` (with
   `APPROVAL_RELAY_SECRET` exported as shown above) end-to-end and confirm the final RESULT block
   shows `xcodebuild test rc : 0` AND `agent-hook rc : 0`, with the audit tail showing
   `"action":"approve"` (not `"deny"`, not "(still blocking)"). Run it at least twice to confirm
   it's not flaky — this exact failure was 100% reproducible before your fix, so a real fix
   should be 100% passing after, not intermittent.
4. Per this repo's rule (`AGENTS.md`/`CLAUDE.md`): update
   `docs/test-runs/2026-07-01-v1-full-verification.md` with a dated follow-up section
   documenting the root cause and fix, mirroring the format of the existing report and its
   earlier "Follow-up: SSH hermes-box real-phone setup" section. Do not claim "done" without
   pasting the actual passing RESULT block as evidence.

## Do NOT touch

- `scripts/validation/relay-approval-e2e.sh`, `LancerUITests/TapInjectionProofTests.swift`,
  `Packages/LancerKit/Sources/InboxFeature/InboxView.swift`,
  `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` (the `addRelayMachine`/
  `hydrateRelayFleetStore` split), `daemon/lancerd/e2e_client.go`'s `stop()`/`connectLoop()` — all
  already fixed and verified today; re-touching them risks re-introducing bugs #1-5 above. If you
  believe one of them is ALSO implicated in this remaining bug, say so explicitly with evidence
  rather than silently changing it.
- Do not turn the production Cloud Run relay off — the user wants it left running.
