# Cross-device conversation sync — release gate (design + execution)

Date: 2026-07-03 (afternoon session, follows `2026-07-03-cross-device-sync-live-verification.md`)
Runner: Claude Fable 5
Branch: `feat/cross-device-conversation-sync` (PR #14)
Hardware this session: exactly **one** connected physical device (Roshan's iPhone, iOS 27.0,
UDID `00008150-0001653C26F8401C`). No second physical Apple device → all two-device CloudKit
legs remain owner-gated, as Runbook PHASE 7 requires.

**Read §1 first.** The headline of this session is not the gate table — it's that the
relay-status bug the morning session left unresolved (its Part 7/8) is now **root-caused with
console + server-log evidence**, and it is a **release blocker** for three of the eight gate
scenarios.

**Follow-up verification (Codex, later 2026-07-03):** the P0 reconnect loop is no longer open
in code. The later Fable session fixed the incomplete-Keychain restore path by gating reconnect on
full restore success and refusing invalid reconnect attempts; Codex then tightened the remaining
non-empty malformed-code case so only 6-digit ASCII pairing codes can be persisted, restored, or
dialed. Fresh local verification passed: `swift build`, `swift test --no-parallel` (556 tests in
92 suites, plus the 13-test secondary bundle), `xcodebuildmcp build_sim` for the `Lancer` app
scheme, `xcodebuildmcp test_sim -only-testing:LancerKitTests/ConversationSyncCoordinatorTests`
(8/8), and `daemon/lancerd go test ./...`. The owner's existing physical phone still needs manual
remove + re-pair because its missing private key is unrecoverable; two-device CloudKit delivery
remains unverified.

---

## 1. ROOT CAUSE FOUND — phone relay reconnect dials with an EMPTY pairing code

The morning session ended with two indistinguishable hypotheses for why the phone's machine
card stays "disconnected" (orange dot): (1) the `RelayFleetStore` reactivity fix was necessary
but not sufficient, or (2) `bridge.isActive` is genuinely false for a real reason. **It's (2),
and the real reason is now proven:**

### Evidence chain (all captured this session)

1. **Device console** (`idevicesyslog`, full log:
   session scratchpad `device-syslog.txt`, 1.08 M lines captured during a live app launch):
   - `11:25:57.786 Lancer: doConnect: connecting to conduit-push-y4wpy6zeva-ts.a.run.app/ws/relay role=phone`
     — repeated at `11:26:15`, `11:26:47`, … (the client's backoff loop).
   - `11:25:49.350 Lancer(CFNetwork): Task <…> received response, status 400` followed by
     `receive URLError: code=-1011 … bad response from the server` with
     `_NSURLErrorWebSocketHandshakeFailureReasonKey=0` — the WebSocket upgrade is rejected
     at the HTTP layer, every attempt, in both the pre-test app instance (pid 37371) and the
     test-launched instance (pid 37433).
2. **Cloud Run request logs** (`gcloud logging read`, service `conduit-push`, project
   `roshan-agent-f1c2466d`): repeated
   `400 GET /ws/relay?role=phone&code=…&publicKey=…` from `Lancer/2 CFNetwork/3888.100.1 Darwin/27.0.0`
   at 15:25:58Z, 15:26:15Z, 15:26:47Z, 15:27:27Z, 15:27:28Z, 15:27:31Z.
   Parsing the logged URL (values not printed anywhere): **`code` length = 0. `publicKey`
   length = 43 (a valid base64url X25519 key), `role=phone`.**
3. **Server 400 condition** (`daemon/push-backend/websocket_relay.go:130`): the handler 400s
   pre-upgrade iff a param is missing/empty or `len(code) != 6`. Empty code → 400. The backend
   is behaving correctly.

So: the phone is reconnecting with a **persisted empty pairing code**, the server correctly
rejects it, and the client retries the identical bad handshake forever. The orange dot is the
truth; the morning session's `RelayFleetStore` Combine-bridging fix (commit `61d02b8a`) was real
but orthogonal.

### Where the empty code comes from (code path, verified at HEAD)

- `AppRoot.hydrateRelayFleetStore` (AppRoot.swift:2116) constructs each restored client with
  `pairingCode: ""`, then calls `restoreNamespacedStoredPairing()`.
- `restoreNamespacedStoredPairing` (E2ERelayClient.swift:278) guards only on
  `storedCode != nil` — **an empty string passes the guard** and is restored as-is.
- `hasStoredPairing(machineID:)` (E2ERelayClient.swift:245) likewise checks `!= nil`, so
  `connect()` fires (AppRoot.swift:2129-2131) with `pairingCode == ""`.
- Writers that can persist `""` in the first place: `persistPairing()`
  (E2ERelayClient.swift:239-243) writes `self.pairingCode` unconditionally, and
  `RelayMachineMigration.migrateLegacyIfNeeded` (RelayMachineMigration.swift:59) copies the
  legacy singular code verbatim — neither validates 6-char shape. Once `""` lands in
  UserDefaults under `lancer.relay.machine.<id>.code`, every launch re-dials it and nothing
  ever escalates to "re-pair required."

### Required fix (P0, release-blocking — not applied this session)

1. Treat a non-6-char stored code as *no pairing*: validate in `persistPairing()` (refuse to
   write), `restoreNamespacedStoredPairing()` and `hasStoredPairing` (treat as incomplete).
2. On a 400-class handshake rejection (permanent, vs. transient network errors), stop the
   retry loop and surface a "re-pair required" state on the machine card instead of an
   eternal orange dot.
3. On the user's actual device, the poisoned `lancer.relay.machine.<id>.code` entry must be
   cleared (re-pair from the Mac after the fix; the fix's validation turns the poisoned state
   into an explicit re-pair prompt).
4. Secondary UI inconsistency captured on the same screenshot: header says "1 running"
   (green) while the same machine's dot is orange — two different sources of truth for
   machine liveness should converge after (1)/(2).

Until this lands, **every relay-transport UI leg of the gate is blocked on the phone**:
composer send via relay, observed-session import (its `isLiveHost` precondition), and any
two-device UI flow over relay.

---

## 2. What was executed this session, with evidence

| # | Check | Layer | Result | Evidence |
|---|---|---|---|---|
| E1 | `ConversationCloudRecords` + `ConversationSyncEngine` unit suites | macOS host `swift test` | ✅ 9/9 passed (2 suites) | `swift test --no-parallel --filter …` — "Test run with 9 tests in 2 suites passed after 0.146 seconds" |
| E2 | `ConversationSyncCoordinator` suite — **previously ran NOWHERE** (iOS-gated, macOS host skips it; the Lancer scheme tests only LancerUITests) | **iOS simulator**, `xcodebuild test -scheme LancerKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LancerKitTests/ConversationSyncCoordinatorTests` | ✅ 8/8 passed, incl. **conflict** ("conflict status marks the conversation conflict and does not touch the mirror row's seq"), **hostOffline** ("a transport failure marks the conversation hostOffline"), **degradedResume** | `Test-LancerKit-Package-2026.07.03_11-25-30--0400.xcresult`; "TEST SUCCEEDED". This *closes* the 2026-06-28 TEST-INFRA "package iOS tests unrunnable" gap for this suite — the package iOS test build works now. |
| E3 | Real-device XCUITest still green; Home renders with real account state | Physical iPhone, `test_device` | ✅ 1/1 passed (104 s incl. build/install) | xcresult `test_device_2026-07-03T15-25-52-092Z_pid1472_7371856d.xcresult`, screenshot `home-live-state` extracted |
| E4 | **CloudKit is live on the device build** — container `iCloud.dev.lancer.mobile` (env Sandbox), zone `LancerConversations` exists server-side with PCS keys | Device console during E3 | ✅ | syslog 11:27:28.275: "Zone PCS was fetched from cache for … zoneName=LancerConversations" |
| E5 | **Engine pull runs for real**: `CKDFetchRecordZoneChangesURLRequest` to gateway.icloud.com for `app=dev.lancer.mobile` | Device console | ✅ | syslog 11:27:27.496 |
| E6 | **Engine push runs for real**: `CKDModifyRecordsURLRequest` completed `err=F` (658-byte response) | Device console | ✅ | syslog 11:27:28.257 |
| E7 | **B9 runtime half — `CKDatabaseSubscription` registration ACCEPTED by the CloudKit server** (morning session had only unit-tested the routing) | Device console | ✅ | syslog 11:27:29.615-618: `CKDModifySubscriptionsURLRequest … with error (null)`; `CKModifySubscriptionsOperation … databaseScope=Private, container=iCloud.dev.lancer.mobile … finished`, bytesUploaded=390 |
| E8 | Relay reconnect handshake | Device console + Cloud Run logs | ❌ **400, empty `code` — §1** | see §1 |
| E9 | Device console logging recipe works end-to-end (the morning session's stated missing capability) | tooling | ✅ | `idevicesyslog -u <UDID>` captured everything above; `gcloud logging read … httpRequest.status=400` gave the server side |

Not run / not runnable this session: anything needing a second signed-in Apple device (§4),
anything needing the relay fix first (§3), reinstall-restore (destructive to the owner's
device state — owner must drive), and the reseeded on-device UI test
(`LANCER_UITEST_RESEED=1` **deletes all saved hosts + approvals on the device** — never run
it against the owner's real phone; that seam is for simulators/dedicated test devices).

---

## 3. The release gate — eight scenarios, split by what can prove them

Legend: **SIM** = provable on simulator/local host · **DEV-1** = provable with the one
physical device (+ this Mac) · **DEV-2** = requires two physical Apple devices on the same
iCloud account · 🔴 = blocked by the §1 relay fix (or use SSH transport as the workaround leg).

| Scenario | Sim-provable part | Physical-only part | Current status |
|---|---|---|---|
| **1. Composer send (real UI)** | SIM: none today — simulator taps are broken in this Xcode-beta env (both prior sessions); XCUITest on sim not yet written for the composer | DEV-1 🔴 via relay; DEV-1 via **SSH/LAN** possible today (opt-in `testLANSSHConnectFromPhysicalDevice`, needs `LANCER_LAN_HOST`/`LANCER_TEST_PW`, still shows "Offline" — separate open network issue) | **RED** — never driven through real UI on any leg |
| **2. A→B CloudKit propagation** | SIM: no-op by design (`CloudSync` is `#if os(iOS) && !targetEnvironment(simulator)`) — a simulator leg can NEVER prove this | DEV-2 only. One-device halves ARE now proven: push (E6), pull (E5), zone (E4) | **AMBER** — device A's half proven live; B's receipt unproven |
| **3. Reinstall restore** | SIM: no (CloudKit no-op) | DEV-1, owner-driven (deletes the app + its Keychain-surviving state; §1 fix should land first or the relay pairing will hydrate incomplete again by design) | **RED / owner-gated** |
| **4. Conflict handling** | ✅ SIM: coordinator conflict path (E2); daemon `baseSeq` conflict detection (Go tests, morning Part 2); protocol-level two-connection conflict provable against the local daemon (morning Part 4 infra) | DEV-2 for the `ConversationSyncBanner` UI ("changed on another device" + Refresh/Resend) on both real devices | **AMBER** — logic proven at every non-UI layer; banner UX unproven |
| **5. Host-offline draft behavior** | ✅ SIM: `.hostOffline` transition proven (E2: transport failure → hostOffline, blocked, never auto-sent) | DEV-1: kill `lancerd` mid-thread, confirm transcript stays readable + composer blocks (🔴 relay leg; SSH leg possible) | **AMBER** |
| **6. Observed-session import** | SIM: none (needs a live host connection to render `observedSessionsBlock`) | DEV-1 🔴 — `testImportObservedTerminalSession` exists (`LANCER_OBSERVED_SESSION_TITLE`-gated) and is blocked precisely by §1 (`isLiveHost == false`) | **RED — blocked by §1** |
| **7. CKDatabaseSubscription silent push** | SIM: routing logic only (unit tests, morning Part 3) | Registration: ✅ **proven live** (E7). Delivery: DEV-2 only — CloudKit does not push change notifications to the device that made the change, so one device cannot prove its own silent-push delivery | **AMBER** — registration green, delivery unproven |
| **8. Device console logging** | — | ✅ DEV-1 **proven** (E9): `idevicesyslog -u 00008150-0001653C26F8401C` + `gcloud logging read` for the relay server side | **GREEN**, with one gap: **SyncKit has zero `os_log`** — CloudKit sync activity is only observable via cloudd's own logs. Add a `Logger(subsystem: "dev.lancer.mobile", category: "ConversationSyncEngine")` (P2, one file) so sync cycles/errors are grep-able like the relay categories already are |

### Two-device execution script (owner + agent, once a second device exists)

Prereqs: §1 fix merged; both devices signed into the same iCloud account; both paired to this
Mac's `lancerd`; `idevicesyslog` running against each device (two terminals, two UDIDs);
timestamps noted at every step. Then Runbook PHASE 7 steps 1–6 verbatim, with these
evidence-capture additions:

1. *Start on A, appears on B*: before touching B, wait ≤60 s watching B's console for
   `cloudd … containerID=iCloud.dev.lancer.mobile` fetch activity (silent push arriving =
   scenario 7 delivery proof). Record "arrived automatically" vs "needed foreground/syncNow".
2. *Follow-up from B*: confirms `resumeMode: "exact"` end-to-end through real UI (the protocol
   layer is already proven for all three vendors — morning Part 4).
3. *Reinstall A*: delete app on A → reinstall → sign in → conversation from step 1 must
   appear from the CloudKit mirror **before** re-pairing to the host (scenario 3).
4. *Conflict*: send from both within ~2 s; exactly one succeeds, the other shows the
   `.conflict` banner with Refresh + Resend (scenario 4 UI).
5. *Host offline*: `launchctl bootout` the daemon; transcript readable, composer
   `hostOffline`, nothing queues; restart daemon, confirm nothing auto-sends (scenario 5).
6. *Observed import*: `claude -p` in a Terminal → Home → Sessions on this Mac → Import to
   Lancer → follow-up resumes the exact vendor session (scenario 6; also re-runs
   `testImportObservedTerminalSession` unblocked).

Do **not** mark `PUBLISH_READINESS_CHECKLIST.md` C7/D2 green until steps 1, 3, 4 pass on two
physical devices — same rule as APNs (C2).

---

## 4. Exit criteria (what "green gate" means)

1. **P0 — §1 relay pairing fix** merged + re-verified on the owner's device (dot goes green,
   `/ws/relay` handshake 101 in Cloud Run logs, no 400s).
2. **P0 — composer send through the real UI** on at least one transport (scenario 1).
3. **P1 — two-device pass** of the §3 script (scenarios 2, 3, 4-UI, 5-device, 6, 7-delivery).
4. **P2 — SyncKit `os_log`** so future regressions are console-diagnosable (scenario 8 gap).
5. Already green and staying green: CI (3 checks), 551-test LancerKit suite, coordinator
   suite now also on iOS simulator (E2 — recommend adding this invocation to CI), daemon
   ledger/durability/exact-resume (morning Part 4), CloudKit push/pull/zone/subscription
   one-device halves (E4–E7).

## 5. Corrections to prior-session assumptions

- "No device console log access" (morning Part 7) — false as of this session: `idevicesyslog`
  (installed) + Cloud Run `gcloud logging read` give both ends; recipe in E9.
- "Package iOS tests unrunnable" (2026-06-28 TEST-INFRA finding) — no longer true for
  `ConversationSyncCoordinatorTests`: the `LancerKit-Package` scheme builds and passes on the
  iOS 27 simulator (E2).
- The `RelayFleetStore` `@Observable` bridging fix (`61d02b8a`) is real but was **not** the
  cause of the persistent orange dot; §1 is.

---

## 6. 2026-07-03 evening session — full re-verification, owner's real device, release gate closed for scenario 1

Runner: Claude Sonnet 5. Hardware: owner's physical iPhone (the same device as §1–§3, still
one physical device only — no second device this session, so scenarios 2/3/4-UI/7-delivery
remain owner-gated exactly as §3's table already marks them). Work done in the main checkout
(`/Users/roshansilva/Documents/command-center`, `feat/cross-device-conversation-sync`), not a
worktree — the uncommitted §1 fix (`isValidPairingCode`, atomic `persistPairing`, `Bool`-returning
`restoreNamespacedStoredPairing`, `connect()` refusal, 5 new `E2ERelayClientRestoreTests`) was
already sitting in that checkout's working tree at session start and is confirmed correct by
code review: no path reaches `connect()` with a missing, empty, or malformed pairing code.

### 6.1 Fresh local verification (all commands, all green)

| Check | Command | Result |
|---|---|---|
| LancerKit build | `cd Packages/LancerKit && swift build` | ✅ `Build complete!` |
| LancerKit full suite | `swift test --no-parallel` | ✅ 556/556 tests, 92 suites + secondary 13/13 bundle |
| New regression tests (filtered) | `swift test --no-parallel --filter E2ERelayClientRestoreTests` | ✅ 5/5 — incl. `missingPrivKey`/`invalidStoredCode` logging the exact diagnostic strings the fix adds |
| App-target build (simulator) | XcodeBuildMCP `build_sim`, scheme `Lancer` | ✅ `SUCCEEDED`, no errors (only pre-existing type-check-time warnings) |
| `ConversationSyncCoordinatorTests` (iOS simulator) | XcodeBuildMCP `test_sim -only-testing:LancerKitTests/ConversationSyncCoordinatorTests` | ✅ 8/8 — conflict, hostOffline, degradedResume all pass |
| `SyncKit` unit suites (after adding the logger, §6.2) | `swift test --no-parallel --filter "ConversationCloudRecords\|ConversationSyncEngine"` | ✅ 9/9 |
| App-target rebuild (after logger change) | XcodeBuildMCP `build_sim` | ✅ `SUCCEEDED` |
| Daemon | `cd daemon/lancerd && go test ./...` | ✅ `ok lancer/lancerd 32.735s`, `ok lancer/lancerd/policy` |

### 6.2 Quality fix: `ConversationSyncEngine` logging (item 5)

Added `private static let logger = Logger(subsystem: "dev.lancer.mobile", category:
"ConversationSyncEngine")` to `Packages/LancerKit/Sources/SyncKit/ConversationSyncEngine.swift`,
matching the existing `E2ERelayClient`/`E2ERelayBridge` convention exactly. Logs: subscription
registration success/failure, remote-notification routing (matched vs. ignored subscriptionID),
cycle start/skip-if-already-running/complete/error, pull record/deletion counts, push candidate
count. Closes the scenario-8 gap this doc's §4 flagged ("SyncKit has zero `os_log`"). Rebuilt
clean (6.1 above).

### 6.3 CI coverage added for `ConversationSyncCoordinatorTests` (item 5)

`.github/workflows/ci.yml`'s `lancer-app` job previously only ran `xcodebuild build` against
`generic/platform=iOS Simulator` (no destination device, so no tests execute there) — the
iOS-gated `ConversationSyncCoordinatorTests` ran nowhere in CI (the macOS-host `swift test` in
`lancerkit-spm` skips `#if os(iOS)` code). Added a step running `xcodebuild test -scheme
LancerKitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
-only-testing:LancerKitTests/ConversationSyncCoordinatorTests`. Verified locally with the exact
command before trusting it in CI: `** TEST SUCCEEDED ** [36.531 sec]`, 8/8 passed.

### 6.4 §1 relay fix — proven live on the owner's device (P0, closed)

Built fresh for device (`build_device`), installed (`install_app_device`), launched with console
streaming (`xcrun devicectl device process launch --console` — `idevice_id -l` / `idevicepair
list` returned nothing for this device, so classic `idevicesyslog` wasn't usable this session;
`devicectl` was the working substitute, though it only captures stdout/stderr `print()`, not
`os_log`, so success-path `Logger.info` calls aren't visible there — only the failure-path
`print()` diagnostics the fix added would show).

Owner removed the broken saved machine and re-paired. Pairing codes are generated by
`lancerd pair` (run on this Mac, not invented by the agent) and typed into the phone's pairing
screen. Sequence (owner accidentally triggered two live sessions via `--help`, which this build
of `lancerd` doesn't special-case — harmless, just two extra abandoned codes):

```
lancerd.stderr.log:
lancerd daemon: E2E relay started for code 414227
2026/07/03 12:42:34 e2e: connected to relay as daemon (code: 414227)
lancerd daemon: E2E relay started for code 167693
2026/07/03 12:42:39 e2e: connected to relay as daemon (code: 167693)
lancerd daemon: E2E relay started for code 873026
2026/07/03 12:42:54 e2e: connected to relay as daemon (code: 873026)
2026/07/03 12:43:15 e2e: paired with phone (code: 873026)   <-- SUCCESS
```

`paired with phone` is the daemon's own state machine confirming full E2E handshake completion —
only reachable after a clean WebSocket upgrade + crypto handshake. Cross-checked Cloud Run
(`gcloud logging read … resource.labels.service_name="conduit-push"`): the two abandoned codes'
`role=daemon` upgrades show as `101` at 16:42:34Z/16:42:39Z; the `873026` daemon-side and any
`role=phone` entries had not appeared in `gcloud logging read` queries run ~2–9 minutes after the
fact (freshness windows 5m/10m/15m/20m/30m all queried) — logged here as an evidence gap (likely
Cloud Logging per-entry ingestion lag, not a discrepancy) rather than claimed as proven.

**Device UI confirms the fix directly** (owner-provided screenshots): machine card shows
**"online · healthy"** with an **ONLINE** green badge, and the Home screen's "Relay host" row
shows a green (not orange) dot with "0 workspaces". This is the actual acceptance criterion —
**scenario 1's blocker (§1) is closed and proven on the owner's real device.**

### 6.5 Scenario 1 — composer send through real UI (P0, closed)

Owner sent "Hi there, tell me a story please" through the real composer against the connected
relay machine. Verified NOT a local echo — it round-tripped through the host:

- `audit.log`: `{"timestamp":"2026-07-03T16:47:25Z","action":"conversation-append-launched","agent":"claudeCode","command":"Hi there, tell me a story please","effect":"allow","rule":"default:ask", …}` — in the tamper-evident hash chain (`prevHash` links to the prior entry).
- `conversations.sqlite`: `conv_33bf1228-7429-458a-bb05-ed5212bdb905`, turn `turn_bec66842-…`
  status `exited`, provider `claudeCode`, `started_at` matching the audit timestamp.
- `conversation_events` for that turn: 20 events, `turn_started` → 17 `output` chunks streaming
  a genuine multi-paragraph short story → `status` (completed). Full real dispatch, full real
  streamed reply.

**Scenario 1 (release-gate §3 table) flips from RED to GREEN** — "never driven through real UI
on any leg" is no longer true; it's now proven over the relay transport specifically (the
transport that was previously blocked).

### 6.6 Scenario 6 — observed-session import (mixed: backend GREEN, iOS client-side gap found)

With the relay live-host precondition now satisfied, attempted the real UI flow (not the gated
XCUITest — getting an exact untruncated session title for XCUITest's string-match assertions
would have required a throwaway daemon-socket client or extra owner back-and-forth; driving the
real "Import to Lancer" button by hand proves the same UI affordance with less overhead). Owner
tapped an already-"Watching" observed session's overflow menu → "Import to Lancer".

**Backend: fully succeeded.** `conversations.sqlite` shows a new row, `source='observedImport'`:
`conv_bd321df0-…`, title = the real first-message preview (not a placeholder), one `completed`
turn bound to `vendor_session_id='18f85e09-…'` (the real Claude Code session ID — enabling
exact-resume on a future append), and **87** `conversation_events` (the full transcript).
`attachObservedSession`/`conversationsAttachObservedSession` (`conversation_rpc.go`,
`conversation_store.go`) work exactly as designed.

**iOS client: found a gap.** After the import, the app navigated to a screen titled "chat"
showing "0 requests / 0 artifacts / No activity in this work thread yet" — not the 87-event
transcript that actually exists on the host. Root cause (from code, not yet fix-verified):
`ObservedSessionView.performImport()` calls `onImported(summary.conversationId)`, which
`AppRoot.swift:1744` wires to `sidebarState.navigate(to: .thread(id: conversationID))` — a bare
navigation by ID with no accompanying fetch/hydrate of the newly-created conversation into the
local GRDB mirror (`ChatConversationRepository`). Since `attachObservedSession` creates the
conversation server-side, bypassing the app's normal local-first `beginTurn` path, the local
mirror has no row for it yet, so the thread view renders its "brand-new empty conversation" empty
state. **Not fixed this session** — flagging precisely per the task's instruction rather than
attempting a live fix on the owner's device without a test harness to verify it.

Owner also asked why import is manual rather than automatic: by design (`conversation_rpc.go:23`
comment, Task 9 of the spec) — an observed session is one the user started directly in a
terminal, bypassing Lancer; auto-importing every terminal session as a tracked Lancer conversation
would silently vacuum up unrelated local work. The explicit tap is a consent gate, and it's also
what binds the vendor session ID for exact-resume on future follow-ups.

**Scenario 6 stays AMBER, but re-characterized**: was "RED — blocked by §1"; now "backend GREEN,
proven with host-ledger evidence; iOS post-import navigation has a real hydration gap that needs
a fix + re-verification, tracked as a new P1 finding, not the old relay blocker."

### 6.7 Updated release gate — eight scenarios

| Scenario | Was (§3) | Now | Note |
|---|---|---|---|
| 1. Composer send (real UI) | RED | **GREEN** | §6.5 — relay transport, real dispatch, real streamed reply |
| 2. A→B CloudKit propagation | AMBER | AMBER (unchanged) | still DEV-2 only; no second device this session |
| 3. Reinstall restore | RED/owner-gated | RED/owner-gated (unchanged) | still DEV-1 owner-driven; not attempted (destructive, no reason to risk it mid-session) |
| 4. Conflict handling | AMBER | AMBER (unchanged) | logic proven; banner UX still DEV-2 |
| 5. Host-offline draft behavior | AMBER | AMBER (unchanged) | sim-proven; device leg not re-attempted this session |
| 6. Observed-session import | RED (blocked by §1) | **AMBER (re-characterized)** | §6.6 — backend proven, new iOS gap found |
| 7. `CKDatabaseSubscription` silent push | AMBER | AMBER (unchanged) | registration still proven; delivery still DEV-2; logger added (§6.2) for future diagnosis |
| 8. Device console logging | GREEN (with SyncKit gap) | **GREEN (gap closed)** | §6.2 — `ConversationSyncEngine` now has the same `os_log` convention as the relay stack |

### 6.8 Still open / needs owner or further work

- **Two-device legs (2, 3, 4-UI, 7-delivery) remain unproven** — genuinely require a second Apple
  device signed into the same iCloud account per `LIVE_LOOP_RUNBOOK.md` PHASE 7's own preamble;
  simulator cannot substitute (`CloudSync`/`ConversationSyncEngine` are simulator no-ops by
  design). Not attempted this session per the owner's explicit choice to proceed one-device-only.
- **New P1 finding**: observed-session-import navigation doesn't hydrate the local mirror before
  navigating, so a freshly-imported conversation renders empty until some other refresh path
  populates it (untested whether backgrounding/foregrounding or `syncNow()` would surface it — not
  verified this session).
- Reinstall-restore (scenario 3) was not attempted even though one physical device was available —
  it's destructive to the owner's real device state and the plan explicitly deferred it to a
  dedicated owner-driven pass rather than risk it as a side effect of this verification session.
- The two abandoned pairing codes (414227, 167693) are harmless — they just expired unused; no
  cleanup action needed.

---

## 7. 2026-07-03 evening session (cont'd) — observed-session-import hydration fix, verified live

Fixed the §6.6 gap (import backend succeeded but the thread rendered empty). Root cause: after
`attachObservedSession` succeeds, `onImported` (`AppRoot.swift`) navigates straight to
`.thread(id: conversationID)`, but nothing had pulled the newly-created conversation into the
local GRDB mirror — `attachObservedSession` writes only to the host ledger, unlike
`startConversation`/`continueConversation`, which write a local mirror row as part of the same
call. `refreshConversationMirror` (the existing helper used by the sync banner's Refresh action)
can't be reused as-is: it resolves the transport FROM an existing local `ChatConversation` row,
which is exactly what doesn't exist yet for a fresh import.

**Fix**: `importObservedSession` (`AppRoot.swift`) now builds the same `ConversationTransport` it
already has in scope (from the `slot`/`bridge` it just used for the attach call) and calls
`env.conversationSyncCoordinator.refreshConversation(conversationID:transport:)` — the same pull
`mergeFetchResponse` already knows how to upsert into an empty mirror — before returning success.
Best-effort: a refresh failure doesn't undo the import (the host row is already real and durable),
it just logs (new `AppRoot` `Logger(subsystem: "dev.lancer.mobile", category: "AppRoot")`) and
leaves the thread to pick up content via whatever refresh-on-open path already exists.

**Verified:**
- `swift build` — clean (note: this file is behind `#if os(iOS)`, so a plain macOS `swift build`
  doesn't actually type-check it; the app-target `build_sim` below is the real gate for this file).
- `swift test --no-parallel` — 556/556 + 13/13, no regressions.
- App-target `build_sim` (scheme `Lancer`, iOS Simulator) — `SUCCEEDED`, 0 warnings, 0 errors.
- App-target `build_device` + `install_app_device` on the owner's physical iPhone — `SUCCEEDED`.
- **Live on-device**: owner tapped "Import to Lancer" again (idempotent — same
  `conv_bd321df0-…` row from §6.6). `lancerd.stderr.log`: `transcript sessionId="18f85e09-…" →
  109 msgs, err=<nil>` at the moment of the tap. Owner's screenshot confirms the thread now
  renders the actual transcript content (real host name, real provider, real text) instead of the
  empty "chat" shell from §6.6.

**Caveat surfaced mid-fix (operational, not code)**: reinstalling the fresh build via
`install_app_device` reset the phone's locally-stored relay pairing (UserDefaults code/URL),
producing a fresh "can't reach the machine" error unrelated to any code change — confirmed by the
Mac-side daemon log showing zero connection attempts from the phone between the reinstall and the
owner's report, then a clean reconnect once re-paired with a fresh `lancerd pair` code. Lesson:
avoid reinstalling to the owner's physical device for iteration when the simulator can validate
the same code path — reserve physical reinstalls for the specific proof steps that require real
hardware.

**Scenario 6 (release gate) flips from AMBER to GREEN**: backend attach + client-side hydration
both proven live on-device.

---

## 8. Observed-session import: auto-import on tap (design change, owner-requested)

Owner's proposal: since `attachObservedSession` is idempotent and imported conversations are
ordinary, archivable/deletable `ChatConversation` rows (`LancerSidebarView.swift` already has
swipe-to-Archive/Delete, generic to any conversation), the separate "Watching → explicit Import to
Lancer" two-step was unnecessary friction — collapse it to "tap opens the real, continuable
conversation directly," matching how ChatGPT/Codex, Telegram, LINE, and Manus all treat a chat-list
tap (checked via Mobbin — none of them gate a list item behind a separate "commit to history"
step; all rely on swipe/long-press Archive/Delete for cleanup instead).

**Change**: `LancerHomeView`'s `onOpenObservedSession` callback (`AppRoot.swift`) now calls a new
`openObservedSessionAutoImporting(_:env:)`, which imports (attach + hydrate, §7's fix) and
navigates straight to `.thread(id:)` on success. On failure (host unreachable, etc.) it falls back
to the old read-only `.observedSession` view, which still offers a manual "Import to Lancer" retry
via its overflow menu — so the explicit-import path isn't removed, just no longer the default.

**Verified**: app-target `build_sim` — `SUCCEEDED`, 0 errors/warnings. `swift test --no-parallel`
— 556/556 + 13/13, no regressions. Not yet re-verified live on-device (would need another physical
rebuild/install, which this session's §6.4 finding says should be reserved for necessary proof
steps, not routine iteration) — flagging as the one remaining live-verification gap for this
change specifically.
