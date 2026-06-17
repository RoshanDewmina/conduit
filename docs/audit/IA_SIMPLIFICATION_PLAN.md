# Conduit iOS — Information Architecture Simplification Plan (4 tabs)

> READ-ONLY architecture map. No source was modified to produce this document.
> All paths are relative to `Packages/ConduitKit/Sources/` unless noted.
> Note: the SPM target compiles **every** `.swift` under `Sources/` regardless of the
> Xcode project membership, so "dead" views still must build — but they are unreachable
> at runtime (not referenced from `AppRoot` or any live destination). None of the
> dead-candidate views appear in `Conduit.xcodeproj/project.pbxproj` (verified: 0 hits each).

---

## 0. Current root navigation (already 4 tabs)

The tab bar is **already** the target four tabs — the IA refactor is partly landed at the root level. The work is consolidating the *destinations behind each tab*, not the tab set.

- `Tab` enum + `rootTabs`: `AppFeature/AppRoot.swift:199` → `[.inbox, .fleet, .activity, .settings]`
  - titles `AppRoot.swift:201-208`, icons `AppRoot.swift:210-217` (`tray`, `square.stack.3d.up`, `clock.arrow.circlepath`, `gear`)
- Tab content host: `compactRoot` `AppRoot.swift:844`; `tabContent` switch `AppRoot.swift:890-915` (one `NavigationStack` per tab, `DSTabBar` via `safeAreaInset`).
- iPad split: `regularRoot` `AppRoot.swift:917` (`NavigationSplitView`).
- **Canonical destination map** — `rootDestination(_:env:)` `AppRoot.swift:976-1037`:
  - `.inbox` → `InboxView` (`AppRoot.swift:980`)
  - `.fleet` → `FleetView` (`AppRoot.swift:988`)
  - `.activity` → `ActivityView(actions:)` (`AppRoot.swift:1011`)
  - `.settings` → `SettingsWithLibraryView` → `SettingsView` (`AppRoot.swift:1014`, wrapper at `AppRoot.swift:1396`)

### Top-level destinations presented OUTSIDE the tabs (sheets / covers, all in AppRoot)
| Surface | Trigger state | file:line |
|---|---|---|
| Onboarding (full screen, pre-tabs) | `!onboardingSeen` | `AppRoot.swift:451-468` |
| `ProvisioningWizard` (sheet) | `showingProvisioningWizard` | `AppRoot.swift:471` |
| `AddHostView` (sheet) | `addHostPresented` | ~`AppRoot.swift:485` |
| `AgentsView` (hosted cloud, sheet) | `showingHostedAgents` | `AppRoot.swift:517-523` |
| `DispatchView` (New Task composer, sheet) | `dispatchPresented` | `AppRoot.swift:524-533` |
| `HostEditorView` (sheet) | `editingHost` | `AppRoot.swift:539` |
| `PasswordPromptView` (sheet) | `passwordPromptHost` | `AppRoot.swift:553` |
| `RunDetailView` (relay run, sheet) | `activeRelayRun` | `AppRoot.swift:378-393` |
| `SessionView` (live terminal, fullScreenCover) | `isShowingLiveSession` | `AppRoot.swift:879-884` |
| `PaywallSheet` | `showingPaywall` | `AppRoot.swift:298` |

---

## 1. LIVE vs DEAD inventory (the load-bearing finding)

**Wired live** (reachable from AppRoot at runtime): `InboxView`, `FleetView`, `ActivityView`, `SettingsView`, `LoopDetailView` (pushed from Fleet `FleetView.swift:123`), `DispatchView`, `RunDetailView`, `SessionView`, `AddHostView`, `OnboardingView`, `ProvisioningWizard`, `AgentsView` + its whole sub-cluster (`AgentDetailView`/`AgentExecView`/`AgentFilesView`/`AgentWorkspaceView`/`AgentOrgView`/`AgentRunDetailView`/`CreateAgentSheet`/`AgentBillingSheet`/`EditScheduleSheet`), `BillingView`/`PremiumComparisonView`/`AuditView`/`TerminalSettingsView`/`E2ERelayPairingView`/`TrustPrivacyView` (all pushed from Settings), `DiffView`/`FilePreviewView` (pushed from Loop/Agent detail + Inbox).

**Scaffolded-but-DEAD** (no live reference anywhere; only their own file or a comment / debug gallery):
| View / store | Evidence | Disposition |
|---|---|---|
| `WorkspacesView` (`WorkspacesFeature/WorkspacesView.swift:46`) | only a comment in `SSHParse.swift:6` | **delete** — superseded by FleetView |
| `SessionsHomeView` (`AppFeature/SessionsHomeView.swift:43`) | only a comment in `DebugGalleryView.swift:1042` | **delete** — superseded by FleetView |
| `WorktreeBoardView` (`AppFeature/WorktreeBoardView.swift:7`) + `WorktreeStore` (`AppFeature/WorktreeStore.swift`) | zero references; `WorktreeStore` used only by `WorktreeBoardView` | **delete pair** (or demote to iPad/advanced per merge #4) |
| `QuotaGuardView` (`AppFeature/QuotaGuardView.swift:6`) | zero references; `onQuotaGuard: nil` passed at `AppRoot.swift:998` | **keep as the drill-in target for merge #3** — wire it, don't delete |
| `FilesView` + `SFTPFilesView` (`FilesFeature/FilesView.swift:66,127`) | zero live references | **delete** (functionality folds into AgentFilesView/Changes) |
| `OnboardingRedesignGalleryView` (`OnboardingFeature/OnboardingRedesignGalleryView.swift:5`) | only `DebugGalleryView.swift:38` | gallery-only; keep as design ref or delete with onboarding redesign |

**Shared infrastructure (stores/models — NOT view code, do not delete in view merges):**
`FleetStore`, `LoopStore` (+`LoopRepository`), `QuotaGuardStore`, `HostHealthStore`, `GitStore`, `RunOutputStore`, `RunControlStore`, `AgentStore`, `ApprovalRepository`, `AuditRepository`, `AuditViewModel`, `BridgeSessionActions`, `AgentHUDStore`. `GitStore` is shared by BOTH `LoopDetailView` (live) and the cloud `AgentDetailView` cluster — never remove it during a view merge.

---

## 2. Per-merge inventory (KEEP / MOVE / DEAD / shared)

### Merge 1 — Approvals + Inbox + Live-Activity approvals + Watch approvals → Inbox
- **KEEP (canonical):** `InboxFeature/InboxView.swift:48` (+ `InboxViewModel` `:12`, `InboxViewModel+Live.swift`). Card components `DesignSystem/Components/InboxCards.swift`, `ChatComponents.swift` (`DSApprovalCard`), `DSDecisionSheet.swift`, `AllowAlwaysScopeSheet.swift`.
- **MOVE-IN / already there:** Inbox already renders a "WHILE YOU WERE AWAY" preview from `awayAuditEntries` (`InboxView.swift:100-106`) via `BridgeAuditFeedView` — this is the merge-2 overlap point (see Risk R2).
- **Shared (NOT view):** the decision pipeline lives in AppRoot, not Inbox — `handleApprovalAction` (`AppRoot.swift:397`), `drainPendingApprovalActions` (`AppRoot.swift:426`), `ApprovalRelay`/`ApprovalIngest`, `configureGlobalInbox` (`AppRoot.swift:664`). Lock-screen notification-action routing: `AppRoot.swift:328-336`.
- **Notification/action extensions (NOT in ConduitKit — separate Xcode targets):** Live Activity → `ConduitLiveActivityWidget/`, `SessionFeature/LiveActivityManager.swift`, `SessionFeature/ApprovalActionIntent.swift`. Watch → `ConduitWatch/InboxListView.swift`, `ApprovalDetailView.swift`, `WatchConnector.swift`; phone side `AppFeature/PhoneWatchConnector.swift`, watch decision sink `AppRoot.swift:~1254-1272`.
- **DEAD:** none unique to this merge. These are already one approval model fanned out to extensions — mostly a *documentation/consistency* merge, not a deletion.

### Merge 2 — Activity + Activity Audit + "while you were away" → one Activity timeline
- **KEEP (canonical):** `InboxFeature/ActivityView.swift:6` (live at `AppRoot.swift:1011`). Renders `BridgeAuditFeedView` (`InboxFeature/BridgeAuditFeedView.swift:6`).
- **MOVE-IN:** the cryptographic audit-chain UI — `SettingsFeature/AuditView.swift:99` (+ `AuditViewModel:10`) — currently lives in **Settings** (`SettingsView.swift:640-641`). Per the proposal "full audit lives only in Activity," this should move from Settings → Activity (verify/export/chain-validity). `BridgeAuditFeedView` (bridge tail) and `AuditView` (durable hash-chain) are **two different audit surfaces** today.
- **Inbox preview:** `InboxView.swift:100-106` already shows a small "while you were away" strip — keep as preview only.
- **Shared:** `AuditRepository`, `AuditViewModel`, `BridgeSessionActions.tailAudit` (`ActivityView.swift:68`), `DaemonChannel.verifyAudit/exportAudit`.
- **DEAD:** none.

### Merge 3 — Fleet + Quota Rings + Quota & Spend → Fleet inline + Quota-Guard drill-in
- **KEEP (canonical):** `AppFeature/FleetView.swift:7`. It already shows spend inline (`agentRow` `$%.2f` at `FleetView.swift:374-377`) and has a built-but-unused `quotaGuardEntry` (`FleetView.swift:223`) gated behind `onQuotaGuard` (passed `nil` at `AppRoot.swift:998`).
- **MOVE-IN / WIRE-UP:** `AppFeature/QuotaGuardView.swift:6` is the drill-in detail — currently **dead**. Merge #3 = pass a non-nil `onQuotaGuard` that pushes `QuotaGuardView`. `QuotaGuardStore` is already live (`FleetView.swift:216`, `AppRoot.swift:992`).
- **Shared:** `QuotaGuardStore`, `HostHealthStore`, `FleetStore`, `FleetSummary`, `DSSpendHero`, `DSMetricTile`, `HostHealthBadge`.
- **DEAD after wiring:** nothing — this merge *resurrects* dead code rather than deleting it.

### Merge 4 — Agent detail + Worktree detail + Worktrees + Run detail → one Loop/Agent Detail
- **KEEP (canonical):** `AppFeature/LoopDetailView.swift:9` — **already has the exact proposed sections**: Overview (`headerSection`/`statusSection`/`identitySection`/`locationSection` `:225-302`), Changes (`changesSection:89`), Progress (`:340`), Approvals (`:425`), Spend (`spendSection:453`), Proof (`proofSection:484`), CI (`:164`). This is the merge target.
- **MOVE-IN:** Run-detail behaviors — `AppFeature/RunDetailView.swift:15` (live relay-run streaming, `AppRoot.swift:381`) provides streaming output + pause/resume/budget (`StreamingOutputText:335`, `BudgetSheet:370`). The "Output" section the proposal wants in Loop detail does not exist in LoopDetailView yet — it lives in RunDetailView. Fold its streaming view in or push it from an "Output" section.
- **DEAD / demote:** `WorktreeBoardView.swift:7` + `WorktreeStore.swift` (zero refs) → delete or demote to iPad/advanced. Standalone "Worktrees board" has no live entry today.
- **SEPARATE cluster — do NOT conflate:** the `AgentDetailView` family (`AgentDetailView.swift:10` + `AgentExecView`/`AgentFilesView`/`AgentWorkspaceView`/`AgentOrgView`/`AgentRunDetailView`) is the **hosted-cloud** (`HostedAgent`) detail, reached only from `AgentsView` (merge #8). It mirrors LoopDetail's sections but operates on `HostedAgent` via `AgentStore`, not `Loop`. Treat it as Advanced/Cloud, not part of the on-device Loop detail.
- **Shared:** `GitStore` (both clusters), `LoopStore`, `RunOutputStore`, `RunControlStore`, `CIEvent`, `Loop`/`Loop.Proof`, `ProofCardView`.

### Merge 5 — Diff Review + Git Files Preview + Files → "Changes" inside detail
- **KEEP (canonical):** `DiffFeature/DiffView.swift:6` (live from `LoopDetailView.swift:77`, `AgentRunDetailView.swift:68`, `InboxView.swift:333,365`) + `FilesFeature/FilePreviewView.swift:11` (live from `AgentFilesView.swift:55`). The "Changes" section = `LoopDetailView.changesSection:89`.
- **DEAD:** `FilesFeature/FilesView.swift:66` (`FilesView`) + `SFTPFilesView:127` — zero live references → delete; SFTP browsing already lives in the cloud `AgentFilesView`.
- **Shared:** `DiffKit/UnifiedDiff.swift`, `GitStore`, `SFTPClient`, `FilesViewModel+SFTP`.

### Merge 6 — New Chat + Session Chat + Voice Input → one Start/Steer composer; voice = input mode
- **KEEP (composer canonical):** `AppFeature/DispatchView.swift:28` — the "New Task" composer (agent picker `:144`, model `:254`, budget `:284`, cwd/prompt `:207/:227`). Wired at `AppRoot.swift:524`.
- **KEEP (deep live surface):** `SessionFeature/SessionView.swift:8` + `Chat/ChatInputBar.swift:20` + `Chat/ChatTranscriptView.swift`. "Session Chat stays the deep live interaction surface."
- **Voice = input mode:** `SessionFeature/DictationEngine.swift` is used **only** by `SessionView.swift:20` today — NOT by DispatchView. Merge #6 means surfacing dictation in the DispatchView composer too (currently absent).
- **MOVE/RECONCILE:** `SessionFeature/LivePromptInputView.swift` (raw-byte steer, used by `ChatInputBar.swift:215`) is the in-session steer path; keep distinct from the start-a-run composer.
- **DEAD:** none.

### Merge 7 — Onboarding + Pairing Hosts SSH + Relay Pairing → single Connect Bridge/Host flow
- **⚠️ ACTIVELY UNDER REDESIGN RIGHT NOW** — `OnboardingFeature/OnboardingView.swift` last modified **Jun 16 18:59** (today). Recent commits `ee6d4fad` "fix onboarding skip", `a6250865` "land in app on pair success". **Do not dispatch a merge-7 edit agent against `OnboardingView.swift` without coordinating** (see Risk R1 / Collision table).
- **KEEP (canonical primary path):** `OnboardingFeature/OnboardingView.swift:21` (5-step, `step:27`, `totalSteps=5`), which embeds `SSHScreen:504` and `BridgePairingView` (`OnboardingView.swift:77`). Plus `QRScannerView.swift` for relay QR.
- **MOVE-IN (maintenance path):** `SettingsFeature/E2ERelayPairingView.swift:7` (pushed from `SettingsView.swift:500`) and `WorkspacesFeature/AddHostView.swift:17` (sheet from Fleet). Proposal: primary setup from Fleet, maintenance in Settings → both should funnel through one Connect-Bridge component.
- **DEAD/gallery:** `OnboardingRedesignGalleryView.swift:5` (gallery-only).
- **Shared:** `E2ERelayClient`, `PairingCrypto`, `RelaySettings`, `ProvisioningWizard`, `HostRepository`.

### Merge 8 — Agent Cloud Hosted + AgentsView + Billing → Advanced/Cloud
- **KEEP (canonical):** `AppFeature/AgentsView.swift:8` + its whole cluster + `SettingsFeature/BillingView.swift:8`.
- **DISCOVERABILITY (problem):** the **only** live entry to `AgentsView` is `AddHostView`'s "conduit cloud" source toggle (`AddHostView.swift:217,313`) → `onUseHosted` → `showingHostedAgents` sheet (`AppRoot.swift:494-523`). There is no Settings or runtime-picker entry. Merge #8 wants a runtime picker / Settings surface. Billing is reachable from Settings (`SettingsView.swift:717`) but cloud agents are not.
- **Shared:** `AgentStore`, `HostedAgent`/`HostedAgentRuntime`/`HostedAgentAPIClient`, `PurchaseManager`, `CloudEntitlementClient`, `BillingEligibility`.

### Merge 9 — Settings → grouped (Connection, Policy, Security, Notifications, Account, Advanced)
- **KEEP (canonical):** `SettingsFeature/SettingsView.swift:380`. Current sections (`SettingsView.swift:438-456`): `headerSection`, `bridgeAndHostsSection:490` (→ Connection), `approvalsSection:511` (→ Policy), `securitySection:593` (→ Security), `trustPrivacySection:667`, `accountSection:709` (→ Account), `resetSection:680` (→ Advanced).
- **Gaps vs proposal:** no dedicated **Notifications** group today; **Advanced** would receive demoted Worktrees board + cloud runtime picker; **Policy** group should host `PolicyEditorView`/`PolicySimulatorView`/`SecretsView` (currently linked piecemeal). Audit (`AuditView`) should LEAVE Settings for Activity (merge #2).
- **Shared:** `SettingsViewModel`, all `SettingsFeature/*` pushed views.

### Merge 10 — Platform Surfaces (Live Activity, Widgets, Watch, complications) → mirror core states
- **Separate Xcode targets, NOT ConduitKit views:** `ConduitWidget/`, `ConduitLiveActivityWidget/`, `ConduitWatch/`, `ConduitWatchWidget/` (verified at repo root).
- **Shared model contract:** `ConduitCore/WidgetSnapshot.swift` is the cross-target state mirror; `SessionFeature/LiveActivityManager.swift`, `DesignSystem/Components/AgentIsland.swift`, `AppFeature/PhoneWatchConnector.swift`. Core states to mirror already modeled: pending approval (`hudStore.pendingApprovals` `AppRoot.swift:622-623`), running loop (`Loop.Status`), quota warning (`QuotaGuard`), completed/failed run (`RunOutputStore`/`.conduitRunCompleteAction` `AppRoot.swift:337`).
- This is a **contract-alignment** merge (one snapshot model → all surfaces), not a view deletion.

---

## 3. Collision risks (files touched by multiple merges)

**`AppFeature/AppRoot.swift` is the single biggest collision hub** — it is the composition root and is touched by merges **1, 2, 3, 4, 6, 7, 8, 10**:
- merge 1: notification routing `:328-376`, watch sink `:1254-1272`
- merge 2: `.activity` destination `:1011`
- merge 3: `onQuotaGuard:` arg `:998`
- merge 4: `RunDetailView` sheet `:378-393`, `LoopDetailView` reachability
- merge 6: `DispatchView` sheet `:524-533`, `dispatchAgents`/`performDispatch` `:733-840`
- merge 7: onboarding block `:451-468`, `ProvisioningWizard`/`AddHostView` sheets `:471-516`
- merge 8: `showingHostedAgents` sheet `:517-523`
- merge 9: `SettingsWithLibraryView` args `:1014-1037, :1396`
→ **AppRoot edits MUST be serialized.** Never run two AppRoot-touching agents in parallel.

Other multi-merge files:
- `InboxFeature/InboxView.swift` — merges **1 + 2** (the away-preview block `:100-106`).
- `SettingsFeature/SettingsView.swift` — merges **2 (remove AuditView), 8 (add cloud entry), 9 (regroup)** all rewrite its section layout → serialize.
- `FleetView.swift` — merges **3 (quota wire) + 4 (loop detail nav) + 7 (connect entry)** → serialize.
- `LoopDetailView.swift` — merges **4 + 5** (Output section + Changes) → serialize (or split by section if disjoint).
- `OnboardingView.swift` — merge **7** AND the **live redesign in progress** → highest collision risk, coordinate with the human.

---

## 4. Safe incremental sequence (keeps `swift build` green + app launchable each step)

Principle: delete dead code first (pure subtractions can't break live paths once confirmed zero-ref), then do additive wiring, then the AppRoot-heavy regroupings last, one at a time.

**Phase A — Dead-code removal (parallelizable; disjoint files; no AppRoot edits):**
- A1 (delete): `WorkspacesFeature/WorkspacesView.swift`
- A2 (delete): `AppFeature/SessionsHomeView.swift`
- A3 (delete pair): `AppFeature/WorktreeBoardView.swift` + `AppFeature/WorktreeStore.swift` (merge 4 demotion)
- A4 (delete pair): `FilesFeature/FilesView.swift` (`FilesView`/`SFTPFilesView`) — keep `FilePreviewView`/`FilesViewModel+SFTP` (used by AgentFilesView) (merge 5)
- These are disjoint files → safe to run as parallel agents. Each: confirm zero refs (already verified), delete, `swift build`. Remove the gallery `case` lines in `DebugGalleryView.swift` only if any reference these (none do for the four above; `FilePreviewView` is referenced and stays).

**Phase B — Additive wiring (mostly serial on shared files):**
- B1 (merge 3): wire `QuotaGuardView` as Fleet drill-in — edit `FleetView.swift` (`quotaGuardEntry` + nav) and the `onQuotaGuard:` arg in `AppRoot.swift`. *Serial* (AppRoot).
- B2 (merge 4/5): add "Output" section to `LoopDetailView.swift` folding `RunDetailView` streaming. *Serial on LoopDetailView*, can run parallel to B3/B4 (different files) but NOT parallel to B1 (AppRoot) if it also touches AppRoot — keep B2 confined to LoopDetailView/RunDetailView.
- B3 (merge 6): add dictation input mode to `DispatchView.swift` (reuse `DictationEngine`). Disjoint file → parallel-safe.
- B4 (merge 2): move `AuditView` from Settings into Activity — edits `ActivityView.swift` (add) + `SettingsView.swift` (remove link). Serial vs other SettingsView edits.

**Phase C — Settings regroup + cloud discoverability (serial; SettingsView + AppRoot):**
- C1 (merge 9): regroup `SettingsView.swift` into Connection/Policy/Security/Notifications/Account/Advanced.
- C2 (merge 8): add a Cloud/runtime entry to Settings/Advanced → `showingHostedAgents`. Touches SettingsView + AppRoot. Do AFTER C1.

**Phase D — Onboarding/connect unification (merge 7) — LAST, human-coordinated:**
- Onboarding is actively being redesigned today. Do not auto-dispatch. Once the redesign settles, unify `OnboardingView` SSH/relay screens with `AddHostView` + `E2ERelayPairingView` into one Connect-Bridge component.

**Cross-cutting (no swift build risk, separate targets):**
- merge 1 & 10 are largely consistency/contract work across `ConduitWatch/`, `ConduitWidget/`, `ConduitLiveActivityWidget/`, `WidgetSnapshot.swift` — schedule independently; they don't touch the four-tab ConduitKit views.

**Parallel-safe set:** {A1, A2, A3, A4} together; then {B3} alongside one of {B1|B2|B4}. **Never parallel:** anything touching `AppRoot.swift`, `SettingsView.swift`, `FleetView.swift`, or `OnboardingView.swift` simultaneously.

---

## 5. Issues / risks with the proposal

**R1 — Onboarding redesign collision (HIGH).** `OnboardingView.swift` was edited today (Jun 16 18:59) and is under active redesign (commits `ee6d4fad`, `a6250865`). Merge #7 directly rewrites this file. Dispatching a merge-7 agent now risks clobbering in-flight work. Defer #7 to last and coordinate with the human.

**R2 — "Decisions-only" Inbox vs "while you were away" overlap (MEDIUM).** Inbox already renders an away-audit strip (`InboxView.swift:100-106`) AND Activity owns the full timeline (`ActivityView.swift`, breadcrumb literally "while you were away" `:26`). The proposal says Inbox is "decisions only" yet may keep a tiny away-preview — these two intents conflict. Decide explicitly: keep the preview (then Inbox isn't strictly decisions-only) or remove it (then drop the `awayAuditEntries` param). There are also **two distinct audit surfaces** — `BridgeAuditFeedView` (bridge tail, live) vs `AuditView` (durable hash-chain, in Settings). Merging "all audit into Activity" must reconcile both, or you ship two different "activity" views.

**R3 — Fleet overload (MEDIUM).** FleetView already carries: saved hosts, live slots, active loops + LoopDetail nav, per-agent spend, local-model banner, pending-approval attention banner, quota-guard entry, host-health. Merge #3 adds quota rings/spend inline and #7 makes it the primary connect entry. Risk of a kitchen-sink tab. Consider sub-sections or a Fleet overview vs detail split before piling on.

**R4 — Cloud/billing discoverability collapses (MEDIUM-HIGH).** The hosted-cloud surface (`AgentsView`) has exactly ONE live entry today: the "conduit cloud" toggle buried inside `AddHostView` (`AddHostView.swift:217` → `onUseHosted` → `AppRoot.swift:503`). If merge #7 unifies/replaces `AddHostView`, that single entry point can be lost, orphaning the entire cloud cluster (`AgentDetailView`/`AgentStore`/`BillingView`). Merge #8 must add a durable Settings/runtime-picker entry BEFORE or DURING any AddHostView rework.

**R5 — Two parallel detail stacks silently diverge (MEDIUM).** `LoopDetailView` (on-device `Loop`) and the `AgentDetailView` cluster (cloud `HostedAgent`) both implement Overview/Changes/Spend/Proof/Audit-style sections against different models/stores, sharing only `GitStore`. The proposal's "one Loop/Agent Detail screen" risks implying a single view, but they cannot trivially merge (different data sources). Plan for two skins of one design language, not one view — and ensure `GitStore` (shared by both) is never removed during a view deletion.

**Secondary flags:**
- **No Notifications settings group exists yet** (merge #9) — it must be built, not regrouped.
- **`RunDetailView` (live relay-run sheet) is presented from AppRoot, not from Loop detail** — merge #4 "Run detail → Loop detail" must preserve the relay-run streaming path (`AppRoot.swift:378-393`, `RunOutputStore`) or live relay output regresses.
- **SPM compiles everything under `Sources/`** — deleting a "dead" view is safe for runtime but you must also delete/adjust any `DebugGalleryView.swift` `case` that constructs it, or the build breaks (relevant to `FilePreviewView`/`DiffView`/`OnboardingView` which ARE gallery-referenced and must stay).
