# V1_SIMPLIFY_REPORT

Date: 2026-06-15
Branch: opencode/v1-simplify

---

## CHANGE 1 — Remove persistent top status bar from all 4 tabs

**Files touched:**
- `Packages/ConduitKit/Sources/InboxFeature/InboxView.swift` — removed `DSStatusHeader(...)` call (lines 123-127) and removed unused `bridgeConnected`, `bridgePolicy`, `todaySpend` params from struct + init. Kept `statusHeaderAgents` (still used by `AgentStatusHeader`).
- `Packages/ConduitKit/Sources/AppFeature/FleetView.swift` — removed `DSStatusHeader(...)` call.
- `Packages/ConduitKit/Sources/InboxFeature/ActivityView.swift` — removed `DSStatusHeader(...)` call.
- `Packages/ConduitKit/Sources/SettingsFeature/SettingsView.swift` — removed `DSStatusHeader(...)` call from `headerSection`.
- `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift` — removed both `PersistentStatusBar(...)` usages (lines 765-775 in `compactRoot`, lines 821-828 in `regularRoot`).

Did NOT touch `DSScreenHeader` or `SpectrumBar` — the rainbow gradient strip remains.

---

## CHANGE 2 — Declutter Fleet (`FleetView.swift`)

**Files touched:**
- `Packages/ConduitKit/Sources/AppFeature/FleetView.swift` — removed three sections from the LazyVStack:
  - `DSSpendHero` block (spend hero card)
  - Quota Guard navigation row (`NavigationLink { QuotaGuardView ... }` and `onQuotaGuard` Button)
  - "Branches & Worktrees" navigation row (`NavigationLink { WorktreeBoardView ... }`)

Kept the `quotaGuardEntry` and `worktreesLink` computed properties and all types/code — only removed the view calls.

---

## CHANGE 3 — Fix onboarding skip routing

**Files touched:**
- `Packages/ConduitKit/Sources/OnboardingFeature/OnboardingView.swift` — added `onAlreadyUseConduit: () -> Void` property and init parameter (defaults to `{}`). Changed the "i already use conduit" button at step 0 to call `onAlreadyUseConduit()` instead of `onContinue()`.
- `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift` — passed `onAlreadyUseConduit` closure that sets `onboardingSeen = true; selectedTab = .fleet` (without `addHostPresented = true`).

This reuses the normal onboarding-complete state (`onboardingSeen = true`) but skips the AddHost sheet that `onContinue` triggers.

---

## CHANGE 4 — Re-gate conduit cloud tab in AddHostView

**Files touched:**
- `Packages/ConduitKit/Sources/AgentKit/ProvisioningFeatureFlags.swift` — added `managedCloudEnabled` static property (UserDefaults key `conduitManagedCloudEnabled`, defaults to `false`) following the same pattern as the existing `lightsailEnabled`.
- `Packages/ConduitKit/Sources/WorkspacesFeature/AddHostView.swift` — imported `AgentKit`; modified `modePicker` to conditionally include "conduit cloud" in the picker options only when `ProvisioningFeatureFlags.managedCloudEnabled` is `true`. When the flag is off, only "bring your own" is shown.

---

## VERIFY

```
$ cd Packages/ConduitKit && swift build
Build complete! (45.15 secs.)
```

**NOTE:** All modified view files (`InboxView.swift`, `FleetView.swift`, `ActivityView.swift`, `SettingsView.swift`, `AppRoot.swift`, `OnboardingView.swift`, `AddHostView.swift`) are guarded by `#if os(iOS)`, so `swift build` skips them. Only `ProvisioningFeatureFlags.swift` (cross-platform) was compiled and verified. An Xcode app-target build is required for full verification — all changed files are listed above for the reviewer.

---

## Notes / Uncertainties

None. All changes were straightforward removals or additions following existing code patterns. The `onAlreadyUseConduit` default empty closure maintains backward compatibility if any call site doesn't provide it.
