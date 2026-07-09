# Lancer feature × improvement matrix vs. orca / happier / omnara

Compiled: **2026-07-09**. Read-only research — inventories every user-facing Lancer feature, checks whether the MIT/Apache competitor clones in `research-repos/{orca,happier,omnara}` implement the same thing, and lists concrete, evidence-backed improvements to borrow.

**Method:** grep + targeted file reads in `research-repos/{orca,happier,omnara}` and cross-check against `ARCHITECTURE.md` §0.1 plus live Lancer paths under `Packages/LancerKit/` and `daemon/lancerd/`. Chat rendering gaps are **not** duplicated here — see [`2026-07-09-chat-ui-port-map.md`](2026-07-09-chat-ui-port-map.md) (companion: [`../plans/2026-07-09-chat-interface-parity-plan.md`](../plans/2026-07-09-chat-interface-parity-plan.md)).

**Licenses:** Orca **MIT**; Happier **MIT** (`LICENCE` + `apps/ui/LICENSE`); Omnara **Apache-2.0**. Patterns and algorithms are portable with attribution; React/RN UI is never copied verbatim — re-implement in SwiftUI informed by their state machines and schemas.

**Legend:** Lancer status = **solid** (wired end-to-end in V1 path), **partial** (backend or UI exists but stub/unverified/unwired), **stub** (design-only or placeholder). *Differentiator* = capability competitors lack or Lancer leads on governance depth.

---

## 1. Workspaces / repo list, multi-repo switching

| | |
|---|---|
| **Lancer** | **partial** — `CursorWorkspacesView.swift:5-40` (live bridge rows + local Add Repo sheet); multi-repo via shell navigation in `CursorAppShell.swift`. |
| **Best competitor** | **Orca** — desktop `WorktreeList.tsx:1-50` (virtualized multi-repo/worktree sidebar); mobile `mobile/app/h/[hostId]/index.tsx:1-50` + `mobile/src/worktree/workspace-list-sections.ts:15-55` (pinned/active/PR-grouped sections, lineage rows). |
| **Happier** | **partial** — worktree materialization only: `apps/ui/sources/components/sessions/new/modules/materializeNewSessionCheckout.ts:23-40` + `repoScmWorktreeService`. |
| **Omnara** | **no** — single-dashboard model, no workspace root. |
| **Borrow** | Orca mobile PR-status grouping (`workspace-pr-status-groups.ts` via `workspace-list-sections.ts:9-10`) and lineage collapse (`mobile-workspace-lineage.ts`) for denser repo switching on phone. |
| **Differentiator** | No — Orca/Happier are ahead on worktree depth; Lancer's honest multi-repo list is thinner. |

## 2. Thread / session list per repo

| | |
|---|---|
| **Lancer** | **partial** — `CursorWorkspaceThreadListView.swift:5-38` (per-workspace threads from live bridge + observed-session rows); cross-device mirror in `ConversationSyncCoordinator.swift` / GRDB. |
| **Best competitor** | **Happier** — `apps/ui/sources/sync/store/buildSessionListViewDataWithServerScope.ts:1-40` (server-scoped session projection with machine reachability). **Orca** — agent rows per worktree in `WorktreeCardAgents.tsx` (sidebar) and mobile `WorktreeListRow` via `mobile/app/h/[hostId]/index.tsx:49`. |
| **Omnara** | **thin** — server-authoritative message table; no rich per-repo session IA. |
| **Borrow** | Happier's server-scoped list builder + reachable-machine projection before rendering session rows. |
| **Differentiator** | **Yes (partial)** — Lancer's observed-session import rows (`CursorObservedSessionsSection.swift`, `CursorShellLiveBridge.swift:149-155`) have no competitor equivalent. |

## 3. Composer with repo / model / run-target pickers

| | |
|---|---|
| **Lancer** | **partial** — `CursorComposerSheet.swift:6-68` (repo, branch, model, run-target pickers + optional `ProofReceipt.Contract` disclosure). |
| **Best competitor** | **Orca** — `NewWorkspaceComposerCard.tsx:1-50` + `useComposerState.ts:1-60` (repo combobox, agent catalog, branch/sparse preset, setup policy, issue/PR deep links). **Omnara** — schema-driven dynamic form: `apps/web/src/components/dashboard/LaunchAgentModal.tsx:11-40` + `src/shared/webhook_schemas.py:61-115`. |
| **Happier** | **yes** — `pick/machine.tsx`, `pick/profile.tsx`, `pick/path.tsx` (secret-satisfaction gate before send). |
| **Borrow** | (1) Orca's unified composer state machine (`useComposerState.ts`) for picker interlocks; (2) Omnara's `WebhookTypeSchema` pattern for provider-specific run-target fields without hardcoding each vendor. |
| **Differentiator** | **Yes (partial)** — proof-receipt contract block in composer (`CursorComposerSheet.swift:12-26`) is unique; picker depth still trails Orca. |

## 4. Global search

| | |
|---|---|
| **Lancer** | **partial** — `CursorSearchOverlay.swift` + `CursorConversationSearchSupport` (`CursorSearchOverlay.swift:4-39`: FTS scopes prompts/responses/artifacts). |
| **Best competitor** | **Orca** — worktree file Quick Open `QuickOpen.tsx:31-43` + ranked settings search `settings-search.ts:32-48` (tiered exact/prefix/substring scoring). **Happier** — memory-only `MemorySearchScreen.tsx` (salvaged; not cross-repo). |
| **Omnara** | **no** global search. |
| **Borrow** | Orca's settings-search ranking tiers for Lancer Settings stub destinations; extend conversation FTS to cross-repo "jump to thread" (Orca Quick Open's deferred-query + modal focus restore pattern: `QuickOpen.tsx:38-60`). |
| **Differentiator** | **Yes** — conversation FTS with artifact scope is Lancer-only among the three clones. |

## 5. Approval / review flow (diff, approve/deny, risk scoring)

| | |
|---|---|
| **Lancer** | **partial→solid daemon, partial UI** — `CursorReviewDiffView.swift:7-38` (real `Approval` binding, blast-radius cards `278-285`); daemon policy `daemon/lancerd/server.go:85-99`, blast radius in `LancerDProtocol.swift:100`. Tier 0 re-proof still open per `ARCHITECTURE.md` §0.1. |
| **Best competitor** | **Orca** — inline Allow/Deny: `NativeChatApprovalCard.tsx:11-54` fed by `agent-hook-listener.ts:647-699` (`PermissionRequest` → `{ approval: { tool, summary } }`). **Happier** — `ApprovalDetailScreen.tsx:7-21` (approve/deny, **no risk scoring**). |
| **Omnara** | **diff without gate** — MCP `approve` tool in `src/servers/mcp/stdio_server.py:307-454` (session-scoped allow lists, not mobile review UI). |
| **Borrow** | Orca's `summarizeApprovalInput` (`agent-hook-listener.ts:649-655`) for one-line tool summaries on the review card. |
| **Differentiator** | **Yes** — governed inbox + blast-radius + risk badge (`CursorReviewDiffView.swift:215-285`) + fail-closed policy engine. Competitors ship approve/deny without scoring or durable audit coupling. |

## 6. Receipts / proof-of-work / run summaries

| | |
|---|---|
| **Lancer** | **partial** — `ReceiptCardView.swift:6-40`, `ProofReceipt.swift`, `ProofReelView.swift` (`lancer.proof/v0` artifact cards in thread). |
| **Best competitor** | **none** — Orca/Happier/Omnara have usage stats and PR summaries, not structured proof contracts. |
| **Borrow** | N/A — competitors have nothing to port; polish Lancer's accept / another-pass / open-on-desktop actions. |
| **Differentiator** | **Yes** — receipt contract + validation commands is a Lancer-only primitive. |

## 7. Return-to-desk / continuity packet across devices

| | |
|---|---|
| **Lancer** | **partial** — `CursorReturnPacketView.swift:7-51` (read-only continuation command + git state); CloudKit mirror `ConversationSyncCoordinator` / `daemon/lancerd/conversation_store.go` (§11.2). |
| **Best competitor** | **Happier** — full workspace replication handoff: `apps/cli/src/session/handoff/workspaceReplicationAdapter/sessionHandoffWorkspaceReplicationAdapter.ts` + UI modals under `apps/ui/sources/components/sessions/handoff/`. **Orca** — transient session restore banner only: `SessionRestoredBanner.tsx` (not a cross-device packet). |
| **Omnara** | **no** continuity packet. |
| **Borrow** | Happier's workspace replication manifest + progress/recovery modals (`SessionHandoffProgressModal.tsx`) for true machine-to-machine handoff beyond copy-paste commands. |
| **Differentiator** | **Yes (partial)** — Lancer's return packet UX is unique; Happier leads on actual workspace bytes replication. |

## 8. Trusted machines / pairing / revocation

| | |
|---|---|
| **Lancer** | **partial** — `CursorTrustedMachinesView.swift`, `CursorRelayPairingSheet.swift`, cloud revoke in `ARCHITECTURE.md` §0.1 (Settings → Devices `GET /v1/devices` + revoke). |
| **Best competitor** | **Orca** — `src/shared/pairing.ts:3-30` (v2 offer, ECDH `publicKeyB64`, `orca://pair?code=`); mobile confirm flow `mobile/app/pair.tsx:7-42`; auth-retry before forced re-pair `mobile/src/transport/rpc-client.ts:116-123`. **Happier** — `MachinesSettingsView.tsx` + QR. |
| **Omnara** | **cloud API key** — no device pairing. |
| **Borrow** | Orca's protocol version kill-switch (`protocol-compat.ts:76-108`) to fence incompatible app/daemon pairs after upgrades. |
| **Differentiator** | **Yes (partial)** — Lancer cloud device revocation + E2E relay; Orca leads on pairing UX polish and version fencing. |

## 9. Add-repo honest / discovery flow

| | |
|---|---|
| **Lancer** | **partial** — `CursorWorkspacesView.swift:12-19` (`CursorAddRepoSheet` locally owned). |
| **Best competitor** | **Orca** — nested-repo discovery `useAddRepoServerPathFlow.ts:24-55` (`scanNestedRepos` + review modal) + create flow `useCreateRepo.ts:16-40`. |
| **Happier** | **partial** — worktree checkout path only (`materializeNewSessionCheckout.ts`). |
| **Omnara** | **no** add-repo flow. |
| **Borrow** | Orca's nested-repo scan → review → upsert pipeline before trusting a folder path. |
| **Differentiator** | No. |

## 10. Settings screens structure

| | |
|---|---|
| **Lancer** | **partial** — `CursorSettingsView.swift:8-135` (shell rows); policy/audit/notifications open **stub sheets** `CursorSettingsStubSheet` (`387-428`, stub copy `367-383`). |
| **Best competitor** | **Orca** — pane architecture `Settings.tsx:33-60` (20+ lazy panes) + searchable entries `settings-search.ts:3-48`. **Happier** — granular per-agent/per-target permissions (salvaged). |
| **Omnara** | **thin** — dashboard settings only. |
| **Borrow** | Orca's ranked settings search + lazy pane mounting (`Settings.load-performance.test.ts` pattern) to replace Lancer stub destinations with real policy/audit/quota panes. |
| **Differentiator** | No — Lancer IA matches wireframes but depth is behind Orca; governance rows are stubs. |

## 11. Onboarding / pairing first-run

| | |
|---|---|
| **Lancer** | **stub** — `CursorOnboardingView.swift:5-10` ("visual-only clone… no real pairing… not yet wired into AppRoot"). |
| **Best competitor** | **Orca** — `OnboardingFlow.tsx:1-60` (agent → theme → notifications → integrations steps). **Happier** — QR + restore (salvaged). |
| **Omnara** | **minimal** — API key entry. |
| **Borrow** | Orca's progressive onboarding with skip-confirmation (`OnboardingSkipConfirmationDialog.tsx`) and notification permission step tied to agent completion alerts. |
| **Differentiator** | **Yes (planned)** — Lancer onboarding wireframe includes a policy-presets step (`CursorOnboardingView.swift:51-54`) competitors lack; still stub until wired. |

## 12. Push notifications / lock-screen approval actions

| | |
|---|---|
| **Lancer** | **solid** (device-proven, re-verify per runbook) — `Notifications.swift:345-357` (`UNNotificationCategory` approve/reject actions), cold-launch buffer `58-64`, `ApprovalRelay.swift:47`; Live Activity push `ARCHITECTURE.md` §0.1. |
| **Best competitor** | **Orca mobile** — permission toggle only `mobile/app/notifications.tsx:23-36` (no lock-screen decision actions). **Happier / Omnara** — **no** lock-screen approve path (salvaged). |
| **Borrow** | Minimal — Lancer leads. Optional: Orca desktop notification sound/volume draft state (`NotificationsPane.tsx:14-24`) for richer settings UX. |
| **Differentiator** | **Yes** — governed lock-screen approve/deny + Live Activity is Lancer's proven wedge; competitors stop at banners/terminal notifications. |

## 13. Emergency stop / kill-switch

| | |
|---|---|
| **Lancer** | **partial** — daemon atomic latch `daemon/lancerd/dispatch.go:1237-1245`, RPC `server.go:1036-1038`; Watch path `WatchApprovalTransfer.swift:144-169`; **no iOS shell control wired** (`PhoneWatchConnector.swift:94` closure only). |
| **Best competitor** | **Orca** — protocol version kill-switch `protocol-compat.ts:89-91` (block incompatible mobile builds); chat slash `/stop` for background terminals `native-chat-slash-commands.ts:75` — **not** fleet emergency stop. |
| **Happier / Omnara** | **no** fleet kill-switch. |
| **Borrow** | Wire Lancer's existing `agent.emergencyStop` RPC to a prominent Settings + Watch control; adopt Orca's version-fence UX copy for post-upgrade safety. |
| **Differentiator** | **Yes** — daemon-side emergency stop + audit entry is unique; UI wiring remains the gap. |

## 14. Setup-drift detection

| | |
|---|---|
| **Lancer** | **partial** — daemon `daemon/lancerd/drift.go:15-99` + RPC `server.go:820-835`; **no Cursor-shell UI** surfacing findings. |
| **Best competitor** | **none** — Orca "drift" references are terminal resize/timer tests, not instruction-file drift. |
| **Borrow** | N/A from competitors — ship iOS drift scan/remediate cards calling existing `DaemonChannel.driftScan` (`SSHTransport/DaemonChannel.swift:374-400`). |
| **Differentiator** | **Yes** — instruction-file drift scan is Lancer-only among clones. |

## 15. Quota / host health monitoring

| | |
|---|---|
| **Lancer** | **partial** — `QuotaGuardStore.swift:7-38`, `HostHealth.swift`, daemon `agent.quota.status` (`DaemonChannel.swift:778-810`). |
| **Best competitor** | **Orca** — multi-provider usage dashboard `UsageOverviewPane.tsx:33-50` (Claude/Codex/OpenCode scans, daily charts). **Happier** — per-provider quota (salvaged). |
| **Omnara** | **no** host quota UI. |
| **Borrow** | Orca's `usage-overview-model.ts` + provider-specific panes (`ClaudeUsagePane.tsx`, `CodexUsagePane.tsx`) for Lancer diagnostics/quota settings. |
| **Differentiator** | **Yes (partial)** — Lancer daemon quota caps + host health RPC; Orca leads visualization. |

## 16. Audit log

| | |
|---|---|
| **Lancer** | **partial** — daemon hash-chained log `server.go:733-750` (`agent.audit.tail/verify/export`); iOS fetch via `DaemonChannel.swift:243`; Settings row opens **stub** (`CursorSettingsView.swift:128-135`, `375-376`). |
| **Best competitor** | **none** — no competitor ships a tamper-evident policy audit trail. |
| **Borrow** | N/A — implement real audit viewer consuming existing tail/verify/export RPCs. |
| **Differentiator** | **Yes** — hash-chained audit is core Lancer moat per `ARCHITECTURE.md` §0.1. |

## 17. Policy engine (presets, blast-radius, simulation)

| | |
|---|---|
| **Lancer** | **partial** — daemon `policy/evaluate.go:64`, simulation `server.go:150` + `agent.policy.simulate` (`791-803`); presets `PolicyPreset.swift:3-100`; UI **stub** (`CursorSettingsView.swift:121-127`). |
| **Best competitor** | **Orca** — agent permission **bypass flags** only (`tui-agent-permissions.ts:10-24`), not a governance engine. **Happier / Omnara** — **no** policy engine (salvaged). |
| **Borrow** | N/A for engine logic — wire Settings to live policy editor + simulation results from daemon. |
| **Differentiator** | **Yes** — deny>ask>allow, blast-radius on approvals, simulation, and allow-always persistence are Lancer-only. |

## 18. Observed-session import

| | |
|---|---|
| **Lancer** | **partial** — `daemon/lancerd/conversation_store.go:1175-1189` (`attachObservedSession`); iOS `CursorObservedSessionsSection.swift`, bridge hook `CursorShellLiveBridge.swift:153-155`. |
| **Best competitor** | **none** — Orca/Happier/Omnara assume sessions they start; no import of foreign CLI transcripts into a governed ledger. |
| **Borrow** | N/A. |
| **Differentiator** | **Yes** — unique bridge from "terminal I didn't start" into governed conversation history. |

## 19. PR / ship actions

| | |
|---|---|
| **Lancer** | **stub UI, partial daemon** — `CursorShipActionSheet.swift:5-18` (presentational, unwired); governed propose `server.go:1326` (`agent.ship.propose`). |
| **Best competitor** | **Orca** — AI-assisted PR composer `CreateHostedReviewComposer.tsx:1-50` + field generation `pull-request-generation.ts:30-47`; primary action resolver `source-control-primary-action.ts` (Create PR when eligible). **Happier** — partial publish-repo (salvaged, no create-PR). |
| **Omnara** | **no** PR ship path. |
| **Borrow** | Orca's `buildPullRequestFieldsPrompt` + hosted-review composer UX; keep Lancer's two-step propose→approve gate (`CursorShipActionSheet.swift:14-17`). |
| **Differentiator** | **Yes (partial)** — phone-initiated ship actions routed through the same approval/policy path is unique; Orca leads PR authoring UX. |

---

## Top borrowable improvements (ranked)

1. **Happier workspace handoff replication** — `apps/cli/src/session/handoff/workspaceReplicationAdapter/sessionHandoffWorkspaceReplicationAdapter.ts` + progress modals (`SessionHandoffProgressModal.tsx`) to close the gap between Lancer's copy-paste return packet and true cross-machine continuity.
2. **Orca multi-provider usage dashboard** — `UsageOverviewPane.tsx:33-50` + `usage-overview-model.ts` to surface existing `agent.quota.status` / spend data instead of hiding it behind diagnostics stubs.
3. **Orca nested-repo add flow** — `useAddRepoServerPathFlow.ts:24-55` honest discovery before `CursorAddRepoSheet` commits a path.
4. **Orca PR composer + AI field generation** — `CreateHostedReviewComposer.tsx` + `pull-request-generation.ts:30-47` wired into governed `agent.ship.propose` (Lancer policy gate retained).
5. **Orca settings search + pane lazy-load** — `settings-search.ts:32-48` + `Settings.tsx:33-60` pattern to replace `CursorSettingsStubSheet` for policy, audit, and notifications.

## Lancer moat / differentiators

Competitors (especially Orca and Happier) already ship **mobile pairing, workspaces, approvals, and composer pickers**. Lancer's defensible wedge — named in `ARCHITECTURE.md` §0.1 — is the **governance layer on your own machines**:

| Moat primitive | Evidence | Competitor gap |
|---|---|---|
| Policy engine + simulation | `daemon/lancerd/policy/`, `agent.policy.simulate` | Orca has bypass flags only; Happier/Omnara have no engine |
| Blast-radius + risk on approvals | `CursorReviewDiffView.swift:215-285`, `Approval.swift:23` | Happier approve/deny without scoring (`ApprovalDetailScreen.tsx`) |
| Hash-chained audit | `server.go:733-750` | None of the clones |
| Lock-screen governed decisions | `Notifications.swift:345-357`, C2 proof `ARCHITECTURE.md` §0.1 | Orca mobile notifications are permission-only (`notifications.tsx`) |
| Proof receipts / contracts | `ProofReceipt.swift`, `ReceiptCardView.swift` | None |
| Observed-session import | `conversation_store.go:1175-1189` | None |
| Setup-drift detection | `drift.go:15-99` | None (Orca "drift" is unrelated terminal timing) |
| Emergency stop (daemon) | `dispatch.go:1237-1245` | Orca has protocol kill-switch only, not fleet agent halt |
| Governed ship propose | `agent.ship.propose` + `CursorShipActionSheet.swift:14-17` | Orca ships PR UX without phone policy gate |

**Lead with policy/audit/emergency-stop;** borrow Orca/Happier for workspace density, composer depth, usage viz, and PR authoring — re-implemented in SwiftUI, attributed per license.
