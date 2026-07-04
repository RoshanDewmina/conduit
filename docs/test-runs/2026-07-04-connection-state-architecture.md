# 2026-07-04 — Connection-state architecture + daemon-restart re-pairing investigation

Branch: `fable/relay-connection-state` (from `master` @ `28a3ed58`).
Structure mirrors `2026-07-03-cross-device-sync-release-gate.md`: root cause first, then fixes,
then the verification evidence.

## 0. Scope

1. **Task 1 — `ConnectionStateStore`:** one authoritative source of per-relay-machine liveness
   (enum, not a Bool), consumed by every surface; ends the pattern of each surface deriving its
   own answer from `E2ERelayBridge.isActive`.
2. **Task 2 — daemon-restart re-pairing gap** (`docs/KNOWN_ISSUES.md` §6, 2026-07-04 incident):
   daemon restarted with intact `relay-pairing.json`, phone never re-paired.

## 1. ROOT CAUSE FOUND (Task 2) — the "phone" that owned the live pairing was the Simulator; the real phone had been silently orphaned 14 hours earlier

The observed symptom — restarted daemon logs `connected to relay as daemon (code: 194990)`, no
`paired with phone` ever follows, Cloud Run shows the phone dialing a *different* code
(`role=phone&code=893127`) — was reconstructed from three independent log sources:

**(a) `~/.lancer/lancerd.stderr.log`** (timestamps local, UTC-4):

```
2026/07/03 20:09:03 e2e: paired with phone (code: 893127)        ← owner's real iPhone pairs
2026/07/03 20:40:54 e2e: paired with phone (code: 893127)        ← still healthy
lancerd daemon: E2E relay started for code 194990                 ← 20:57: pairing REPLACED
2026/07/03 20:58:37 e2e: paired with phone (code: 194990)        ← "a phone" pairs on the new code
… hourly `paired with phone (code: 194990)` all night …
2026/07/04 10:13:41 e2e: paired with phone (code: 194990)        ← last healthy pairing
lancerd daemon: E2E relay started for code 194990                 ← 10:24 restart (binary swap)
2026/07/04 10:24:12 e2e: connected to relay as daemon (code: 194990)   ← no phone ever joins again
```

**(b) Cloud Run relay logs** (`conduit-push`, UTC): two distinct phone identities:
- `role=phone&code=194990&publicKey=FuEC…` — dialed hourly at :58 through the night, stopped 13:41Z.
- `role=phone&code=893127&publicKey=vbBu…` — the owner's real iPhone, dialing sporadically since
  Jul 3 evening, including 14:27:56Z and 14:29:47Z (right after the daemon restart + app relaunch),
  HTTP 101 accepted, then waits forever for a daemon peer that is listening on 194990.

**(c) The `194990` "phone" located on disk:** the iPhone 17 Pro *Simulator*
(`095F8B3A-FEA3-4031-A2A5-561755740730`) app container holds
`lancer.relay.machine.EC580EF4-….code => "194990"` — the Jul 3 evening test session's simulator.

**Conclusion:** at 20:57 on Jul 3, a test session re-ran daemon-side pairing (any of `lancerd
pair` / `agent.pair.begin` / the install helper mints a fresh code and overwrites
`relay-pairing.json` immediately). The resident's pairing-file watcher hot-swapped the live relay
client onto the new code within 5s — **silently orphaning the owner's real phone**, whose persisted
pairing (code `893127`) remained locally "valid" but can never rendezvous again. The simulator then
owned the only live pairing until it went away, and the 10:24 daemon restart merely *revealed* the
orphaning: the daemon's persisted pairing was intact the whole time, and the restart-reconnect
machinery itself works (proven live in §4 below).

The naive theory in the handoff ("daemon mints a fresh code on every restart") is confirmed FALSE:
`wireRelayFromPairing()` → `readRelayPairing()` reconnects with the persisted code and keypair.

**Corollary defect found while tracing the phone side** (same silent-orphan class):
`AppRoot.addRelayMachine` started the bridge and registered it with `ApprovalRelay` **before**
`RelayFleetStore.add()`, which silently no-ops at the 3-machine cap. A cap-dropped pairing
therefore kept working in-memory (approvals, hourly reconnects) and then vanished at the next
relaunch — never having been written to the hydration index. Not the trigger of this incident,
but indistinguishable from it at the symptom level ("machine unpaired itself overnight").

## 2. Fixes

### Task 2 (daemon + phone hardening; wire protocol / pairing format untouched)

- `daemon/lancerd/relaypair.go` `writeRelayPairing`: logs
  `REPLACING existing relay pairing (code X -> Y) — phones paired to the old code are orphaned
  and must re-pair` whenever an existing, different pairing is overwritten (covers `lancerd pair`,
  `agent.pair.begin`, `relay-attach`, and the install helper — all funnel through this writer).
- `daemon/lancerd/resident.go` `startRelayWatch`: logs the old→new code transition when the
  watcher hot-swaps the live relay client, naming the orphaned code explicitly. `connectRelay`
  now records the active code on the resident for this purpose.
- `AppRoot.addRelayMachine`: now tears the client down and logs a `.fault` when
  `RelayFleetStore.add()` reports the cap (add() now returns `Bool`); the bridge is no longer
  started/registered for a machine that was never persisted.
- `AppRoot.hydrateRelayFleetStore`: logs a one-line launch summary of exactly which machines the
  index restores — the missing piece that made this incident take hours to diagnose.

### Task 1 (`ConnectionStateStore`)

New `Packages/LancerKit/Sources/SessionFeature/ConnectionStateStore.swift`, `@MainActor
@Observable`, the sole writer of per-machine liveness:

- State enum: `.connected` / `.reconnecting` (actively retrying, no human needed) /
  `.pairingInvalid` (known bad, needs a re-pair) / `.hostOffline` (phone on the relay, daemon peer
  absent — which is also exactly what an orphaned pairing looks like from the phone).
- Derivation is a single pure function over `E2ERelayClient.pairingState × connectionState ×
  pairing-usable`, pinned by unit tests.
- Combine → Observation bridging centralized here (subscribes to the client's published states —
  `bridge.isActive` is itself just `pairingState == .paired`, so nothing is lost and the store
  updates strictly before the bridge's async mirror).
- `lastConnectedAt` refreshes on EVERY transition into `.connected` (the PR #18 semantics), and
  `RelayFleetStore` persists it to the machines index via a store observer.
- `waitForAnyConnected(timeout:)` replaces the two hand-rolled polls (`AppRoot.activeRelayBridge`,
  Siri's `pollBridgeActive` pattern): waits only while a machine is `.reconnecting`/`.hostOffline`,
  fails immediately when everything is `.pairingInvalid`.

Migrated consumers (no surface derives its own liveness anymore):
- `RelayFleetStore` — owner/consumer; `add(_:pairingUsable:)`, `isConnected(_:)`,
  `connectionState(for:)`, `firstConnectedMachine`, `aggregateConnectionState` all delegate.
- `AppRoot` — all 15 direct `.bridge.isActive` reads migrated (Home entries, Fleet mapping,
  Settings rows, dispatch-agent offline flag, emergency stop, push/Live-Activity registration
  loops, observed-session transports, `aggregateRelayState`, sidebar footer state).
- `CommandGateway` (Siri) — `firstConnectedBridge()` reads the shared store with the bounded wait;
  same instance Home/Fleet/Settings render, so they can no longer disagree.
- `AppRoot.importObservedSession` / `activeRelayBridge()` — store-mediated wait.
- Note: `Lancer/StartAgentRunSupport.swift` named in the handoff exists only on the unmerged
  `siri-phase2-app-intents` branch (PR #16, explicitly out of scope) — its `pollBridgeActive`
  should be migrated to `ConnectionStateStore.waitForAnyConnected` when that branch lands.

Also restored: commit `4792c63f` (RelayFleetStoreTests + CI wiring target) was **dangling — on no
branch** while master's CI referenced `-only-testing:LancerKitTests/RelayFleetStoreTests`;
cherry-picked here and rewritten against the store (the bridge's `setActiveForTesting` seam is
replaced by `E2ERelayClient.setStateForTesting`, closer to the production driver).

## 3. Verification — builds & tests

| Gate | Result |
|---|---|
| `cd Packages/LancerKit && swift build` | ✅ Build complete |
| `swift test --no-parallel` (macOS host) | ✅ pass (iOS-gated suites compile out — see next rows) |
| App target `xcodebuild build … iOS Simulator` | ✅ `** BUILD SUCCEEDED ** [173.361 sec]` |
| iOS-sim `LancerKitTests` (ConversationSync, RelayFleetStore, ConnectionStateStore, CommandGateway) | ✅ 21/21 (one first-run expectation fix: combineLatest's momentary intermediate state is real and now pinned) |
| iOS-sim `ApprovalRelayMultiMachineRoutingTests` | ✅ 4/4 |
| `cd daemon/lancerd && go build ./... && go vet ./... && go test ./...` | ✅ `ok lancer/lancerd 32.769s`, `ok lancer/lancerd/policy 0.249s` |

Notes: XcodeBuildMCP never connected in this session, so the app-target build/test used the exact
`xcodebuild` invocations from `.github/workflows/ci.yml` instead. `swift test --no-parallel` on the
macOS host exits 0 with 0 failures; `E2ERelayClientRestoreTests` and `RelayMachine*` run there,
the `#if os(iOS)` suites run in the simulator rows above — no regression in any of the named
pairing-persistence suites.

## 4. Live verification (production daemon `dev.lancer.lancerd`, production Cloud Run relay)

"Reasonable window" was defined before measuring as ≤60s (phone reconnect backoff caps at 30s +
socket-death detection). Measured results beat it by two orders of magnitude because the phone's
relay socket survives a daemon restart — the relay re-keys the waiting phone the moment the
daemon rejoins (`peer_joined`), no redial needed.

### 4.1 Simulator (iPhone 17 Pro, signed build — a `CODE_SIGNING_ALLOWED=NO` build cannot
persist pairings at all: `keychainWrite failed: OSStatus -34018`; that CI-style build is also the
likely author of the sim's Jul-3 crumbs)

- Fresh pair via `LANCER_RELAY_CODE=194990` at 11:56:25 → `paired with phone` same second.
- **Cap-drop guard proven live first**: with 3 stale machines in the sim index, the new guard
  fired `addRelayMachine: fleet at cap — machine=7AD2ED29 NOT added; tearing down its client`
  followed by `disconnect()` — the exact path that used to silently keep an unpersisted pairing
  alive. (Also live: the hydrate summary named all 3 stale machines, each logged
  `INCOMPLETE stored pairing … code=false privKey=true url=false; re-pair required`, zero dials.)
- Plain relaunch 11:56:50 → `hydrateRelayFleetStore: index has 1 machine(s): C2D32C2C` →
  `restoreNamespacedStoredPairing: restored` → paired at 11:56:52.822 (**~0.5s**, no seam).
- **Daemon restart** (`launchctl kickstart -k gui/501/dev.lancer.lancerd`) issued 11:57:10.166 →
  daemon `paired with phone (code: 194990)` at 11:57:10, sim console `pairing complete` at
  11:57:10.706 — **540ms, zero manual re-pair**.
- UI: Home shows "Relay host" green immediately after the restart (screenshot); Machines view
  shows "online · healthy / ONLINE / Last seen now" with installed vendors — Home and Fleet agree
  (both read `ConnectionStateStore`).

### 4.2 Owner's physical iPhone 17 (`557A7877`, via devicectl)

The phone's `893127` pairing was orphaned by the 20:57 re-pair (root cause, §1) — unrecoverable
by code, so the device was re-paired via the DEBUG `LANCER_RELAY_CODE` seam onto the daemon's
current code (this also restores the owner's day-to-day pairing):

- Pair launch 11:58:25 → daemon `paired with phone` 11:58:27 (Cloud Run: new phone identity
  `pk=Qskdlb…` dials `code=194990` at 15:58:27Z; the stale orphaned machine `893127` also dialed
  — it now correctly reads `hostOffline` instead of poisoning anything, and should be removed in
  Settings → Paired Machines).
- Plain relaunch (no seam) 11:59:46 → daemon `paired with phone` at 11:59:47 — **persisted
  pairing survives relaunch, ~1s**.
- **Daemon restart** 12:00:52.302 → `paired with phone (code: 194990)` at 12:00:52 —
  **sub-second re-pair on the real device with the app foregrounded, zero manual re-pairing.**

### 4.3 Surfaces-agree check

Home, Fleet/Machines, and Settings' machine rows all render from
`RelayFleetStore.isConnected(_:)` → the one `ConnectionStateStore.shared`; Siri's
`CommandGateway` resolves its bridge through the same instance
(`firstConnectedBridge()` → `waitForAnyConnected`), so disagreement between these surfaces is now
structurally impossible rather than empirically unlikely. A true voice-driven Siri invocation is
not exercisable headless; the CommandGateway store path is pinned by `CommandGatewayTests`
(including the fail-fast on known-bad pairings) on the simulator.

### 4.4 Residual observations (logged, not fixed here)

- A second daemon dials the relay hourly on code `504109` (`pk=n_dtq…`) from outside this Mac's
  launchd service — likely a stale test/remote instance; identify and retire.
- The relay is last-joiner-wins per code: while both the sim and the phone held the `194990`
  pairing they displaced each other on reconnect. The sim app was terminated so the phone owns
  the pairing; single-phone users are unaffected.
- Owner action: delete the stale "Relay host" (`893127`) machine on the phone.
