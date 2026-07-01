# Multi-machine relay support — implementation report

Date: 2026-07-01
Status: implemented, build-verified, simulator-verified for the reachable surfaces; **not yet verified with a real live pairing or on a physical two-machine setup**.

## 1. What this feature does

Before this change, Lancer's E2E relay path supported exactly **one** paired machine at a
time — a single app-wide `E2ERelayClient`/`E2ERelayBridge` pair. Pairing a second machine
silently clobbered the first (same global Keychain/UserDefaults slot, same bridge instance,
same `ApprovalRelay.e2eBridge` reference). This work adds real multi-machine support, capped
at 3 paired machines, matching the existing SSH fleet's cap:

- Pair up to 3 relay machines independently, each with its own namespaced Keychain/UserDefaults
  identity, its own `E2ERelayClient`/`E2ERelayBridge`, and its own live connection state.
- An approval delivered by machine A always routes its decision back to machine A specifically
  — never to whichever relay bridge happens to be connected (fail-closed dict-based routing).
- Home and the Machines/Fleet screen both render every paired machine as its own row/card,
  not a single collapsed "the relay machine" slot.
- Settings gets a real "Paired Machines" list (pair, see connection state, unpair), replacing
  the old single "Relay pairing" screen that could only ever hold one pairing.
- A one-shot migration converts anyone already on the old single-machine pairing into the new
  scheme automatically, with no dual-write period and no data loss.

## 2. Work breakdown (7 lanes, executed via parallel + sequential subagents)

Each lane was independently build/test-verified before the next depended on it. Lanes A–E ran
in parallel (disjoint files); F and G had to be sequential (single-owner, interlocking files).

### Lane 0 — Foundational types
**Files:** `LancerCore/Identifiers.swift`, `LancerCore/RelayMachineRecord.swift` (new),
`SSHTransport/RelayMachineMigration.swift` (new), `SSHTransport/E2ERelayClient.swift`,
`Tests/LancerKitTests/RelayMachineTests.swift` (new, 7 tests)

- `RelayMachineID` — new phantom-typed ID (`TypedID<RelayMachineTag>`), following the exact
  pattern already used for `HostID`/`SessionID`/etc.
- `RelayMachineRecord` — persisted identity: `id`, `displayName`, `pairedAt`, `lastConnectedAt`.
  Plus `relayFleetMaxMachines = 3` and `isRelayFleetFull(count:)` as pure, engine-testable
  free functions.
- `E2ERelayClient` gained a `machineID: RelayMachineID` property and a full namespaced
  persistence API (`persistPairing()`, `hasStoredPairing(machineID:)`,
  `storedPairingCode(machineID:)`, `storedPairingPrivKey(machineID:)`,
  `storedRelayURL(machineID:)`, `deleteStoredPairing(machineID:)`,
  `restoreNamespacedStoredPairing()`), added *alongside* the old singular API (not yet
  removed) so nothing broke mid-flight.
- `RelayMachineMigration.migrateLegacyIfNeeded()` — one-shot, `async`, `@MainActor`: reads the
  three legacy singular keys; if all three are present and the private key decodes as valid
  Curve25519, synthesizes one `RelayMachineRecord`, writes it under the new namespaced scheme
  plus a JSON-encoded machines-index Keychain entry, and deletes the legacy keys. If the legacy
  state is missing or corrupt, it deletes whatever fragments exist and returns `nil` — every
  path ends in a clean, fully-migrated or fully-empty state, never a straddle.

### Lane A — Bridge/routing core
**Files:** `SessionFeature/E2ERelayBridge.swift`, `SessionFeature/ApprovalRelay.swift`

- `E2ERelayBridge` gained a required `machineID: RelayMachineID` (constructor param, no
  default — deliberately forces every call site to know which machine it's bridging). Every
  notification it posts (`lancerE2EApprovalReceived`, `lancerE2EStatusUpdate`,
  `lancerE2ELoopUpdate`, `lancerE2ERunOutput`, `lancerE2ERunStatus`, `lancerE2EToolStart`,
  `lancerE2EArtifact`) now carries `"machineID"` in its `userInfo`, so any listener can tell
  which machine a message came from without inspecting the payload (the daemon's JSON has no
  machine field and never will).
- `ApprovalRelay` gained `relayBridges: [RelayMachineID: E2ERelayBridge]` and
  `registerRelayOrigin(approvalID:machineID:)`. `forwardDecisionOnly` gained a new routing step
  *ahead of* the old singular `e2eBridge` fallback: if an approval was tagged with its origin
  machine and that machine still has a live bridge, the decision goes there and nothing else is
  tried. If either lookup misses — never a relay approval, or the machine was unpaired since —
  it falls straight through to the existing SSH/backend/queue chain. No substitution with a
  different relay ever happens.

### Lane B — `RelayFleetStore`
**File:** `AppFeature/RelayFleetStore.swift` (new)

The live, `@Observable` multi-machine store — the direct analogue of the existing SSH
`FleetStore`. Holds `[Machine]` (each bundling a `RelayMachineRecord` + its own
`E2ERelayClient` + `E2ERelayBridge` + per-machine `installedAgentVendors`), enforces the cap
via `isRelayFleetFull`, and on every `add`/`remove` keeps the on-disk machines-index in sync
via `RelayMachineMigration.writeIndex(...)` so a relaunch sees an accurate list. `remove` tears
down the bridge, disconnects the client, and deletes its namespaced Keychain/UserDefaults
entries — no orphaned credentials survive an unpair.

### Lane C — Pairing UX
**Files:** `SettingsFeature/E2ERelayPairingView.swift`, `SettingsFeature/RelayMachinesListView.swift`
(new), `SettingsFeature/SettingsView.swift`, plus one correctness fix to `SSHTransport/E2ERelayClient.swift`

- **Correctness fix found and fixed here:** `E2ERelayClient.handleMessage`'s `peer_joined` case
  was writing directly to the *legacy global* Keychain/UserDefaults keys on every successful
  pairing — meaning two `E2ERelayClient` instances pairing concurrently would stomp on the exact
  same slot the instant either one paired. Fixed by routing that write through the new
  `persistPairing()` (namespaced by `self.machineID`) instead. This was the one behavioral bug
  that would have made multi-machine pairing silently corrupt itself even with every other lane
  landed correctly.
- `E2ERelayPairingView` rewritten: every presentation now constructs a brand-new, self-contained
  `E2ERelayClient` (fresh random `machineID`) — no more "pair against an app-wide client" mode.
  At the 3-machine cap it shows a disabled state with explanatory copy instead of a pairing form.
  On successful pairing it hands `(client, record)` back via a callback and dismisses; if the
  user backs out before pairing completes, the client disconnects and nothing was ever persisted
  — no partial state.
- New `RelayMachinesListView` — the actual "Paired Machines" surface: a row per machine (name +
  live dot + unpair button) plus a "+ Pair another machine" row. `SettingsView`/`TrustPrivacyView`
  now thread `relayMachines`/`onRelayPaired`/`onRelayUnpair` instead of a single `E2ERelayClient?`.
- **Module-boundary constraint respected:** `SettingsFeature` doesn't depend on `AppFeature` or
  `SessionFeature` (checked against `Package.swift` before designing this), so the pairing
  callback only ever hands back `(E2ERelayClient, RelayMachineRecord)` — plain SSHTransport/
  LancerCore types. Building the actual `E2ERelayBridge`/`RelayFleetStore.Machine` from that pair
  is `AppRoot.swift`'s job (Lane F), which is the one place that can see everything.

### Lane D — Home rendering
**File:** `AppFeature/LancerHomeView.swift`, plus a small addition to `ObservedSessionsCache.swift`

- Replaced the single `relayHostName: String?` / `relayHostConnected: Bool` params with
  `relayMachines: [RelayHomeEntry]` (a small `Sendable` display struct: id/name/connected).
  The machine-list fold that used to special-case exactly one relay host now loops over the
  whole list — N relay machines show up as N rows, each with its own live/connecting dot,
  exactly like N SSH hosts already did.
- Observed-sessions loading became per-host: `loadSessions` changed from a no-arg closure to
  `(String) async -> [ObservedSession]`, fanned out concurrently (via `withTaskGroup`, not a
  sequential loop) across every currently-live host so N machines don't serialize N round-trips.
  `ObservedSessionsCache` gained a dict-keyed `loadByHost`/`saveByHost` pair alongside the
  original flat cache (additive, not a replacement).
- `HomeMachine`/`MachineTreeCard` (the actual card rendering) were deliberately left untouched
  per standing project guidance not to touch that component.

### Lane E — Routing tests
**File:** `Tests/LancerKitTests/ApprovalRelayMultiMachineTests.swift` (new, 3 tests)

Tests the fail-closed property of Lane A's new routing step: an unregistered approval falls
through without hanging; a registered approval whose machine has no bridge falls through; a
registered approval whose machine ID doesn't match the *only* bridge present (two distinct
machine IDs, one bridge) falls through without misrouting to the wrong bridge. Since
`E2ERelayBridge.isActive` can only become `true` via a real WebSocket handshake, the "successful
routing to a live bridge" happy path isn't unit-testable here — that's covered by the live
simulator run and needs a real daemon to fully exercise (see §5).

### Lane F — `AppRoot.swift` integration (the big one)
**Files:** `AppFeature/AppRoot.swift` (~245 insertions / 153 deletions across ~20 call sites),
`SessionFeature/ApprovalRelay.swift` (deleted the now-dead `e2eBridge` property + its fallback
block), `AppFeature/RelayFleetStore.swift` (added `setInstalledAgentVendors`/`updateDisplayName`
mutators), `OnboardingFeature/OnboardingRedesignGalleryView.swift` (onboarding's own pairing step
now hands its freshly-paired machine back via a new `onPaired` callback instead of silently
mutating an app-wide client), `AppFeature/LancerHomeView.swift` (one incidental fix — see below).

This is the lane that actually wires the app together. Highlights:

- Deleted `AppEnvironment.e2eRelayClient` (the single app-wide client) entirely, along with
  `E2ERelayClient.restoreStoredPairing()` (its only caller). Machine hydration is now async,
  driven by `RelayMachineMigration.migrateLegacyIfNeeded()` + `readIndex()` at launch, rebuilding
  a real `E2ERelayClient`/`E2ERelayBridge` pair per persisted record.
- One shared `addRelayMachine(client:record:env:)` helper does all per-machine wiring (build the
  bridge, register it with `ApprovalRelay`, add it to the store, subscribe to its `isActive`
  stream for installed-agent discovery + push-token registration + status-badge aggregation) —
  called from launch hydration, the Settings pairing callback, onboarding's pairing callback,
  and the `LANCER_RELAY_CODE` debug seam. One code path, four callers, instead of four
  near-duplicate implementations.
- The dispatch-agent picker's relay ids changed from `"relay|<agentID>"` to
  `"relay|<machineID>|<agentID>"` so N machines' agents can coexist in the picker without
  colliding — `NewChatTabView`'s existing grouping (`agent.hostID ?? agent.hostName`) already
  handled this generically from an earlier, unrelated redesign, so no changes were needed there.
- Fixed a real, previously-latent bug while doing this: `openWorkspace(for: agent)` used to
  ignore `agent.hostID` entirely and just check a single global relay flag — meaning tapping an
  SSH agent's workspace button could incorrectly show the relay file browser if a relay happened
  to be active. Now it resolves the tapped agent's actual machine.
- **Incidental fix required to get the authoritative build green:** `LancerHomeView`'s
  `loadSessions` closure parameter was missing `@Sendable`, which broke its own internal
  `withTaskGroup` fan-out (added in Lane D). Fixed as part of getting Lane F's build green since
  it blocked the only build that type-checks this code.
- Documented, deliberate interim limitations (all noted inline in code comments): `FleetView`
  still received first-machine-only shaped data at this point (Lane G's job); several
  transport-fallback functions (`loadAgentCommands`, `resumeConversation`'s relay branch,
  `fetchObservedTranscript`, `sendObservedSessionFollowUp`) fall back to "first active relay
  machine" rather than a specific one, since their existing call sites don't carry a machine
  identity — fixing that would be a separate, larger change to those call sites' own signatures.

**Note on process:** this lane hit an account-wide session-usage limit on its first attempt and
returned after ~100 seconds having made no edits at all. It was retried from scratch once the
limit cleared and completed successfully the second time — flagging this because it's the one
point in this whole effort where a subagent failed outright, and it's worth knowing the first
"Lane F" attempt contributed nothing to the final result.

### Lane G — `FleetView` generalization
**Files:** `AppFeature/FleetView.swift`, one call site in `AppFeature/AppRoot.swift`

Replaced `FleetView`'s last remaining single-machine params (`relayActive`, `relayHostName`,
`relayAgentLabels`, `onOpenRelayChat: (() -> Void)?`) with a `[FleetRelayMachine]` list and an
`onOpenRelayChat: ((RelayMachineID) -> Void)?` callback. The Machines screen now renders one
card per *active* relay machine (`ForEach`) instead of at most one; the header's "focus machine"
name/state (which can only ever show one name) falls back to the first active relay machine,
consistent with how the SSH side already works when nothing is selected.

## 3. Verification performed

### 3.1 Automated (SwiftPM, macOS host)

```
cd Packages/LancerKit && swift build   → Build complete!, 0 errors
cd Packages/LancerKit && swift test    → 471 tests in 83 suites passed
                                        + 13 tests in 2 suites passed (HostServiceClient)
                                        = 484 tests, 0 failures
```

Run independently by me after every lane landed, not just trusted from subagent self-reports.
10 of those 484 tests are new to this feature (7 in `RelayMachineTests.swift`, 3 in
`ApprovalRelayMultiMachineTests.swift`). Caveat carried over from existing project memory: this
macOS host does not execute `#if os(iOS)`-gated test files at all (they're compiled out, not
run) — a pre-existing infrastructure gap, not something introduced or hidden by this feature.

### 3.2 Authoritative iOS app-target build (XcodeBuildMCP)

Every file this feature touches is `#if os(iOS)`-gated, so the SwiftPM build above never
actually type-checks the code that changed. The real gate is the Xcode app-target build against
the `Lancer` scheme:

- Run once after Lane F landed: `build_sim` — **SUCCEEDED, 0 errors, 0 warnings.**
- Run again after Lane G landed: `build_sim` — **SUCCEEDED, 0 errors, 0 warnings.**
- Run a third time by me, independently, via `build_run_sim` before starting simulator
  verification below — **SUCCEEDED** (35.3s), 0 errors, 0 warnings, installed and launched.

### 3.3 Live simulator verification (this session, iPhone 17 Pro / iOS 27 sim)

Screenshots in `screenshots/` alongside this report. Note on scope: this sandboxed environment
has no working input-automation path for this simulator (`idb`'s companion process isn't
reachable — confirmed by directly invoking `ui_tap`/`ui_describe_all` and getting a connection-
refused error against `/tmp/idb/<udid>_companion.sock`; there's also no windowed target for
mouse-driven computer-use control of Simulator.app in this sandbox). So verification here covers
every screen reachable via the app's existing `#if DEBUG` launch-argument seams
(`LANCER_DESTINATION`, `LANCER_SEED_DEMO`, `LANCER_FAKE_RELAY_HOST` — all pre-existing,
documented in `.claude/rules/ios-ui-and-gallery.md`), not deep interactive tap-throughs. That's
an honest limitation, not a workaround pretending to be full coverage — see §5 for what a real
device/daemon pass would additionally need to prove.

**`01-home-empty-onboarded.jpg`** — cold app state (onboarding already completed on this sim
from a prior run), zero relay machines paired. Home renders "All clear tonight" and a "YOUR
MACHINES → Connect a machine" empty-state row. Confirms `LancerHomeView`'s new `relayMachines:
[RelayHomeEntry] = []` default and the empty-list fold path don't regress the zero-machine case.

**`02-settings-landing.jpg`** — `LANCER_DESTINATION=settings`. Settings renders cleanly:
Policy & Governance, Default autonomy, Policy presets, Enforcement log, Team & roles, Emergency
stop, General/Appearance. (The "Relay pairing" row itself lives further down under a Connection
section not visible without scrolling, which this sandbox's lack of tap/swipe automation
couldn't reach — see the caveat above.) No crash, no error, `settingsDestination`'s newly-
threaded `relayMachines`/`onRelayPaired`/`onRelayUnpair` params construct and render without
issue.

**`03-home-with-relay-machine.jpg`** — `LANCER_SEED_DEMO=1 LANCER_FAKE_RELAY_HOST=Roshans-
MacBook-Pro`. **This is the key visual proof of Lane D's fold logic**: "YOUR MACHINES" now shows
a live row for "Roshans-MacBook-Pro" with a green connected dot and a project count, generated
entirely through the new `RelayHomeEntry`-list path (the debug seam feeds exactly one entry, but
it's flowing through the *same* list-shaped code path that N real paired machines would use —
the old code special-cased a single optional host by name; this renders it by iterating a list
of one).

**`04-machines-ssh-hosts.jpg`** — `LANCER_DESTINATION=machines LANCER_SEED_DEMO=1
LANCER_FAKE_RELAY_HOST=Roshans-MacBook-Pro`. Shows the Machines/Fleet screen rendering 4 demo SSH
hosts correctly (Dev VPS focused in the header, Save Hosts list below) — confirming Lane G's
changes didn't regress the SSH side of `FleetView`. **No relay card appears here, and that's
correct, not a bug**: `LANCER_FAKE_RELAY_HOST` has only ever fed `LancerHomeView` (documented in
`.claude/rules/ios-ui-and-gallery.md` as "Home's machine list renders without a real relay");
it was never wired to `FleetView`, before this feature or after it. Verifying `FleetView`'s new
`FleetRelayMachine` card visually would need either a real live pairing or a temporary seam this
report deliberately didn't add (adding test-only wiring right before finalizing felt like the
wrong tradeoff) — so that specific card rendering is verified by code review + the passing
app-target type-check, not a screenshot. See §5.

**Runtime logs** — checked all three launches' captured runtime logs (`grep -iE
"error|crash|fatal|EXC_BAD"`, filtering the expected benign "prefetch"/"deprecat[ed]" noise):
zero matches across all three. No crash, no uncaught error, on any of the three launches.

## 4. Files changed (complete list)

**New files:**
- `Packages/LancerKit/Sources/LancerCore/RelayMachineRecord.swift`
- `Packages/LancerKit/Sources/SSHTransport/RelayMachineMigration.swift`
- `Packages/LancerKit/Sources/AppFeature/RelayFleetStore.swift`
- `Packages/LancerKit/Sources/SettingsFeature/RelayMachinesListView.swift`
- `Packages/LancerKit/Tests/LancerKitTests/RelayMachineTests.swift`
- `Packages/LancerKit/Tests/LancerKitTests/ApprovalRelayMultiMachineTests.swift`

**Modified files:**
- `Packages/LancerKit/Sources/LancerCore/Identifiers.swift`
- `Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift`
- `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`
- `Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift`
- `Packages/LancerKit/Sources/SettingsFeature/E2ERelayPairingView.swift`
- `Packages/LancerKit/Sources/SettingsFeature/SettingsView.swift`
- `Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift`
- `Packages/LancerKit/Sources/AppFeature/ObservedSessionsCache.swift`
- `Packages/LancerKit/Sources/AppFeature/FleetView.swift`
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
- `Packages/LancerKit/Sources/OnboardingFeature/OnboardingRedesignGalleryView.swift`

No `daemon/lancerd` or `daemon/push-backend` (Go) changes — this is entirely a client-side
multi-machine capability. The existing wire protocol (`agentDispatch`, `approvalResponse`,
`agentStatus`, etc.) already carries no machine identity of its own; that's fine, because every
machine gets its own WebSocket connection/bridge instance, so the *transport* itself
disambiguates machines — no protocol change was needed.

## 5. Known limitations / not yet verified

- **No real live pairing was exercised.** Everything above is build-correctness and
  reachable-screen UI verification. The actual value of this feature — two or three real
  `lancerd` daemons, each paired independently, approvals routing to the right one, one going
  offline without affecting the others — needs a physical device (or at minimum a real relay
  server + real daemon processes) and hasn't been run in this session.
- **`FleetView`'s new relay card is unverified visually** (see §3.3) — code-reviewed and
  type-checked, not screenshotted with an actual card present.
- **Deep Settings navigation (the actual "Paired Machines" list, the pairing code-entry screen,
  the cap-reached state) is unverified visually** — this sandbox has no working tap/swipe path
  to the Simulator in this session (idb companion unreachable; no computer-use window target).
- Several interim "first active relay machine" fallbacks remain by design (see Lane F above) —
  not bugs, but not full multi-machine-aware either. Listed explicitly in code comments at each
  site (`loadAgentCommands`, `resumeConversation`, `fetchObservedTranscript`,
  `sendObservedSessionFollowUp`, `homeDestination`'s `onOpenObservedSession` hostname fallback).
- The push-registration fan-out (`registerPushTokenForActiveTransport` now loops every active
  machine) is code-reviewed but not confirmed against a real APNs token / real push-backend in
  this session.
