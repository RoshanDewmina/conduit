# Fable Frontend Wipe + Rebuild — Plan

**Date:** 2026-07-09 (Wave 0 executed by Fable 5 this date)
**Track:** Frontend wipe → Orca study → Apple docs → rebuild (plan-first)
**Status:** **Wave 0 COMPLETE — awaiting owner APPROVED.** No deletes performed; no product/backend code touched.
**Inventory base:** main checkout `~/Documents/command-center`, branch `feat/chat-overhaul-w0a`, tip `d4db7da7`, **dirty working tree** (W0.A dogfood in flight — see IN-FLIGHT flags).
**Supersedes (frontend portion only):** [`2026-07-09-fable-cleanup-PASTE.md`](2026-07-09-fable-cleanup-PASTE.md) / [`2026-07-09-fable-cleanup-plan-only.md`](2026-07-09-fable-cleanup-plan-only.md).
**Companion PASTE:** [`2026-07-09-fable-frontend-wipe-PASTE.md`](2026-07-09-fable-frontend-wipe-PASTE.md) · **Status:** [`2026-07-09-fable-frontend-wipe-Status.md`](2026-07-09-fable-frontend-wipe-Status.md)

---

## Goal

1. **Wave 0 (DONE, this doc):** evidence-backed **KEEP vs DELETE** inventory of Lancer frontend UI chrome, Orca study, Apple docs citations, rebuild architecture + stub-shell strategy → **STOP for owner APPROVED**.
2. **Wave 1 (after APPROVED, separate session):** delete only rows in the approved DELETE table; app must still compile via the stub shell.
3. **Wave 2:** full rebuild plan (screens, adapters, design system) from Orca patterns + Apple docs — still plan before code.
4. **Wave 3:** implement in a separate session.

Owner intent (locked): prior cleanup/rebuild attempt (commit `25609ca0`, executed from `2026-07-09-fable-frontend-shell-rebuild-brief.md`) did not land well; wipe frontend chrome aggressively, study Orca, read latest iOS docs, build only after a solid plan. "Delete everything on the frontend" = **aggressive UI chrome wipe**, not `rm -rf AppFeature` and not any backend change.

## Non-goals

- No deletes / product code in this Wave 0 session (docs only — verified, see Status).
- **Backend OFF LIMITS forever on this track:** `daemon/**`, `daemon/push-backend/**`, `daemon/agent-runner/**` and their Go tests.
- No Siri **Approve** intent, ever. No Face ID / biometric gate reintroduction.
- No reverting unrelated dirty git (W0.A dogfood edits are in flight on this branch).
- No committing competitor code (`research-repos/orca` is MIT — patterns + attribution only, verified `LICENSE:1-3` "MIT License / Copyright (c) 2026 Lovecast Inc.").
- No iOS 27 target raise in this track (separate Siri/iOS27 M0).
- Watch targets untouched (embed already cut 2026-07-08).

---

## Current state this plan inventories (important — differs from the seed hypotheses)

The shell was **already rebuilt once** (`25609ca0`, "Rebuild Cursor shell UI with Orca-informed 3-root IA and docked composer"). Consequences verified this session:

- The sheet-era views the seed plan listed (CursorComposerSheet, CursorProfileDrawer, CursorRunOnSheet, CursorModelSheet, CursorContextSheet, CursorShipActionSheet, CursorCommitsSheet, CursorRepoPickerSheet, CursorWorkspaceDetailSheet, CursorReturnPacketView, CursorDiffView, CursorBottomComposer, CursorThreadRow, …) **no longer exist**. Do not cite them as wipe targets.
- `CursorStyle/` is now 29 files: ~10 chrome views + 1 router + **13 engine/contract/seam files** (all on the hard-KEEP list, all verified to exist with importers).
- The rebuilt shell **no longer references a single `DesignSystem/Cursor/Components/*` atom** — nine atoms flipped to outright dead; the four Cursor token files remain load-bearing (Chat cards + live shell files).
- A 3-root Home/Workspaces/Settings switch exists (`CursorHomeView` is real), implemented as a **custom root switch, deliberately not `TabView`** (`CursorAppShell.swift:116-119`: "TabView caches the first empty child" bug, workaround 2026-07-09; re-evaluating TabView is a flagged follow-up).
- `LANCER_CURSOR_SHELL` / `LANCER_CURSOR_SHELL_LIVE` both live in `CursorShellLaunchSeam.swift:23-24` (LIVE-wins rule, tested by `CursorShellLaunchSeamTests`).
- 12 CursorStyle files + `AppRoot.swift`, `ConversationSyncCoordinator.swift`, `E2ERelayBridge.swift`, `SyncKit/ConversationSyncEngine.swift`, 3 test files are **dirty (IN-FLIGHT, W0.A)**. Wave 1 must not run until that work is landed/stashed.

## What "frontend" means (unchanged posture)

| Layer | Wipe posture |
|---|---|
| UI chrome: `CursorStyle/*View*`, docked-composer view, dead DesignSystem atoms, orphan feature-view modules, chrome-only UITests | **DELETE (proposed)** — Table 1 |
| Looks-like-frontend but load-bearing: bridge/contracts/engines/stores/seams/tokens/Chat governance cards/intents/extension contracts | **HARD KEEP** — Table 2 |
| Shell router + extension UI | **REWRITE / stub** — Tables 3 & 5 |
| Backend `daemon/**` | **OFF LIMITS** |

## Methodology (executed)

Per `.claude/skills/lancer-dead-view-sweep/SKILL.md`: root reachability from `AppRoot.swift` + launch seams; importer count per type = files (non-test, non-self) matching `rg -l '\bType\b'` across `Packages/LancerKit/Sources`, `Packages/LancerKit/Tests`, `Lancer`, `LancerUITests`, `LancerLiveActivityWidget`, `LancerWidget`, `LancerWatch`, `LancerWatchWidget`. Four parallel read-only inventory subagents produced the raw tables against the main checkout (a first pass ran against a stale worktree and was **discarded and re-run**; proof-of-tree required in output); every 0-ref / DELETE row was then **re-verified by the orchestrator** with an independent `rg` pass this session. Dirty files flagged IN-FLIGHT and never proposed for silent deletion.

---

## Table 1 — DELETE (proposed)

Importer counts are **non-test** external files; "shell" = `CursorAppShell.swift`. IN-FLIGHT = dirty in `git status` (W0.A) — deletable only after that work lands.

### 1a. CursorStyle chrome views (function recreated in Wave 3 against the unchanged bridge contract)

| path (`Packages/LancerKit/Sources/AppFeature/CursorStyle/`) | kind | importers | risk if wrong | notes |
|---|---|---|---|---|
| `CursorHomeView.swift` | view | 1 (shell) | Home root gone | IN-FLIGHT. Consumes `onOpenThread`, `onDispatch`, attention/thread state |
| `CursorWorkspacesView.swift` | view | 1 (shell) | Workspaces root gone | IN-FLIGHT. Takes value snapshots + `onDecide`/`onOpenReview`/`onRequestPairing` closures |
| `CursorWorkspaceThreadListView.swift` | view | 1 (shell) | thread list gone | Consumes `onSelectThread`, `onDispatch`, `CursorComposerCWDResolution` |
| `CursorWorkThreadView.swift` | view | **7** (shell, ConversationSyncCoordinator, Chat/{ReceiptCardView, ProofReelView, QuestionCardView}, pacer, bridge) | chat/transcript surface gone; highest cross-module fan-in | IN-FLIGHT. Drives transcript model + pacer + autoscroll; hosts Receipt/Question cards. Wave 3 replacement must re-host those KEEP engines/cards |
| `CursorSettingsView.swift` | view | 2 (AppRoot, shell) | Settings root gone | IN-FLIGHT. Consumes `onPaired`/`onRemoveMachine`/`onClearInvalid`/`onReset` |
| `CursorTrustedMachinesView.swift` | view | 1 (CursorSettingsView) | machine mgmt UI gone | IN-FLIGHT. Chrome over `CursorTrustedMachineModel` (KEEP) |
| `CursorOnboardingView.swift` | view | 2 (AppRoot, shell) | first-run gone | Calls `onRequestPairing` |
| `CursorPRDetailView.swift` | view | 1 (shell) | none — honest stub | Self-describes as deferred `prDetail` route stub |
| `CursorRelayPairingSheet.swift` | view | 2 (CursorTrustedMachinesView, AppRoot) | **pairing broken** | ⚠️ Embeds the real pairing flow (produces `E2ERelayClient` + `RelayMachineRecord`, calls `onPaired`). Wave 1 must keep a minimal pairing surface or re-host this logic in the stub — see Table 3 |
| `CursorReviewDiffView.swift` | view | 3 (AppRoot, shell, bridge) + 2 UITests | **approval loop UI broken** | ⚠️ The governed-approval decision screen (`pendingApproval`/`lookupApproval`/`onDecide`). Wave 1 keeps a stub Review surface (Table 3); coverage in `CursorShellLiveApprovalTests` must stay green |
| `CursorSearchOverlay.swift` | view | 2 (support file, shell) | search UI gone | Calls `onSearch` (FTS); `CursorConversationSearchSupport` is KEEP |
| `Components/CursorDockedComposer.swift` | view | 3 (WorkThread, ThreadList, Home) | composer gone | IN-FLIGHT. Docked-composer *pattern* survives (Orca §3 + `safeAreaInset`); uses KEEP `CursorComposerDraftStore` + `CursorComposerCWDResolution` |
| `CursorObservedSessionsSection.swift` — **View struct only** | view | 1 (ThreadList) | observed-sessions row gone | `CursorObservedSessionMapping` + `RowModel` + `ImportError` in the same file are **KEEP** (4 importers + tests) — split the file, don't drop it |

### 1b. Dead DesignSystem files (0 live consumers, transitively — every row re-verified by orchestrator `rg`)

| path (`Packages/LancerKit/Sources/DesignSystem/`) | importers | notes |
|---|---|---|
| `Components/DSButton.swift` | 0 | fully dead |
| `Components/LancerGlassChrome.swift` | 1 (dead DSButton only) | dies with DSButton |
| `Components/States/DSTypedErrorCard.swift` | 0 | fully dead |
| `Components/DSChip.swift` (`DSChipTone`) | 2 (both dead: DSTypedErrorCard, AgentState) | transitively dead |
| `Components/AgentState.swift` | 1 (dead CursorBlockedReasonRow) | transitively dead |
| `Components/Atomic/DotMatrixView.swift` | 2 (dead Primitives parts, DSTypedErrorCard) | dies with them |
| `ShortcutKey.swift` | 0 | fully dead |
| `Typography.swift` (`DSCapsStyle`/`DSRoundedCapsStyle`) | 0 | fully dead |
| `TerminalSafeTextField.swift` | 0 | dead despite load-bearing name — double-check no planned composer use before delete |
| `Components/Primitives.swift` — partial | `DSExitChip` alive (ReceiptCardView) | delete `DSStatusDot`/`DSSearchField`/`DSEmptyState`; **keep `DSExitChip`** (move or trim file) |
| `Cursor/Components/CursorApprovalBanner.swift` | 0 | dead post-rebuild |
| `Cursor/Components/CursorBlockedReasonRow.swift` | 0 | dead |
| `Cursor/Components/CursorBottomSheetContainer.swift` | 0 | dead |
| `Cursor/Components/CursorDetailHeader.swift` | 0 | dead |
| `Cursor/Components/CursorDiffStatText.swift` | 0 | dead (AppFeature duplicate already deleted) |
| `Cursor/Components/CursorHeaderBar.swift` | 0 | dead |
| `Cursor/Components/CursorListRow.swift` | 0 real (1 token-file mention) | effectively dead |
| `Cursor/Components/CursorProgressRing.swift` | 0 | dead |
| `Cursor/Components/CursorSectionHeader.swift` | 0 | dead |

### 1c. Orphan feature modules / files (0 imports anywhere; Package.swift edits required)

| path | importers | notes |
|---|---|---|
| `Packages/LancerKit/Sources/DiffFeature/` (whole module, sole file `DiffView.swift`) | 0 (`import DiffFeature` nowhere) | Remove product line `Package.swift:47`, target `:195`, dep edges `:188` (InboxFeature — declared but unused) and `:231` (AppFeature umbrella). NB: `DiffView` uses `DSDivider`/`.bottomDrawer`/`DSIconView` — deleting it further orphans those (re-count after) |
| `Packages/LancerKit/Sources/FilesFeature/` (whole module, sole file `FilePreviewView.swift`) | 0 | Remove `Package.swift:48`, `:200`, `:235`. Haptics loses one consumer (still alive via InboxViewModel) |
| `Packages/LancerKit/Sources/WorkspacesFeature/HostKeyConfirmSheet.swift` (file only) | 0 | **Keep `SSHParse.swift`** (AppRoot imports the module for it) |
| `Packages/LancerKit/Sources/SessionFeature/LivePromptInputView.swift` | 0 (one doc-comment mention in SessionViewModel:1103) | dead legacy PTY input, superseded by composer |

### 1d. UITests (see Table 4 for full disposition)

| path | notes |
|---|---|
| `LancerUITests/HomeButtonTapTests.swift` | chrome-only tap assertions; partially targets already-removed IA (profile drawer) — likely already failing |
| `LancerUITests/TapInjectionProofTests.swift` — 2 of 6 tests | `testTapInjectionViaTabSwitch` (nav chrome) + `testFaceIDToggleOptIn` (Face ID removed permanently 2026-07-07 — dead regardless of wipe) |

---

## Table 2 — KEEP (hard)

Why each looks "frontend" but is load-bearing. All verified present with importers on `d4db7da7`.

### 2a. CursorStyle engine/contract/seam files (13)

| file | why KEEP |
|---|---|
| `CursorShellLiveBridge.swift` | **The API contract** — `@Observable` state + every closure (`onDispatch`, `onContinue`, `onDecide`, `onSearch`, `onOpenThread`, `onPollThread`, `onPaired`, `onRemoveTrustedMachine`, `onRequestRefresh`, `pendingApproval*`, …). 8 importers incl. AppRoot + RunOutputStore. IN-FLIGHT |
| `CursorShellLiveEnvironment.swift` | Environment plumbing that hands the bridge to every screen |
| `CursorShellLaunchSeam.swift` | Mock/live env-var resolution (`LANCER_CURSOR_SHELL[_LIVE]`, LIVE-wins), dedicated test |
| `CursorComposerContract.swift` | `CursorComposerCWDResolution` wired into ThreadList/DockedComposer/AppRoot. (`CursorComposerContract` enum itself currently 0 production importers — IN-FLIGHT diff may add consumers; keep, re-check at Wave 1) |
| `CursorComposerDraftStore.swift` | Draft persistence engine |
| `CursorTranscriptMapper.swift` | Turn→row mapper incl. Orca-ported pending-turn overlay fix. IN-FLIGHT |
| `CursorThreadTranscriptModel.swift` | Live transcript model. IN-FLIGHT |
| `CursorStreamingTextPacer.swift` / `CursorStreamingTextSmoother.swift` | Streaming pacing engine (Happier-mined, attributed) |
| `CursorTranscriptAutoScrollPolicy.swift` | Autoscroll policy (Orca-mined, attributed) |
| `CursorMarkdownPreprocessor.swift` | Markdown pipeline |
| `CursorAssistantMarkdownView.swift` | MarkdownUI renderer — keep or thin-wrap (owner list); only consumer of preprocessor |
| `CursorThreadAttention.swift` | Attention/needs-you domain model; crosses into PersistenceKit |
| `CursorTrustedMachineModel.swift` | Machine row/formatting/snapshot model (5 importers). IN-FLIGHT |
| `CursorConversationSearchSupport.swift` | FTS query scoping (tested) |
| + `CursorObservedSessionMapping` (+RowModel/ImportError) inside `CursorObservedSessionsSection.swift` | 4 importers + test — split from its View wrapper at Wave 1 |

### 2b. AppFeature non-CursorStyle

`AppRoot.swift` (root router, deep links, push, bridge population — IN-FLIGHT), `ConversationSyncCoordinator.swift` (IN-FLIGHT), `ApprovalIngest.swift`, `DispatchAgent.swift`, all `*Store.swift` (Agent/Fleet/RelayFleet/RunControl/RunOutput/QuotaGuard), `PhoneWatchConnector.swift`, `DebugSeeder.swift` (UITest reseed seam — verify usage at Wave 1).

### 2c. SessionFeature (all engines + governance chat surfaces)

Engines: `E2ERelayBridge` (IN-FLIGHT), `ApprovalRelay` (15 importers), `CommandGateway`, `ConnectionStateStore`, `ActiveRunRegistry`, `RunDispatchService`, `StartAgentRunPreparer`, `SessionViewModel`, `ScenePhaseObserver`, `LiveActivityManager` (defines `LancerSessionAttributes`), `LiveActivityPresentation`, `ApprovalActionIntent` (widget-invoked intent).
Governance surfaces (owner hard-KEEP): `Chat/{ReceiptCardView, QuestionCardView, ProofReelView}.swift` + models `ReceiptCardModel`, `QuestionCardModel`, `AnswerQuestionResolver`.
⚠️ `Chat/ReturnPacketModel.swift`: hard-KEEP-listed but **currently orphaned** (its only view consumer died in the `25609ca0` rebuild; test-only refs now). Owner decision at Wave 2: re-wire a return-packet surface or retire the model deliberately. Not a silent delete.

### 2d. Whole modules (non-UI)

`IntentsKit`, `LancerCore` (incl. `WidgetSnapshot` App-Group contract), `PersistenceKit`, `SyncKit` (IN-FLIGHT file), `SSHTransport`, `SecurityKit`, `AgentKit`, `NotificationsKit` (incl. `SiriNavigation` which references the shell), `HostControlKit`, `AccountKit`, `InboxFeature`, `OnboardingFeature`, `DiffKit`, `PreviewKit`, `TerminalEngine` (incl. `RawTerminalView` — live PTY surface), `WorkspacesFeature/SSHParse.swift`, `SettingsFeature` (`PaywallSheet` presented from AppRoot:337; PurchaseManager used by LancerApp/AgentStore).

### 2e. `Lancer/` app target — all 11 files

`LancerApp.swift` (`@main`, APNs + Live Activity token wiring + lock-screen decision delegate; body is just `AppRoot()` — **no deletable chrome inside**), `LancerAppShortcuts.swift` (AppShortcutsProvider must live in app target), `SiriRelevanceCoordinator`, `SiriSurfaceBootstrap`, `StartAgentRunIntent` + `StartAgentRunSupport`, `RunControlIntents`, `StatusQueryIntents`, `DenyApprovalIntent` (deny-only by design — **no Approve intent**), `AnswerQuestionIntent`, `AgentVendorAppEnum`.

### 2f. DesignSystem keep-side

Tokens: `Cursor/Tokens/{CursorPalette (CursorColors), CursorScheme, CursorType, CursorMetrics}.swift`, `Tokens.swift` (`LancerTokens`/`LancerAppearance`/`LancerAccentTheme` — AppRoot deps), `FontRegistration.swift` (LancerApp init), `Haptics.swift`.
Atoms with live keep-side consumers (Chat cards / Paywall / DiffView): `CursorArtifactCard`, `CursorHairlineDivider`, `CursorIconButton`, `CursorPillButton`, `CursorStatusBadge`, `DSDivider`, `DSIcon`/`DSIconView`, `DSExitChip`, `BottomDrawer.swift` + `CursorDrawer` (alive only via DiffView — if 1c deletes DiffFeature, re-count: BottomDrawer/CursorDrawer/DSDivider likely become deletable too; flagged for Wave 1 re-verify).

---

## Table 3 — REWRITE / stub strategy (what survives Wave 1 so the app compiles)

**Invariant:** after Wave 1, `AppRoot.cursorShellRoot` still compiles and hosts `CursorShellLiveBridge`; mock + live launch seams still work; pairing and approval remain reachable (ugly is fine, broken is not).

| artifact | Wave 1 action |
|---|---|
| `CursorAppShell.swift` | **Rewrite in place to a minimal stub root** (~150 lines): keep `CursorRoute` enum verbatim (`workspaceThreadList(String)`, `workThread(String?)`, `prDetail`, `reviewDiff` — `CursorAppShell.swift:14-17`; names are Siri/APNs/LA contracts), keep deep-link parsing (`:342-350`), keep the 3-root switch skeleton + bridge/value-snapshot init signature used by `AppRoot.swift:793-805`, replace each root's body with a placeholder list wired to bridge state. Keep custom root switch for the stub (TabView caching bug, `:116-119`); TabView re-evaluation is a Wave 3 decision |
| Pairing surface | Stub Settings root keeps a "Pair machine" row presenting a **minimal retained pairing sheet** — either keep `CursorRelayPairingSheet.swift` through Wave 1 (delete it in Wave 3 when its replacement exists) or extract its `E2ERelayClient` flow into a plain stub sheet. Recommended: **defer this one delete to Wave 3** — it is the only chrome file whose function cannot be stubbed with a no-op |
| Review surface | Same treatment: keep `CursorReviewDiffView.swift` through Wave 1 (it is the live approval loop; `CursorShellLiveApprovalTests` must stay green), replace in Wave 3 |
| Docked composer | Stub thread screen gets a plain `TextField` in `.safeAreaInset(edge: .bottom)` calling `onDispatch`/`onContinue` — keeps dispatch usable during Waves 1–2 |
| `CursorObservedSessionsSection.swift` | Split: move `CursorObservedSessionMapping`+`RowModel`+`ImportError` into a new `CursorObservedSessionMapping.swift`; delete the View |
| `CursorWorkspacesView` add-repo logic | `CursorAddRepoSheetPresentation` (tested by `CursorAddRepoSheetTests`) currently lives inside the view file — extract before deleting the view |
| Extensions | See Table 5 |

**Staged delete order (Wave 1):** land/stash W0.A dirty work → new worktree → (1) rewrite CursorAppShell to stub; (2) delete 1a views except RelayPairingSheet + ReviewDiffView; (3) delete 1b dead DS files; (4) delete 1c orphans + Package.swift edits; (5) delete/split 1d tests; (6) gate: `swift build` + `swift test` + XcodeBuildMCP app-target build + mock-shell launch + `CursorShellLiveApprovalTests`.

---

## Table 4 — UITests after chrome wipe

| file | disposition | reason |
|---|---|---|
| `LancerUITests/CursorAppShellExhaustiveTests.swift` | **KEEP, update selectors at Wave 3** | Already rewritten post-`25609ca0` (214 lines, 8 tests) for the 3-root mock shell; asserts stub-compatible behaviors (roots visible, no fake data, honest deferred stubs) |
| `LancerUITests/CursorShellLiveApprovalTests.swift` | **KEEP — must stay green through Wave 1** | Live approval loop (reseed → Review → approve → `onDecide`) |
| `LancerUITests/DispatchHaikuFlowTests.swift` | **KEEP** (selector touch-ups) | Live dispatch + model-picker wiring |
| `LancerUITests/HomeButtonTapTests.swift` | **DELETE** | Chrome-only; asserts removed IA (profile drawer) |
| `LancerUITests/LegacyUIRemovalTests.swift` | **REWRITE markers** | Guard intent survives; refresh marker list to this wipe's deprecated chrome |
| `LancerUITests/TapInjectionProofTests.swift` | **SPLIT** | Keep `testApproveDecisionApplies`, `testRelayApprovalUnblocksHostHook`, `testLocalhostSSHShowsTOFUAndConnects`, `testSavedHostReconnectPresentsPrompt`; delete `testTapInjectionViaTabSwitch` (chrome) + `testFaceIDToggleOptIn` (Face ID removed 2026-07-07) |
| `Packages/LancerKit/Tests/LancerKitTests/` — 10 `Cursor*` files + `ReturnPacketModelTests`, `ThreadAttentionTests`, `ConversationSyncCoordinatorTests` (IN-FLIGHT) | **KEEP — all must stay green** | All cover extracted non-view logic (contract, bridge, mapper, seam, tokens, search, add-repo presentation, attention). `CursorAddRepoSheetTests` requires the Table 3 extraction first |

---

## Table 5 — Extension targets

| target | disposition | evidence |
|---|---|---|
| `LancerLiveActivityWidget/` | **REWRITE UI chrome (stub until Wave 3)** — lock-screen approve/deny must keep rendering | Binary contracts (untouchable): `LancerSessionAttributes` (`SessionFeature/LiveActivityManager.swift:47`, used at `LancerLiveActivityWidget.swift:47,117,…`), `ApprovalActionIntent` (`ApprovalActionIntent.swift:75` → widget `:249,261`), `LiveActivityPresentation` (`:29` → widget `:118,279,…`). Widget imports only SessionFeature/NotificationsKit — **never DesignSystem** (hardcodes `LAPalette`, `LancerTokens` appears in a comment only) — so the DS wipe cannot break it |
| `LancerWidget/` | **REWRITE UI chrome (stub until Wave 3)** | Contract: `WidgetSnapshot` App-Group keys (`LancerCore/WidgetSnapshot.swift:1` → `LancerStatusWidget.swift:34-37`). Imports LancerCore only |
| `LancerWatch/` + `LancerWatchWidget/` | **OUT OF SCOPE / KEEP** | Watch embed cut 2026-07-08 (`project.yml:140` comment); not embedded in the iOS app |

---

## Orca study notes (Wave 0 — verified this session)

Donor: `research-repos/orca` (gitignored clone of `stablyai/orca`, tip `775fa95`). **MIT** verified (`LICENSE:1-3`). Patterns + logic portable with attribution comment (`// Ported from stablyai/orca (MIT): <path>`); **no verbatim React/RN code**.

**Prior Phase R citations re-verified line-accurate** (see [`2026-07-09-orca-shell-port-design.md`](2026-07-09-orca-shell-port-design.md), which remains valid): `pair-confirm.tsx:147-160` (`router.replace('/h/{hostId}')` at :160), `launch-agent-in-new-tab.ts:97`, `NativeChatView.tsx:403-405` (flex column: transcript `flex-1 min-h-0`, composer sibling), `native-chat-pending.ts:118-153` (pending sends as synthetic messages until transcript provably advances), `native-chat-autoscroll.ts:26-44`.

**New shell-IA mining (this session):**

| finding | evidence | proposed Lancer rebuild behavior |
|---|---|---|
| Orca mobile is a **single-root expo-router Stack** — no tabs/drawer; Home = host list + Resume card + stats; Settings is one push off Home's gear | `mobile/app/_layout.tsx:145-172` | Input to IA decision below — Orca fuses what Lancer splits into Home + Workspaces |
| Host detail becomes **sidebar + detail split on wide layouts** only | `mobile/app/h/_layout.tsx:29-52,60-64,141-158` | iPad: consider `NavigationSplitView` for Workspaces, size-class-gated; phone keeps stack |
| Home: hosts sorted by `lastConnected` desc; row = name + StatusDot + "N worktrees · M active"; long-press action sheet (Connect/Disconnect/Rename/Remove) | `mobile/app/index.tsx:421-422,846-873,1030-1080` | Workspaces machine rows: same info density + long-press management |
| **Resume card** — single most-recently-active worktree across all hosts, one tap to session | `index.tsx` footer + `pickResumeWorktree` (import :27) | Real gap: add "jump back in" affordance on Home |
| Session list: 5 sort modes (`smart/name/recent/repo/manual`, default recent) + grouping by repo/status | `src/worktree/workspace-view-settings.ts:11`, `workspace-list-picker-options.ts:4`, `index.tsx:167` | Thread list: sort/group picker instead of flat chronology (Wave 3 nice-to-have) |
| Connection health escalates through **named attempt thresholds**, verdict can override dot color; "never-connected" vs "went stale" distinguished | `src/transport/connection-health.ts:33-77` (`WARNING_ATTEMPTS=3`, `UNREACHABLE_ATTEMPTS=12`, `STALE_SINCE_LAST_CONNECT_MS=60s`); `src/components/StatusDot.tsx:16-31` | Map `ConnectionPhase` to staged verdicts in the rebuilt shell (binary online/offline is a known Lancer weakness) |
| "Active" badge counts only `working/active/permission` statuses | `index.tsx:196` | Attention counting rule for Home/Workspaces badges |
| Empty states: full onboarding screen when 0 hosts ("Pair Desktop" CTA + numbered steps); contextual per-filter empties in lists; **no global offline banner** — per-host inline state | `index.tsx:744-772`, `h/[hostId]/index.tsx:1150-1156` | Replace onboarding chrome with pair-first empty state on Home; drop global banners in favor of per-machine status |
| Chat engine patterns (streaming/markdown/tools/pending) | already mined — [`../product/2026-07-09-chat-ui-port-map.md`](../product/2026-07-09-chat-ui-port-map.md) (Happier primary donor for streaming; Orca synthetic-bubble; Omnara thin-client) | No further study pass needed (owner Addenda #6); engines already ported + attributed in KEEP files |

---

## Apple docs citations (verified via apple-docs MCP this session)

1. **NavigationStack** — root + `navigationDestination(for:)`, `init(path:)` binding for deep links / programmatic navigation (iOS 16+): https://developer.apple.com/documentation/swiftui/navigationstack. Rebuild keeps `CursorRoute` as the typed path currency.
2. **`safeAreaInset(edge: .bottom)`** (iOS 15+) — pins the docked composer below a scrolling transcript while growing the safe area, lifting with the keyboard without a sheet: https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l. This is the SwiftUI equivalent of Orca's `flex-1`/`shrink-0` column.
3. **`scrollDismissesKeyboard(_:)`** (iOS 16+, `.interactively` for chat): https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:) and **`defaultScrollAnchor(.bottom)`** (iOS 17+) for bottom-pinned transcripts with correct content-growth behavior: https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:).
4. **TabView / Tab** (programmatic selection, badges): https://developer.apple.com/documentation/swiftui/tabview — reference for the Wave 3 "custom root switch vs TabView" re-evaluation (current code avoids TabView for a first-paint caching bug, `CursorAppShell.swift:116-119`).
5. **App Intents constraints the rebuild must not break:** `AppShortcutsProvider` (https://developer.apple.com/documentation/appintents/appshortcutsprovider) — shortcuts must stay in the app target (`Lancer/LancerAppShortcuts.swift:11-17` documents the metadata-merge constraint); deep-link route names are intent/notification currency. WWDC25 275 "Explore new advances in App Intents", WWDC26 345/240 (see [`2026-07-09-wwdc-ios-capability-inventory.md`](2026-07-09-wwdc-ios-capability-inventory.md) §A for the full verified session index).
6. **Live Activity constraints:** `ActivityAttributes` is a Codable app↔extension contract (https://developer.apple.com/documentation/activitykit/activityattributes) — `LancerSessionAttributes` and its ContentState cannot change shape independently of the widget binary; push-token flow per WWDC23 10185 + WWDC26 223 (inventory §B).

---

## Rebuild architecture (Wave 2/3 direction)

**IA recommendation: keep the Cursor 3-root shell (Home / Workspaces / Settings), Orca-informed content — do not switch to Orca's single-root stack.**
Rationale: (a) deep-link routes, Siri navigation (`NotificationsKit/SiriNavigation.swift`), UITests, and `ARCHITECTURE.md` §4.1 all assume the 3-root shape — a single-root merge is a cross-cutting doc/code change with no demonstrated user win; (b) Orca's evidence (its Home fuses host list + resume + stats, Settings one push away) doesn't invalidate 3 roots, it warns that **Home and Workspaces must not duplicate each other**. So define crisp content contracts: **Home = attention** (needs-you queue from `CursorThreadAttention`, pending-approval banner, Orca-style Resume card, recent threads), **Workspaces = browse/manage** (machines + repos + thread lists + observed sessions + pair CTA when empty), **Settings = machines mgmt + app config**. Owner may still choose the Orca merge at APPROVED time; everything else in this plan is IA-shape-independent.

Skeleton (Wave 3): stub shell grows into `CursorAppShell` (rewritten) → 3 roots, each a `NavigationStack` with `navigationDestination(for: CursorRoute.self)`; thread screen = transcript (`ScrollView` + `defaultScrollAnchor(.bottom)` + existing mapper/model/pacer/autoscroll engines + Receipt/Question/ProofReel cards) over a docked composer (`safeAreaInset(.bottom)`, draft store, CWD resolution, run-target/model pickers); pairing per Orca §1 (replace-semantics landing on the paired machine); connection verdicts per Orca health thresholds. All views consume **only** `CursorShellLiveBridge` state/closures — the bridge API is frozen (additive fields allowed, documented).

**Design system:** rebuild keeps the four Cursor token files as the base (Chat cards depend on them); new chrome components are written fresh under `DesignSystem/Cursor/Components/` as needed — do not resurrect the dead atoms.

Known-bug bar: the rebuild must not regress the catalog in [`../design-audit/2026-07-08-cursor-shell-frontend-audit.md`](../design-audit/2026-07-08-cursor-shell-frontend-audit.md) + shell-rebuild-brief "known bugs that must not return" (approval recovery banners, Review shows real approval, run-target pick applies, CWD absolute via `repoPaths`, `onSearch`-backed search, no forced-light).

---

## Risks

| risk | mitigation |
|---|---|
| Deleting a bridge/contract file | Table 2 hard-KEEP + importer evidence on every DELETE row + owner APPROVED gate |
| App won't compile after Wave 1 | Table 3 stub shell + staged delete order + gate after each stage |
| Pairing/approval loop breaks mid-wipe | RelayPairingSheet + ReviewDiffView explicitly deferred to Wave 3; `CursorShellLiveApprovalTests` must stay green through Wave 1 |
| **W0.A dirty-tree collision** | Wave 1 blocked until owner lands/checkpoints `feat/chat-overhaul-w0a` dogfood work; execute in an isolated worktree; 12 CursorStyle files flagged IN-FLIGHT |
| Backend touch | OFF LIMITS; Wave 1 gate includes `git diff --name-only | rg '^daemon/' → must be empty` |
| License | MIT verified; attribution comment shape mandated; no clone commit (gitignored) |
| Stale-tree inventory (bit this session's first subagent pass) | All tables re-derived on `d4db7da7` with proof-of-tree; re-verify counts at Wave 1 start if the branch has moved |
| DS keep-atoms orphaned by 1c module deletes | Re-count `BottomDrawer`/`CursorDrawer`/`DSDivider`/`DSIconView` after DiffFeature/FilesFeature removal |

## Verify commands

**Wave 0 (done):** read-only `rg` inventory + `git status` — no build needed (no code changed).
**Wave 1 (future session, isolated worktree):**
```bash
cd Packages/LancerKit && swift build && swift test
# app target (iOS-gated code): XcodeBuildMCP session_show_defaults → build_sim
# mock shell smoke: build_run_sim with LANCER_CURSOR_SHELL=1 (3 stub roots visible)
# live approval loop: run CursorShellLiveApprovalTests (test_sim)
git diff --name-only | rg '^daemon/' && echo FAIL || echo OK
```
**Wave 2–3:** per rebuild plan; shell-rebuild-brief Done-bar D1–D10 carries forward as the Wave 3 bar.

## Decision log

| date | decision |
|---|---|
| 2026-07-09 | Owner: wipe frontend aggressively, study Orca, read Apple docs, plan before build; backend off limits; APPROVED gate before any delete |
| 2026-07-09 | Supersedes frontend portion of `2026-07-09-fable-cleanup-*` |
| 2026-07-09 | **Wave 0 executed by Fable 5** from the main checkout (`feat/chat-overhaul-w0a` @ `d4db7da7`); stale-worktree first pass discarded and re-run with proof-of-tree |
| 2026-07-09 | Subagents: Sonnet used for read-only inventory (owner in-session choice; this harness has no composer models). First-pass wrong-tree lesson: subagent `cd` + proof-of-tree now mandatory |
| 2026-07-09 | Prior `25609ca0` rebuild treated as current chrome: its views are the wipe candidates; its engine extractions (contract enum, mapper fix, launch seam) are KEEPs |
| 2026-07-09 | **IA recommendation: keep 3-root, Orca-informed content contracts** (Home=attention+resume, Workspaces=browse, Settings=manage); owner may override at APPROVED |
| 2026-07-09 | `CursorRelayPairingSheet` + `CursorReviewDiffView` deferred to Wave 3 (function can't be no-op-stubbed); everything else in Table 1 deletable at Wave 1 |
| 2026-07-09 | `ReturnPacketModel` orphaned — owner decision at Wave 2 (re-wire or retire), no silent delete |

## Progress

- [x] Wave 0: KEEP/DELETE inventory complete (importer counts on every DELETE row, orchestrator-verified)
- [x] Wave 0: Orca study notes with file:line (prior citations re-verified + new IA mining)
- [x] Wave 0: Apple docs citations
- [x] Wave 0: Rebuild architecture + stub-shell strategy + staged delete order
- [ ] Owner **APPROVED** (tables locked, IA choice confirmed)
- [ ] Wave 1: W0.A landed/checkpointed → isolated worktree → deletes per approved tables → gate green, no `daemon/**` touched
- [ ] Wave 2: full rebuild plan
- [ ] Wave 3: implement (separate session; Done-bar D1–D10)

---

## Addenda (2026-07-09 — owner review; locked, all reflected in tables above)

1. Extension targets → Table 5 (LA widget/status widget REWRITE-stub; Watch OUT OF SCOPE/KEEP; binary contracts listed with file:line).
2. Governance chat surfaces hard-KEEP → Table 2c.
3. CursorStyle transcript/streaming engine hard-KEEP → Table 2a (all 13 verified present on this tree).
4. Deep-link route names survive → Table 3 row 1 (`CursorAppShell.swift:14-17`).
5. Wave 1 in isolated worktree after dogfood checkpoint; Cursor vendor M1 separate session; no owner-iPhone reinstall without ask → Risks + staged order.
6. Orca primary; Happier/Omnara via port-map only → Orca notes final row.
7. Known-bug catalog read (shell-rebuild-brief + cursor-shell-frontend-audit) → Rebuild architecture "known-bug bar".
