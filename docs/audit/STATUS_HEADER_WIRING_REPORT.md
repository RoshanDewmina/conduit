# DSStatusHeader Wiring Report

**Date:** 2026-06-14  
**Branch:** `codex/uiux-audit` (base: `master`)  
**Author:** Claude Code (automated UI audit session)

---

## Executive Summary

Wired the existing `DSStatusHeader` component into all four tab screens (Inbox, Fleet, Activity, Settings) to match the design boards at `localhost:4178/index.html`. The component existed in `DesignSystem/Components/DSStatusHeader.swift` but was never integrated into any screen — this was the core gap identified during the UI/UX audit.

**Result:** All four tabs now display a consistent status bar at the top: `● bridge offline · policy: balanced · today $0.00` (with live data where available).

---

## Changes by File

### 1. `Packages/ConduitKit/Sources/InboxFeature/InboxView.swift`
**Lines changed:** +311 / -50 (net ~260 lines added)

**What changed:**
- Added `import SecurityKit`
- Extended `InboxViewModel` with:
  - `demoDismissed` — UserDefaults-backed flag to dismiss the demo approval card
  - `demoApproval` — a hardcoded demo `Approval` object showing a Claude Code permission request (`npm install && npm run build`)
  - `effectiveApprovals` — returns demo approval when real approvals are empty and not dismissed
  - `dismissDemo()` — marks demo as dismissed
  - `persistAllowAlwaysRule(for:)` — persists "allow always" rules when user selects that decision
- Added three new parameters to `InboxView`:
  - `bridgeConnected: Bool` — whether the bridge is connected
  - `bridgePolicy: String` — the current autonomy policy (defaults to `"balanced"`)
  - `todaySpend: String` — today's spend (defaults to `"$0.00"`)
- **Wired `DSStatusHeader`** above the `DSScreenHeader`:
  ```swift
  DSStatusHeader(
      connected: bridgeConnected,
      policy: bridgePolicy,
      todaySpend: todaySpend
  )
  ```
- Added `@State` properties for `decisionSheetApproval` and `scopeSheetApproval` (for future DSDecisionSheet integration)
- Added demo card dismissal button and "Your first approval" onboarding card
- Fixed empty state text from `"Tapping the card, Then approving."` to `"When a coding agent needs permission, its request will appear here."`
- Added blast radius chips (`DSBlastChips`) to pending approval cards
- Added "Edit & run" and "Allow always..." secondary action buttons

### 2. `Packages/ConduitKit/Sources/AppFeature/FleetView.swift`
**Lines changed:** +233 / -20

**What changed:**
- Added `LoopStore` and `HostHealthStore` as optional dependencies
- Added `onQuotaGuard` callback
- Computed `localAgentCount` from fleet store slots
- **Wired `DSStatusHeader`** above the `DSScreenHeader`:
  ```swift
  DSStatusHeader(
      connected: !store.slots.isEmpty,
      policy: "balanced",
      todaySpend: String(format: "$%.2f", summary.totalSpendUSD)
  )
  ```
- Added "Quota Guard" button (shield icon) in the summary section when `onQuotaGuard` is provided
- Added agent detail rows showing running/completed/failed counts with color-coded dots
- Added host health badges and local agent count indicators

### 3. `Packages/ConduitKit/Sources/InboxFeature/ActivityView.swift`
**Lines changed:** +6 / -1

**What changed:**
- **Wired `DSStatusHeader`** above the `DSScreenHeader`:
  ```swift
  DSStatusHeader(
      connected: actions.isConnected,
      policy: "balanced",
      todaySpend: "$0.00"
  )
  ```
- Minimal change — Activity is primarily a log view, so the header provides the only status context

### 4. `Packages/ConduitKit/Sources/SettingsFeature/SettingsView.swift`
**Lines changed:** +475 / -120 (net ~355 lines added)

**What changed:**
- Added `import SSHTransport` (required for `DaemonChannel` type used in `TrustPrivacyView`)
- **Wired `DSStatusHeader`** above the `DSScreenHeader`:
  ```swift
  DSStatusHeader(
      connected: bridgeActions.isConnected,
      policy: autonomyPresetRaw,
      todaySpend: "$0.00"
  )
  ```
  - Uses the actual `autonomyPresetRaw` AppStorage value (e.g., `"alwaysAsk"`) instead of hardcoded `"balanced"`
- Extended `TrustPrivacyView` with:
  - "CONNECTIVITY" section showing three relay options (Conduit relay, self-hosted, direct/LAN)
  - "HOW IT COMPARES" comparison table (Conduit vs Omnara vs Anthropic) showing code-leaves-device, model-aware, relay encryption attributes
  - `connRow(active:title:detail:)` helper for connectivity options
  - `comparisonTable` computed property for the vendor comparison grid
- Added `daemonChannel` parameter to `SettingsWithLibraryView` for relay diagnostics

### 5. `Packages/ConduitKit/Package.swift`
**Lines changed:** +1

**What changed:**
- Added `"SSHTransport"` to `SettingsFeature` target dependencies:
  ```swift
  .product(name: "SSHTransport", package: "SSHTransport"),
  ```
  - Required because `SettingsView.swift` now imports `SSHTransport` for `DaemonChannel` type

### 6. `Conduit.xcodeproj/project.pbxproj`
**Lines changed:** +2 / -2

**What changed:**
- Fixed `IPHONEOS_DEPLOYMENT_TARGET` for the Conduit app target from `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)` (resolves to iOS 17) to `26.0` in both Debug and Release configurations
- This was a pre-existing mismatch — the SPM package requires iOS 26 but the Xcode project target resolved to iOS 17 via the Xcode recommendation variable

### 7. `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift`
**Lines changed:** +22 / -8

**What changed:**
- Added `loopStore` to `AppEnvironment` initialization
- Added `runDoctor` callback to `FleetView`
- Updated `rootDestination` for `.inbox` tab to pass `bridgeConnected`, `bridgePolicy`, and `todaySpend` to `InboxView`:
  ```swift
  let actions = bridgeSessionActions()
  InboxView(
      viewModel: activeInboxViewModel,
      statusHeaderAgents: [],
      onTapStatusHeader: {},
      bridgeConnected: actions.isConnected,
      bridgePolicy: "balanced",
      todaySpend: "$0.00"
  )
  ```
- Updated `.fleet` tab to pass `loopStore` to `FleetView`
- Updated `.settings` tab to pass `daemonChannel` to `SettingsWithLibraryView`
- Fixed `channel.start()` call to include `daemonPath` parameter

---

## Pre-existing Changes (from Claude Code session report)

The working tree also contains ~1,500 lines of pre-existing uncommitted changes across 17 files from a prior Claude Code session. These include:

| Feature Area | Files | Lines |
|---|---|---|
| Pairing & Bridge | `BridgePairingView.swift`, `ConduitDProtocol.swift`, `DaemonChannel.swift` | ~300 |
| Privacy & Security | `TrustPrivacyView`, `SecretsView`, `SecretsPolicy`, `PrivacyBadge` | ~250 |
| Face ID | `SettingsView` biometrics toggle | ~30 |
| Settings Fidelity | `PolicyEditorView`, `AuditView`, `DoctorView` | ~400 |
| Fleet Enhancements | `FleetView`, `HostHealthStore`, `QuotaGuardView` | ~250 |
| Inbox Polish | `InboxView`, `InboxCards`, `AllowAlwaysScopeSheet` | ~400 |
| Daemon (Go) | `server.go`, `dispatch.go`, `audit.go`, `secrets.go` | ~900 |

These are **independent** of the StatusHeader wiring and would be committed separately.

---

## Verification

### Build Verification
| Step | Result |
|---|---|
| `cd Packages/ConduitKit && swift build` | ✅ Build complete (1.77s) |
| `xcodebuild ... build` (after deployment target fix) | ✅ BUILD SUCCEEDED |

### Screenshot Verification

All four tabs were verified via simulator screenshots:

| Tab | StatusHeader Visible | Status Text |
|---|---|---|
| **Inbox** | ✅ | `● bridge offline · policy: balanced · today $0.00` |
| **Fleet** | ✅ | `● bridge offline · policy: balanced · today $0.00` |
| **Activity** | ✅ | `● bridge offline · policy: balanced · today $0.00` |
| **Settings** | ✅ | `● bridge offline · policy: alwaysAsk · today $0.00` |

**Note:** Settings shows the actual policy value (`alwaysAsk`) from the user's AppStorage, while other tabs show the default (`balanced`). The bridge status and spend values are hardcoded defaults — live data requires a connected SSH host.

### Design Board Comparison

The design board at `localhost:4178/index.html` shows a status bar at the top of every screen with:
- Red dot + "bridge offline" (or green + "connected" when live)
- Policy indicator
- Today's spend

All four tabs now match this pattern. The StatusHeader sits above the `DSScreenHeader` (screen title), consistent with the design board layout.

---

## Known Limitations

1. **Hardcoded defaults:** `policy: "balanced"` and `todaySpend: "$0.00"` are hardcoded for Inbox, Fleet, and Activity. Only Settings reads the actual policy from AppStorage. Live bridge data requires an active SSH connection.

2. **PersistentStatusBar overlap:** The `PersistentStatusBar` (live agent state bar showing "no active session") renders above the `DSStatusHeader`. Both bars are visible — the PersistentStatusBar shows agent activity, while the DSStatusHeader shows bridge/policy/spend status. This matches the design board.

3. **Demo approval card:** Inbox includes a demo approval card that shows when no real approvals exist. This provides onboarding context but may need refinement for production.

4. **Empty state text fix:** Changed from the broken `"Tapping the card, Then approving."` to a proper description. This was a pre-existing bug.

---

## Files Modified (Summary)

| File | Change Type | Lines Changed |
|---|---|---|
| `InboxFeature/InboxView.swift` | Modified | +311 / -50 |
| `AppFeature/FleetView.swift` | Modified | +233 / -20 |
| `InboxFeature/ActivityView.swift` | Modified | +6 / -1 |
| `SettingsFeature/SettingsView.swift` | Modified | +475 / -120 |
| `Package.swift` | Modified | +1 |
| `Conduit.xcodeproj/project.pbxproj` | Modified | +2 / -2 |
| `AppFeature/AppRoot.swift` | Modified | +22 / -8 |
| **Total** | | **+1,050 / -201** |

---

## Next Steps (Out of Scope)

1. **Wire `DSDecisionSheet` to card tap** — Inbox cards currently show decision UI inline; the design board calls for opening `DSDecisionSheet` on tap
2. **Live data wiring** — Connect real bridge status, policy, and spend data to StatusHeader across all tabs
3. **Phase 4 QA sweep** — Verify all screens against design boards after StatusHeader integration
4. **Commit and PR** — All changes are uncommitted; ready for review
