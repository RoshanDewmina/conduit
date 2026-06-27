# Phase 3 — Screen Inventory

> Canonical list of every screen / sheet / state, derived from navigation code (not by tapping).
> Reachability + keep/merge/defer/remove judged against the **V1-simplify** mandate.
> Source: AppRoot.swift (`SidebarDestination`, `AppDrawerRoute`), per-feature view files.
> Screenshot refs: **real-app** captures in `docs/design-handoff/app-screenshots/`; older component renders in `docs/audits/screenshots/`.

## ⚠️ Cleanup applied 2026-06-23 (build-verified; ~−10,000 LOC)
The following inventory entries have been **DELETED from code** (some rows below are now historical):
- **Debug gallery harness** (DebugGalleryView + all `*GalleryScreen`/`*Harness`/`StatesGallery`) — the LANCER_GALLERY route is gone.
- **Legacy onboarding** ON-L: `OnboardingView` + Welcome/InstallBridge/Pair/Scan/Paired/Caution/FirstRun screens. Production uses `OnboardingRedesignView`.
- **Duplicate/dead views:** KEY-1 `KeysView` (+ KeyImportView, whole KeysFeature module), V2-9 `FilesView` (legacy SFTP), AGT-8 `AgentsView`, AGT-2 `AgentDetailView`, AGT-3 `AgentRunDetailView`, AGT-4 `AgentExecView`, AGT-6 `AgentOrgView`, `AgentWorkspaceView`, `AgentBillingSheet`, `CreateAgentSheet`, SET-20 `PremiumComparisonView`.
- **Orphaned prototype components:** `DSDecisionSheet`, `HostHealthBadge`, `InboxEmptyState`, `DSOfflineState`, `DSSkeletonRow`, `DSSlowOverlay`, `AgentStatusBar`, `ExplainSheet`, `RelayChatViewModel` — plus the 5 gallery prototypes (Agent Features / HUD / Proof Card / Sessions-glyph / Typed-Inbox).
- **Archived dirs:** repo `archive/` (conduit/lancer dead-views) and `Packages/LancerKit/archive/`.
- **KEPT (owner decision):** deferred-V2 code — hosted-cloud (Provisioning/RunnerStatus/RunnerSetup/SelfHostVsHosted/ProviderDetail), Loops, Worktrees.

Net live surface is now ~20% smaller. Entries below tagged Remove/Merge that name a deleted file are **done**.

## Navigation model
- **Root:** `AppRoot.swift` — `compactRoot` (iPhone: NavigationStack + slide drawer) / `regularRoot` (iPad: NavigationSplitView).
- **Primary destinations (`SidebarDestination`):** `.home`, `.newChat`, `.thread(id)`, `.needsAttention`, `.machines`, `.settings`, `.observedSession(…)`.
- **Drawer/sheet routes (`AppDrawerRoute`):** `.addMachine`, `.relayPairing`, `.addHost`, `.editHost`, `.activity`.
- **Full-screen:** SessionWorkspaceContainer → SessionView (SSH terminal).
- **Vestigial:** `enum Tab` — present, unused. Do not reintroduce.
- **Gallery:** `LANCER_GALLERY=<route>` → DebugGalleryView (49 routes, `#if DEBUG`).

## Legend
Keep = core V1 · Merge = fold into another surface · Defer = V2 (retain, unwire) · Remove = delete candidate · Legacy = superseded duplicate

---

## 1. Onboarding

| ID | Screen | File | Reach | Purpose | Verdict |
|---|---|---|---|---|---|
| ON-1 | Account entry (Supabase) | OnboardingFeature/AccountEntryView.swift | first run | Login/signup gate | Keep (question necessity — see onboarding audit) |
| ON-2 | Value / hero | OnboardingFeature/OnboardingRedesignGalleryView.swift `.value` | first run | Why Lancer | Keep (shorten) |
| ON-3 | Pair bridge | `.pair` (+BridgePairingView, QRScannerView) | first run | 6-digit / QR relay pairing | Keep |
| ON-4 | Policy preset | `.policy` | first run | Autonomy Balanced/Permissive/Restrictive | Keep (could be default + contextual) |
| ON-5 | SSH setup (optional) | OnboardingSSHSetupScreen | first run | Optional Mac terminal enable | Defer/contextual (not core V1 relay path) |
| ON-L | Legacy onboarding (7-step) | OnboardingFeature/OnboardingView.swift | gallery only | Welcome→InstallBridge→Pair/Scan/Paired→Caution→FirstRun | **Remove (Legacy)** |

## 2. Primary navigation

| ID | Screen | File | Reach | Purpose | Verdict |
|---|---|---|---|---|---|
| NAV-1 | Home / Command Home | AppFeature/LancerHomeView.swift | `.home` | Dashboard: recent threads, pending approvals, machines, observed sessions, relay status | Keep (strongest screen) |
| NAV-2 | Sidebar drawer | AppFeature/LancerSidebarView.swift | swipe/toggle | Profile, New Chat CTA, search, nav, recent threads, relay footer | Keep |
| NAV-3 | New Chat composer | AppFeature/NewChatTabView.swift | `.newChat` | Agent dispatch: picker, cwd, model, policy preview | Keep (strongest screen) |
| NAV-4 | Chat history / thread | AppFeature/ChatHistoryView.swift | `.thread(id)` | Persisted conversation + live-follow resume | Keep |
| NAV-5 | Inbox / Needs Attention | InboxFeature/InboxView.swift | `.needsAttention` | Approvals (approve/reject), policy editor entry, audit history | Keep |
| NAV-6 | Machines / Fleet | AppFeature/FleetView.swift | `.machines` | SSH hosts + relay host; status/health/quotas/drift | Keep (fix loading state) |
| NAV-7 | Settings | SettingsFeature/SettingsView.swift | `.settings` | Connection/Notifications/Security/Advanced/Account hub | Keep (regroup) |

## 3. Chat / artifacts

| ID | Screen | File | Verdict |
|---|---|---|---|
| CHAT-1 | Chat archive (restore/delete) | AppFeature/ChatArchiveView.swift | Keep |
| CHAT-2 | Artifact detail | AppFeature/ChatArtifactDetailView.swift | Keep |
| CHAT-3 | Diff viewer | DiffFeature/DiffView.swift | Keep |
| CHAT-4 | File preview | FilesFeature/FilePreviewView.swift | Keep |

## 4. Approvals / activity

| ID | Screen | File | Verdict |
|---|---|---|---|
| APR-1 | Activity / audit feed | InboxFeature/ActivityView.swift | Keep (sheet, not root) |
| APR-2 | Bridge audit feed | InboxFeature/BridgeAuditFeedView.swift | Merge into APR-1 |

## 5. Terminal / SSH (legacy/secondary transport)

| ID | Screen | File | Verdict |
|---|---|---|---|
| TERM-1 | Session container (TOFU prompt) | AppFeature/SessionWorkspaceContainer.swift | Keep (power-user) |
| TERM-2 | SSH session shell | SessionFeature/SessionView.swift | Keep (power-user) |
| TERM-3 | Live terminal (PTY/OSC-133) | SessionFeature/LiveTerminalView.swift | Keep |
| TERM-4 | Live prompt input | SessionFeature/LivePromptInputView.swift | Keep |

## 6. Machines — sub-surfaces

| ID | Screen | File | Verdict |
|---|---|---|---|
| MCH-1 | Add machine chooser (relay vs SSH) | AppDrawerRoute.addMachine | Keep |
| MCH-2 | Add host (SSH wizard) | WorkspacesFeature/AddHostView.swift | Keep (power-user) |
| MCH-3 | Host editor | WorkspacesFeature/HostEditorView.swift | Keep |
| MCH-4 | Relay file browser | AppFeature/RelayFileBrowserView.swift | Keep |
| MCH-5 | Quota guard / usage | AppFeature/QuotaGuardView.swift | Keep |
| MCH-6 | Drift findings | AppFeature/DriftFindingsView.swift | Keep (post-launch moat) |

## 7. Settings sub-screens (15+)

| ID | Screen | File | Verdict |
|---|---|---|---|
| SET-1 | Trust & privacy (pairings/revocation) | SettingsFeature/TrustPrivacyView.swift | Keep |
| SET-2 | Autonomy level | AutonomyLevelView | Merge → policy |
| SET-3 | Appearance | AppearanceSettingsView | Defer (app is fixed-dark — likely no-op) |
| SET-4 | Accent | AccentSettingsView | Keep (minor) |
| SET-5 | Provider keys | ProviderKeysView | Keep |
| SET-6 | Notifications | NotificationsSettingsView | Keep |
| SET-7 | Terminal settings | TerminalSettingsView | Merge → terminal/power-user |
| SET-8 | SSH keys | SSHKeysView | Keep (merge w/ KeysView dup) |
| SET-9 | E2E relay pairing | E2ERelayPairingView | Keep |
| SET-10 | Device management | DeviceManagementView | Keep |
| SET-11 | Doctor | DoctorView | Keep |
| SET-12 | Policy editor (YAML) | PolicyEditorView | Keep (simplify — YAML is power-user) |
| SET-13 | Policy simulator | PolicySimulatorView | Defer/merge |
| SET-14 | Audit | AuditView | Merge → APR-1 |
| SET-15 | Secrets | SecretsView | Keep |
| SET-16 | Shortcut bar editor | ShortcutBarEditor | Defer |
| SET-17 | Billing | BillingView | Keep |
| SET-18 | Sync status | SyncStatusView | Defer |
| SET-19 | Paywall | PaywallSheet | Keep |
| SET-20 | Premium comparison | PremiumComparisonView | Merge → paywall |

## 8. Keys (duplicate of SSH keys)

| ID | Screen | File | Verdict |
|---|---|---|---|
| KEY-1 | Keys list | KeysFeature/KeysView.swift | **Merge** (duplicate of SET-8 SSHKeysView) |
| KEY-2 | Key import | KeysFeature/KeyImportView.swift | Keep (fold into merged keys) |

## 9. Agent-run detail sprawl (consolidation target)

| ID | Screen | File | Verdict |
|---|---|---|---|
| AGT-1 | Run detail | AppFeature/RunDetailView.swift | Merge |
| AGT-2 | Agent detail | AppFeature/AgentDetailView.swift | Merge |
| AGT-3 | Agent run detail | AppFeature/AgentRunDetailView.swift | Merge |
| AGT-4 | Agent exec | AppFeature/AgentExecView.swift | Merge |
| AGT-5 | Agent files | AppFeature/AgentFilesView.swift | Merge |
| AGT-6 | Agent org | AppFeature/AgentOrgView.swift | Remove (unclear purpose) |
| AGT-7 | Agent workspace | AppFeature/AgentWorkspaceView.swift | Merge |
| AGT-8 | Agents list | AppFeature/AgentsView.swift | Merge |
| AGT-9 | Provider detail | AppFeature/ProviderDetailView.swift | **Defer-V2** (0-ref) |

> 8 agent-detail views is a major duplication smell — consolidate to ≤2 (a run transcript + a run-files panel).

## 10. Deferred-V2 (orphaned, retain, unwire)

| ID | Screen | File | Verdict |
|---|---|---|---|
| V2-1 | Hosted provisioning | HostedProvisioningView.swift | Defer-V2 (0-ref) |
| V2-2 | Hosted runner status | HostedRunnerStatusView.swift | Defer-V2 (0-ref) |
| V2-3 | Runner setup | RunnerSetupView.swift | Defer-V2 |
| V2-4 | Self-host vs hosted | SelfHostVsHostedView.swift | Defer-V2 (0-ref) |
| V2-5 | Loop detail | LoopDetailView.swift | Defer-V2 (unwired) |
| V2-6 | Worktrees board | WorktreesFeature/WorktreesBoardView.swift | Defer-V2 |
| V2-7 | New worktree | WorktreesFeature/NewWorktreeView.swift | Defer-V2 |
| V2-8 | Worktree conflicts | WorktreesFeature/WorktreeConflictsView.swift | Defer-V2 |
| V2-9 | Files (SFTP) | FilesFeature/FilesView.swift | Defer/Remove (legacy SFTP) |

## 11. States to capture (per key screen)
loading · empty · error · offline/disconnected · connected · permission-denied (camera for QR, notifications) · success · failure. Prior session flagged: **FleetView relay-host empty-for-30s then dumps many conversations (missing loader)**, **Face-ID re-prompt on "review claude code"** — capture/note these.

## Reconciliation
- Sidebar destinations in code: 7 → all inventoried (NAV-1..7 + observed session).
- AppDrawerRoute: 5 → inventoried (MCH-1, SET-9, MCH-2/3, APR-1).
- Gallery routes: 49 → screenshotted in Phase 4 (mapping in the coverage note).
- **Total distinct screens: ~58** (incl. settings sub-screens + sprawl). Target after simplification: ~20–25.
