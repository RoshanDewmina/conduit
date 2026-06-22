# Review — App Targets, Extensions & Build/Submission Config

**Scope:** Lancer app target, LancerWidget, LancerLiveActivityWidget, LancerWatch, LancerWatchWidget, `project.yml`, plus the glue in LancerKit that those targets exercise for **Governed Approvals v1** (push registration, notification actions, Live Activity, WatchConnectivity approval transfer).

**Branch / worktree:** `feat/governed-approvals` @ `/Users/roshansilva/Documents/cc-wt/governed-approvals-audit`
**Method:** static read-only review (no builds run). Apple-rule checks cross-referenced against current required-reason-API / permission guidance. Each finding ran through an adversarial "is it reachable in a Release build?" pass.

---

## SUBMISSION-COMPLIANCE CHECKLIST (feeds Phase-6 go/no-go)

| # | Item | Result | Notes |
|---|------|--------|-------|
| 1 | **Usage strings for every requested permission** | ❌ **FAIL** | `NSMicrophoneUsageDescription` **and** `NSSpeechRecognitionUsageDescription` are **missing** but the in-session mic/dictation button requests both → guaranteed crash + review rejection (see **B1**). Face ID string present ✅. Notifications need no string ✅. No camera/photos/contacts/location APIs used ✅. |
| 2 | **PrivacyInfo.xcprivacy accurate** | ⚠️ **PARTIAL** | FileTimestamp + UserDefaults + SystemBootTime declared. SystemBootTime (35F9.1) **is still warranted** because Sentry is *linked* (binary-presence rule, not runtime) — see **M-note**. CrashData *collection* is declared but Sentry never starts (empty DSN) → over-declared (see **m3**). FileTimestamp reason code is arguably wrong for the actual call site (see **m4**). No disk-space / active-keyboard APIs used → correctly absent ✅. |
| 3 | **Entitlements minimal & DeviceTesting NOT in Release** | ✅ **PASS** | `Lancer-DeviceTesting.entitlements` is an **orphan** — `project.yml` wires the app to `Lancer/Lancer.entitlements` for *all* configs (no per-config override), so DeviceTesting never ships. iCloud + `aps-environment` require a paid-account / CloudKit-container provisioning step (acknowledged in `project.yml` comments). |
| 4 | **ATS — no insecure exceptions** | ✅ **PASS** | Only `NSAllowsLocalNetworking` (benign). No `NSAllowsArbitraryLoads`, no `NSExceptionDomains`, **no** exception added for the `https://35.201.3.231.sslip.io` backend (valid TLS, plain HTTPS). |
| 5 | **App icons & launch assets complete; versions consistent** | ⚠️ **PARTIAL** | App + Watch 1024 icons present (single-size). `LaunchScreen` set. **Version mismatch:** `project.yml` `MARKETING_VERSION 0.1.0` vs hard-coded `CFBundleShortVersionString 1.0` in every Info.plist — the literal wins, the build setting is inert (see **m2**). All plists internally consistent at `1.0 / 1`. |
| 6 | **Widget / Watch / LiveActivity targets submission-valid** | ⚠️ **PARTIAL** | Info.plist + `NSExtension` point-identifiers correct; no debug-only entitlements; app-group wiring correct. **But** `ENABLE_APP_INTENTS_METADATA_EXTRACTION = NO` puts the Live-Activity/widget App-Intent buttons at risk in Release (see **M1**). |
| 7 | **Release-hygiene compile-out** | ✅ **PASS** | `isPro` bypass, `DebugSeeder`, debug host auto-trust are all `#if DEBUG` (verified file-level guard + call-site guard). No shipping "REVIEW" pill found (only the DEBUG `LANCER_GALLERY=review` route). Production TOFU host-key prompt intact (`autoTrustHostKey` defaults `false`). |

**Net:** **NO-GO** until **B1** (missing mic/speech usage strings) is fixed — it is an automatic crash + rejection. **M1–M5** should be resolved or explicitly waived before submission.

---

## BLOCKER

**[BLOCKER] Lancer/Info.plist (+ project.yml:42-66) — `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` missing while the dictation feature requests microphone + speech recognition.**
- `Packages/LancerKit/Sources/SessionFeature/DictationEngine.swift:19-36` calls `SFSpeechRecognizer.requestAuthorization` (line 21) and activates `AVAudioSession(.record)` + an `AVAudioEngine` input tap (lines 28, 36). iOS **terminates the process** if the corresponding purpose string is absent when the permission is requested.
- **Reachability: HIGH / certain.** `DictationEngine` is instantiated in the shipping session UI (`SessionFeature/SessionView.swift:20`) and driven by the mic button in `SessionFeature/Chat/ChatInputBar.swift:255` (`onMic` → `dictation.start(...)`, `SessionView.swift:288-294`). Not debug-gated. First mic tap in any session → crash. App Review also auto-flags protected-resource access without purpose strings.
- **Proposed fix:** add to the Lancer target `info.properties` in `project.yml`:
  - `NSMicrophoneUsageDescription` — e.g. "Lancer uses the microphone to dictate terminal commands by voice."
  - `NSSpeechRecognitionUsageDescription` — e.g. "Lancer transcribes your speech on-device/Apple servers to let you dictate commands." Then regenerate the project.

---

## MAJOR

**[MAJOR] project.yml:16 — `ENABLE_APP_INTENTS_METADATA_EXTRACTION: "NO"` (project base, inherited by app + both iOS widget extensions) risks breaking the Live Activity / Dynamic Island / widget approval buttons.**
- The governed-approvals headline surface uses App Intents: `ApprovalActionIntent` (`SessionFeature/ApprovalActionIntent.swift:20`, a `LiveActivityIntent`) for the Approve/Reject buttons in `LancerLiveActivityWidget/LancerLiveActivityWidget.swift:59-79,114-133`, and `LancerWidgetIntent` (`AppIntentConfiguration`) in `LancerWidget/LancerStatusWidget.swift:13,51`. Disabling metadata extraction skips generating the `Metadata.appintents` bundle the system uses to discover/resolve intents across the process boundary.
- The intent is correctly `public` and conforms to `LiveActivityIntent` with `openAppWhenRun = true` (so `perform()` runs in the app process and reaches `ApprovalRelay`) — those are necessary but **not** obviously sufficient when metadata extraction is off. Community/Apple-forum evidence is consistent that intents must be discoverable (and `public`) for the system to invoke them in Release.
- **Reachability: HIGH, but needs on-device Release confirmation** (cannot build in this pass). If broken, lock-screen/Dynamic-Island approvals silently do nothing.
- **Proposed fix:** remove the project-base override (default is `YES`), or set `ENABLE_APP_INTENTS_METADATA_EXTRACTION = YES` on the Lancer app + `LancerWidget` + `LancerLiveActivityWidget` targets. Verify the buttons fire `perform()` in a Release build on device.

**[MAJOR] SessionFeature/LiveActivityManager.swift:151-165 — `updatePendingApprovals(_:)` rebuilds `ContentState` without `pendingApprovalID`, stripping the Approve/Reject buttons; it races the correct update path.**
- The buttons in the Live Activity render only `if let approvalID = context.state.pendingApprovalID, !approvalID.isEmpty` (`LancerLiveActivityWidget.swift:57,112`). `updatePendingApprovals` preserves `status/agentName/isStreaming` from `lastContent` but **omits `pendingApprovalID` → nil**.
- It is called from `AppFeature/AppRoot.swift:500-507` on **every** pending-count change (`.onChange(of: …filter(\.isPending).count)`), explicitly to keep the badge live while backgrounded. The correct path (`SessionViewModel.setLiveActivityPendingApprovals` → `updateLiveActivityIfNeeded` → `manager.update(... pendingApprovalID:)`, `SessionViewModel.swift:492-538`) *does* carry the ID. Both fire from the same DB change as independent async tasks → last-writer-wins. If `updatePendingApprovals` wins, the buttons vanish exactly when an approval is pending.
- **Reachability: HIGH.** Every approval arrival changes the count and triggers the ID-dropping path; also fires on subsequent count changes while backgrounded.
- **Proposed fix:** make `updatePendingApprovals` preserve `base.pendingApprovalID` (and `base.isStreaming` is already preserved), or route the `AppRoot.onChange` through the full `update(...)`/`setLiveActivityPendingApprovals` path so the ID is never dropped.

**[MAJOR] AppFeature/AppRoot.swift:894-905 — Watch-originated approval decisions are not persisted to the local DB, so they re-sync as still-pending and never clear the Live Activity / inbox count.**
- The watch `onDecision` only records an audit row + `channel.respond(...)`. Unlike the in-app inbox path (`InboxFeature/InboxViewModel+Live.swift:50-53` calls `repository.decide` then `onDecision`) and the Live-Activity-intent path (`SessionFeature/ApprovalRelay.swift:51-52` calls `approvalRepo.decide`), the watch path **never calls `approvalRepo.decide`**.
- `AppFeature/ApprovalIngest.swift:24-43` only ingests `.approvalPending` (it has no "resolved" branch), so nothing else marks the row decided. The row stays `pending` → `PhoneWatchConnector` task #1 (`PhoneWatchConnector.swift:107-114`, filters `$0.isPending`) re-pushes it to the watch (the approval **reappears** after the user decided it), and `onPendingApprovalsChanged` keeps the Live Activity/Dynamic-Island count elevated.
- **Reachability: HIGH** for any watch decision while a session is connected (decision reaches lancerd, but local state diverges).
- **Proposed fix:** in the watch `onDecision`, call `approvalRepo.decide(id, decision)` before/after `channel.respond`, or route the watch decision through `ApprovalRelay.shared.enqueue(...)` (which already persists + audits + forwards) for parity with the other two entry points.

**[MAJOR] LancerWatch/WatchConnector.swift:41-46 + WatchStore.swift:57-62 — watch decision send is best-effort `sendMessage` only (no `errorHandler`, no guaranteed-delivery fallback) while the UI optimistically clears the row → silent loss of a watch "Allow".**
- `send(_:)` transmits only when `WCSession.default.isReachable`; if the phone is unreachable the message is **dropped silently** (no `transferUserInfo`/`updateApplicationContext` queue, no retry, `errorHandler: nil`). `WatchStore.decideApproval` plays a success haptic, sends, then immediately `approvals.removeAll { $0.id == item.id }` + updates the complication — so the watch *shows success regardless of delivery*.
- Adversarial pass: it **fails safe security-wise** (lancerd's 120 s timeout auto-**denies**, never auto-approves). But a user's **Approve** is silently lost when the phone is unreachable — the headline "approve from your wrist" path is unreliable, and the watch claims success.
- **Reachability: MEDIUM-HIGH** (any time the iPhone app isn't reachable: locked-away phone, app not foregrounded, BT/Wi-Fi gap).
- **Proposed fix:** add an `errorHandler` to `sendMessage` and fall back to `transferUserInfo` (guaranteed background delivery) when not reachable or on error; only clear the row on confirmed delivery (or show a pending/queued state). Note this delivery is **at-most-once**, not exactly-once — see **m1**.

---

## MINOR

**[m1] SessionFeature/ApprovalRelay.swift:67-75 — exactly-once is not guaranteed client-side; the relay does at-least-once and relies on lancerd idempotency.**
- When no channel is attached, `enqueue` both `postDecisionToBackend(...)` **and** `queue.append(...)`; the queued item is later re-sent via `drainQueue → ch.respond` on `setChannel` (`AppRoot.swift:956`). So one decision can be delivered via the HTTP backend relay *and* again via SSH. `DaemonChannel.respond` (`SSHTransport/DaemonChannel.swift:116-130`) carries no client dedup token. Combined with watch + Live-Activity entry points, the same `approvalId` can be responded multiple times.
- Adversarial pass: safe **iff** lancerd dedups by `approvalId` (and the design's 120 s auto-deny is the fail-safe backstop). Duplicate audit rows are also produced.
- **Proposed fix:** confirm/Document lancerd idempotency on `approvalId`; consider a client-side "already-responded" guard keyed by `approvalId` to avoid duplicate backend+SSH sends and duplicate audit entries.

**[m2] project.yml:90,131,167,193,227 vs Lancer/Info.plist:17-18 (and every extension Info.plist) — `MARKETING_VERSION 0.1.0` never reaches the bundle; `CFBundleShortVersionString` is hard-coded `1.0`.**
- The plists use literal `1.0`/`1`, not `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, so the build settings are inert and future version bumps in `project.yml` silently won't apply. All targets are internally consistent at `1.0 / 1` (so the watch/app pairing is fine for now).
- **Proposed fix:** either change the plists to `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, or drop the unused build-setting values to avoid confusion. Pick the real submission version deliberately.

**[m3] Lancer/PrivacyInfo.xcprivacy:51-62 — CrashData collection is declared, but Sentry never starts (empty DSN), so no crash data is actually collected/sent.**
- `LancerApp.swift:33,44-53`: `sentryDSN = ""` → `configureSentry()` returns early; SDK never initializes. Over-declaration isn't a rejection risk, but the manifest is inaccurate.
- **Proposed fix:** decide the Sentry story before submit. If shipping Sentry, set the DSN (then the declaration + the SystemBootTime entry are accurate). If not, remove the `Sentry` SPM dependency (`project.yml:29-31,101`) and the CrashData + SystemBootTime declarations together.

**[m4] Lancer/PrivacyInfo.xcprivacy:7-15 — FileTimestamp reason `C617.1` ("display timestamps to the person") may not match the actual call site.**
- The only file-timestamp required-reason call found is `SSHTransport/SFTPClient.swift:163` (`FileManager.attributesOfItem(atPath:)`), used to read a local file's **`.size`** for upload progress — not to display timestamps. (Remote SFTP listing timestamps come over the SSH/SFTP protocol, which is not the covered API.)
- Adversarial pass: a reason *is* required (the API is used), so this is accuracy not omission. `3B52.1` (access timestamps within the app/group/CloudKit container) or a more apt reason may be correct depending on whether the uploaded file is user-picked vs in-container.
- **Proposed fix:** confirm what `attributesOfItem` is used for and whether the SFTP browser displays file timestamps; pick the reason code that matches (`C617.1` only if timestamps are shown to the user).

**[m5] Lancer/Info.plist:38-42 — `NSAllowsLocalNetworking` is set and Lancer is an SSH client to user-entered hosts (often LAN), but there is no `NSLocalNetworkUsageDescription`.**
- No Bonjour/`NWBrowser`/`NetServiceBrowser` usage was found (so the Local Network prompt may not be triggered by discovery), but a direct connection to a LAN host can still surface the iOS Local Network permission; without the string the prompt has no rationale and can be denied → LAN connects fail.
- **Reachability: MEDIUM / verify on device** (depends on whether users target LAN hosts; ATS local-networking is enabled, implying that's intended).
- **Proposed fix:** if LAN hosts are supported, add `NSLocalNetworkUsageDescription` (e.g. "Lancer connects to SSH servers on your local network."). Verify on a physical device against a LAN host.

---

## NIT

**[nit1] LancerWatch/Assets.xcassets/AppIcon.appiconset/Contents.json — watch icon declares only a single `watch-marketing` 1024×1024.** Modern Xcode supports single-size icons; verify the watch app icon renders/validates for the watchOS 26 deployment target at archive time.

**[nit2] Lancer.entitlements:5-6 / project.yml:77 — `aps-environment: production` is used for both Debug and Release (no per-config override).** Correct for App Store/TestFlight; just note local dev-device push needs a `development` token (works fine for submission).

**[nit3] SessionFeature/LiveActivityManager.swift:114-118 — Live Activity is started with `pushType: nil` (no push token).** This is a deliberate design (updates only while the app has execution time); a new approval arriving while the app is suspended/terminated won't refresh the Live Activity badge (the separate APNs alert still fires). Submission-valid; documenting the limitation for the governed-approvals reviewers.

**[nit4] AppFeature/FleetStore.swift:9-14 — stale comment claims "ApprovalRelay (ws-i) does NOT exist."** It does exist and is wired (`AppRoot.swift:956-957`). Doc rot only.

---

## Verified OK (adversarial pass passed — no action)

- **APNs registration / actions** (`Lancer/LancerApp.swift:99-208`): `registerForRemoteNotifications()` on launch; categories (`approval` → `approval.approve` w/ `.authenticationRequired`, `approval.reject` w/ `.destructive`; `run-complete` → `run.view`) registered in `NotificationsKit/Notifications.swift:201-226` and the action identifiers **match** the `AppDelegate` switch — approve/reject routing is consistent. `requestAuthorization` is requested (`AppRoot.swift:266-267`). Background `remote-notification`/`fetch` modes declared and `didReceiveRemoteNotification` calls `completionHandler(.newData)`.
- **Token registration is gated** on a non-empty backend URL (`LancerApp.swift:119`) — safe no-op on simulator / when unset.
- **ATS / backend**: clean, see checklist #4.
- **DeviceTesting entitlements**: not wired into any config, see checklist #3.
- **Release hygiene**: `PurchaseManager.isPro` (`SettingsFeature/PurchaseManager.swift:44-51`) and `SessionShellView.isPro` bypass, `DebugSeeder` (`#if os(iOS) && DEBUG`, call site `AppRoot.swift:480-482` `#if DEBUG`), and debug auto-trust (`LiveTerminalView`/`DebugTerminalHarness`/`DebugSessionHarness`, all `#if DEBUG`) compile out of Release. Production keeps the TOFU host-key prompt.
- **Widget data contract**: phone writes `WidgetSnapshot` keys (`SessionViewModel.swift:542-548`) that `LancerWidget/LancerStatusWidget.swift:34-44` reads (same app group + keys). Watch `InboxCountWidget.swift:28-31` reads `watchPendingCount`, written by `WatchStore.swift:78-80` on-watch — consistent within the watchOS sandbox. Timeline refresh policy (15 min + `reloadAllTimelines()`) is reasonable.
- **Live Activity lifecycle**: single activity per host, dedup on re-`start`, `end`/`endAll` on disconnect (`LiveActivityManager.swift:89-198`); `staleDate` set on every update.
- **SWIFT_STRICT_CONCURRENCY = complete** applies to every target (project base; widget extensions inherit it). watchOS targets re-declare it explicitly.

### M-note — SystemBootTime (35F9.1) declaration is warranted
No app/LancerKit code calls `systemUptime`/`systemBootTime` (grep clean). The only caller is the **linked** Sentry SDK. Required-reason declarations are driven by **binary presence**, not runtime execution, so while `Sentry` remains an SPM dependency (`project.yml:29-31,101`) the `35F9.1` entry is **correct/required** even with an empty DSN. (Sentry ≥8 also ships its own privacy manifest, so the app-level entry is partly redundant but harmless.) This only becomes removable if the Sentry dependency itself is dropped — see **m3**.
