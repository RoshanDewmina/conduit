# 02 — Current codebase state

> Compiled 2026-07-02 by direct source inspection (five parallel read-only subagents covering
> Device Hub/testing, product architecture/persistence, security/approval-flow, App
> Intents/Siri, and Live Activities/WidgetKit) plus independent verification of `project.yml`,
> `Package.swift`, `ARCHITECTURE.md` §0.1, `docs/KNOWN_ISSUES.md`, and
> `docs/PUBLISH_READINESS_CHECKLIST.md`. No files were edited and no builds were run to produce
> this document. Citations are `file:line`; treat anything without a citation as inference, not
> verified fact.

## Architecture in one paragraph

Lancer is a relay-first governed-approval control plane, not a phone IDE or a terminal client.
Three layers: the iOS app (`Packages/LancerKit/`, 23 SPM targets), the `lancerd` Go resident
daemon (policy/approval/audit/dispatch, survives SSH drops), and `push-backend` (Stripe billing +
the blind E2E relay + APNs). **V1's only transport is the E2E relay** — the phone never holds an
SSH session in V1 (`ARCHITECTURE.md:49-54`). Persistence is GRDB/SQLite
(`Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift:17,245`), not SwiftData, despite
`SettingsView.swift:216` incorrectly saying SwiftData in its copy. Navigation is a sidebar/split-view
shell (`SidebarShellState.swift:6`, `AppRoot.swift:1177,1287,1482`) — `enum Tab` is vestigial.

## Deployment target — verified drift

| Claimed | Actual | Evidence |
|---|---|---|
| iOS 27.0 (`docs/agent-contract.md:28`, `ARCHITECTURE.md` references) | **iOS 26.0** | `project.yml:13` `IPHONEOS_DEPLOYMENT_TARGET: "26.0"`; `project.yml:47,215,231,248,269,285` (app + extension targets) all `26.0`; `Packages/LancerKit/Package.swift:19` `.iOS(.v26)` |
| watchOS target | **11.0** | `project.yml:160,199` `WATCHOS_DEPLOYMENT_TARGET: "11.0"` |
| macOS target (Mac companion) | **15.0** | `project.yml:318` `MACOSX_DEPLOYMENT_TARGET: "15.0"` |
| Local toolchain | Xcode 27.0 (build 27A5194q), iOS 27.0 SDK installed | verified locally via `xcodebuild -version` and SDK path `iPhoneOS27.0.sdk` this session |

**Read this precisely:** the *toolchain* is iOS 27/Xcode 27. The *product's declared minimum
deployment target* is iOS 26.0. This is not automatically a bug — an app can build against a newer
SDK while shipping a lower deployment target, and iOS 27-only APIs already in use elsewhere in this
codebase (e.g. `EnvironmentValues.isDynamicIslandLimitedInWidth`, used in
`LancerLiveActivityWidget/LancerLiveActivityWidget.swift`, per the 2026-07-02 session report §13)
must be `@available`-gated when the deployment target is 26.0 — confirm this gating exists before
assuming today's iOS-27-only code is safe to ship at the current target. Whichever is correct (raise
the target to 27, or fix the docs to say 26), doc and target currently disagree — see
`docs/agent-contract.md` §2 ("iOS 27-only APIs... can be used without `#available` gating once the
rest of the file requires iOS 27" — that clause is false at the *current* 26.0 target).

## Implementation matrix

Classification legend: **Full** = works end to end with evidence of a real code path and (where
claimed) live verification. **Partial** = real code exists but a real gap breaks the end-to-end
story. **Missing** = no production code found by repo-wide search. **Misleading** = docs/product
copy assert something the code does not currently do.

### Relay transport & approvals

| Capability | State | Evidence | Gap |
|---|---|---|---|
| E2E relay auth (shared control-plane secret, per-session token, constant-time compare, TTLs, prod secret guard) | **Full** | `daemon/push-backend/relay_security.go:33,98,143` | None found — this is the strongest security layer in the app |
| Relay-only device registration → relay token roundtrip | **Full** (fixed 2026-07-02) | `daemon/lancerd/e2e_router.go` `deviceRegister`→`deviceRegistered`; `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift`; `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift` | Was broken until same-day fix (§1 of the 2026-07-02 session report) — a fresh regression here would silently reintroduce the 120s-timeout failure mode |
| Approval never auto-denies while a client is reachable | **Full** (fixed 2026-07-02) | `daemon/lancerd/server.go` `handleHookWithNotify`; `TestApprovalNeverAutoDeniesReachableClient` | — |
| No-client path fails **open** (auto-approve after 8s) | **Full, by design — flagged as the largest security concern** | `daemon/lancerd/server.go:1185,1293`; contradicts hook's own fail-closed-when-unreachable posture at `daemon/lancerd/hook.go:57` and the policy engine's ask/deny defaults at `daemon/lancerd/policy/evaluate.go:30` | See `07-security-and-trust.md` |
| Approval integrity: hash-binding decision to exact command/diff/tool-input shown to the user | **Missing** | `Approval.swift:3`, `E2ERelayMessage.swift:33`, `daemon/lancerd/approval.go:39`, `daemon/push-backend/decisions.go:11` all carry IDs/text but no `commandHash`/`diffHash`/`patchHash`/`toolInputHash` | See `07-security-and-trust.md` — largest single security gap in the app |
| E2E frame replay resistance (sequence/epoch/replay cache) | **Missing** | `daemon/lancerd/e2e_crypto.go:15` frames are version/nonce/ciphertext/tag only; backend forwards ciphertext verbatim (`daemon/push-backend/websocket_relay.go:309`) | Duplicate encrypted frames could replay `agentDispatch`/`agentRunControl` |
| Stale-socket decrypt race on reconnect | **Full** (fixed 2026-07-02) | `connectGeneration` counter, `Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift` | Live-confirmed on physical device |
| In-chat inline approval widget | **Full** (fixed 2026-07-02) | `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift` `pendingApprovalCount` + restructured branch order | — |
| Push-notification tap → correct thread | **Full** (fixed 2026-07-02) | `AppRoot.swift` `.lancerOpenApproval` handler → `FleetThreadMapper.findConversation` | — |
| Biometric gate on approval decisions | **Removed for V1 (2026-07-01, deliberate owner decision)** | `ARCHITECTURE.md:73` "Biometric gate and app-lock were removed for V1... approvals commit on tap and the app never shows a lock screen"; `SecurityKit/BiometricGate.swift:11` still exists as a type but is **not wired into** `ApprovalActionIntent.swift:41`, `AppRoot.swift:1987,2027` | **This directly conflicts with any "gate high-risk approvals behind Face ID" recommendation below — flagged explicitly, see `07-security-and-trust.md`** |
| Audit chain integrity | **Partial** | Daemon audit is hash-chained (`daemon/lancerd/audit.go:14,84`), but human-decision records store only coarse fields (`server.go:1350`); the app's own audit export computes a **separate** chain from app-side metadata, not the daemon chain (`AuditVerifyExportView.swift:50`) | Two independently-computed "chains" for the same events is a correctness risk, not just a completeness one |
| Relay-only diagnostics (doctor/host-health/drift) | **Partial** | `HostHealthStore.swift:36` only polls the live SSH fleet slots, not relay-only machines; daemon RPCs exist (`server.go:575,593,676,680`) but aren't routed over `E2ERelayBridge` | V1 is relay-first; diagnostics are still SSH-first |

### Siri / App Intents / Spotlight

| Capability | State | Evidence | Gap |
|---|---|---|---|
| 5 Siri Shortcuts (status, pending approvals, pause, stop, deny-latest) — registered & executable | **Full** (fixed 2026-07-02, two distinct bugs) | `Lancer/LancerAppShortcuts.swift:19`, `Lancer/LancerApp.swift:39`, `Lancer.xcodeproj/project.pbxproj:681` | Required moving `AppShortcutsProvider` **and** the 5 intent types into the app target — see "Two Siri platform limitations" below |
| Voice-approve | **Deliberately absent** — a security decision, not a gap | `Lancer/LancerAppShortcuts.swift:4` registers phrases for exactly the 5 above, never `ApprovalActionIntent` | Correct as-is; do not add |
| `DenyLatestApprovalIntent` correctness | **Partial** | Picks newest pending approval with no entity/machine disambiguation; `CommandGateway.swift:81` reports `.ok` after local enqueue, not confirmed daemon delivery; passes empty `hostID` → audit metadata `hostId: ""` + random fallback UUID (`ApprovalRelay.swift:169,245`) | Ambiguous with >1 machine/approval; audit trail pollution |
| `RunControlIntents` (pause/stop/status) multi-run disambiguation | **Partial** | `ActiveRunRegistry.swift:4` stores run IDs only, no `RunEntity`; `CommandGateway.swift:106` falls back to "first active relay bridge" | Breaks with >1 concurrent run or >1 paired machine |
| `AppEntity` / `IndexedEntity` / `EntityQuery` for any domain object (run, approval, machine, conversation) | **Missing** | Repo-wide search found zero production usages | This is the single largest addressable App Intents gap — see `03-app-intents-and-siri.md` |
| Core Spotlight / `CSSearchableItem` indexing | **Missing** | Search exists only in-app via SQLite FTS (`AppDatabase.swift:302`, `ChatConversationRepository.swift:278`, `BlockRepository.swift:60`) — never surfaced to system Spotlight | — |
| `AppIntentsTesting` coverage | **Missing** | No test target references it | The exact bug class hit twice in production (§14/§15 of the 2026-07-02 report) is precisely what this framework catches |
| Deep links (`lancer://auth/callback`, `lancer://billing/complete`) | **Broken for their actual producers** | `Lancer/LancerApp.swift:69` `onOpenURL` rejects non-empty paths; `AccountClient.swift:316` and `daemon/push-backend/billing.go:304` emit exactly those non-empty paths | Auth/billing deep-link completion is currently a dead path |
| Widget `AppIntent` configuration | **Minimal** | `LancerWidget/LancerStatusWidget.swift:13` `LancerWidgetIntent` has title/description only, no host/entity parameter | Widget can't be configured per-machine |

**Two Siri platform limitations already discovered and fixed (load-bearing context for any new
App Intents work):**
1. `AppShortcutsProvider` must physically live in the **app target's own compiled binary** — it
   does not merge correctly from a linked SPM library, even though plain `AppIntent` conformances
   do merge fine from a library. (Apple Developer Forums thread 710552, confirmed via the
   compiled `Metadata.appintents` bundle.)
2. When the *same* `AppIntent` type is compiled into **two separate binaries** (e.g. the main app
   target and a widget extension that also links the shared library), static discovery tolerates
   the duplication but **runtime execution lookup fails** ("Couldn't find AppShortcutsProvider").
   Fix was moving the 5 Siri-only intents out of `SessionFeature` (also linked by
   `LancerLiveActivityWidget`) into the app target; `ApprovalActionIntent` correctly stays in
   `SessionFeature` since the widget extension genuinely needs it in-process.

Any new entity/intent work (App Schemas, `IndexedEntity`, Execution Targets) must be evaluated
against both of these constraints — see `03-app-intents-and-siri.md` for whether WWDC26's
"Execution Targets" concept actually resolves limitation #2.

### Live Activities / Dynamic Island / WidgetKit / Watch

| Capability | State | Evidence | Gap |
|---|---|---|---|
| Local Live Activity start/update/end, stale dates, push tokens | **Full** | `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift:153,198,319` | — |
| Live Activity survives app backgrounding | **Missing / misleading** | `ARCHITECTURE.md:76` claims push-driven Live Activity while closed; `AppRoot.swift:338` calls `.end()` on **every** activity when backgrounded | This is the single largest Live Activity gap — see `04-live-activities-and-dynamic-island.md` |
| Live Activity wired into the relay-dispatch flow (the actual V1-primary transport) | **Full** (fixed 2026-07-02, not yet visually confirmed live) | `NewChatTabView.swift:1019` calls `.start()`/`.update()`/`.end()` keyed by `liveActivityKey` | Code-verified via clean build only; owner should confirm on physical device (Lock Screen / Dynamic Island) |
| Dynamic Island expanded/compact/minimal regions, approve/reject buttons | **Full** | `LancerLiveActivityWidget/LancerLiveActivityWidget.swift:23,194` real `LiveActivityIntent` plumbing, not a stub | — |
| Dynamic Island landscape / width-aware layout | **Full** (fixed 2026-07-02) | `LancerLiveActivityWidget.swift:151` uses `EnvironmentValues.isDynamicIslandLimitedInWidth` (confirmed real in the shipped iOS 27 SDK, not guessed) | — |
| Risk level surfaced in Live Activity content state | **Missing** | Content state has no risk field | High/critical approvals can't be visually distinguished or gated in the Island — see `04-live-activities-and-dynamic-island.md` |
| Relay-only Live Activity/push-to-start token registration | **Missing** | Token forwarding only happens when `daemonChannel` exists (`AppRoot.swift:1745`); the relay-only path registers **APNs device tokens**, not **Live Activity tokens** (`E2ERelayBridge.swift:123`) | Relay-only pairings (the V1-primary path) may never get push-driven Live Activity updates at all |
| Backend push-to-start (`event: "start"`) sender | **Missing** | `daemon/push-backend/main.go:451` has `/register-activity-token` and update payloads (`liveactivity.go:108`), but no push-to-start `event: "start"` sender found | Can't start a Live Activity purely from a server push while the app is fully closed |
| WidgetKit home-screen widget reflects relay chat state | **Stale** | `LancerWidget/LancerStatusWidget.swift:18` reads app-group snapshots written only from the **legacy SSH** `SessionViewModel.swift:605`; the relay chat path does not appear to update widget snapshots | Widget likely shows stale/wrong state for the actual V1-primary transport |
| Watch app: WCSession phone↔watch sync | **Full, but phone-dependent** | `PhoneWatchConnector.swift:24`; `WatchConnector.swift:41` only sends when reachable | Watch app is intentionally **not embedded** in the iOS bundle (`project.yml:138`) — ships/updates separately |
| Local notification / Watch-transfer content redaction | **Partial — a real privacy gap** | Remote APNs pushes are redacted (`main.go:380`, `liveactivity.go:231`), but **local** notifications expose raw commands (`NotificationsKit/Notifications.swift:209`) and Watch transfers display raw command/output (`WatchApprovalTransfer.swift:24`) | Local-only surfaces (lock screen banner on the same device, Watch face) leak more than the remote push path does — inconsistent, not by design |

### Persistence, diagnostics, tests

| Capability | State | Evidence |
|---|---|---|
| GRDB/SQLite persistence (conversations, turns, artifacts, FTS) | **Full** | `AppDatabase.swift:17,245`; `ChatConversationRepository.swift:12,82,166,309` |
| Settings copy says "SwiftData" | **Misleading (copy bug, not a storage bug)** | `SettingsFeature/SettingsView.swift:216` — no `import SwiftData` anywhere in production sources |
| Daemon diagnostics (doctor, audit tail/verify/export, host health, drift scan/remediate) | **Full for SSH fleet, partial for relay-only** | `daemon/lancerd/server.go:575,593,676,680`; gap above |
| Test baseline (as of 2026-06-27/2026-06-18 checklist) | **Green** | LancerKit: 449 Swift Testing + 13 HostControlKit + 8 XCTest tests pass; `go test ./...` green in `lancerd`/`push-backend`/`agent-runner`; app-target Xcode build SUCCEEDED 0 errors/0 warnings |
| App-target UI test suite | **Thin** | `LancerUITests` has 9 test methods total (`project.yml:282`); 4 are `XCTSkip`-quarantined against the superseded tab-bar nav (`docs/KNOWN_ISSUES.md` §1, `TapInjectionProofTests.swift:58,193,256`) |
| `AppIntentsTesting`, deep-link routing tests, Spotlight/entity tests, Live-Activity-lifecycle tests, WidgetKit provider tests, replay-resistance tests, approval-hash-binding tests | **Missing (all)** | repo-wide search, corroborated independently by all 5 subagents |

## Dead code / stubs / non-goals (already correctly excluded from V1)

Per `ARCHITECTURE.md` §0.1: hosted-cloud execution UI (`ProviderDetailView`,
`HostedProvisioningView`, `HostedRunnerStatusView`, `SelfHostVsHostedView`) is 0-ref, compiles,
stays in tree, intentionally unwired — **do not recommend deleting it or reviving it for this
audit's V1-focused scope.** The full interactive terminal pipeline (`LiveTerminalView`,
`TerminalEngine`, SFTP, port forwarding) is likewise real, working, and deliberately unwired from
V1 navigation (owner decision 2026-06-30) — this audit's recommendations should not propose
reintroducing terminal depth as a WWDC26 opportunity.
