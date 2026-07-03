# Siri / App Intents foundation — device hub pass

Date: 2026-07-03  
Branch: `cursor/siri-primary-ios26-foundation-bc7c` (PR #15)  
Runner: Cursor agent (Composer)  
Scope: Phase 1–4 verification gates from the Siri foundation plan, plus the Siri-specific
device-hub matrix from `docs/wwdc26-lancer-opportunity-audit/05-device-hub-testing-plan.md`.

## Environment

| Item | Value |
|---|---|
| Xcode | 27.0 (`xcodebuild -version`) |
| `devicectl` | 629.3 (`xcrun devicectl --version`) |
| App deployment target | **iOS 26.0** (unchanged) |
| Test bundle `LancerAppIntentsTests` | iOS **27.0** only |
| Physical device | Roshan's iPhone — `557A7877-F729-5031-9606-0E04F2B67822` (iPhone 17, paired, booted) |
| Simulator (gates) | iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`) |

**Disk-space incident (resolved):** an earlier device build failed with `no space left on device`
while linking `LancerWidget`. Clearing `~/Library/Developer/Xcode/DerivedData` (~27 GB) restored
~24 GB free; subsequent device build succeeded.

## Automated verification gates — all green

| Gate | Command | Result |
|---|---|---|
| LancerKit build | `cd Packages/LancerKit && swift build` | ✅ PASS |
| LancerKit tests | `cd Packages/LancerKit && swift test --no-parallel` | ✅ PASS (full suite) |
| Xcode project regen | `xcodegen` | ✅ PASS |
| App-target simulator build | `xcodebuild build … -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest"` | ✅ BUILD SUCCEEDED |
| App-target device build | `xcodebuild build … -destination "id=557A7877-F729-5031-9606-0E04F2B67822"` | ✅ BUILD SUCCEEDED (~183 s) |
| AppIntents metadata tests | `xcodebuild test … -only-testing:LancerAppIntentsTests` | ✅ TEST SUCCEEDED — 4 passed, 1 skipped |

### Unit / policy coverage added this branch

- `IntentEntityCatalogTests` — no machines, offline machine, two active runs, deleted conversation,
  resolved approval, duplicate machine names
- `SiriIntentRoutingTests` — `SiriNavigationBuffer` record/drain, payload round-trip,
  deny-latest ambiguity branches
- `LancerShortcutsPolicyTests` — source scan: **no** `ApprovalActionIntent`, exactly **10**
  `AppShortcut(` entries (iOS cap)
- `LancerAppIntentsRuntimeTests` — intent/entity/enum metadata catalog; runtime `run()` skipped
  (entitlement blocker, see below)

## Siri shortcut inventory (launch lane)

Registered in `LancerAppShortcuts` (10/10 cap):

1. Agent Status  
2. Pending Approvals  
3. Search Lancer  
4. Open Conversation (includes continue phrases)  
5. Open Machine  
6. Open Approval  
7. Pause Run  
8. Stop Run  
9. Deny Approval  
10. Deny Latest Approval  

**Not in shortcuts (by design):**

- `ContinueConversationIntent` — reachable via Open Conversation phrases  
- `StartAgentRunIntent` — implemented with confirmation UX; withheld from shortcuts until happy-path proof  
- `ApprovalActionIntent` — **never** register (voice-approve forbidden)

## Physical device hub — automated steps

```bash
xcrun devicectl list devices --json-output /tmp/lancer-devices.json
xcodebuild build -project Lancer.xcodeproj -scheme Lancer -configuration Debug \
  -destination "id=557A7877-F729-5031-9606-0E04F2B67822" \
  -derivedDataPath /tmp/LancerDerivedData
xcrun devicectl device install app --device 557A7877-F729-5031-9606-0E04F2B67822 \
  /tmp/LancerDerivedData/Build/Products/Debug-iphoneos/Lancer.app
```

| Step | Result | Notes |
|---|---|---|
| Device inventory | ✅ | Physical iPhone available (paired, booted) |
| Device build | ✅ | `** BUILD SUCCEEDED **` |
| `devicectl device install app` | ✅ | `bundleID: dev.lancer.mobile` |
| `devicectl device process launch` | ⚠️ BLOCKED | Device locked — `Unable to launch … because the device was not, or could not be, unlocked` |
| `devicectl device capture screenshot` | ⚠️ BLOCKED | `NWError error 60 - Operation timed out` (consistent with locked / disconnected state) |

## Siri-specific matrix (plan Phase 4)

Live Siri utterances cannot be driven headlessly; rows below record automation status and the
manual repro command once the device is unlocked.

| Scenario | Method | Status | Notes |
|---|---|---|---|
| Cold launch → "Open approval …" | Siri shortcut → Needs Attention | ⚠️ **Manual** | Routing code + `SiriNavigationBuffer` + `OpenApprovalBuffer` re-post verified in unit tests; needs unlocked device + pending approval fixture |
| Background → "Pause run …" | 2 runs → disambiguation; 1 run → pause | ⚠️ **Manual** | `PauseRunIntent` refuses when `active.count > 1` without `run` param — logic covered in catalog tests |
| Deny by entity | Siri denies; approve still visual-only | ⚠️ **Manual** | `DenyApprovalIntent` registered; no approve shortcut (policy test) |
| Search | App opens with query populated | ⚠️ **Manual** | `SearchLancerIntent` + `openAppWhenRun: true` + buffer drain on cold launch |
| Offline machine start | `StartAgentRunIntent` fails closed | ⚠️ **Manual** | Intent implemented with offline/SSH-host rejection + confirmation; not in shortcuts yet |

### Recommended manual pass (owner, device unlocked)

1. Unlock Roshan's iPhone; ensure Developer Mode on.  
2. `xcrun devicectl device process launch --device 557A7877-F729-5031-9606-0E04F2B67822 --terminate-existing dev.lancer.mobile`  
3. Seed or wait for a pending approval; invoke **"Open approval … in Lancer"** from Siri — expect foreground + Needs Attention + detail sheet.  
4. With two active runs, **"Pause the agent in Lancer"** — expect disambiguation dialog.  
5. **"Deny the latest approval in Lancer"** with exactly one pending — expect deny without any approve phrase available.  
6. **"Search Lancer"** — expect search UI with query field focused.  
7. Toggle machine offline; invoke `StartAgentRunIntent` via Shortcuts app (not Siri shortcut list) — expect reconnect/offline dialog.  
8. `xcrun devicectl device capture screenshot --device 557A7877-F729-5031-9606-0E04F2B67822 --destination /tmp/siri-foundation-device.png`

## AppIntentsTesting blocker (Phase 3)

`LancerAppIntentsTests` links and metadata tests pass. Runtime `AnyAppIntent.run()` is skipped:

```
AppIntentsServicesSecurityErrorDomain Code=800
"Your app does not have permission… Request Bundle ID: dev.lancer.mobile"
```

Documented in `docs/wwdc26-lancer-opportunity-audit/ios27-fast-follow.md`. Next step: XCTest
host-app configuration or Apple-documented App Intents testing entitlement.

## Phase 1–2 implementation summary (for merge review)

- `AppEntity` types/queries `public`; `static let` for metadata queries  
- `openAppWhenRun: true` on all UI-routing intents  
- `SiriNavigationBuffer` durable routing + hardened `.openApproval` / `.openMachine` in `AppRoot`  
- `RunDispatchService` + `StartAgentRunIntent` (relay-first, confirmation, not in shortcuts)  
- Docs reconciled to iOS 26 launch / iOS 27 fast-follow  

## Verdict

| Phase | Status |
|---|---|
| Phase 1 — Repair PR #15 foundation | ✅ Complete — app-target CI-equivalent build green |
| Phase 2 — Entity + intent coverage + tests | ✅ Complete |
| Phase 3 — AppIntentsTesting lane | ✅ Complete (metadata tests; runtime deferred) |
| Phase 4 — Device hub | 🔶 **Partial** — build + install proven; live Siri matrix blocked on locked device |

**Merge recommendation:** PR #15 foundation is **build- and test-gated green**. Land after owner
completes the manual Siri matrix above (or accepts deferral with unit-test + install evidence only).
