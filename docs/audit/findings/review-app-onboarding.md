# Governed Approvals v1 — Pre-submission audit: App shell / Fleet / Activity / Agents / Workspaces / Onboarding

Branch: `feat/governed-approvals` (NEW IA: Inbox / Fleet / Activity / Settings).
Scope: navigation, state/lifecycle, strict concurrency, onboarding, TOFU UI, empty/loading/error, retain cycles, silent failures.
Out of scope (other reviewer): ApprovalIngest / FleetStore approval-decision logic.
Method: static read of the worktree; no builds run; every candidate ran through an adversarial reachability pass.

---

## App navigation map (for the E2E coordinator)

### Root selection — `AppRoot.body` → `mainBody` → `readyRoot` → `rootContainer`
- `#if DEBUG` `LANCER_GALLERY` → `DebugGalleryView` (gallery harness; not a normal launch).
- App-lock gate: if `appLockEnabled && !isUnlocked` → `LaunchLockView` (biometric).
- `environment == .failure` → `ContentUnavailableView("Failed to start")` (dead-end by design — DB open failed).
- First launch (`onboardingSeen == false`) → `OnboardingView` (7 screens).
- Else → `rootContainer`, which forks on size class:
  - **Compact (iPhone)** → `compactRoot`: `PersistentStatusBar` on top + custom `DSTabBar`; the selected tab is rendered as its **own** `NavigationStack` (`tabContent`).
  - **Regular (iPad/landscape)** → `regularRoot`: `NavigationSplitView` (sidebar lists the 4 tabs) + `detail: rootDestination(selectedTab)` — **no NavigationStack in detail** (see MAJOR-2).

### Tabs (`rootDestination`)
- **Inbox** (`tray`) → `InboxView(activeInboxViewModel)` — pending/decided approvals; `editingApproval`/`diffApproval` sheets. Empty state present.
- **Fleet** (`server`) → `FleetView(fleetStore)` — summary strip + connected slots' agent rows. Empty state → **"Connect a host"** → `addHostPresented` sheet (`AddHostView`). Rows are **not** tappable.
- **Activity** (`clock.arrow.circlepath`) → `ActivityView(bridgeSessionActions())` — bridge audit tail; loading/empty/error all present (needs a connected bridge).
- **Settings** (`gear`) → `SettingsWithLibraryView` → `SettingsView` + toolbar **Library** link → `LibraryView` (snippets / SSH keys / hosted agents).

### How the terminal / live session is reached
1. **Connect flow:** Onboarding or Fleet "Connect a host" → `AddHostView` → *connect & save* → `AppRoot.openSession` → (`PasswordPromptView` sheet if password auth) → `AppRoot.startSession` → sets `isShowingLiveSession = true` → **`fullScreenCover` → `SessionView`** (the Warp-style block terminal).
2. **Re-entry:** `PersistentStatusBar` (top of compact/regular root) tap → `isShowingLiveSession = true` (only visible while `hudStore.agents` is non-empty, i.e. a live session exists).
3. **Notification "run complete"** → `selectFleetSlot` + `isShowingLiveSession = true`.
4. **Provisioning:** Onboarding screen 7 "create a workspace" → `ProvisioningWizard` sheet → `onComplete` → `openSession`.
5. **Hosted (cloud) agents:** `AddHostView` "lancer cloud" → `onUseHosted` → `showingHostedAgents` sheet → `AgentsView` → (its own NavigationStack) → `AgentDetailView` → Exec / Files / `AgentWorkspaceView` / `AgentOrgView` / `AgentRunDetailView`.

### Orphaned in the new IA (defined but never instantiated in any live path)
`HostsView`, `WorkspacesView`, `SessionsHomeView`, `WorkflowsView`, `HistoryView`, `DispatchComposerView`, and the `editingHost` sheet. The recents/saved-host **reconnect** capability lived in `SessionsHomeView`/`HostsView` and has no replacement — see MAJOR-4.

---

## BLOCKER

### [BLOCKER] AppRoot.swift:926 (+944) / SessionView.swift:196–212 / AppRoot.swift:455–468 — First connection to a new host (the TOFU path) hard-hangs; the host-key prompt never appears
`startSession` raises the live-session cover **before** connecting:
```
self.isShowingLiveSession = true   // AppRoot.swift ~926  (fullScreenCover → SessionView)
...
await vm.connect()                 // AppRoot.swift ~944  (host-key check happens HERE)
```
For any genuinely new host, `TOFUHostKeyValidator` throws `LancerError.hostKeyUnknown`, so `connect()` sets `pendingHostKeyFingerprint` and transitions to `.disconnected` (SessionViewModel.swift:298–305). Two independent defects then trap the user:

1. **The TOFU sheet can't present.** `HostKeyConfirmSheet` is attached via `.sheet` on `readyRoot` (AppRoot.swift:455–468), but `readyRoot` is the same presenter that is already presenting the `SessionView` `fullScreenCover` (raised from its `compactRoot`/`regularRoot` descendant). A view controller can present only one modal at a time, and SwiftUI cannot present a `.sheet` over a `.fullScreenCover` from the same presenter — the host-key prompt is deferred/dropped, so it never becomes visible.
2. **The connect overlay sticks.** `SessionView`'s `SSHConnectOverlay` is shown for `.connecting` and its `.onChange(of: vm.status)` has **no case for `.disconnected`** (SessionView.swift:196–211, `default: break`). So after the host-key failure the overlay stays on a full-screen `Color.black.opacity(0.9)` "Connecting…" frame forever, covering the `ChatHeaderView` back button; its tap handler is inert for the `.connecting` phase. `fullScreenCover` has no interactive swipe-dismiss. The user is hard-stuck and must force-quit.

**Reachability:** EVERY first connect to a new host (BYO via `AddHostView`, password or Ed25519, and the provisioning path) — `hostKeyUnknown` always fires the first time. New hosts can therefore never be trusted/connected; relaunch repeats the hang. This makes the governed-approvals session flow unusable for any host not already trusted. Confirmed: `SessionView` never references `pendingHostKeyFingerprint`/`HostKeyConfirmSheet`, and `AddHostView.connectAndSave` does not pre-trust (no auto-trust), so the prompt path is the real path.

**Proposed fix:** Present the host-key confirmation from **inside** `SessionView` (so it's above the cover), OR do not raise `isShowingLiveSession` until the key is trusted/`status == .connected`. Independently, handle `.disconnected`/`hostKey pending` in the `SSHConnectOverlay` `onChange` so the overlay dismisses (or routes to the prompt) instead of sticking on "Connecting…". Either change alone unblocks; do both.

---

## MAJOR

### [MAJOR] AppRoot.swift:700–709 — Regular width (iPad/landscape): detail column has no NavigationStack, so in-tab pushes are dead
`regularRoot` puts `rootDestination(selectedTab)` directly in `NavigationSplitView { … } detail:` with no enclosing `NavigationStack`. `NavigationLink`s rendered in the detail (e.g. Settings → **Library** in `SettingsWithLibraryView.toolbar`, and `SettingsView`'s internal links) have no stack to push onto and silently do nothing.
**Reachability:** any regular-size-class layout (iPad, iPhone landscape on large devices). The compact path wraps each tab in its own `NavigationStack`, so iPhone portrait is fine.
**Proposed fix:** wrap the detail in `NavigationStack` (mirror `compactRoot`), or move to a `NavigationSplitView`-aware destination model.

### [MAJOR] OnboardingView.swift:837–842 — Face ID priming claims to enable app lock but never persists it
Screen 5 copy: *"Require Face ID before approving high-risk actions or opening the app."* The "use face id" button only runs `BiometricGate.shared.unlock(reason:)` once and then `advance()`; it never writes `@AppStorage("appLockEnabled")` (or any per-approval biometric flag). The user finishes onboarding believing the app/approvals are gated behind Face ID, but `appLockEnabled` stays `false`.
**Reachability:** every user who taps "use face id" in onboarding.
**Proposed fix:** set `appLockEnabled = true` (and/or the approval-biometric preference) on success; on biometric failure/cancel, don't claim it's enabled.

### [MAJOR] AppRoot.swift:415–428 / AddHostView.swift:845 — No saved-host list / edit / delete / reconnect in the new IA; re-adding duplicates hosts
The new IA dropped the Sessions/Hosts home. `HostsView`, `WorkspacesView`, `SessionsHomeView` and the `editingHost` sheet are never instantiated (`editingHost` is only ever set back to `nil`, AppRoot.swift:423). Fleet shows only **live** slots, not saved `Host` records. After relaunch (no live slots) the only action is "Connect a host" → `AddHostView`, which always mints `id: HostID()` (AddHostView.swift:845) → re-adding the same host creates duplicate records, and there's no UI to edit/delete them. Previously-saved hosts cannot be reconnected without re-entering details.
**Reachability:** any returning user (second launch onward).
**Proposed fix:** surface a saved-hosts/recents list with reconnect + edit/delete (the orphaned `SessionsHomeView`/`HostsView` already implement most of it), and upsert by identity instead of always minting a new `HostID`.

### [MAJOR] AppRoot.swift:443–454 — Password-retry-after-auth-failure sheet has the same present-over-cover conflict as the TOFU sheet
`awaitingPasswordRetry` (set after 2 auth failures during `connect()`, SessionViewModel.swift:322–323) drives a `.sheet` on `readyRoot`, which (like the TOFU sheet) can't present over the already-raised `SessionView` cover. The user sees the `.failed` overlay (dismissible), but the new-password prompt won't appear until they back out of the live session entirely; in-place reconnect re-uses the same wrong credential and re-fails.
**Reachability:** wrong password on the live connect flow. Recoverable (unlike the BLOCKER) by dismissing the cover, but confusing.
**Proposed fix:** same as the BLOCKER — present these auth sheets from within `SessionView`, or defer raising the cover until `connected`.

---

## MINOR

### [MINOR] AppRoot.swift:662–687 & 769–779 — Tab navigation state is not preserved across tab switches
The custom `DSTabBar` + `switch selectedTab` builds a fresh `NavigationStack` for only the selected tab, so switching tabs tears down the previous tab's stack: in-tab push depth and scroll position are lost, `.task`/`onAppear` re-run, and inline-constructed view models (e.g. `SettingsViewModel`, see NIT) are rebuilt on every re-entry. A real `TabView` keeps visited tab subtrees alive.
**Reachability:** any push-then-switch-tabs interaction. Functional impact is modest (most Settings state is `@AppStorage`/reloaded), but nav-depth loss is user-visible.
**Proposed fix:** use `TabView(selection:)` with one `NavigationStack` per tab, or hoist per-tab `NavigationPath` state into `AppRoot`.

### [MINOR] OnboardingView.swift:716–733 — SSH screen shows a hardcoded "detected on your network" success chip regardless of reality
The green pulse + "detected on your network" is static (comment: "static, best-effort feel"). It's a fabricated detection claim shown before any probe — conflicts with the honest-priming goal.
**Proposed fix:** drive it from a real reachability probe, or relabel it as illustrative ("you'll see this when detected").

### [MINOR] FleetView.swift:32–43 — Fleet rows aren't tappable; no manual active-slot switcher for multi-session
`agentRow` is plain content (not a Button/NavigationLink). With >1 fleet slot, the active slot can only change via notifications/`jumpToUnreadLiveSession`; there's no user-driven way to select a slot or open its terminal from Fleet.
**Proposed fix:** make rows select the slot (`selectFleetSlot`) and/or open `isShowingLiveSession`.

### [MINOR] AgentOrgView.swift:90–97 — "Send invite" silently swallows errors and clears the field on failure
`try? await store.inviteMember(...)` then `inviteEmail = ""` unconditionally → a failed invite looks identical to success.
**Proposed fix:** surface an error banner (the view already has the token palette for it) and keep the email on failure.

### [MINOR] AppRoot.swift:408–414 — `showingHostedAgents` renders a blank sheet if `agentStore` is still nil
The sheet body is `if let agentStore { … }` with no else; if `configureCloudServices` hasn't populated `agentStore` yet, the user gets an empty (swipe-only) sheet.
**Proposed fix:** show a `ProgressView`/placeholder in the `else`, or gate the trigger on `agentStore != nil`.

### [MINOR] AppRoot.swift:542–573 — Global `LiveInboxViewModel` from `configureGlobalInbox` is orphaned by `startSession`; its observation task leaks
`configureGlobalInbox` builds a `LiveInboxViewModel` (starting an `observationTask`, InboxViewModel+Live.swift:27) and assigns it to `inboxVM`/`liveInboxVM`. `startSession` then replaces both with a per-session VM, but the global VM's task is never stopped → duplicate DB observation / minor leak.
**Proposed fix:** stop/cancel the previous VM's observation before replacing, or reuse a single inbox VM.

### [MINOR] AppRoot.swift:883–942 — Per-session overwrite of `scenePhaseObserver` and watch handlers means only the latest slot gets lifecycle/watch handling
Each `startSession` reassigns `self.scenePhaseObserver`, `watchConnector.onEmergencyStop/onRunSnippet`, and `startSyncing(... sessionViewModel: vm ...)` to the newest session, so background suspend/resume and Watch emergency-stop/run only target the most recently connected slot, not all live slots.
**Proposed fix:** maintain per-slot observers, or document single-session lifecycle as a known limitation.

---

## NIT

### [NIT] OnboardingView.swift:334 — `await` on a non-async call
`await Notifications.shared.registerCategories()` awaits a `public nonisolated func registerCategories()` (Notifications.swift:201) — the flagged "no async operations occur within 'await'" warning. Drop the `await` (AppRoot.swift:266 calls it correctly without `await`).

### [NIT] AppRoot.swift:771 — `SettingsViewModel(keyStore:)` constructed inline in `rootDestination(.settings)`
A new VM is allocated on every body evaluation while the Settings tab is shown; `SettingsView`'s `@State` keeps the first, so the rest are wasted churn (harmless, but allocate once / hoist to `@State`).

### [NIT] AppRoot.swift:251–268 & 474–478 — Redundant duplicate work
`configureCloudServices` is invoked from both `mainBody`'s `.task` and `readyRoot`'s `.task`; notification `requestAuthorization` runs from `AppRoot`'s `.task` and again from the onboarding notification screen. The `agentStore == nil` guard makes it mostly idempotent, but `pm.configure`/`refreshCloudEntitlement`/relay config run twice.

### [NIT] HostEditorView.swift:204 — Stale instruction text
Ed25519 empty-state says "Generate an Ed25519 key in **Settings > SSH Keys**", but keys now live under **Library › SSH Keys** (cf. AddHostView.swift:642). Align the copy.

### [NIT] AppFeature — dead/unreachable views in the new IA
`SessionsHomeView`, `WorkflowsView`, `HistoryView`, `DispatchComposerView` (gallery-only) are defined but never instantiated in a live path. Either wire them into the new IA or remove to avoid reviewer confusion (note: `SessionsHomeView`/`HostsView` contain the reconnect/recents logic referenced in MAJOR-4).

---

## Cleared on adversarial pass (checked, not bugs)
- `HostKeyConfirmSheet` itself is correct TOFU UX: explicit **Trust & Connect** / **Cancel**, no auto-trust, fingerprint shown; the `.sheet` `set:` and both Cancel paths call `rejectHostKey()` which clears the fingerprint and transitions `.disconnected` (a clean abort). The defect is *presentation* (BLOCKER), not the sheet.
- `InboxView` stores its VM as a plain `var` (not captured `@State`), so live-VM swaps (`inboxVM = liveVM`) are observed correctly via `@Observable`.
- View models are `@MainActor @Observable`; cross-actor closures (`LiveInboxViewModel.onDecision`, watch sync) hop via `await MainActor.run`; lifecycle/session closures capture `[weak vm]`/`[weak self]`/`[weak agentStore]` — no obvious retain cycles or off-main UI mutations found.
- `CreateAgentSheet`, `EditScheduleSheet`, `AgentDetailView`, `AgentWorkspaceView`, `HostEditorView` have proper cancel paths, error surfacing, and `.task`-based loads; no recreate-each-render state loss (all use `@State`/`@Bindable` correctly).
- Onboarding: no skip path lands in a broken state — every exit (`get started`, `i already use lancer`, `not now`, `skip`, screen-7 CTAs) routes to `onContinue`/`onSetupWorkspace` and lands on Fleet with the add-host sheet; the Notifications step asks before claiming (honest).
