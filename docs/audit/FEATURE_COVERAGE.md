# Conduit — Feature / Capability Coverage Matrix

**Scope:** Governed Approvals v1 pre-submission audit (read-only, source-derived).
**Branch:** `feat/governed-approvals` (worktree `cc-wt/governed-approvals-audit`, HEAD `e6d0bf8e`).
**Method:** Enumerated from source — `AppRoot.swift` nav graph, every ConduitKit module, the `daemon/` Go backend, and the widget/watch/Live-Activity targets. Reachability is traced from the live tab graph down to each control. Anything reachable only via `DebugGalleryView` (gated by `CONDUIT_GALLERY`, compiled `#if DEBUG`) is flagged **debug-gallery-only**.

## Live information architecture (confirmed)

`AppRoot.Tab` (`AppFeature/AppRoot.swift:170-195`) defines exactly four root tabs, default `.inbox`:

| Tab | Icon | Root destination (`rootDestination`, AppRoot.swift:752) |
|---|---|---|
| **Inbox** | `tray` | `InboxView` (agent approvals) |
| **Fleet** | `square.stack.3d.up` | `FleetView` (connected agent slots) |
| **Activity** | `clock.arrow.circlepath` | `ActivityView` (bridge audit feed) |
| **Settings** | `gear` | `SettingsView` (+ Library via toolbar) |

The terminal/session is demoted to **session depth** — `SessionView` is a `fullScreenCover` (`AppRoot.swift:651`, `712`) over the tab graph, not a tab. Compact uses `DSTabBar` inside each tab's `NavigationStack`; regular uses `NavigationSplitView`. This matches the intended governance-first IA. ✅

---

## Coverage matrix

Legend for **Reachable normally?**: `yes` = reachable by a normal user through the live tab graph; `yes·cloud` = reachable but gated behind a Conduit Cloud entitlement; `yes·onboarding` = only during first-run onboarding; `yes·session` = only at session depth (live SSH session open); `debug-gallery-only` = only via `CONDUIT_GALLERY`; `NO` = no normal-user entry point found.

### A. App root / navigation / IA

| Capability | Module/File | UI surface | How reached (nav path) | Reachable normally? | Notes |
|---|---|---|---|---|---|
| 4-tab root (Inbox/Fleet/Activity/Settings) | `AppFeature/AppRoot.swift:170,606,689` | `DSTabBar` / `NavigationSplitView` | app launch | yes | Compact + regular layouts |
| Persistent agent status bar | `DesignSystem/PersistentStatusBar.swift` via `AppRoot.swift:638,693` | top strip | always (when agents live) | yes | Tap → live session; reconnect button |
| Live session cover | `SessionFeature/SessionView.swift` | full-screen cover | tap status bar / open host | yes·session | Not a tab (demoted) |
| App lock (Face ID on launch) | `AppRoot.swift:234,335` `LaunchLockView` | lock screen | Settings toggle `appLockEnabled` | yes | Biometric gate |
| Color scheme override | `AppRoot.swift:124,130` | — | Settings → Appearance | yes | `conduitColorScheme` |
| Lock-screen approval action routing | `AppRoot.swift:299,318` `handleApprovalAction` | notification buttons | APNs notification | yes | Routes to inbox/fleet slot decide |
| Run-complete notification routing | `AppRoot.swift:302` | notification | APNs | yes | Jumps to fleet slot |

### B. Inbox — governed approvals (core loop)

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Pending/decided approval list | `InboxFeature/InboxView.swift:65` | Inbox tab | Inbox | yes | Live-backed by `LiveInboxViewModel` |
| Approve / Deny | `InboxView.swift:160,166,180,186` | `DSApprovalCard` | Inbox | yes | → daemon channel / relay |
| Allow-always | `InboxView.swift:165,181` | card button | Inbox | yes | `.approvedAlways`; surfaces a rule in Settings |
| Edit-and-run (edit tool JSON) | `InboxView.swift:161,196` editSheet | sheet + `DiffView` | Inbox → Edit & run | yes | Live diff preview of edits |
| View patch diff | `InboxView.swift:179,246` diffSheet | `DiffFeature/DiffView` | Inbox card → View diff | yes | For `.patch`/`patch != nil` |
| Typed card — Ask question (choices) | `InboxView.swift:137` `DSAskQuestionCard` | Inbox | Inbox | yes | Answer index returned |
| Typed card — MCP call | `InboxView.swift:150` `DSMCPCallCard` | Inbox | Inbox | yes | tool name/use-id/args/risk |
| Blast-radius banner | `InboxView.swift:188` `DSBlastRadiusBanner` | Inbox | Inbox | yes | when `approval.blastRadius` present |
| "While you were away" feed | `InboxView.swift:83` + `BridgeAuditFeedView.swift` | Inbox header | Inbox (when `awayAuditEntries`) | yes | Currently passed `[]` from AppRoot (`rootDestination` `.inbox` uses `[]`) |
| Decision relay fallback (no live channel) | `SessionFeature/ApprovalRelay.swift`, `AppRoot.swift:562` | — | automatic | yes | POSTs to push-backend `/approval/decision` |

### C. Fleet

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Connected agent slots list | `AppFeature/FleetView.swift:31` | Fleet tab | Fleet | yes | per-host sections, vendor status |
| Fleet summary strip (vendors/sessions/spend) | `FleetView.swift:51` + `ConduitCore/FleetSummary.swift` | Fleet | Fleet | yes | refresh via bridge status |
| Connect a host (empty state) | `FleetView.swift:28` → `AppRoot.addHostPresented` | button | Fleet (empty) | yes | → `AddHostView` |
| Pull-to-refresh bridge status | `FleetView.swift:47,84` | Fleet | Fleet | yes | `FleetStore.refreshBridgeStatus` |
| Multi-slot fleet store | `AppFeature/FleetStore.swift`, `ConduitCore/FleetSlotManager.swift` | — | automatic | yes | maxSlots; slot select on open |

### D. Activity

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Bridge audit feed (auto-allow/deny/escalate) | `InboxFeature/ActivityView.swift` + `BridgeAuditFeedView.swift` | Activity tab | Activity | yes | `tailAudit(100)` over SSH bridge |
| Empty/offline state | `ActivityView.swift:35`, `BridgeAuditFeedView.swift:18` | Activity | Activity (disconnected) | yes | "Connect to a host…" |

### E. Settings + toggles/flags

| Capability / toggle | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| AI provider picker (Anthropic/OpenAI) | `SettingsFeature/SettingsView.swift:183,227` | Settings → AI Provider | Settings | yes | `supportedProviders` = anthropic, openai only |
| API key entry + test + remove | `SettingsView.swift:251,420` | Settings → API Keys | Settings | yes | Keychain; test calls provider |
| Theme (system/light/dark) | `SettingsView.swift:163,278` `conduitColorScheme` | segmented | Settings → Appearance | yes | |
| Require Face ID on launch | `SettingsView.swift:164,301` `appLockEnabled` | toggle | Settings → Security | yes | |
| Redact secrets in saved history | `SettingsView.swift:165,312` `redactSavedHistory` | toggle | Settings → Security | yes | Consumed in `BlockRepository.swift:131` |
| Security audit log | `SettingsView.swift:321` → `AuditView.swift` | nav row | Settings → Security | yes | `AuditViewModel` over `AuditRepository` |
| Approval policy (autonomy preset) | `SettingsView.swift:167,481` `inbox.autonomyPreset` | segmented | Settings → Agent approvals | yes | Gated by flag `flag.autonomyPresets` (default true) |
| Edit bridge `policy.yaml` | `SettingsView.swift:500` → `PolicyEditorBridgeScreen.swift` | nav row | Settings → Agent approvals | yes | Functional only when SSH connected |
| Notification min-risk filter | `SettingsView.swift:520` | segmented | Settings → Notification filters | yes | `NotificationFilter` |
| Notification per-agent filter | `SettingsView.swift:543` | toggles | Settings → Notification filters | yes | claude/codex/cursor/opencode/devin/unknown |
| Quiet hours | `SettingsView.swift:560` | toggle + pickers | Settings → Notification filters | yes | |
| Allow-always rules list + revoke | `SettingsView.swift:610` | list | Settings → Allow-always rules | yes | derived from `.approvedAlways` approvals |
| Terminal settings (font/keepalive/sleep/haptics/scrollback/theme/gestures) | `SettingsFeature/TerminalSettingsView.swift:7-17` | nav screen | Settings → Integrations → Terminal settings | yes | `terminal*`, `gesture*` AppStorage |
| Compare Free vs Pro | `SettingsView.swift:347` → `PremiumComparisonView.swift` | nav row | Settings → Integrations | yes | |
| Billing & usage | `SettingsView.swift:354` → `BillingView.swift` | nav row | Settings → Integrations | yes | `showPaidSurfaces = true` (`SettingsView.swift:187`) |
| Team org row | `SettingsView.swift:357,681` | row | Settings → Integrations | yes·cloud | when `cloudEntitlement?.teamOrg` |
| iCloud sync status | `SettingsView.swift:361` → `SyncStatusView.swift` | inline | Settings → Integrations | yes | `showPaidSurfaces` gate |
| About / privacy / version | `SettingsView.swift:372-404` | section | Settings | yes | |
| **Library** (entry) | `AppRoot.swift:991,1011` `SettingsWithLibraryView` | toolbar button | Settings → Library | yes | nav from Settings nav bar |
| Debug "Unlock all features" | `TerminalSettingsView.swift:262` `DebugProBypassToggle` | toggle | Settings → Terminal (Debug builds) | debug-only | `#if DEBUG`; `conduitDebugProBypass` |

**Feature flags (no in-Settings UI toggle; code-default):**

| Flag | File | Default | Gates | UI toggle? |
|---|---|---|---|---|
| `flag.autonomyPresets` | `SettingsView.swift:168` | true | Agent-approvals section | none (code only) |
| `flag.approvalBar` | `SessionFeature/Chat/ChatInputBar.swift:40` | true | in-session approval banner | none |
| `flag.mediaAttachment` | `ChatInputBar.swift:41` | true | composer paperclip/media | none |
| `conduitLightsailProvisioningEnabled` | `AgentKit/ProvisioningFeatureFlags.swift` | true (DEBUG) | Lightsail in provisioning wizard | none (programmatic `setLightsailEnabled`) |
| `conduitDebugProBypass` | `SettingsFeature/PurchaseManager.swift:75` | false | force Pro (debug) | Debug toggle only |
| `conduitDebugCloudEntitlement` | `PurchaseManager.swift:80` | false | force cloud (debug) | none |

### F. Session depth (live SSH terminal / blocks / chat)

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Warp-style block transcript | `SessionFeature/Chat/ChatTranscriptView.swift`, `ToolCardView.swift` | session | open live session | yes·session | `BlockRenderer` |
| Chat input + submit | `Chat/ChatInputBar.swift` | session | session | yes·session | |
| In-session approval banner | `ChatInputBar.swift:40` | session | session | yes·session | flag `flag.approvalBar` |
| Media attachment (paperclip) | `ChatInputBar.swift:41` | session | session | yes·session | flag `flag.mediaAttachment` |
| Explain command (AI) | `SessionView.swift:36,554` inline `explainSheet` | sheet | block → Explain | yes·session | Uses inline sheet (not `ExplainSheet.swift`) |
| Snippet palette | `SessionView.swift:49` `SnippetPaletteSheet.swift` | sheet | session → snippet | yes·session | param-filled snippets |
| Expandable keyboard panel | `SessionView.swift:266` `TerminalKeyboardPanel.swift` | panel | session keyboard | yes·session | |
| Keyboard accessory rail | `SessionView.swift:244` `KeyboardAccessoryRail.swift` | rail | session | yes·session | Ctrl/arrows/tab |
| Dictation (mic) | `SessionView.swift:288` `DictationEngine.swift` | mic | session | yes·session | |
| Command history sheet | `SessionView.swift:433` | sheet | session → clock | yes·session | |
| Port forwarding | `SessionView.swift:157` `PortForwardView.swift` | sheet | session header → port-forward | yes·session | `PortForwardViewModel` |
| tmux reattach | `SessionView.swift:164,462` | sheet | session (auto on detect) | yes·session | `TmuxClient` |
| Reconnect / disconnect | `SessionView.swift:84,92` | header menu | session | yes·session | |
| Raw terminal (full-screen TUI) | `SessionView.swift:101,353` `TerminalEngine/RawTerminalView.swift` | embedded | `vm.isRaw` | dormant | Legacy escalation path; nothing drives it (per CLAUDE.md) |

### G. Library (snippets / keys / workflows / agents)

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Library home (category grid) | `AppFeature/LibraryView.swift` | screen | Settings → Library | yes | |
| Snippets library | `LibraryView.swift:55` → `ManagementViews2.swift:156` `SnippetsLibraryView` | nav | Library → Snippets | yes | run action is TODO (see drift) |
| Snippet editor | `SettingsFeature/SnippetEditorView.swift` | sheet | (see drift — not wired from Library "+") | partial | exists, not entered from Library |
| SSH keys management | `LibraryView.swift:67` → `ManagementViews2.swift:12` `KeysManagementView` | nav | Library → SSH Keys | yes | host-count is mock (drift) |
| Key import | `KeysFeature/KeyImportView.swift` | sheet | via KeysManagementView | yes | |
| Workflows | `LibraryView.swift:79` → `ManagementViews2.swift:269` `WorkflowBuilderView` | nav | Library → Workflows | yes | mock data + "add step" TODO (drift) |
| Hosted agents (cloud) | `LibraryView.swift:92` → `AppFeature/AgentsView.swift` | nav | Library → Agents | yes·cloud | only if `agentStore.hasCloudEntitlement`; else disabled card |
| "+ new snippet" | `LibraryView.swift:36` | header button | Library | yes (dead) | `/* new snippet — TODO */` (drift) |
| Recent snippet run | `LibraryView.swift:115` | row | Library | yes (dead) | `/* run snippet — TODO */` (drift) |

### H. Hosted agents / Conduit Cloud (AgentKit + AgentStore)

All of the following require a cloud entitlement (reached via Library → Agents, or AddHost → "use hosted runtime" `AddHostView.swift:286` → `AppRoot.swift:408` `showingHostedAgents`).

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Agents list | `AgentsView.swift` | screen | Library → Agents / AddHost hosted | yes·cloud | `AgentStore` → push-backend `/agents` |
| Create agent | `AgentsView.swift:64` `CreateAgentSheet.swift` | sheet | Agents → + | yes·cloud | POST `/agents` |
| Agent billing sheet | `AgentsView.swift:67` `AgentBillingSheet.swift` | sheet | Agents | yes·cloud | |
| Agent detail | `AgentsView.swift:142` `AgentDetailView.swift` | nav | Agents → row | yes·cloud | |
| Agent exec / dispatch run | `AgentDetailView.swift:199` `AgentExecView.swift` | nav | Agent detail | yes·cloud | POST `/runs` |
| Agent files / artifacts | `AgentDetailView.swift:202` `AgentFilesView.swift` | nav | Agent detail / run detail | yes·cloud | `/runs/{id}/artifacts` |
| Agent workspace | `AgentDetailView.swift:206` `AgentWorkspaceView.swift` | nav | Agent detail | yes·cloud | |
| Run detail + logs | `AgentDetailView.swift:277` `AgentRunDetailView.swift` | nav | Agent detail | yes·cloud | `/runs/{id}/logs` |
| Org / members | `AgentDetailView.swift:248` `AgentOrgView.swift` | nav | Agent detail | yes·cloud | invite email "not yet enabled" (drift) |
| Schedules (create/edit) | `AgentDetailView.swift:48` `EditScheduleSheet.swift` | sheet | Agent detail | yes·cloud | `/agents/{id}/schedules` |
| Dispatch composer | `AppFeature/DispatchComposerView.swift` | screen | — | debug-gallery-only | `CONDUIT_GALLERY=cc-dispatch` only call site |

### I. Onboarding / provisioning

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Onboarding flow | `OnboardingFeature/OnboardingView.swift` | full screen | first launch (`!onboardingSeen`) | yes·onboarding | |
| Multi-cloud provisioning wizard | `OnboardingFeature/ProvisioningWizard.swift` | sheet | Onboarding → "set up workspace" (`AppRoot.swift:357`) | yes·onboarding | **No post-onboarding entry** (drift) |
| Fly.io provisioner | `AgentKit/Provisioners/FlyProvisioner.swift` | — | provisioning wizard | yes·onboarding | |
| AWS Lightsail provisioner | `AgentKit/Provisioners/LightsailProvisioner.swift` | — | wizard (flag-gated) | yes·onboarding | `ProvisioningFeatureFlags.lightsailEnabled` |
| Orbstack provisioner | `AgentKit/Provisioners/OrbstackProvisioner.swift` | — | wizard | yes·onboarding | |

### J. Host management / add-host

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Add host (paste-to-parse) | `WorkspacesFeature/AddHostView.swift` | sheet | Fleet → Connect / onboarding | yes | paste `ssh …`, clipboard sniff |
| Inline Ed25519 key-gen | `AddHostView.swift:577` | card | AddHost → advanced → Ed25519 | yes | enclave key |
| Full host editor (new host) | `AddHostView.swift:737` → `HostEditorView.swift` | push | AddHost → "more options" | yes | tmux/startup cmd |
| **Edit a saved host** | `AppRoot.swift:415` `HostEditorView` (sheet on `editingHost`) | sheet | — | **NO** | `editingHost` only ever set to `nil` (`AppRoot.swift:423`) (drift) |
| **Saved hosts list / reconnect / delete** | `AppFeature/HostsView.swift`, `WorkspacesFeature/WorkspacesView.swift` | screen | — | **NO** | both public but never instantiated (drift) |
| Password prompt | `AppRoot.swift:1054` `PasswordPromptView` | sheet | connecting password host | yes | |
| Host-key TOFU confirm | `WorkspacesFeature/HostKeyConfirmSheet.swift` | sheet | first connect to new host | yes | `TOFUHostKeyValidator` |
| SSH agent-forwarding auth | `AppRoot.swift:823` | error alert | — | NO (defensive) | `.agent` never selectable in AddHost/HostEditor; emits "not implemented" if a host had it |

### K. Files / Diff / Preview feature modules

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| Unified diff viewer | `DiffFeature/DiffView.swift`, `DiffKit/UnifiedDiff.swift` | sheet | Inbox edit/diff sheets | yes | reachable via Inbox |
| **SFTP file browser** | `FilesFeature/FilesView.swift` | screen | — | **NO** | public, no call site (drift) |
| File text preview | `FilesFeature/FilePreviewView.swift`, `TextPreview.swift` | screen | only via `FilesView`/gallery | NO | reachable only from orphaned FilesView |
| **Web/localhost preview** | `PreviewFeature/PreviewView.swift`, `SmartPreviewView`, `PreviewSurface` | screen | — | **NO** | only referenced by orphaned `SessionShellView.swift:143` (drift) |
| Port detection / local forward | `PreviewKit/PortDetector.swift`, `LocalPortForward.swift` | — | (consumed by PreviewFeature) | NO | not surfaced |

### L. Notifications / Live Activity / widgets / watch

| Capability | Module/File | UI surface | How reached | Reachable normally? | Notes |
|---|---|---|---|---|---|
| APNs categories (approval + run-complete) | `NotificationsKit/Notifications.swift`, `AppRoot.swift:266` | system | automatic | yes | Approve/Reject lock-screen actions |
| Live Activity / Dynamic Island | `ConduitLiveActivityWidget/ConduitLiveActivityWidget.swift`, `SessionFeature/LiveActivityManager.swift` | lock screen / island | session backgrounded | yes | pending-approval badge, Approve/Reject via `ApprovalActionIntent` |
| Home/Lock-screen status widget | `ConduitWidget/ConduitStatusWidget.swift` | widget | add widget | yes | small + accessory families; app-group snapshot |
| Watch app (4 tabs) | `ConduitWatch/ConduitWatchApp.swift` | watchOS | paired watch | yes | Inbox / Session status / Activity / Snippet runner |
| Watch approve/deny + emergency stop | `ConduitWatch/ApprovalDetailView.swift`, `SessionStatusView.swift` | watchOS | watch | yes | `WatchConnector` ↔ `PhoneWatchConnector` (`AppRoot.swift:883`) |
| Watch inbox-count complication | `ConduitWatchWidget/InboxCountWidget.swift` | complication | add complication | yes | accessoryCircular/Corner |

### M. Backend HTTP routes — `daemon/push-backend` (relay + cloud)

| Route | Handler / file | Purpose | Notes |
|---|---|---|---|
| `POST /register` | `main.go:58` `handleRegister` | register APNs device token by sessionID | |
| `POST /approval` | `main.go:59` `handleApproval` | push approval alert via APNs | |
| `POST /run-complete` | `main.go:60` `handleRunComplete` | push run-complete alert | |
| **`POST /approval/decision`** | `main.go:61`, `decisions.go:33` `handlePostDecision` | **app posts a decision (relay-in)** | `{approvalId, decision, sessionId, editedToolInput?}`; in-memory by session |
| **`GET /decisions?sessionId=`** | `main.go:62`, `decisions.go:51` `handlePollDecisions` | **conduitd drains decisions (relay-out)** | conduitd `decision_poll.go` polls + resolves |
| `GET /health` | `main.go:63` | health check | |
| `POST /billing/checkout` | `billing.go:77` | Stripe checkout session | |
| `POST /billing/portal` | `billing.go:78` | Stripe billing portal | |
| `GET /billing/subscription-status` | `billing.go:79` | subscription status | |
| `GET /billing/entitlement` | `billing.go:80` | entitlement lookup | |
| `POST /billing/webhook` | `billing.go:81` | Stripe webhook | |
| `GET /billing/return` | `billing.go:82` | post-checkout return | |
| `GET /billing/credits` | `credits.go:182` | credit balance | |
| `GET /billing/quota` | `quotas.go:160` | quota | |
| `POST /usage` | `usage.go:42` | usage ingest | |
| `POST /agents` | `agents.go:94` | create hosted agent | |
| `GET /agents` | `agents.go:95` | list agents | |
| `GET /agents/{id}` | `agents.go:96` | get agent | |
| `DELETE /agents/{id}` | `agents.go:97` | delete agent | |
| `POST /runs` | `agents.go:98` | create run | |
| `GET /runs/{id}` | `agents.go:99` | get run | |
| `GET /runs` | `agents.go:100` | list runs | |
| `POST /runs/{id}/logs` | `run_logs.go:58` | append run logs | |
| `GET /runs/{id}/logs` | `run_logs.go:59` | get run logs | |
| `PATCH /runs/{id}` | `run_logs.go:60` | patch run | |
| `POST /runs/{id}/cancel` | `run_logs.go:61` | cancel run | |
| `GET /runs/{id}/control` | `run_logs.go:62` | run control stream | |
| `POST /runs/{id}/artifacts` | `artifacts.go:62` | create artifact | GCS-backed (`artifacts_gcs.go`) |
| `GET /runs/{id}/artifacts` | `artifacts.go:63` | list artifacts | |
| `DELETE /runs/{id}/artifacts/{artifactId}` | `artifacts.go:64` | delete artifact | |
| `GET /runs/{id}/artifacts/{artifactId}/download` | `artifacts.go:65` | download artifact | |
| `POST /agents/{id}/schedules` | `schedules.go:64` | create schedule | |
| `GET /agents/{id}/schedules` | `schedules.go:65` | list schedules | |
| `POST /schedules/{id}/trigger` | `schedules.go:66` | trigger schedule | |
| `PATCH /schedules/{id}` | `schedules.go:67` | update schedule | |
| `DELETE /schedules/{id}` | `schedules.go:68` | delete schedule | |
| `GET /orgs/{id}/members` | `orgs.go:61` | list org members | |
| `POST /orgs/{id}/members` | `orgs.go:62` | invite org member | email delivery not enabled (see `AgentOrgView`) |

### N. conduitd RPC surface — `daemon/conduitd` (JSON-RPC over SSH)

`conduitd` is not an HTTP server; it speaks length-prefixed JSON-RPC over the SSH channel (`server.go` dispatch at `:347`). Methods consumed by the iOS `DaemonChannel`:

| RPC method | File:line | App caller (DaemonChannel) |
|---|---|---|
| `ping` | `server.go:347` | keepalive |
| `agent.approval.response` | `server.go:350` | `channel.respond(...)` (the approval decision) |
| `agent.audit.tail` | `server.go:365` | Activity / "while away" feed |
| `agent.policy.get` | `server.go:377` | Edit bridge policy.yaml |
| `agent.policy.reload` | `server.go:389` | reload policy |
| `agent.policy.set` | `server.go:400` | save policy.yaml |
| `agent.status` | `server.go:415` | Fleet bridge status |
| `conduit.device.register` | `server.go:425` | register device for APNs |
| `agent.dispatch` | `server.go:437` | dispatch agent |
| `agent.cancel` | `server.go:445` | cancel run |
| `agent.schedule.add/list/remove` | `server.go:452,460,463` | schedules |
| `agent.approval.pending` (emit) | `approval.go:103` | drives Inbox via `ApprovalIngest` |

Policy engine (`conduitd/policy/`), risk scoring (`AgentKit/RiskScorer.swift`), redaction (`AgentKit/Redactor.swift`), and per-agent hooks (`hook.go`, `opencode_hook.go`, `agent_registry.go`) back the auto-allow/deny/escalate decisions surfaced in Activity.

### O. Debug gallery (NOT normal-user-reachable)

`DebugGalleryView.swift` (`#if DEBUG`, gated by `CONDUIT_GALLERY`) is the only entry for these. None ship to a normal user.

| Route(s) | Views | Notes |
|---|---|---|
| `components`, `chat`, `blocks`, `hud`, `statusheader`, `keyboard`, `states`, `features`, `inbox-typed`, `pages`, `hosts`, `library`, `statusbar`, `addhost` | component catalogs / mocks | visual reference only |
| `mgmt-agentpolicy` | `AgentPolicyView` (`ManagementViews1.swift:224`) | gallery-only; TODO-laden |
| `mgmt-agents` | `AgentListView` (`ManagementViews1.swift:307`) | gallery-only; `// TODO: create agent` etc. |
| `mgmt-vmlist` / `mgmt-vmdetail` | `VMListView`/`VMDetailView` (`ManagementViews1.swift:403,520`) | gallery-only; `// TODO: connect/stop/destroy`, mock metrics |
| `mgmt-diagnostics` | `DiagnosticsView` (`ManagementViews2.swift:374`) | gallery-only; `// TODO: wire to real SSHSession diagnostics` |
| `mgmt-commandbar` | `CommandBarView` (`ManagementViews2.swift:456`) | gallery-only |
| `cc-dispatch` | `DispatchComposerView` | gallery-only (only call site) |
| `orb-*`, `onboarding*`, `diff`, `filepreview`, `paywall`, `compare`, `billing`, `session` | misc | `DebugSessionHarness`, `DebugTerminalHarness` |

---

## DRIFT

### (a) IMPLEMENTED-BUT-HIDDEN — capability built, no normal-user UI entry

| # | Capability | Evidence (file:line) | One-line fix |
|---|---|---|---|
| 1 | **Saved-hosts list + reconnect/delete** (the only way to revisit a saved host) | `AppFeature/HostsView.swift:13`, `WorkspacesFeature/WorkspacesView.swift:46` — public, **zero call sites**; Fleet shows live slots only | Add a "Saved hosts" list (Fleet empty-state section or Settings → Hosts) wired to `HostRepository` with reconnect/edit. |
| 2 | **Edit an existing host** | `AppRoot.swift:415` presents `HostEditorView` on `$editingHost`, but `editingHost` is **only ever set to `nil`** (`AppRoot.swift:423`); the only `onEdit` callbacks live in orphaned `HostsView`/`WorkspacesView` | Wire a host-row "Edit" action (from fix #1) to set `editingHost = host`. |
| 3 | **SFTP file browser** | `FilesFeature/FilesView.swift:66` — public `FilesView`, **no call site** anywhere in the app graph | Add a "Files" button in `SessionView`'s `ChatHeaderView` presenting `FilesView(session:)` at session depth. |
| 4 | **Web / localhost preview** | `PreviewFeature` (`PreviewView`/`SmartPreviewView`/`PreviewSurface`) referenced only by orphaned `AppFeature/SessionShellView.swift:143` | Present `SmartPreviewView(session:)` from `SessionView` (e.g., when `PortDetector` finds a forwarded HTTP port). |
| 5 | **Multi-cloud provisioning wizard** (Fly/Lightsail/Orbstack) post-onboarding | `OnboardingFeature/ProvisioningWizard.swift` reached only via `AppRoot.swift:357` (`!onboardingSeen`); no entry after onboarding | Add a "Provision a workspace" action to the Fleet empty state / AddHost that sets `showingProvisioningWizard = true`. |
| 6 | **Session history** | `AppFeature/HistoryView.swift:65` — public `HistoryView`, no call site | Surface as a row in Activity or Settings (`SessionSnapshotRepository` already persists). |
| 7 | **Standalone Workflows + WorkflowEngine** as a first-class surface | `AppFeature/WorkflowsView.swift:7` orphaned (`// TODO: back with real workflow service`); Library uses mock `WorkflowBuilderView` instead | Either delete `WorkflowsView` or route Library → real engine (`AgentKit/WorkflowEngine.swift`). |
| 8 | **`ExplainSheet`** | `SessionFeature/ExplainSheet.swift:8` public, no call site — `SessionView` uses its own inline `explainSheet` (`SessionView.swift:554`) | Dead duplicate — delete, or replace the inline sheet with it. |
| 9 | **`KeysView`** (KeysFeature) | `KeysFeature/KeysView.swift:94` public, no call site — Library uses `KeysManagementView` | Dead duplicate — delete or route Library → `KeysView`. |
| 10 | Legacy roots `SessionsHomeView`, `SessionShellView`, `AdaptiveRoot` | `AppFeature/SessionsHomeView.swift:43`, `SessionShellView.swift:42`, `AdaptiveRoot.swift:7` — only used by previews/each other | Remove pre-IA dead code (also un-hides #4 dependency). |

### (b) SHOWN-BUT-UNIMPLEMENTED — visible UI that is stubbed / dead-end / TODO

| # | UI element | Evidence (file:line) | Fix |
|---|---|---|---|
| 1 | **Library "+ new snippet"** header button does nothing | `AppFeature/LibraryView.swift:36` — `DSIconButton(.plus) { /* new snippet — TODO */ }` | Present `SettingsFeature/SnippetEditorView` (already built) and save via `SnippetRepository`. |
| 2 | **Library "RECENT" snippet row** tap does nothing | `LibraryView.swift:115` — `DSSnippetRow(...) { /* run snippet — TODO */ }` | Wire tap to run/insert the snippet (e.g., into active session or copy). |
| 3 | **Snippets library "run"** is a no-op | `ManagementViews2.swift:252` — `// TODO: run snippet` (reachable Library → Snippets) | Wire to `SessionViewModel.runCommand` / insert. |
| 4 | **Workflows screen** shows mock data and "add step" is dead | `LibraryView.swift:79` → `WorkflowBuilderView` (`ManagementViews2.swift:269`); data = `LibraryMocks` (`LibraryMocks.swift:4` "TODO: back with real workflow service"); `ManagementViews2.swift:343` `// TODO: add step` | Back with `WorkflowEngine`; implement add-step, or hide the Workflows card until real. |
| 5 | **AppRoot paywall never triggers** | `AppRoot.swift:149-150` `showingPaywall`/`paywallFeatureName` declared; the `.sheet` (`:269`) is wired but **never set `true`** in the live graph (only orphaned `SessionShellView.swift:147+` sets it); `paywallFeatureName` never assigned | Either wire Pro-gated actions to set `showingPaywall = true` with a feature name, or remove the dead sheet. (Paywall content is still reachable via Settings → Compare/Billing.) |
| 6 | **Library SSH-Keys host count is mocked** | `ManagementViews2.swift:21` — "Mock host-count associations (TODO: wire real per-key host tracking)" (reachable Library → SSH Keys) | Compute per-key host usage from `HostRepository`. |
| 7 | **Org member invite** claims success but sends nothing | `AppFeature/AgentOrgView.swift:99` — "Invites are recorded on the server; email delivery is not yet enabled" (reachable yes·cloud via Agents → org) | Implement email delivery or relabel as "invite link" until enabled. |

### Defensive / non-drift notes
- **SSH agent-forwarding** (`AppRoot.swift:823`, "not implemented yet"): no UI ever creates an `.agent` host (`AddHostView`/`HostEditorView` only emit `.password`/`.ed25519`), so this branch is unreachable defensive code rather than a user-facing dead-end.
- **`xai` / `openrouter` provider key tests** return "not yet supported" (`SettingsView.swift:108,111`), but only `anthropic`/`openai` appear in `supportedProviders`, so the unsupported branches aren't user-reachable from the picker.
- **Raw full-screen terminal** (`RawTerminalView`) is present but **dormant** — nothing drives `vm.isRaw` in the shipping path (per `CLAUDE.md`); alt-screen TUIs render inside their block instead.

---

*Generated from source on branch `feat/governed-approvals`. All paths are relative to the worktree root `cc-wt/governed-approvals-audit/`.*
