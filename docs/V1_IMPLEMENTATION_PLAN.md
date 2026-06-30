# V1 Implementation Plan — Lancer

> **Status:** locked for V1 implementation  
> **Companion:** V1_PRODUCT_SPEC.md, V1_STATE_AND_ACTION_MATRIX.md  
> **Rule:** Do not create a new file when an existing one can be modified. Dispositions below are authoritative.

---

## File Disposition Map

Each relevant existing file is marked: **keep** / **modify** / **merge** / **delete** / **defer**.

### LancerCore (models — mostly keep)

| File | Disposition | Notes |
|---|---|---|
| `LancerCore/Approval.swift` | **keep** | Rich model; do not add fields. `Kind`, `Risk`, `Decision`, `AgentSource` stay as-is. |
| `LancerCore/Session.swift` | **keep** | `Status`, `SessionOrigin`, `ConnectionState.derive()` stay. |
| `LancerCore/LancerDProtocol.swift` | **keep** | `RunStatusParams`, daemon event protocol — no changes. |
| `LancerCore/RunControl.swift` | **keep** | `RunControlStatus` — no changes. |
| `LancerCore/FleetSummary.swift` | **keep** | |
| `LancerCore/FleetSlotManager.swift` | **keep** | |
| `LancerCore/Host.swift` | **keep** | |
| `LancerCore/HostHealth.swift` | **keep** | |
| `LancerCore/WatchApprovalTransfer.swift` | **defer** | Watch is deferred V1. |
| `LancerCore/Worktree.swift` | **keep** | |

**New model to add (no existing file):**
- `LancerCore/AttentionItem.swift` — define `AttentionKind` + `AttentionItem` per V1_PRODUCT_SPEC.md. **Do not add a store; this is a computed projection.**

---

### AppFeature (navigation + home)

| File | Disposition | Notes |
|---|---|---|
| `AppFeature/SidebarShellState.swift` | **modify** | Remove `.governance` and `.needsAttention` as primary sidebar routes; keep `.needsAttention` as a deep-link-only destination for push notification routing. Add `attentionItems: [AttentionItem]` computed from FleetStore. |
| `AppFeature/LancerSidebarView.swift` | **modify** | Remove governance row. Remove needsAttention row (sidebar badge only; "See all" is a sheet from Home). |
| `AppFeature/LancerHomeView.swift` | **modify** | Add "Needs attention" section above machines. Add bottom composer strip. Use `AttentionItem` projection. |
| `AppFeature/FleetStore.swift` | **modify** | Add `attentionItems: [AttentionItem]` computed property (projection over slots + inbox VMs). |
| `AppFeature/FleetView.swift` | **modify** | Remove governance navigation link. Clean up for V1 (Machines root only). |
| `AppFeature/FleetThreadMapper.swift` | **keep** | |
| `AppFeature/GovernanceHomeView.swift` | **defer** | Move to a section inside SettingsView; remove from sidebar routing. Keep file. |
| `AppFeature/RunDetailView.swift` | **merge → SessionView** | Fold run status header + tool blocks into `SessionView`. Do not delete until merge is complete. |
| `AppFeature/RunControls.swift` | **merge → SessionView** | Move Stop / Continue controls inline. |
| `AppFeature/RunControlStore.swift` | **keep** | Logic stays; only the view changes. |
| `AppFeature/RunOutputStore.swift` | **keep** | |
| `AppFeature/SessionWorkspaceContainer.swift` | **modify** | Remove Work/Files/Diff/Preview tabs from default view. Terminal logs accessible via a "Logs" drawer only. |
| `AppFeature/NewChatTabView.swift` | **modify** | Becomes the empty/new state of Work Thread (Start Work). Not a sidebar root. |
| `AppFeature/ChatHistoryView.swift` | **keep** | Used for thread list in sidebar. |
| `AppFeature/ChatArchiveView.swift` | **defer** | Not a primary V1 surface. |
| `AppFeature/ObservedSessionView.swift` | **modify** | Add "Observed" badge in header. Ensure read-only until "Take Control" confirmed. |
| `AppFeature/AgentFilesView.swift` | **defer** | |
| `AppFeature/ChatArtifactDetailView.swift` | **keep** | |
| `AppFeature/ProviderDetailView.swift` | **defer** | |
| `AppFeature/QuotaGuardView.swift` | **keep** | Keep but not a primary surface. |
| `AppFeature/RelayFileBrowserView.swift` | **defer** | |
| `AppFeature/SelfHostVsHostedView.swift` | **defer** | Not V1. |
| `AppFeature/HostedProvisioningView.swift` | **defer** | Not V1. |
| `AppFeature/HostedRunnerStatusView.swift` | **defer** | Not V1. |
| `AppFeature/ApprovalIngest.swift` | **keep** | Source of truth for live approval stream. |
| `AppFeature/DriftRemediationView.swift` | **defer** | |
| `AppFeature/WorkspaceRouting.swift` | **keep** | |

---

### InboxFeature (approval queue)

| File | Disposition | Notes |
|---|---|---|
| `InboxFeature/InboxView.swift` | **modify** | Becomes "Needs Attention — See All" sheet (not a root). Reachable from Home "See all" + push deep-link via `.needsAttention`. |
| `InboxFeature/ActivityView.swift` | **defer** | Audit log deferred V1. |
| `InboxFeature/BridgeAuditFeedView.swift` | **defer** | |
| `InboxFeature/AllowAlwaysScopeSheet.swift` | **keep** | Low-risk auto-approve flow — keep wired. |

---

### SessionFeature (Work Thread + approval actions)

| File | Disposition | Notes |
|---|---|---|
| `SessionFeature/SessionView.swift` | **modify** | This is the Work Thread. Add run status header (current step), inline approval card, activity log section. Composer is ChatInputBar. |
| `SessionFeature/SessionViewModel.swift` | **keep** | SSH connection state machine — no changes. |
| `SessionFeature/ApprovalActionIntent.swift` | **modify** | Add `ReplyDeliveryStatus` enum; add offline-queue support (store decision locally when `ConnectionState == .offline`, send on reconnect). Idempotency key = `approvalID` (the UUID string already stable from `Approval.id`); make it explicit in the intent parameter rather than reconstructed from context. |
| `SessionFeature/ApprovalRelay.swift` | **keep** | |
| `SessionFeature/E2ERelayBridge.swift` | **keep** | |
| `SessionFeature/LiveActivityManager.swift` | **keep** | |
| `SessionFeature/Chat/ChatInputBar.swift` | **keep** | The composer — used in both Work Thread and Home. |
| `SessionFeature/Chat/ChatTranscriptView.swift` | **keep** | Activity log base. |
| `SessionFeature/Chat/ToolCardView.swift` | **keep** | Tool block display. |
| `SessionFeature/LiveTerminalView.swift` | **modify** | Available only via Work Thread → "Logs" drawer. Not shown by default. |
| `SessionFeature/PortForwardView.swift` | **defer** | |
| `SessionFeature/SnippetPaletteSheet.swift` | **keep** | |
| `SessionFeature/SSHConnectOverlay.swift` | **keep** | |
| `SessionFeature/LivePromptInputView.swift` | **keep** | |
| `SessionFeature/RecentPatch.swift` | **keep** | |
| `SessionFeature/KeyboardAccessoryRail.swift` | **keep** | |
| All other SessionFeature chat files | **keep** | |

---

### DesignSystem (components)

| File | Disposition | Notes |
|---|---|---|
| `DesignSystem/Components/DSReviewSheet.swift` | **modify** | Promote to full Approval Review screen. Add risk-tier gating (evidence expand, diff-reviewed flag, biometric gate for critical). |
| `DesignSystem/Components/InboxApprovalCard.swift` | **keep** | Used on Home attention section and InboxView. |
| `DesignSystem/Components/InboxApprovalDetail.swift` | **modify** | Merge into or replaced by DSReviewSheet as the promoted Approval Review. |
| `DesignSystem/Components/DSApprovalBanner.swift` | **keep** | Inline approval card in Work Thread. |
| `DesignSystem/Components/DSBlastRadiusBanner.swift` | **keep** | |
| `DesignSystem/Components/PersistentStatusBar.swift` | **keep** | |
| `DesignSystem/Components/AgentStatusHeader.swift` | **keep** | |
| All other DS components | **keep** | |
| `DesignSystem/AttentionFlashRing.swift` | **keep** | |

---

### DiffFeature

| File | Disposition | Notes |
|---|---|---|
| `DiffFeature/DiffView.swift` | **modify** | Add file-summary list (impact annotated) as default entry. Add "Mark reviewed" per file. Add "Ask about this" action. Wire back to Approval Review to signal reviewed state. |

---

### OnboardingFeature (pairing — code-only)

| File | Disposition | Notes |
|---|---|---|
| `OnboardingFeature/OnboardingPairing.swift` | **modify** | Drop QR entry path. Code-only flow: Enter Code → Verify → Connected → Notifications. The setup code is a short-lived rendezvous identifier only — not a permanent credential. |
| `OnboardingFeature/BridgePairingView.swift` | **modify** | Remove camera/QR UI. Keep code entry + machine name confirm + trust fingerprint display. After code redemption, device public keys are exchanged and the relay mints scoped per-device credentials; do not store the setup code after pairing. |
| `OnboardingFeature/QRScannerView.swift` | **defer** | Keep in codebase; remove from onboarding navigation. |
| `OnboardingFeature/OnboardingScanScreen.swift` | **defer** | QR scan screen — remove from onboarding flow. |
| `OnboardingFeature/AccountEntryView.swift` | **modify** | Move after pairing is complete (offer account only after first value, not at first run). |
| `OnboardingFeature/OnboardingSSHSetupScreen.swift` | **keep** | |
| `OnboardingFeature/OnboardingPolicy.swift` | **keep** | Policy template selection at onboarding. |
| `OnboardingFeature/OnboardingChrome.swift` | **keep** | |
| `OnboardingFeature/CoachmarkTour.swift` | **keep** | |
| `OnboardingFeature/ProvisioningWizard.swift` | **defer** | Hosted provisioning deferred V1. |
| `OnboardingFeature/OnboardingRedesignGalleryView.swift` | **keep** | Preview/gallery seam. |

---

### SettingsFeature

| File | Disposition | Notes |
|---|---|---|
| `SettingsFeature/SettingsView.swift` | **modify** | Add Governance section (link to GovernanceHomeView). Reorder: Notifications, Security, Governance, Account, Advanced. |
| `SettingsFeature/E2ERelayPairingView.swift` | **keep** | |
| `SettingsFeature/DeviceManagementView.swift` | **keep** | |
| `SettingsFeature/SSHKeysView.swift` | **keep** | |
| `SettingsFeature/TrustView.swift` | **keep** | |
| `SettingsFeature/DoctorView.swift` | **keep** | Accessible from Settings → Advanced. |
| `SettingsFeature/SyncStatusView.swift` | **keep** | |
| `SettingsFeature/ProviderKeysView.swift` | **keep** | |
| `SettingsFeature/SecretsView.swift` | **keep** | |
| `SettingsFeature/TerminalSettingsView.swift` | **keep** | |
| `SettingsFeature/ShortcutBarEditor.swift` | **keep** | |
| `SettingsFeature/PolicyPresetsView.swift` | **keep** | In Governance section. |
| `SettingsFeature/PolicyEditorView.swift` | **defer** | Advanced — defer for V1. Keep file. |
| `SettingsFeature/PolicyMatrixView.swift` | **defer** | |
| `SettingsFeature/PolicySimulatorView.swift` | **defer** | |
| `SettingsFeature/AuditView.swift` | **defer** | |
| `SettingsFeature/AuditVerifyExportView.swift` | **defer** | |
| `SettingsFeature/TeamRolesView.swift` | **defer** | |
| `SettingsFeature/BillingView.swift` | **defer** | |
| `SettingsFeature/PaywallSheet.swift` | **defer** | |

---

### WorkspacesFeature

| File | Disposition | Notes |
|---|---|---|
| `WorkspacesFeature/AddHostView.swift` | **modify** | Entry point reachable from Machines → "Pair machine". Simplify to code-only pairing path. |
| `WorkspacesFeature/HostEditorView.swift` | **keep** | Machine detail edit. |
| `WorkspacesFeature/HostKeyConfirmSheet.swift` | **keep** | TOFU key confirm — must stay on production path. |

---

### SecurityKit / HostControlKit

| File | Disposition | Notes |
|---|---|---|
| `SecurityKit/PairingCrypto.swift` | **keep** | |
| `HostControlKit/PairingPayload.swift` | **keep** | |

---

### New Files Required

| File | Purpose |
|---|---|
| `LancerCore/AttentionItem.swift` | Define `AttentionKind` enum + `AttentionItem` struct (see V1_PRODUCT_SPEC.md) |
| (extend `ApprovalActionIntent.swift`) | Add `ReplyDeliveryStatus` enum; no new file needed |

---

## First Vertical Slice

Build and validate **only this path** before any other implementation work begins.

```
1. lancerd generates a test AttentionItem (medium approval, kind=.patch)
2. FleetStore.attentionItems exposes it
3. LancerHomeView shows the attention card
4. User taps [Review] → DSReviewSheet (Approval Review) opens
5. User expands evidence (medium risk gate)
6. User taps Approve
7. ApprovalActionIntent fires with stable idempotency key (approvalID)
8. daemon receives decision at-least-once; idempotent DB guard ensures one visible outcome
9. Work Thread (RunDetailView) activity log shows "Approved ✓"
```

Fixture cases to validate before moving on (see V1_STATE_AND_ACTION_MATRIX.md):
- [ ] Fixture 1: Medium approval (standard path above)
- [ ] Fixture 2: Critical approval + biometrics
- [ ] Fixture 3: Agent question (choice picker)
- [ ] Fixture 4: Already-handled (read-only history)
- [ ] Fixture 5: Expired (faded card, no action)
- [ ] Fixture 6: Reply delivery failure + retry
- [ ] Fixture 7: Machine disconnect mid-review

---

## Implementation Order

```
1. Define AttentionItem (LancerCore/AttentionItem.swift)
   ↓
2. Add FleetStore.attentionItems computed property
   ↓
3. Modify LancerHomeView: attention section + bottom composer
   ↓
4. Promote DSReviewSheet to full Approval Review with risk-tier gates
   ↓
5. Add ReplyDeliveryStatus to ApprovalActionIntent + offline queue
   ↓
6. Validate all 7 fixture cases with preview seams (LANCER_SEED_DEMO=1)
   ↓
7. Modify SessionView: run status header, inline approval card, activity log
   ↓
8. Wire push notification deep-link → .needsAttention → InboxView sheet
   ↓
9. Modify OnboardingPairing: code-only flow, defer QR
   ↓
10. Demote .governance / .needsAttention from sidebar; add Governance section in Settings
    ↓
11. Modify DiffView: file summary + mark-reviewed + ask-about-this
    ↓
12. Empty/offline/error states for all modified screens
    ↓
13. Accessibility pass (VoiceOver labels, minimum tap targets)
```

**Do not start Settings, billing, audit export, CI events, search, Watch, or provisioning before step 9.**

---

## Verification Gate

For each step above, the gate is:

1. `cd Packages/LancerKit && swift build` — zero errors
2. For app-shell / navigation / strict-concurrency changes: XcodeBuildMCP app-target build
3. Run the relevant fixture in simulator: `SIMCTL_CHILD_LANCER_SEED_DEMO=1 SIMCTL_CHILD_LANCER_DESTINATION=<route> xcrun simctl launch booted dev.lancer.mobile`
4. Screenshot and verify against the layouts in V1_PRODUCT_SPEC.md
5. Never claim "done" from inspection — show the build output and screenshot

---

## What Not To Build During V1

- New navigation roots beyond Home / Work / Machines / Settings
- Any screen whose disposition is "defer" above
- Parallel shadow models for `Approval`, `Session`, `Host` — adapt existing ones
- Bottom tab bar (the old Tab enum is vestigial — do not reintroduce)
- Side-by-side diff layout
- Full terminal as a default Work Thread view
- Inline billing / paywall during the core approval flow
- `SidebarDestination` cases beyond the 4 roots + deep-link targets above
