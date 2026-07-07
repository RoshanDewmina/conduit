# View sweep — 2026-07-06

Systematic audit of every SwiftUI view surface after the Cursor shell cutover.

## Cursor shell (PASS — screenshot suite)

`LancerUITests/CursorAppShellExhaustiveTests` walks and screenshots:

| View | File | Status |
|------|------|--------|
| Onboarding | `CursorOnboardingView.swift` | Cursor ✓ |
| Workspaces root | `CursorWorkspacesView.swift` | Cursor ✓ |
| Profile drawer | `CursorProfileDrawer.swift` | Cursor ✓ |
| App Settings | `CursorSettingsView.swift` | Cursor ✓ |
| Search overlay | `CursorSearchOverlay.swift` | Cursor ✓ |
| Repo thread list | `CursorWorkspaceThreadListView.swift` | Cursor ✓ |
| Repo picker | `CursorRepoPickerSheet.swift` | Cursor ✓ |
| Work thread | `CursorWorkThreadView.swift` | Cursor ✓ |
| Review / approval | `CursorReviewDiffView.swift` | Cursor ✓ |
| PR detail | `CursorPRDetailView.swift` | Cursor ✓ |
| Composer sheet | `CursorComposerSheet.swift` | Cursor ✓ (floating card) |
| Run-on picker | `CursorRunOnSheet.swift` | Cursor ✓ |
| Model picker | `CursorModelSheet.swift` | Cursor ✓ (Haiku default live) |
| Relay pairing | `CursorRelayPairingSheet.swift` | Cursor ✓ |

## App overlays migrated this sweep

| View | File | Change |
|------|------|--------|
| Relay file browser | `RelayFileBrowserView.swift` | Migrated DS → Cursor chrome |
| Relay workspace unavailable | `SessionWorkspaceContainer.swift` | Migrated DS → Cursor chrome |
| Legacy activity drawer | `ActivityView.swift` | **Deleted** (route removed) |

## Still legacy DesignSystem (reachable only via SSH / drawers)

These remain on the old Lancer DS because they are SSH-terminal infrastructure, not Cursor navigation targets. They are **not** reachable from the default Workspaces → thread flow.

| View | File | Reachable via |
|------|------|----------------|
| Add host | `AddHostView.swift` | `drawerRoute.addHost` (SSH path) |
| Host editor | `HostEditorView.swift` | Add host advanced |
| Live SSH session | `SessionView.swift` | Connected host fullScreenCover |
| Workspace drawer tabs | `SessionWorkspaceContainer.swift` | SSH session drawer |
| Password prompt | `AppRoot.swift` `PasswordPromptView` | SSH connect |
| Quota guard | `QuotaGuardView.swift` | Paywall seam |

## Deleted this pass (~250KB legacy UI)

**SettingsFeature** (views removed, kept `SettingsViewModel`, `PurchaseManager`, `PaywallSheet`, `BillingEligibility`):
- `SettingsView.swift` and all policy/settings sub-views (18 files)

**InboxFeature** (kept `InboxViewModel` + `LiveInboxViewModel`):
- `InboxView.swift`, `BridgeAuditFeedView.swift`, `AllowAlwaysScopeSheet.swift`

## Migrated this pass

| View | Change |
|------|--------|
| `PasswordPromptView` (AppRoot) | Full Cursor chrome |
| `AddHostView` | Cursor-style header + light background |

## Still legacy (SSH terminal stack only)

`SessionView`, workspace drawer tabs, `HostEditorView` body, `QuotaGuardView`, `PaywallSheet` (monetization — separate visual language OK for now)

- `LegacyUIRemovalTests` — fails if POLICY BRIDGE / GENERAL / legacy Inbox appear
- `DispatchHaikuFlowTests` — composer defaults to Claude Haiku 4, dispatch send
- `CursorShellLiveApprovalTests` — approval banner → Review → Approve

## Next pass (if continuing)

1. Cursor-style `AddHostView` or hide SSH add-host behind Settings → Trusted machines only
2. Delete orphaned `SettingsView.swift` tree + `InboxView` struct (keep `InboxViewModel`)
3. SSH `SessionView` — optional Cursor header; terminal body stays DS/monospace by design
