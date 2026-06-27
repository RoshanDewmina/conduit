# Relay Daemon Integration — Audit Report

## Summary

Integrated the resident `lancerd daemon` with the E2E blind relay so a
relay-paired phone gets the full loop: approval requests forwarded over the
relay, decisions returned and applied, and agent dispatch initiated and tracked
over the relay — all without SSH.

## Changes per Part

### Part 1 (Go) — Resident daemon brokers over the relay

**`resident.go`**
- `runDaemon()` now calls `wireRelayFromPairing()` on startup to read
  `relay-pairing.json` and, if present, create the E2E relay client + router on
  the SAME `server` that owns the socket/queue/approvals. This means
  `handleHookWithNotify`'s approval fan-out (existing at line 1039–1041) now
  reaches the relay.
- `connectRelay()` decodes the persisted keypair, creates an
  `e2eRelayClientWithKey`, wires `newE2ERouter(client, core)`, and calls
  `core.setE2ERouter(router)` then `client.start()`.
- `startRelayWatch()` creates a polling file watcher that detects changes to
  `relay-pairing.json` and reconnects the relay client with the new config.
- The existing SSH/attach path is untouched — the relay is an additional
  delivery channel alongside attach/push. `applyDecision` is already idempotent
  (first-decision-wins via the `approvals.resolve` delete-under-lock).
- `clientReachable` already checks `attach != nil` OR `deviceRegistered()`; the
  relay does not change this predicate (the phone is already a push-registered
  device).

**`e2e_router.go`**
- Extracted `relayClient` interface so the router is testable without a live
  WebSocket. Production `*e2eRelayClient` satisfies it.

**`server.go`**
- `emitNotification()` now fans out to `s.e2e.sendRelayNotification(method, params)`
  when the router is active, so `agent.run.output` / `agent.run.status` emitted
  by the dispatcher reach the relay.

### Part 2 — Pairing handoff (relay-pairing.json)

**`relaypair.go`** (new)
- `relayPairConfig` struct with `RelayURL`, `Code`, `PrivateKey`, `PublicKey`.
- `relayPairingPath()` → `~/.lancer/relay-pairing.json`
- `readRelayPairing()` / `writeRelayPairing()` — JSON persistence.
- `relayPairWatcher` — polls the file every 5s using SHA-256 hash comparison,
  fires `onChange` when the content changes.

**`relay_install_helper.go`**
- `printRelayInstructions()` now persists the generated pairing code + keypair to
  `relay-pairing.json` after printing the QR. The private key is kept so the
  resident daemon can connect with the same identity the QR advertised.

**`main.go`**
- Added `lancerd relay-attach <code>` subcommand for manual/managed pairing
  flows. Generates a fresh keypair, writes relay-pairing.json, and advises the
  user to restart or let the daemon auto-detect within 5s.
- Updated usage string.

### Part 3 (Go) — Dispatch over the relay

**`e2e_router.go`**
- Added `agentDispatch` case to `handleMessage()`: unmarshals
  `{agent, cwd, prompt, model?, budgetUSD?}`, calls `server.runDispatch(p)`,
  and sends the `dispatchResult` back over the relay.
- Added `sendRelayNotification()` — wraps JSON-RPC notifications (`agent.run.output`,
  `agent.run.status`) into relay inner messages (`agentRunOutput`, `agentRunStatus`)
  and sends them encrypted through the relay when paired.
- Added `methodToRelayType()` mapping.

### Part 4 (iOS) — Surface the relay-paired daemon as a dispatchable agent

**`E2ERelayMessage.swift`**
- Added `DispatchParams` struct (agent, cwd, prompt, model, budgetUSD).
- Added `RelayInnerEnvelope<T>` generic wrapper.

**`E2ERelayBridge.swift`**
- Added `sendDispatch(agent:cwd:prompt:budgetUSD:model:)` — sends
  `agentDispatch` through the relay and awaits a `dispatchResult` response via
  `CheckedContinuation`.
- Added handling for `dispatchResult`, `agentRunOutput`, `agentRunStatus` in
  `handleRelayMessage()`.

**`AppRoot.swift`**
- `dispatchAgents()`: when `e2eBridge?.isActive == true`, appends a "Relay Agent"
  dispatchable with id `relay|opencode`.
- `performDispatch()`: routes `relay|*` agent IDs through the bridge's
  `sendDispatch()` instead of `slot.channel.dispatchAgent()`. The existing SSH
  dispatch path is unchanged.

## Pairing-code handoff design

```
lancerd pair (or relay-attach)
  │
  ├── generates X25519 keypair + 6-digit code
  ├── prints ANSI QR (existing behavior)
  └── writes ~/.lancer/relay-pairing.json
        { relayURL, code, privateKey, publicKey }

lancerd daemon (startup)
  │
  ├── reads relay-pairing.json
  ├── creates e2eRelayClient(relayURL, code, persistedKeypair)
  ├── creates e2eRouter(client, server)
  ├── server.setE2ERouter(router)
  └── client.start() → connects to relay WebSocket

Phone:
  │
  ├── scans QR (gets relayURL + code + daemonPubKey)
  ├── connects to relay with own keypair + same code
  └── derives session key (X25519 ECDH + HKDF-SHA256, §4 of PAIRING_PROTOCOL.md)

Change detection:
  ── relayPairWatcher polls relay-pairing.json every 5s
     on change: stops old client, creates new one with updated config
```

## Files changed

| File | Change |
|------|--------|
| `daemon/lancerd/relaypair.go` | **NEW** — pairing config persistence + watcher |
| `daemon/lancerd/resident.go` | Modified — E2E relay wire-up in runDaemon |
| `daemon/lancerd/main.go` | Modified — added relay-attach, updated usage |
| `daemon/lancerd/relay_install_helper.go` | Modified — persist pairing after QR |
| `daemon/lancerd/e2e_router.go` | Modified — agentDispatch handler, relay notification, relayClient interface |
| `daemon/lancerd/e2e_client.go` | Modified — newE2ERelayClientWithKey constructor |
| `daemon/lancerd/server.go` | Modified — emitNotification fans out to relay |
| `daemon/lancerd/e2e_router_test.go` | **NEW** — tests for agentDispatch, relay notifications, pairing persistence, watcher, resident wiring |
| `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift` | Modified — added DispatchParams + RelayInnerEnvelope |
| `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift` | Modified — sendDispatch + dispatch message handlers |
| `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` | Modified — relay agent in dispatchAgents, relay route in performDispatch |

## Test results

```
daemon/lancerd$ go build ./...                    ✓
daemon/lancerd$ go test ./... -count=1 -timeout 120s   ✓ (21.9s)
daemon/push-backend$ go build ./...                 ✓
Packages/LancerKit$ swift build                    ✓ (39.5s)
```

Specific new tests:
- `TestE2ERouterDispatch` — agentDispatch with default policy → needsApproval
- `TestE2ERouterDispatchStarted` — agentDispatch with permissive policy → started
- `TestE2ERouterSendRelayNotification` — fan-out messages sent only when paired
- `TestE2ERouterHandleApprovalResponse` — existing approval path still works
- `TestMethodToRelayType` — method→relay-type mapping table
- `TestRelayPairPersistence` — read/write round-trip
- `TestRelayPairWatcher` — file change detection via polling
- `TestResidentRelayWiringNoPanicWithoutPairing` — no crash when no file
- `TestResidentRelayWiring` — router + client created when file exists

## Reviewer deployment / test instructions

### 1. VPS lancerd redeploy

```bash
# On the relay host (VPS):
cd daemon/push-backend
go build -o push-backend ./...
# restart the push-backend service

# On the daemon host (where agents run):
cd daemon/lancerd
go build -o lancerd .
# install + restart lancerd daemon
```

### 2. Live phone pairing

```bash
# On the daemon host:
lancerd pair
# Shows QR code + saves relay-pairing.json
# Daemon auto-detects within 5s and connects to relay

# On iPhone:
# Open Lancer, tap "Relay Pairing", scan the QR
# Phone connects as role=phone with the same pairing code
# Daemon and phone derive shared session key
# Encrypted channel established
```

### 3. Verify approval flow

With the phone paired:
- Agent triggers a hook (PreToolUse) that escalates → phone receives
  `approvalPending` over E2E relay
- Phone responds → `approvalResponse` reaches `server.applyDecision`
- Hook receives the decision and proceeds accordingly

### 4. Verify dispatch flow

```bash
# With phone paired:
# The dispatch button in the iOS app shows "Relay Agent" (non-offline)
# Send a prompt → agentDispatch goes over relay → daemon launches agent
# Output/status streams back as agentRunOutput/agentRunStatus
```

### 5. Known limitations

- The `relay-pairing.json` keypair is ephemeral: `lancerd pair` generates a
  fresh one each time. Long-lived daemon sessions (e.g. a tailscale-hosted VPS)
  should use `lancerd relay-attach <code>` with a code distributed out-of-band.
- File polling (5s) means a relay config change takes up to 5s to auto-detect.
  For faster turnaround, SIGUSR1 or a unix-socket RPC could be added later.
- The iOS relay dispatch only supports the `opencode` agent name for now
  (hardcoded in `AppRoot.dispatchAgents()`). Extend by pulling agent list from
  the daemon's doctor report or a new relay message.
