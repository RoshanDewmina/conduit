# Security P0 — remaining items (design plan)

Compiled: 2026-07-06  
Scope: items 3 and 4 from the cross-platform security audit. **No code in this doc** — implementation deferred to a dedicated session.

Related fixes landed in the same worktree branch:

- **BiometricGate fail-closed** — `Packages/LancerKit/Sources/SecurityKit/BiometricGate.swift`
- **Relay pairing overwrite guard** — `daemon/lancerd/relaypair.go` (fail unless `--force` / RPC `force`)

---

## 3. Emergency Stop — daemon-side atomic primitive

### Problem

`AppRoot.performEmergencyStop()` (`Packages/LancerKit/Sources/AppFeature/AppRoot.swift:1677-1687`) is **client-orchestrated**:

1. Disconnect every connected SSH `SessionViewModel`.
2. For each **connected** relay machine, iterate `runOutputStore.runs` and fire `sendRunControl(runId:, action: "stop")` per non-terminal run.

This is not atomic and has several failure modes:

| Gap | Effect |
|-----|--------|
| **Race with new dispatches** | A run started after the client snapshot is never stopped. |
| **Per-run, per-machine fan-out** | N machines × M runs = N×M relay messages; partial failure leaves agents running with no single success/failure report. |
| **Client-only run inventory** | `runOutputStore` may be stale or empty (cold launch, another device, observed/tmux sessions the phone never tracked). |
| **No local Mac path** | `LancerMac/MenuBarContentView.swift` and `ManagementView.swift` have disabled Emergency Stop TODOs — no `lancerd` RPC exists. |
| **No audit single-event** | Each stop may emit `run-stopped` separately; there is no one tamper-evident “emergency stop invoked” record tying the operator action to all cancellations. |

The daemon already has the right **per-run** primitive: `dispatcher.cancel(runID)` (`daemon/lancerd/dispatch.go:1308`), invoked by relay `agentRunControl` via `server.applyRunControl` (`server.go:456-467`). What's missing is a **fleet-wide, daemon-authoritative** entry point.

### Proposed daemon RPC

Add one JSON-RPC method on the resident control socket (and mirror over E2E relay):

```
agent.emergency.stop
```

**Params (optional):**

```json
{
  "reason": "user-initiated",       // optional string for audit
  "includeObserved": true           // default true: also signal tmux/vendor observed sessions
}
```

**Behavior (single critical section on the daemon):**

1. Acquire `dispatcher.mu` (or a dedicated `emergencyStop` mutex that blocks new `dispatch`/`continue` until step 4 completes — see below).
2. Snapshot all in-flight runs from `dispatcher.runs` where `Status` is `running` or `paused`.
3. For each snapshot entry: `cancel(runID)` (existing kill + audit).
4. Optionally: enumerate active observed/tmux sessions and send SIGTERM / vendor-specific stop (same path `applyRunControl("stop")` uses today).
5. Append **one** hash-chained audit entry, e.g. `action: "emergency-stop"`, `effect: "cancelled"`, `command: "<count> runs"`, `approvalId: "<uuid-of-this-stop-event>"`.
6. Return a structured result:

```json
{
  "stoppedRunIds": ["…"],
  "alreadyTerminal": 2,
  "failed": []
}
```

**Optional hardening (recommended for P0):**

- While emergency stop runs, reject new `agent.dispatch` / `agent.run.continue` with a short-lived `503`/`emergency-stop-in-progress` error (prevents the race in step 1).
- Idempotency: second call within a grace window returns the same result without re-killing.

Relay path: add `agentEmergencyStop` E2E message type (parallel to `agentRunControl`) handled in `e2e_router.go` → `server.emergencyStopAll()`.

### Client changes

| Surface | Change |
|---------|--------|
| **iOS `AppRoot.performEmergencyStop()`** | Replace nested loops with one call: `daemonChannel.emergencyStop()` or `bridge.sendEmergencyStop()` on the active transport. Update UI from returned `stoppedRunIds`; refresh `runOutputStore` from daemon status query. |
| **Watch `PhoneWatchConnector`** | Route `.emergencyStop` to the same RPC (already wired to `onEmergencyStop` — swap implementation). |
| **Siri / `CommandGateway`** | Add intent handler that calls the atomic RPC instead of per-run `sendRunControl`. |
| **LancerMac menu + Management** | Enable buttons; call `HostServiceClient` → `agent.emergency.stop` over the local IPC socket (no relay needed when at the machine). |
| **Settings Emergency Stop row** | Already has `onEmergencyStop` closure — keep, re-point to shared client helper. |

**UX:** Keep a confirmation step on phone (destructive alert); Mac menu can stay one-click per `docs/product/mac-ios-responsibility-matrix.md`.

**Tests:**

- Go: `TestEmergencyStopCancelsAllRunning`, `TestEmergencyStopIdempotent`, `TestDispatchBlockedDuringEmergencyStop` (if hardening included).
- Swift: replace `performEmergencyStop` integration test seam; `ApprovalDecisionAuth`-style unit test with mock channel.

### Why not client-orchestrated iteration?

Emergency stop is a **safety primitive**. The phone is often not the source of truth for which processes are live (observed sessions, runs started from the Mac, runs started after the last status push). Only the daemon holds the authoritative `dispatcher.runs` map and process handles.

---

## 4. Audit hash-chain external anchor

### Current state

`daemon/lancerd/audit.go` implements a local hash chain:

- Each `AuditEntry` stores `prevHash` + `hash` (SHA-256 over canonical JSON payload).
- `Verify()` recomputes the chain from disk — detects tampering **within** the log file.
- **Gap:** An attacker with filesystem access can truncate the log and rebuild a valid chain from an arbitrary genesis. There is no independent tip the owner can compare against.

### Option A — Signed periodic checkpoints to owner-controlled storage (recommended first step)

**Mechanism:**

1. Every N entries (e.g. 100) or every T hours (e.g. 24h), the daemon builds a checkpoint:

   ```json
   {
     "v": 1,
     "tipHash": "<last entry hash>",
     "entryCount": 1234,
     "firstTimestamp": "…",
     "lastTimestamp": "…",
     "daemonId": "<stable host id / relay pubkey fingerprint>"
   }
   ```

2. Sign checkpoint with a **daemon-held Ed25519 key** generated at install (`~/.lancer/audit-anchor.key`, mode `0600`, never leaves host).

3. Publish `(checkpoint, signature)` to one or more anchors the owner controls:

   - **Push-backend** (if account signed in): `POST /v1/devices/{id}/audit-checkpoint` — server stores latest tip per device; phone can display “last anchored tip” in Trust Center.
   - **Optional export file**: `~/.lancer/audit-checkpoints.jsonl` append-only copy for air-gapped verification.

4. Phone / Mac UI: “Verify audit chain” runs local `Verify()` **and** fetches latest anchored tip; mismatch → prominent warning.

| Pros | Cons |
|------|------|
| Small incremental change; reuses existing push-backend device binding | Requires network + backend availability for anchor freshness |
| Owner-visible tip in app without reading Mac filesystem | Compromised daemon could sign a forked chain unless phone occasionally fetches full checkpoint history |
| Fits self-hosted operators (can skip cloud, use local JSONL only) | Key rotation story needed (document re-anchor procedure) |

### Option B — Phone-held tip counter signed on each sync

**Mechanism:**

1. On each successful relay/SSH session, phone sends `audit.tipQuery` → daemon returns `{tipHash, entryCount}`.
2. Phone appends `(tipHash, entryCount, timestamp)` to its own Keychain-backed or GRDB table.
3. On demand, phone compares daemon-reported tip to locally stored history; regression → alert.

| Pros | Cons |
|------|------|
| No new backend endpoint | Phone only sees tips when connected; offline gap |
| Works offline-first after first sync | Malicious daemon could lie consistently if phone never had a prior tip |
| Complements Option A (weak alone, strong together) | Does not help Mac-only / headless daemon operators |

### Recommendation

Ship **Option A** first (signed checkpoints + optional push-backend storage), add **Option B** as defense-in-depth on the phone. Document manual verification:

```bash
lancerd doctor --audit-verify   # local chain
curl …/v1/devices/{id}/audit-checkpoint   # compare tip
```

Do **not** anchor only inside `~/.lancer/` — that shares the same trust boundary as the log being protected.

---

## Relay pairing: why fail-on-overwrite (not multi-slot) in this pass

The phone already supports up to **3 paired machines** (`relayFleetMaxMachines`), but the **daemon** exposes one relay identity (one code + one X25519 keypair in `relay-pairing.json`). The resident maintains a **single** live `e2eRelayClient` watched via `relayPairWatcher`.

Multi-slot on the daemon would require:

- Schema change (`relay-pairings.json` array or directory per slot),
- Resident holding N concurrent relay clients (or multiplexing — not supported by current relay pair-by-code model),
- Operator UX for which code pairs which phone,
- Migration for existing installs.

**Fail-on-overwrite** is smaller and safer: accidental `lancerd pair` during testing cannot silently orphan phones; operators must `rm relay-pairing.json` or pass `--force` / RPC `force: true` and read the stderr orphan warning. Full multi-phone-per-daemon (one code, many phones) remains the intended model — the bug was **silent replacement**, not lack of multiple codes.

Longer-term multi-slot is only needed if the product requires **multiple independent relay channels per host** (e.g. separate codes for prod vs. dev daemons on one Mac). Track as P2 architecture if that surfaces in product requirements.
