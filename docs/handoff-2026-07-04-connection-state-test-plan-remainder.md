# Handoff: remaining items from the connection-state test plan (2026-07-04)

**Context:** `/Users/roshansilva/Downloads/lancer-test-plan-and-architecture-review.md` was a
5-agent research report proposing an exhaustive test plan + a `ConnectionStateStore`
architecture refactor for Lancer's relay connectivity bugs. A fresh code survey found 2 of
its 7 claimed bugs were already fixed by a merged PR (`c9b86283`/`2c3c51d1`), so the actual
work was scoped down to just the confirmed-open gaps. That scoped work is **done and merged
to `master`**:

- `4792c63f` — `RelayFleetStoreTests.swift` regression test (bridge-reconnect observation)
- `33d77253` — bounded retry in `ConversationSyncCoordinator` before `.hostOffline`
- `2583dc0f`, `2bd3f3d8` — cleanup/plan doc
- `d576998b` — wired `RelayFleetStoreTests` into CI (it was silently not running)

Plan file: `docs/superpowers/plans/2026-07-04-connection-state-confirmed-fixes.md`

What follows is the report's remaining scope, **not yet built**, ranked by size. Each item
has a self-contained prompt you can hand to Fable directly — no need to re-explain context,
just paste the prompt.

---

## 1. (Real, still-open) UI doesn't distinguish "needs re-pair" from "paired, host offline"

`docs/KNOWN_ISSUES.md:302` names this directly: the connectivity dot only has "connected" vs
"disconnected" — it doesn't tell the user WHY a machine is disconnected (invalid pairing vs.
host genuinely offline vs. reconnecting). This is the smallest, most concrete leftover gap and
doesn't require the full `ConnectionStateStore` refactor to fix narrowly.

**Prompt for Fable:**
> In the Lancer iOS repo, `RelayFleetStore.aggregateConnectionState` (`Packages/LancerKit/Sources/AppFeature/RelayFleetStore.swift:140-143`) only derives `.offline`/`.connecting`/`.relayPaired` — three states — from `bridge.isActive: Bool`. `E2ERelayClient.PairingState` (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift:38-52`) already has a richer `.unpaired/.waitingForPeer/.paired/.pairingFailed(String)` enum, and `E2ERelayClient.ConnectionState` (same file, lines 22-36) has `.disconnected/.connecting/.connected/.reconnecting(attempt:)`. Add a per-machine computed property (or a new field on `RelayFleetStore.Machine`) that surfaces "needs re-pair" (derived from `client.pairingState == .pairingFailed` or an invalid/missing stored pairing) as a DISTINCT UI state from "paired but host currently offline" (derived from `client.connectionState`). Wire it into wherever the Home/Fleet/Settings connectivity dot is rendered (grep for `aggregateConnectionState` and `RelayMachineRow`/`RelayHomeEntry` usages) so a re-pair-needed machine shows a different color/icon/copy than a merely-offline one. Write a `RelayFleetStoreTests.swift` regression test for the new distinction (that file/pattern already exists — follow its `@MainActor @Suite` + in-memory-Keychain-isolation style). Verify with `cd Packages/LancerKit && swift build && swift test`, plus the iOS-simulator run for the `#if os(iOS)`-gated suite (see `.github/workflows/ci.yml`'s `lancer-app` job for the exact command). Do NOT touch `ConversationSyncCoordinator.swift` or the retry logic added in commit 33d77253 — out of scope for this change.

---

## 2. Fault-injection test harness (report's original section 2) — partially superseded

The report wanted `FakeConversationTransport`/`FakeRelayBridge`/a pure `isFresh(...)` freshness
function. Two of those are now moot or already covered:
- `ConversationSyncCoordinatorTests.swift`'s existing `makeTransport(...)` closure helper
  already IS the fake transport — no new file needed, already used by the retry tests in
  commit `33d77253`.
- The report's Siri "10-minute freshness" heuristic **does not exist in the current
  codebase** — a code survey (2026-07-04) grepped for `freshness`/`isStale`/`600` and found
  nothing; `CommandGateway` reads `bridge.isActive` live, not a persisted timestamp. Do NOT
  build `SiriConnectivityFreshnessTests` against a heuristic that isn't there — verify first.

The one still-real gap: **no fake/scripted `E2ERelayBridge` double exists** for driving
reconnect-race scenarios in a UI test (report's bug #5, "one-shot bridge-liveness check racing
a fresh reconnect"). Task 1 of the merged plan added a narrow `#if DEBUG` `setActiveForTesting`
seam on the real `E2ERelayBridge` for exactly this — it may already be sufficient; check before
building a separate fake class.

**Prompt for Fable:**
> In the Lancer iOS repo, before writing any new test infrastructure: (1) confirm via `grep -rn "freshness\|isStale\|lastConnectedAt" Packages/LancerKit/Sources/SessionFeature/CommandGateway.swift` that Siri's connectivity check still reads `bridge.isActive` live (not a persisted timestamp) — if that's still true, there is no "Siri freshness" bug to test, skip that entirely. (2) Look at `E2ERelayBridge.setActiveForTesting(_:)` (added in commit `4792c63f`, `#if DEBUG`-gated in `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`) and `RelayFleetStoreTests.swift` for the pattern of driving a scripted reconnect sequence without a live relay. If a reconnect-race scenario needs testing at the UI/XCUITest layer (not just the `RelayFleetStore` unit level already covered), extend that same DEBUG seam rather than building a parallel fake bridge class — this codebase avoids mocking frameworks, real objects with test seams are the established pattern (see `E2ERelayClientRestoreTests` in `RelayMachineTests.swift` for another example of this style).

---

## 3. XCUITest scenarios (report's section 3) — nothing built yet, largest remaining item

The report lists 8 workflows × several scenarios each (onboarding/pairing, new-chat dispatch,
follow-up/continue, approvals, observed-session import, Siri intents, notifications/Live
Activity, settings/trust) — none of these XCUITests exist today. This is genuinely large (a
full UI-automation suite), needs a booted simulator per run, and touches many screens. Not
something to grind through under a background loop — it needs its own scoped plan and
probably its own dedicated session.

**Prompt for Fable:**
> In the Lancer iOS repo, read `/Users/roshansilva/Downloads/lancer-test-plan-and-architecture-review.md` section "3. XCUITest scenarios by workflow" (the 🖥/📱-tagged bullet list). None of these XCUITests exist in the repo yet — confirm via `find . -path '*LancerUITests*' -name '*.swift'` and grep for existing scenario names first, since some UI test infra may already partially exist. Pick ONE workflow at a time (start with "Onboarding/pairing" — it's the most self-contained and highest-value: empty-code rejection is a direct regression test for the 2026-07-03 "permanent orange dot" bug). Use the `.claude/rules/ios-ui-and-gallery.md` DEBUG launch seams (`LANCER_DESTINATION`, `LANCER_SEED_DEMO`, `LANCER_FAKE_RELAY_HOST`) documented in that file to reach each screen deterministically rather than driving the full live pairing flow in every test. Write ONE new XCUITest file per workflow (don't try to do all 8 in one PR), verify via `mcp__XcodeBuildMCP__*` build/test tools per `CLAUDE.md`'s MCP tooling table, and check in incrementally. This is intentionally NOT scoped as a single task — treat each workflow bullet as its own follow-up request.

---

## 4. Physical-device-only matrix (report's section 4) — needs a real device, not automatable here

Real APNs delivery, real Siri speech recognition, two-device CloudKit/relay sync timing,
TestFlight/StoreKit sandbox purchase — cannot be done in CI or simulator. The report's
"minimum automatable-on-device pass" (extending `PhysicalDeviceCrossDeviceSyncTests.swift`)
is worth doing but requires an actual iPhone connected and is a "run before each release
candidate" cadence item, not continuous work.

**Prompt for Fable (only when a physical device is available):**
> In the Lancer iOS repo, read `/Users/roshansilva/Downloads/lancer-test-plan-and-architecture-review.md` section "4. Physical-device-only matrix". Extend `LancerUITests/PhysicalDeviceCrossDeviceSyncTests.swift` per that section's "Minimum automatable-on-device pass" paragraph: assert the connectivity dot matches ground truth after a forced daemon restart, a scripted `devicectl` launch + device-side APNs trigger via a debug endpoint, and an XCUITest driving the Siri intent's confirmation-sheet UI (not the voice pipeline). This needs a physical iPhone connected via `XcodeBuildMCP`'s physical-device build/test + LLDB tools (see `CLAUDE.md`'s MCP table) — do not attempt on simulator.

---

## 5. Full `ConnectionStateStore` architecture consolidation — explicitly deferred by owner decision

The report's headline recommendation (replace `E2ERelayBridge.isActive: Bool` with a richer
enum consumed uniformly everywhere) was explicitly scoped OUT of the 2026-07-04 work by the
owner's decision, after a code survey found the specific Siri-staleness bug it was justified
by doesn't reproduce in current code. It's real (the bridge does collapse a richer
`ConnectionState` down to a bool, losing "reconnecting" vs "pairing invalid" distinctions) but
touches dozens of `guard isActive else {...}` call sites across `E2ERelayBridge.swift` (881
lines) — a ~1-week refactor per the report's own estimate, not a quick follow-up.

**Prompt for Fable (only if/when the owner decides to greenlight this):**
> In the Lancer iOS repo, `E2ERelayBridge.isActive: Bool` (`Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift:14`) is derived from `E2ERelayClient.pairingState` (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift:20`) but collapses that richer `PairingState` enum (`.unpaired/.waitingForPeer/.paired/.pairingFailed(String)`) plus `ConnectionState` (`.disconnected/.connecting/.connected/.reconnecting(attempt:)`) down to a single bool. Every RPC method in that file (`sendDecision`, `sendDispatch`, `relayListDir`, etc. — dozens of call sites) gates with `guard isActive else {...}`. Replace `isActive` with a richer published enum (e.g. `.connected/.reconnecting(attempt: Int)/.pairingInvalid/.hostOffline`) that IS a projection of `pairingState`+`connectionState` rather than a lossy bool, migrate every call site that reads `isActive`, and update `RelayFleetStore.aggregateConnectionState` + any Home/Siri/notification-handler consumer accordingly. This is a large, single-owner refactor — do it on its own branch, keep `isActive` as a computed `Bool` alias during migration if any call site can't be converted in the same pass, and run the FULL test suite (`swift test` + the iOS-simulator suites) after every batch of call-site migrations, not just at the end.

---

## Summary for the owner

Items 1 and 2 are small/medium and safe to hand off as-is. Item 3 is the big one — treat each
workflow as its own request, don't ask Fable to do all 8 in one shot. Item 4 needs you to have
a physical device connected when you ask for it. Item 5 needs an explicit go-ahead since it's
a real architectural change, not a bug fix — flag it for a decision, don't just greenlight it
by default.
