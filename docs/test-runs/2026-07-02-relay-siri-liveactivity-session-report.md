# Session report — relay reliability, Siri/AppIntents, and Live Activity fixes

Date: 2026-07-02
Runner: Claude Sonnet 5, working directly with the owner on physical-device + simulator testing
Branch: `master` (all changes committed directly, no feature branch)

## Executive summary

This session picked up from a prior physical-device V1 verification pass and ran a long,
iterative round of live testing across the governed-approval loop, multi-machine relay pairing,
Siri/App Shortcuts, and Live Activities/Dynamic Island. Nine real, previously-unknown bugs were
found and fixed, each confirmed against live behavior (daemon logs, compiled OS metadata, unified
system logs, or direct visual inspection) rather than assumed fixed from code review alone. Ten
commits landed on `master`. One operator mistake (an accidental pairing-code rotation against the
owner's real daemon instead of an isolated test instance) was made, disclosed immediately, and
repaired within the same turn.

The single most significant fix is §8 (stale-socket decrypt failures) — a race condition that
silently broke every relay message send/receive after any reconnect churn, on both the physical
device and in simulator testing. The most involved investigation was §12 (Siri execution
failures), which uncovered a documented but obscure Apple App Intents platform limitation.

---

## 1. Relay approval-decision routing gap (relay-only pairings never got their auth token)

**Symptom:** Approvals sent from the phone were not reliably reaching the daemon; some resolved
via the daemon's 120-second fail-closed timeout instead of the user's actual tap.

**Root cause:** `ApprovalRelay`'s decision-delivery path (`forwardDecisionOnly`) has a fallback
chain: per-machine relay bridge → SSH channel → backend REST POST → local redelivery queue. For a
relay-only pairing (no SSH host — the actual V1-primary configuration), the SSH fallback is always
nil, so recovery depends entirely on the REST fallback, which requires `ApprovalRelay.relayToken`
to be non-empty (`Authorization: Bearer` header). Tracing every call site of `setRelayToken`
showed it was **only ever set from the SSH-connect handshake** — the relay-only path's daemon
message (`deviceRegister`) was fire-and-forget on the Go side and never sent the token back to the
phone. Result: on any relay-only pairing, `relayToken` stayed empty for the process lifetime, so
the moment the primary WebSocket send had any hiccup (very plausible given the session's many
manual re-pair/unpair cycles), the decision silently parked in the local queue with zero working
fallback, and the daemon's independent 120-second timeout won every time.

**Fix:**
- `daemon/lancerd/e2e_router.go` — `deviceRegister` handler now replies with a new
  `deviceRegistered` message carrying `relayToken`.
- `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift` — added `DeviceRegisteredData` +
  `.deviceRegistered` case to the wire-message enum.
- `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift` — new `"deviceRegistered"` case
  in `handleRelayMessage` calls `approvalRelay.setRelayToken(...)`.

## 2. Approval timeout should pause, not auto-deny (owner directive)

**Ask:** The owner explicitly requested that a pending approval the user hasn't yet answered
should keep waiting indefinitely, not auto-deny after 120 seconds — the 120s fail-closed timeout
was originally meant only for "nobody could ever possibly answer," not "the human just hasn't
answered yet."

**Fix (`daemon/lancerd/server.go`, `handleHookWithNotify`):**
- Removed the `approvalTimeout = 120 * time.Second` constant and its associated
  `waitWithTimeout(decisionCh, approvalTimeout)` + auto-deny branch for the **reachable-client**
  path. That path now blocks on the decision channel with no timeout at all.
- Removed the fixed `conn.SetDeadline(time.Now().Add(130 * time.Second))` connection deadline for
  the same reason — leaving it in place would have silently reintroduced the same cutoff via a
  socket-level I/O error instead of the removed application-level timer.
- **Explicitly preserved, unchanged:** the separate "no reachable client at all" path
  (`clientReachable != nil && !clientReachable()`), which still fails open (auto-approve) after an
  8-second grace (`noClientGrace`) — this is a different scenario (nobody could ever answer) and
  was correctly left alone.
- `daemon/lancerd/hook.go` (`runAgentHook`) — the `lancerd agent-hook` CLI itself had its own,
  independent client-side socket deadline (`--timeout` defaulting to 120s, applied as
  `*timeout + 10s`) that would have silently reintroduced the exact same cutoff even after the
  server-side fix. Changed the default to `0` ("wait indefinitely"), only applying a deadline when
  a caller explicitly passes `--timeout > 0`.
- Test changes: deleted `TestApprovalTimeoutSendsResolvedNotification` (asserted the now-removed
  behavior); added `TestApprovalNeverAutoDeniesReachableClient` (proves the hook blocks
  indefinitely, still-pending 200ms in, until an explicit decision arrives).

**Verified:** `go build ./... && go vet ./... && go test ./... -count=1` — 233 subtests, 0
failures, including the new regression test.

## 3. In-chat instant approval widget (visibility problem, not a routing bug)

**Symptom:** The owner reported no clear, fast way to see and act on a pending approval from
inside an active chat thread — approvals were only reliably visible via the separate Inbox tab or
a delayed push notification.

**Root cause (confirmed, not assumed):** The inline approval card in `NewChatTabView` already
existed and routed through the correct `decisionSink → ApprovalRelay.forwardDecisionOnly` path, but
had two real bugs:
1. `isAwaitingApproval` only flipped true from a **synchronous** dispatch/continueRun
   `"needsApproval"` reply — a **mid-run PreToolUse-hook escalation** (which arrives asynchronously,
   via relay push into `inboxViewModel.approvals`, with no synchronous reply involved at all) never
   set it, so the card never appeared for that (very common) case.
2. The view's `else if` branch chain checked "has this run produced output yet" *before* checking
   for a pending approval, so once a run streamed any content at all (the normal case), the branch
   that would show the card became unreachable.

**Fix (`Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`):** Added
`pendingApprovalCount` + `.onChange(..., initial: true)` to catch async escalations regardless of
how they arrived; restructured the assistant-turn view to check for a pending/denied approval
unconditionally and append the card below existing streamed output instead of being excluded by it.

## 4. Push notification taps opened the wrong screen

**Symptom:** Tapping an approval push notification's body deep-linked to the generic Inbox list
regardless of which specific approval or thread it was about.

**Fix (`Packages/LancerKit/Sources/AppFeature/AppRoot.swift`, `.lancerOpenApproval` handler):** Now
looks up the approval by ID in `activeInboxViewModel.approvals`, resolves its owning conversation
via `FleetThreadMapper.findConversation`, and navigates directly to that thread (where the in-chat
approval card from §3 lives) — falling back to the generic Inbox only if no matching thread is
found. Inbox itself is unchanged and still the place to browse all pending/past approvals.

## 5. Multi-machine pairing: rename feature + two rounds of a Home/Machines collapse bug

**5.1 — No way to rename a paired machine.** Every newly-paired relay machine defaults to the
identical display name "Relay host" until renamed, but there was no rename affordance anywhere in
the app. Added a pencil-icon + alert-based rename flow to `RelayMachinesListView`
(`Packages/LancerKit/Sources/SettingsFeature/RelayMachinesListView.swift`), persisted via
`RelayFleetStore.updateDisplayName` — which itself needed a fix, since it wasn't writing the
Keychain-backed machines index at all before this change (a programmatic rename wouldn't have
survived relaunch).

**5.2 — Home showed 2 machines as 1 card (round 1).** `LancerHomeView`'s machine list grouped
hosts into a plain `Set<String>` keyed by display name. Two distinct relay machines sharing the
identical default name ("Relay host") silently collapsed into a single Home card, even though the
Machines tab (keyed by `RelayMachineID`) correctly showed both as separate entries — a real,
user-visible divergence between two surfaces showing the same underlying data, discovered live
while testing multi-machine pairing. First fix: rows keyed by `RelayMachineID` when a relay
identity exists, falling back to name-keying only for SSH/thread-history hosts (no separate
machine identity) or the *first* relay machine to report an already-known name.

**5.3 — Home showed 2 machines as 1 card (round 2, a bug in the round-1 fix itself).** The first
fix's fold-in logic only prevented a *second* relay machine from merging into an *earlier relay
row* of the same name — it didn't account for a name that already existed as an SSH/thread-history
host **before any relay entry was processed at all**. Confirmed live: after renaming attempts, two
machines still both defaulting to "Relay host" continued to merge into that pre-existing row.
Fixed by tracking relay-claimed names separately from the initial SSH-host name set, so only the
genuinely first relay machine to claim a name folds in — every subsequent one gets its own row
regardless of what pre-existed.

## 6. Cross-device cwd normalization (project/session identity bug)

**Symptom:** Discovered while designing a "projects/workspaces" concept — a phone-dispatched chat
and a terminal session in the exact same real directory would silently fail to group or continue
as the same project.

**Root cause:** A fresh relay dispatch's `cwd` defaults to the literal string `"~"`
(`AppRoot.dispatchAgents()`). This is only ever expanded to a real absolute path by the daemon's
`expandHome` (`daemon/lancerd/dispatch.go`), and only for that process's own launch directory — the
resolved value was never sent back to the phone, so the raw `"~"` is what got persisted into
`ChatConversation.cwd`. Terminal/observed sessions, by contrast, always carry a real absolute path
straight from the vendor CLI's own transcript. Since `FleetThreadMapper`/`LancerHomeView` compare
cwd values by plain string equality, and there is no path-normalization utility anywhere in the
codebase, these two representations of "the same real directory" never matched.

**Fix:**
- `daemon/lancerd/dispatch.go` — `dispatchResult` (the Go struct returned by `agent.dispatch`) gained
  a `CWD` field, populated with `expandHome(p.CWD)` on a successful "started" result.
- `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift` — matching optional `cwd` field
  added to the Swift `DispatchResult` (backward compatible: `nil` when talking to an older daemon).
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — `ActiveChatRun` gained a `cwd` field;
  every construction site (fresh relay dispatch, fresh SSH dispatch, follow-up continue, resumed-
  from-history) now threads through `result.cwd ?? <original value>`.
- `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift` — `createConversation` now persists
  `run.cwd` (the daemon-resolved value), not the raw local `cwd` variable.

This was a genuine prerequisite finding surfaced by planning work, not something hunted for
directly — flagged as a "prerequisite, not a nice-to-have" in the design doc (§7 below) before being
fixed the same session.

## 7. Projects/workspaces design doc

Dispatched a background research agent to produce `docs/design/projects-workspaces-concept.md` —
a full design document for an explicit "project" concept (today, a project is purely implicit: a
directory that chat threads happen to share). Core decision: **path is the canonical identity, a
display name is a cosmetic overlay** — mirroring how machine names now work (§5), reusing the same
per-machine, user-renameable UX pattern without literally reusing Keychain-blob storage.

The doc surfaced two things that needed a real decision, both resolved same-session rather than
left open:
1. **The cwd-normalization bug (§6 above)** — found by the design agent while grounding the doc
   in actual current code, fixed immediately since it's foundational to any project concept.
2. **Storage layer for project records** — the design agent flagged that literally copying the
   machine-record pattern (Keychain, single blob, full re-serialize on every write) would create a
   real write-amplification/race risk once auto-create-on-every-cwd removes the human pacing that
   keeps the 3-machine index's churn low today. Decided: project records will live in GRDB/SQLite
   (the same store `ChatConversationRepository` already uses), keyed by `(machineID,
   normalizedPath)` with a real `UPDATE ... WHERE` — not Keychain. No secret material is involved,
   so Keychain's only justification (co-locating with `E2ERelayClient`'s actual pairing keys) does
   not apply to project records. This is a decision recorded for whoever implements the feature
   next — no project-record code was written this session, only the design doc.

This design work has not yet been implemented in code (deliberately out of scope for this session
beyond the cwd-normalization prerequisite fix).

## 8. CommandGateway + 5 new Siri AppIntents (merged from a background worktree)

A background agent (working in an isolated git worktree, per the repo's parallel-work convention)
built:
- **`CommandGateway`** (`Packages/LancerKit/Sources/SessionFeature/CommandGateway.swift`) — a
  single UI-independent entry point for run-control (pause/resume/cancel) and status queries,
  usable from contexts with no live view model in scope (chiefly AppIntents). Fixes a real,
  separately-confirmed gap: `agent.pause`/`resume`/`cancel`/`status` previously only worked over
  legacy SSH — silently no-op for a relay-only phone, V1's actual primary transport.
- New relay message types (`runControl`/`statusQuery`) so the E2E relay can carry these existing
  daemon RPCs — no new daemon business logic, just a second transport for RPCs that already worked
  over SSH.
- 5 new AppIntents, deliberately narrow per an earlier product/security decision (approve must
  never be voice-triggered): `AgentStatusQueryIntent`, `PendingApprovalsQueryIntent`,
  `PauseRunIntent`, `StopRunIntent`, `DenyLatestApprovalIntent`, plus an `AppShortcutsProvider`
  (`LancerAppShortcuts`) registering Siri phrases for exactly these 5 — never for the existing
  `ApprovalActionIntent` (approve/reject).

**Merge-time findings (bugs the background agent's work had, caught during review, not blindly
trusted):**
1. `RunControlIntents.swift` had a genuine compiler error: `Result<String, LocalizedStringResource>`
   — `LocalizedStringResource` does not conform to `Error`. Fixed by replacing the `Result` with a
   plain local enum (`SoleActiveRunResolution`).
2. A `@MainActor`-isolation error: `ActiveRunRegistry.shared` is `@MainActor`-isolated but was read
   from a non-isolated function. Fixed by marking `resolveSoleActiveRun()` and both `perform()`
   methods `@MainActor`.
3. A stale-API bug: `CommandGateway.swift` referenced `ApprovalRelay.e2eBridge` (a single-bridge
   property) — but master's `ApprovalRelay` had been refactored to `relayBridges:
   [RelayMachineID: E2ERelayBridge]` (a multi-machine dictionary) during the same day's earlier
   multi-machine pairing work. The background agent's snapshot of `ApprovalRelay` predated that
   change. Fixed both call sites (`sendRunControl`, `queryStatus`) to use
   `relayBridges.values.first(where: { $0.isActive })`, mirroring the same "first active relay
   machine" fallback pattern already used elsewhere in `AppRoot.swift` for the same reason (no
   machine context reaches an AppIntent).
4. A genuine merge conflict in `E2ERelayBridge.swift` (both master and the worktree branch had
   independently added a new `case` arm to the same `switch` and a new property to the same class)
   — resolved by keeping both additions side-by-side, since they were non-overlapping.

**Verified:** `go build/vet/test` (daemon), `swift build`/`swift test` (LancerKit, 473+ tests), and
the real iOS app-target build via `xcodebuild` (which caught findings #1 and #2 — plain `swift
build` does not type-check `#if os(iOS)` code and would have missed both).

## 9. An operator mistake: accidentally rotated the owner's real daemon pairing

While setting up an isolated test daemon for simulator-only Live Activity testing, a
`lancerd relay-attach <code>` command was run **against the real `~/.lancer` daemon** instead of a
separate, isolated `HOME`-scoped instance — this immediately disconnected the owner's actual
physical-device pairing (confirmed via the daemon log switching from the phone's live code to a
new one within the same second the command ran). This was caught, disclosed to the owner
immediately in the same turn (not glossed over), and repaired by generating a fresh stable code
for the owner to re-pair with. All subsequent test-daemon work was done against a properly
isolated `HOME=~/.lancer-simtest` instance created specifically to prevent a repeat.

## 10. Stale-socket decrypt failures — the connect-generation race (most significant fix)

**Symptom:** Reproduced twice independently — once during the session's own simulator testing,
and separately on the owner's real phone (`"hi"` typed and sent, message never reached the
daemon) — the daemon logged repeated `chacha20poly1305: message authentication failed` immediately
after a **freshly successful** pairing handshake (`"paired with phone"` logged, then decrypt
failures starting seconds later).

**Root cause:** `E2ERelayClient.connect()` already had an idempotent guard (added in an earlier
session) that tears down the prior `webSocketTask` and resets `sessionKey` before starting a new
connection — this protects against a second `connect()` call *reusing* stale state. It does **not**
protect against a message already in flight on the *old, just-cancelled* socket: `URLSession
WebSocketTask.receive`'s completion-handler-based API is not torn down synchronously by
`cancel()`. A message that arrived on a stale socket can still fire its completion handler and hop
back via `Task { @MainActor in ... }` **after** a subsequent `connect()` has already overwritten
`sessionKey` with the new session's key — so the stale callback decrypts an old message using the
wrong (newer) key and fails authentication. This is architecturally indistinguishable from a real
crypto bug from the daemon's side, but is purely a client-side stale-completion-handler race —
most likely to fire under exactly the conditions hit this session: background/foreground churn
(e.g., the system's "Turn on Shortcuts with Siri?" authorization sheet backgrounding the app)
overlapping with a manual or automatic reconnect.

**Fix (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift`):** Added a
`connectGeneration: Int` counter, incremented on every `connect()`, `disconnect()`, and the
internal auto-reconnect-after-disconnect path. `doConnect()` and `listenForMessages()` both now
take an explicit `generation` parameter, captured at the moment they were armed; every receive
callback (both the success and failure/error paths) checks `generation == connectGeneration`
before doing anything and silently drops the message/event if it no longer matches — instead of
touching shared state or firing `handleMessage`/`handleDisconnect`.

**Verified:** `swift build`, `swift test` (LancerKit, all green), and the real iOS app-target
build. Live re-verification: after deploying the fix, the owner confirmed sending a chat message
worked correctly end-to-end on the physical device.

## 11. Live Activities never fired for the app's actual primary use case

**Finding (discovered while investigating how to test Live Activities, not hunted for
separately):** `LancerLiveActivityManager.shared.start(...)` — the call that actually begins a
Live Activity — was only ever invoked from `SessionViewModel.swift`'s legacy SSH-connect flow.
The relay-dispatch flow (`AppRoot.performDispatch`'s relay branch, `NewChatTabView` — the actual
primary V1 transport, since "the phone never holds an SSH session in V1" per
`ARCHITECTURE.md` §0.1) never touched the Live Activity manager at all. Every phone-initiated chat
via the relay — the normal way the app is actually used — was therefore invisible on the Lock
Screen / Dynamic Island, despite Live Activities being otherwise fully implemented and working for
the (secondary, legacy) SSH path.

**Fix (`Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`):**
- Added a `liveActivityKey: String?` state, set once from the *first* dispatched run's ID and
  reused across follow-up turns (each of which mints its own new `runId`) — one chat thread = one
  continuous Live Activity, mirroring how `SessionViewModel` keys its own activity by the whole
  session, not by each individual command run within it.
- On a fresh dispatch success, calls `LancerLiveActivityManager.shared.start(...)`.
- On a follow-up send success, calls `.update(activityKey:status:)` on the **same** key (not a new
  one), so a multi-turn conversation stays one Activity instead of spawning a new one per turn.
- On the run reaching a terminal state (`runIsTerminal`), calls `.end(activityKey:)`.
- Deliberately did *not* duplicate the existing global `updatePendingApprovals` broadcast
  (`AppRoot.swift` ~line 698), which already keeps every active activity's approval count fresh
  app-wide regardless of which view dispatched it.

**Verified:** `swift build`, the real iOS app-target build via `xcodebuild`. Live visual
confirmation was attempted in the simulator but the session ran out of patience with repeated
relay-connection instability from its own rapid test-daemon re-pairing churn (a self-inflicted
test-environment issue, explicitly disclosed as not code-verified) — recommended for the owner to
confirm directly on-device, which is the more reliable environment for this anyway.

## 12. New fast Live Activity testing workflow (Device Hub research + Xcode Previews)

At the owner's request, researched "Device Hub" (Xcode 27's replacement for `Simulator.app`,
confirmed via web search against Bitrise/InfoQ/Appcircle WWDC 2026 coverage — same underlying
simulators, new unified UI, explicitly "designed for agent interaction") and Xcode's native
Live-Activity preview support.

Added proper `#Preview` blocks to `LancerLiveActivityWidget/LancerLiveActivityWidget.swift`:
- Lock Screen, Dynamic Island Expanded, Dynamic Island Compact, Dynamic Island Minimal.
- 7 realistic content states: connected, streaming, needs-approval (1 pending), multiple
  approvals (3 pending), just-approved, reconnecting, over-budget.

This is rendered directly via `mcp__xcode__RenderPreview` against a live Xcode window — no
simulator home screen, lock screen, or notification-center navigation required at all, which was
the owner's explicit ask ("instead of using the janky simulator to go back home").

**Visually confirmed correct** via direct screenshot inspection of the rendered previews:
- Lock Screen: basic "connected" state and "1 pending · $1.18" pending-approval state both render
  correctly.
- Dynamic Island Expanded: the Approve/Reject buttons render correctly with live styling.
- Dynamic Island StandBy variant: renders acceptably (readable, correctly proportioned) — with the
  caveat that Xcode's canvas simulation of StandBy may not fully capture real-device quirks like
  Always-On-Display dimming.

**Visually confirmed a real gap** (leading to §13 below): the Dynamic Island Compact view, when
rendered with the `"Compact (Landscape)"` preview variant, showed the exact same cramped, non-
adapted layout as portrait — the widget had zero special-casing for landscape at the time.

## 13. Landscape Dynamic Island layout fix

Building directly on the new preview-based workflow (§12), dispatched a focused background agent
to fix the confirmed landscape gap.

**API verification (not guessed):** `apple-docs`' index does not yet cover iOS 27/WWDC 2026 APIs
(confirmed via `list_wwdc_years` returning no 2026 entries), so the agent instead grepped the
**actual shipped SDK on this machine** —
`/Applications/Xcode-beta.app/.../iPhoneOS27.0.sdk/.../WidgetKit.swiftmodule/arm64e-apple-
ios.swiftinterface` — and found the real declaration:
```swift
extension EnvironmentValues {
  @available(iOS 27.0, *)
  public var isDynamicIslandLimitedInWidth: Bool { get }
}
```
This is stronger ground truth than a documentation search, since it's the exact SDK this project
actually compiles against.

**Fix (`LancerLiveActivityWidget/LancerLiveActivityWidget.swift`):** Environment values can only be
read from inside a SwiftUI `View`'s body, not a plain function — added a small generic
`DynamicIslandWidthReader<Content: View>` wrapper view that reads
`@Environment(\.isDynamicIslandLimitedInWidth)` and forwards it to a `@ViewBuilder` closure.
`compactTrailingView` now branches on this: in landscape, it renders `EmptyView()` (drops the
numeric/status text badge entirely, relying on the leading status dot's color alone); in portrait,
unchanged behavior (extracted into a new `compactTrailingBadge` helper). `compactLeadingView`, the
Expanded region, Minimal view, Lock Screen view, approval buttons, and all `#Preview` content are
untouched.

**Verified:** `xcodebuild` app-target build green. Visually re-confirmed via `RenderPreview`,
comparing portrait vs. landscape renders for both a "needs approval" state and a plain "connected"
state — portrait shows the dot + badge; landscape now shows only the dot, no cramped/clipped text.

## 14. Siri phrases were never registered at all (first of two distinct Siri bugs)

While live-testing the newly-merged Siri intents (§8) on the physical device, the owner reported
none of the suggested phrases worked. Investigation (inspecting the app's own compiled
`Metadata.appintents` bundle — the file iOS actually uses to know what Siri phrases exist) found
the smoking gun directly in the `xcodebuild` log: `appintentsnltrainingprocessor: "No AppShortcuts
found - Skipping"`, and the merged app-level metadata's `autoShortcuts` array was completely
empty — even though the **per-module** `SessionFeature.appintents` bundle (an intermediate build
artifact) correctly listed all 5 shortcuts with their phrase templates.

**Root cause:** `LancerAppShortcuts` (the `AppShortcutsProvider` conformance) lived in
`SessionFeature`, a linked SPM library — never referenced anywhere in the actual `Lancer` app
target's own source. This is a known, documented `AppShortcutsProvider` limitation (confirmed via
web search against Apple Developer Forums thread 710552): the type must be reachable from the
app's own compiled binary for Xcode's app-intents metadata *merge* step to include it — unlike
plain `AppIntent` conformances, which do merge correctly from a linked framework (confirmed:
individual intents like `PauseRunIntent` showed up fine in the merged metadata; only the
*shortcuts/phrases* registration was silently dropped).

**Fix:** Moved `LancerAppShortcuts.swift` from
`Packages/LancerKit/Sources/SessionFeature/` to `Lancer/` (the app target itself), importing
`SessionFeature` to reference the actual intent types (which correctly stay in the shared
library). Also added a defensive call to `LancerAppShortcuts.updateAppShortcutParameters()` in
`LancerApp.init()` (Apple's documented re-registration hook for locale/parameter changes) — though
verified this call *alone*, without the file relocation, did **not** fix the empty `autoShortcuts`
problem (confirmed by testing the runtime-call-only fix first and re-inspecting the compiled
metadata, which was still empty) — the real fix is the file's *location*, not the runtime call.

**Verified:** Rebuilt via `xcodegen generate` (new file needs project regeneration) +
`xcodebuild`; directly inspected the freshly-compiled `Lancer.app/Metadata.appintents/
extract.actionsdata` and confirmed `autoShortcuts` now contains exactly the 5 intended entries,
with `ApprovalActionIntent` correctly absent (the "Siri never approves" security decision holds).

## 15. Siri phrases registered but every execution crashed (second, more serious Siri bug)

After fix §14 deployed, the owner tested a phrase via Siri's system "Turn on Shortcuts with Siri?"
authorization sheet (confirmed this dialog itself is the correct, expected `AppShortcutsProvider`
onboarding flow, not a separate/broken mechanism) — then reported the underlying commands still
weren't reaching the app.

A dispatched subagent (using the `mcp__ios-simulator__*` tools, after finding the `device-
interaction` skill referenced by the newer Device-Hub-native tools doesn't actually exist in this
environment — a real tooling-availability finding, not a code bug) confirmed: all 5 actions **are**
now correctly listed in the Shortcuts app (registration is fixed), but **every single execution
attempt** — 4 of 5 tried — failed identically with a system alert: **"Unable to run App
Shortcut"**, a generic runtime failure with no result-dialog text.

**Root cause investigation:** Rather than guess, pulled the simulator's unified system log
directly (`xcrun simctl spawn ... log show`) and found the exact underlying error: `Shortcuts[...]
[com.apple.shortcuts:General] Unable to run App Shortcut: Couldn't find AppShortcutsProvider.` —
despite the compiled metadata (§14) being confirmed correct. A targeted web search for this exact
error string surfaced a second, distinct, documented Apple platform limitation: "App Intents code
should NOT be placed in shared frameworks other than extensions or the main app" — when the same
AppIntent type is compiled into **two separate binaries**, static discovery (scanning compiled
metadata across all linked binaries) tolerates the duplication fine, but the **runtime execution
lookup** gets confused about which binary owns the intent and fails.

Checked `project.yml` and confirmed exactly this: `LancerLiveActivityWidget` (the widget
extension, needed for its own `ApprovalActionIntent` approve/reject buttons) *also* directly links
`SessionFeature` — the same library the 5 Siri-only intents lived in. So `AgentStatusQueryIntent`,
`PendingApprovalsQueryIntent`, `PauseRunIntent`, `StopRunIntent`, and `DenyLatestApprovalIntent`
were all compiled into **both** the main app binary and the widget-extension binary, even though
the widget extension has no legitimate need for any of them.

**Fix:** Moved `StatusQueryIntents.swift`, `RunControlIntents.swift`, and
`DenyLatestApprovalIntent.swift` from `Packages/LancerKit/Sources/SessionFeature/` to `Lancer/`
(the app target) — the identical relocation pattern already applied to `LancerAppShortcuts.swift`
in §14, for the same underlying reason. `ApprovalActionIntent` correctly stays in `SessionFeature`,
since the widget extension's own UI genuinely needs it in-process.
`CommandGateway`/`ActiveRunRegistry` (plain classes, not `AppIntent` conformances) are unaffected
and correctly stay shared.

**Verified:**
- Directly inspected the widget extension's own compiled `Metadata.appintents` after the fix and
  confirmed it now contains **only** `ApprovalActionIntent` — the 5 Siri-only intents are gone
  from there, present exclusively in the main app's metadata.
- Reinstalled fresh on the simulator and re-ran the exact failing repro (tapping the "Pending
  Approvals" tile in the Shortcuts app): pulled the unified log again for the same time window and
  confirmed the `"Couldn't find AppShortcutsProvider"` error **no longer appears** — a stark,
  concrete contrast to before, where it fired on 100% of attempts. A brief black Dynamic-Island
  pill appeared during execution (consistent with something actually running), though the session
  could not 100%-conclusively confirm a visible result dialog before it dismissed, due to
  simulator timing/screenshot-cadence limitations — flagged honestly as not fully visually closed
  out, recommending the owner re-test directly on the physical device where App Intents execution
  is known to be more reliable than in-simulator.
- `swift build`/`swift test` (LancerKit) and `xcodebuild` app-target build both green.

---

## Full commit list (chronological, all on `master`)

| Commit | Summary |
|---|---|
| `989d86e6` | Fix relay-token routing gap (§1) + never-auto-deny-on-timeout (§2) + in-chat approval widget (§3) |
| `7e73a82e` | Route approval push-notification taps to the originating thread, not Inbox (§4) |
| `acbbf76a` | Add machine rename; fix Home collapsing distinct machines by name — round 1 (§5.1, §5.2) |
| `ac5669a7` | Persist daemon-resolved absolute cwd (§6); fix Home fold-in bug round 2 (§5.3); add projects/workspaces design doc (§7) |
| `f05b8b63` | Merge CommandGateway + 5 Siri AppIntents from background worktree, with 3 bugs fixed during merge review (§8) |
| `38e15032` | Fix stale-socket decrypt failures via connect-generation counter (§10) |
| `b98dc358` | Wire Live Activities into the relay-dispatch flow (§11) |
| `7595e264` | Add landscape Dynamic Island layout + `#Preview` coverage (§12, §13) |
| `b94d172b` | Move `AppShortcutsProvider` to the app target — Siri phrases were never registered (§14) |
| `31d8f528` | Move the 5 Shortcuts-only intents into the app target — fixes execution-time crash (§15) |

All 10 commits are on `master`, none pushed to any remote (no push was requested or performed).

## What is verified vs. not yet fully verified

**Verified with strong, direct evidence (logs, compiled artifacts, or live device confirmation):**
- Approval routing, timeout-to-pause behavior, in-chat widget, push-notification routing (§1–4) —
  confirmed live on the physical device with real audit-log timestamps showing approvals resolving
  in seconds via genuine taps, not the 120s timeout.
- Machine rename and the Home/Machines consistency fix (§5) — confirmed via live pairing/renaming
  on both the physical device and a scratch simulator instance.
- cwd normalization (§6) — confirmed via clean build + test; not separately re-verified live this
  session beyond the original discovery, since it's a persistence-layer fix with no immediately
  visible UI signal.
- CommandGateway/Siri AppIntents merge (§8) — confirmed via full build/test suite; the 3
  merge-time bugs were compiler/runtime errors caught by the build itself, not subtle behavior bugs.
- The stale-socket decrypt-failure fix (§10) — confirmed live on the physical device: the owner
  sent a chat message successfully after the fix deployed, where it had reliably failed before.
- Siri phrase registration (§14) and the dual-target execution fix (§15) — confirmed via direct
  inspection of the actual compiled `Metadata.appintents` OS-level artifacts (the most reliable
  evidence available, stronger than UI observation) and via unified-log absence of the previously-
  100%-reproducible crash.
- Landscape Dynamic Island (§13) — confirmed via direct visual inspection of `RenderPreview`
  output, portrait vs. landscape, for two distinct content states.

**Not yet fully, independently verified — flagged honestly, not glossed over:**
- Live Activity wiring into the relay-dispatch flow (§11) — code-verified (clean build) but not
  visually confirmed live; the session's simulator testing was blocked by unrelated relay-
  connection instability from its own repeated test-daemon re-pairing, not a code issue. The owner
  should confirm directly on the physical device by sending a message and checking the Lock Screen
  / Dynamic Island.
- The Siri execution fix's *result dialog* (§15) — the underlying crash is confirmed gone via the
  unified log, but a genuinely visible, correct result dialog text was not 100% conclusively
  screenshotted in the simulator due to timing. Recommended physical-device re-test.
- The projects/workspaces design (§7) is a **design document only** — no implementation code was
  written for the feature itself this session, only its cwd-normalization prerequisite.

## Outstanding / deferred items (explicitly not done this session)

- Implementing the projects/workspaces feature itself (§7) — design doc exists, decisions made,
  no code written.
- The account-based relay auto-pairing idea (raised earlier, noted in memory as a future idea,
  not pursued this session).
- Broader WWDC 2026 AppIntents opportunities flagged by research but explicitly deferred as lower
  priority: on-screen View Annotations for run/approval disambiguation, `AppIntentsTesting`
  framework adoption for the new intents, Watch/CarPlay Live Activity presence via
  `.supplementalActivityFamilies`, `RelevantEntities` proactive Spotlight surfacing.
- Full multi-machine live relay matrix testing (2-3 genuinely separate real machines) — the
  session used isolated same-Mac test-daemon instances for multi-machine testing, not distinct
  physical hardware.
