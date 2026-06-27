# V1 Readiness Audit — Screen Reachability, Dead Code & Cheap Wins

**File:** `docs/audit/V1_READINESS_AUDIT.md`
**Date:** 2026-06-15
**Branch:** `oc/readiness-audit2`

## 1. Screen Reachability Table

### Reachable from production (tab, navigation destination, sheet, full-screen cover)

| View | File:Line | Reachable via |
|---|---|---|
| `AppRoot` | `AppFeature/AppRoot.swift:123` | Root entry point |
| `LaunchLockView` | `AppFeature/AppRoot.swift:1324` | App lock check |
| `OnboardingView` | `OnboardingFeature/OnboardingView.swift:21` | `readyRoot` sheet (`AppRoot:433`) |
| `ProvisioningWizard` | `OnboardingFeature/ProvisioningWizard.swift:91` | Sheet (`AppRoot:451`) |
| `InboxView` | `InboxFeature/InboxView.swift:47` | `.inbox` tab (`AppRoot:959`) |
| `BridgeAuditFeedView` | `InboxFeature/BridgeAuditFeedView.swift:6` | InboxView + ActivityView |
| `AllowAlwaysScopeSheet` | `InboxFeature/AllowAlwaysScopeSheet.swift:11` | InboxView sheet |
| `ActivityView` | `InboxFeature/ActivityView.swift:6` | `.activity` tab (`AppRoot:988`) |
| `FleetView` | `AppFeature/FleetView.swift:7` | `.fleet` tab (`AppRoot:967`) |
| `SettingsView` | `SettingsFeature/SettingsView.swift:380` | Via `SettingsWithLibraryView` |
| `TrustPrivacyView` | `SettingsFeature/SettingsView.swift:154` | Settings nav link |
| `TerminalSettingsView` | `SettingsFeature/TerminalSettingsView.swift:6` | Settings nav link |
| `E2ERelayPairingView` | `SettingsFeature/E2ERelayPairingView.swift:7` | Settings nav link |
| `PremiumComparisonView` | `SettingsFeature/PremiumComparisonView.swift:6` | Settings nav link |
| `BillingView` | `SettingsFeature/BillingView.swift:8` | Settings nav link |
| `ProviderKeysView` | `SettingsFeature/ProviderKeysView.swift:7` | Settings nav link |
| `PolicyEditorBridgeScreen` | `SettingsFeature/PolicyEditorBridgeScreen.swift:7` | Settings nav link |
| `PolicyEditorView` | `SettingsFeature/PolicyEditorView.swift:6` | Via PolicyEditorBridgeScreen |
| `PolicySimulatorView` | `SettingsFeature/PolicySimulatorView.swift:6` | Via PolicyEditorView |
| `SecretsView` | `SettingsFeature/SecretsView.swift:92` | Settings nav link |
| `AuditView` | `SettingsFeature/AuditView.swift:99` | Settings nav link |
| `DoctorView` | `SettingsFeature/DoctorView.swift:36` | Settings nav link |
| `SyncStatusView` | `SettingsFeature/SyncStatusView.swift:7` | Embedded in SettingsView |
| `PaywallSheet` | `SettingsFeature/PaywallSheet.swift:6` | Sheet |
| `SessionView` | `SessionFeature/SessionView.swift:8` | Full-screen cover (`AppRoot:858`) |
| `ChatHeaderView` | `SessionFeature/Chat/ChatHeaderView.swift:8` | SessionView |
| `ChatTranscriptView` | `SessionFeature/Chat/ChatTranscriptView.swift:11` | SessionView |
| `ToolCardView` | `SessionFeature/Chat/ToolCardView.swift:11` | ChatTranscriptView |
| `ChatInputBar` | `SessionFeature/Chat/ChatInputBar.swift:20` | SessionView |
| `SSHConnectOverlay` | `SessionFeature/SSHConnectOverlay.swift:35` | SessionView |
| `SnippetPaletteSheet` | `SessionFeature/SnippetPaletteSheet.swift:6` | SessionView sheet |
| `PortForwardView` | `SessionFeature/PortForwardView.swift:92` | SessionView sheet |
| `KeyboardAccessoryRail` | `SessionFeature/KeyboardAccessoryRail.swift:72` | SessionView |
| `LivePromptInputView` | `SessionFeature/LivePromptInputView.swift:18` | ChatInputBar |
| `RawTerminalView` | `TerminalEngine/RawTerminalView.swift:46` | SessionView, ToolCardView |
| `AddHostView` | `WorkspacesFeature/AddHostView.swift:17` | Sheet |
| `HostEditorView` | `WorkspacesFeature/HostEditorView.swift:158` | Sheet |
| `KeysView` | `KeysFeature/KeysView.swift:106` | Settings nav link |
| `KeyImportView` | `KeysFeature/KeyImportView.swift:99` | KeysView sheet |
| `DiffView` | `DiffFeature/DiffView.swift:6` | InboxView, LoopDetailView, AgentRunDetailView |
| `LoopDetailView` | `AppFeature/LoopDetailView.swift:9` | FleetView nav link |
| `RunDetailView` | `AppFeature/RunDetailView.swift:15` | Sheet |
| `DispatchView` | `AppFeature/DispatchView.swift:28` | Sheet |
| `AgentsView` | `AppFeature/AgentsView.swift:8` | Sheet |
| `AgentDetailView` | `AppFeature/AgentDetailView.swift:10` | AgentsView nav link |
| `AgentRunDetailView` | `AppFeature/AgentRunDetailView.swift:10` | AgentDetailView nav link |
| `AgentOrgView` | `AppFeature/AgentOrgView.swift:9` | AgentDetailView nav link |
| `AgentExecView` | `AppFeature/AgentExecView.swift:9` | AgentDetailView nav link |
| `AgentFilesView` | `AppFeature/AgentFilesView.swift:12` | AgentDetailView + AgentRunDetailView |
| `AgentWorkspaceView` | `AppFeature/AgentWorkspaceView.swift:11` | AgentDetailView nav link |
| `CreateAgentSheet` | `AppFeature/CreateAgentSheet.swift:7` | AgentsView sheet |
| `EditScheduleSheet` | `AppFeature/EditScheduleSheet.swift:9` | AgentDetailView sheet |
| `AgentBillingSheet` | `AppFeature/AgentBillingSheet.swift:10` | AgentsView sheet |

### Debug/gallery-only (only from `DebugGalleryView.swift`)

| View | File:Line |
|---|---|
| `DebugGalleryView` | `AppFeature/DebugGalleryView.swift:18` |
| `ReviewSessionRow` | `AppFeature/DebugGalleryView.swift:731` |
| `ReviewActivityItem` | `AppFeature/DebugGalleryView.swift:813` |
| `BlocksReviewScreen` | `AppFeature/DebugGalleryView.swift:891` |
| `AgentHUDGalleryScreen` | `AppFeature/DebugGalleryView.swift:985` |
| `TypedInboxGalleryScreen` | `AppFeature/DebugGalleryView.swift:1117` |
| `FeaturesGalleryScreen` | `AppFeature/DebugGalleryView.swift:1245` |
| `KeyboardGalleryScreen` | `AppFeature/DebugGalleryView.swift:1426` |
| `ProofCardGalleryScreen` | `AppFeature/DebugGalleryView.swift:1497` |
| `StatesGalleryScreen` | `AppFeature/StatesGallery.swift:8` |
| `DebugSessionHarness` | `AppFeature/DebugSessionHarness.swift:19` |
| `DebugTerminalHarness` | `AppFeature/DebugTerminalHarness.swift:16` |
| `OrbConnectedDemo` | `AppFeature/DebugGalleryView.swift:701` |
| `OrbPhasesDemo` | `AppFeature/DebugGalleryView.swift:714` |
| `AgentStatusHeaderGalleryScreen` | `AppFeature/DebugGalleryView.swift:1046` |
| `OnboardingRedesignGalleryView` | `OnboardingFeature/OnboardingRedesignGalleryView.swift:5` |

### Orphaned (defined, zero production references)

| View | File:Line | Notes |
|---|---|---|
| `SessionsHomeView` | `AppFeature/SessionsHomeView.swift:43` | Vestigial — replaced by tab-based navigation |
| `SessionRowView` | `AppFeature/SessionsHomeView.swift:255` | Only referenced from SessionsHomeView |
| `KeysManagementView` | `AppFeature/LibrarySupportViews.swift:9` | Skeleton — keys managed via KeysView instead |
| `WorktreeBoardView` | `AppFeature/WorktreeBoardView.swift:7` | Full board view, never linked |
| `QuotaGuardView` | `AppFeature/QuotaGuardView.swift:6` | Standalone view, never linked |
| `FilesView` | `FilesFeature/FilesView.swift:66` | File browser — file ops done via AgentFilesView |
| `SFTPFilesView` | `FilesFeature/FilesView.swift:127` | Same feature, never linked |
| `SnippetEditorView` | `SettingsFeature/SnippetEditorView.swift:8` | Full snippet editor, no nav link |
| `PreviewSurface` | `PreviewFeature/PreviewSurface.swift:8` | Entire PreviewFeature has zero production routes |
| `PreviewView` | `PreviewFeature/PreviewSurface.swift:31` | Same |
| `SmartPreviewView` | `PreviewFeature/PreviewSurface.swift:48` | Same |
| `PreviewToolbar` | `PreviewFeature/PreviewToolbar.swift:6` | Same |
| `ExplainSheet` | `SessionFeature/ExplainSheet.swift:8` | Standalone — inline explainSheet used instead |
| `LiveTerminalView` | `SessionFeature/LiveTerminalView.swift:183` | Only in DebugGalleryView |
| `GlobalInboxGateView` | `AppFeature/AppRoot.swift:1377` | Defined, never instantiated |

## 2. Dead Code — Production-Unreferenced Symbols

| Symbol | File:Line | Evidence |
|---|---|---|
| `InboxViewModel.dismissDemo()` | `InboxFeature/InboxView.swift:24` | Only called from dead `isDemo` branches |
| `isDemo = false` + all `isDemo ? X : Y` branches | `InboxFeature/InboxView.swift:173,265,277,289,297` | Dead ternary — always evaluates to `else` |
| `DSEmptyState` (private redeclaration) | `AppFeature/WorktreeBoardView.swift:268` | Shadows DesignSystem's `DSEmptyState` |
| `RunDiff` | `AppFeature/AgentRunDetailView.swift:410` | Private shim, unused |
| `IdentifiableDiff` | `AppFeature/LoopDetailView.swift:544` | Fileprivate shim, unused |
| `DSIconTokenView` | `DesignSystem/Components/DSIcon.swift:466` | Public, zero production refs |
| `DSSpendHero` | `DesignSystem/Components/DSSpendHero.swift:7` | Public, zero production refs |
| `DSStatusHeader` | `DesignSystem/Components/DSStatusHeader.swift:9` | 1 internal ref only |
| `DSMetricTile` | `DesignSystem/Components/ManagementAtoms.swift:6` | Public, zero production refs |
| `DSRiskRow` | `DesignSystem/Components/ManagementAtoms.swift:69` | Public, zero production refs |
| `DSStepNode` | `DesignSystem/Components/ManagementAtoms.swift:120` | Public, zero production refs |
| `DSHealthRow` | `DesignSystem/Components/ManagementAtoms.swift:176` | Public, zero production refs |
| `DSToast` | `DesignSystem/Components/Primitives.swift:527` | Public, zero production refs |
| `DSSkeletonRow` | `DesignSystem/Components/States/DSSkeletonRow.swift:7` | Public, zero production refs |

## 3. Cheap Wins — Quick Fixes

| Location | Line | Issue | Proposed fix |
|---|---|---|---|
| `InboxFeature/InboxView.swift` | 23-24, 173, 265, 277, 289, 297 | `isDemo` dead branches + `dismissDemo()` | Remove all `isDemo` conditionals and `dismissDemo()`. The demo teaser was removed; dead code remains. |
| `AppFeature/AppRoot.swift` | 1121 | `"SSH agent forwarding is not implemented yet."` | Either implement the feature or remove the affordance pointing to it. |
| `OnboardingFeature/AgentOrgView.swift` | 99 | `"Invites are recorded on the server; email delivery is not yet enabled."` | Either enable email delivery or soften the copy to "coming soon." |
| `AppFeature/AppRoot.swift` | 95 | `.xai` provider: `return nil  // M5+` | Gate behind feature flag to avoid user-facing empty state for a provider that doesn't work. |
| `SettingsFeature/SnippetEditorView.swift` | entire file | No nav link reaches this view | Either add a nav link from Settings or remove the dead feature. |
| `PreviewFeature/*` | entire feature | No production routes reach any preview view | Either wire navigation or remove/dead-strip the feature. |
| `FilesFeature/FilesView.swift` | entire file | File browser defined but unreachable | Either wire via a file navigation action or remove. |

## 4. Prioritized Lists

### Fix before dogfood (high impact, low effort)

| Priority | Issue | Location | Fix |
|---|---|---|---|
| P1 | Dead `isDemo` branches | `InboxFeature/InboxView.swift` multiple lines | Remove dead ~50 lines of branching code |
| P2 | `SSH agent forwarding not implemented` user-facing string | `AppFeature/AppRoot.swift:1121` | Remove the feature affordance or gate it |
| P3 | `.xai` provider returns nil with no error state | `AppFeature/AppRoot.swift:95` | Add feature flag or show disabled state |

### Fix before publish (lower impact, higher effort)

| Priority | Issue | Location | Fix |
|---|---|---|---|
| P4 | Orphaned `SessionsHomeView` ~300 lines dead code | `AppFeature/SessionsHomeView.swift` | Remove if redundant with tab nav |
| P5 | `FilesFeature` entire module unreachable | `FilesFeature/FilesView.swift` | Wire navigation or dead-strip |
| P6 | `PreviewFeature` entire module unreachable | `PreviewFeature/*` | Wire or dead-strip |
| P7 | `SnippetEditorView` unreachable | `SettingsFeature/SnippetEditorView.swift` | Wire nav link or dead-strip |
| P8 | DesignSystem components with zero production refs | Various (`DSMetricTile`, `DSRiskRow`, `DSStepNode`, `DSHealthRow`, `DSToast`, `DSSkeletonRow`, `DSIconTokenView`, `DSSpendHero`) | Audit and either remove or ensure they're used before publishing |
| P9 | "email delivery not yet enabled" user-facing copy | `OnboardingFeature/AgentOrgView.swift:99` | Fix copy or implement delivery |

## 5. Summary

- **Reachable views:** ~55
- **Debug/gallery-only:** 16
- **Orphaned views (dead code):** ~17
- **Dead non-view symbols:** ~15 (mostly in DesignSystem)
- **User-facing TODOs/placeholders requiring action:** 4
- **Known compiler warning:** resolved (was `InboxView.swift:272`, `isDemo` ternary — build emits no warnings from our code)