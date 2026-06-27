# Phase 2 — Backend ↔ Frontend Feature Matrix

> Every backend capability traced to its frontend. Status vocabulary:
> **Connected-E2E** (backend+API+UI wired, owner-verified live before) · **Wired** (backend+UI present,
> not re-verified live this audit) · **Backend-only** (no Swift caller / no UI) · **Internal** (Swift
> caller exists but no user-facing trigger) · **Mock/gallery-only** · **Deferred-V2** · **Planned**.
> "Runtime verified" = proven at runtime by prior owner test runs or this audit; **live relay E2E was
> NOT re-run this audit (owner: done with those)** — those rows marked "prior-run".
> Evidence: lancerd `daemon/lancerd/server.go` handlers; iOS `DaemonChannel` / `E2ERelayBridge` callers (Explore pass 2026-06-23).

## A. Core agent loop — dispatch / approve / continue (V1 CORE)

| Feature | Release | Backend | API/RPC | Frontend UI | E2E | Tests | Runtime | Status | Action |
|---|---|---|---|---|---|---|---|---|---|
| Dispatch agent | V1 | dispatch.go `runDispatch` | `agent.dispatch` | NewChatTabView send → `DaemonChannel.dispatchAgent` / `E2ERelayBridge.sendDispatch` | yes | yes | prior-run | **Connected-E2E** | Re-verify per vendor argv (drift) |
| Continue / follow-up | V1 | dispatch.go `runContinue` | `agent.run.continue` | NewChat follow-up / AppRoot.resumeConversation | yes | yes | prior-run | **Connected-E2E** | Per-vendor continue re-verify |
| Approval response | V1 | server.go `applyDecision` | `agent.approval.response` + relay `/approval/decision` | InboxView / DSDecisionSheet / lock-screen | yes | yes | PASSED 2026-06-23 (C2) | **Connected-E2E** | — |
| Cancel run | V1 | dispatcher.cancel | `agent.cancel` | AgentRunDetailView Cancel | yes | partial | prior-run | **Wired** | Confirm reachable in shipping nav |
| Pause / Resume run | V1 | dispatcher.pause/resume | `agent.pause` / `agent.resume` | `RunControl` only — **no UI button** | no | — | no | **Internal** | Decide: expose or defer |
| Per-run budget cap | V1 | dispatcher.setBudget | `agent.budget.set` | NewChat budget input | yes | partial | prior-run | **Wired** | Verify input reachable |
| Policy engine (ask/allow/deny) | V1 | policy pkg, server.go `policyEffect` | (internal) | — (governs all dispatch) | yes | yes (124 Go) | prior-run | **Connected-E2E** | — |
| Device register (relay/APNs/activity) | V1 | server.go `lancer.device.register*` | 3 RPCs | AppRoot foreground/handshake | yes | yes | PASSED 2026-06-23 | **Connected-E2E** | — |

## B. Governance — policy / audit / quota (V1)

| Feature | Release | Backend | RPC | Frontend | Status | Action |
|---|---|---|---|---|---|---|
| Policy get/set/reload | V1 | policy engine | `agent.policy.get/set/reload` | PolicyEditorView | **Wired** | B7 reachability check |
| Policy simulate | V1 | policy.Simulate | `agent.policy.simulate` | PolicySimulatorView | **Wired** | Confirm reachable |
| Audit tail/verify/export | V1 | audit.go (hash-chain) | `agent.audit.tail/verify/export` | ActivityView / AuditView | **Wired** | — |
| Quota status / setCap | V1 | dispatcher quota guard | `agent.quota.status/setCap` | QuotaGuardView (FleetView → Usage & limits) | **Wired** | — |
| Quota updateSpend | V1 | dispatcher | `agent.quota.updateSpend` | backend-driven (ApprovalRelay) | **Internal** | — (correct) |

## C. Fleet / host (V1)

| Feature | Backend | RPC | Frontend | Status | Action |
|---|---|---|---|---|---|
| Host health | health.go | `agent.host.health` | HostHealthStore → FleetView badge | **Wired** | — |
| Setup-drift scan | drift.go | `agent.drift.scan` | FleetView "Setup drift" card → DriftFindingsView | **Wired** (moat, post-launch) | — |
| Agent status / installed | agent_status.go | `agent.status` / `agent.agents.installed` | FleetStore; agent picker | **Wired** | — |
| Doctor diagnostics | server.go `collectDoctorReport` | `agent.doctor` | DoctorView | **Wired** | — |
| Pairing (begin) | pair_rpc.go | `agent.pair.begin` | E2ERelayPairingView (Mac-side QR) | **Wired** (macOS) | — |

## D. Observed sessions (read-only) (V1 partial)

| Feature | Backend | RPC | Frontend | Status |
|---|---|---|---|---|
| List vendor sessions | session_index.go | `agent.sessions.list` | ObservedSessionView | **Wired** (read-only) |
| Session transcript | transcript_watcher.go | `agent.sessions.transcript` | ObservedSessionView | **Wired** (read-only) |

## E. Git / files (V1 partial)

| Feature | Backend | RPC | Frontend | Status | Action |
|---|---|---|---|---|---|
| Git status/diff/changedFiles | git.go | `agent.git.status/diff/changedFiles` | GitStore → DiffFeature/AgentFilesView | **Wired** | — |
| Git ship (commit/PR) | git.go `gitShip` | `agent.git.ship` | DiffFeature "Ship It" | **Wired** | — |
| Git clone | git.go `gitClone` | `agent.git.clone` | **no Swift caller** | **Backend-only** | Wire or defer |
| Worktree list | git.go | `agent.worktree.list` | GitStore → WorktreesFeature | **Wired** but WorktreesFeature is sprawl | Defer (V2) |
| FS list dir | fs.go | `agent.fs.ls` | `@`-mention autocomplete + RelayFileBrowserView (relay only) | **Wired** (relay) | SSH path has no caller |
| Commands list | commands.go | `agent.commands.list` | NewChat composer autocomplete | **Wired** | — |
| CI recent | git.go `recentCIEvents` | `agent.ci.recent` | **no caller (scaffolded)** | **Backend-only** | Wire or defer |

## F. Secrets broker (V1)

| Feature | RPC | Frontend | Status |
|---|---|---|---|
| Store/list/delete | `agent.secret.store/list/delete` | SecretsView | **Wired** |
| Request (agent→phone) | `agent.secret.request` | backend-initiated push | **Backend-only** (correct) |
| Authorize / revoke | `agent.secret.authorize/revoke` | SecretsView approve/revoke | **Wired** |

## G. Scheduling & loops (PLANNED / not wired)

| Feature | RPC | Frontend | Status | Action |
|---|---|---|---|---|
| Schedule add/list/remove | `agent.schedule.add/list/remove` | **no UI** (list internal only) | **Backend-only** | Defer V2 — flag in brief |
| Loop update/list | `agent.loop.update/list` | LoopDetailView exists but **not wired** | **Planned/orphaned** | Defer V2 — flag in brief |

## H. push-backend control plane (hosted — DEFERRED V2 for execution; relay parts are V1)

| Group | Routes | V1 role | Frontend | Status |
|---|---|---|---|---|
| Approval relay | `/register`, `/approval`, `/run-complete`, `/approval/decision`, `/decisions`, `/ws/relay`, `/register-activity-token` | **V1 transport** | relay client/bridge | **Connected-E2E** (prior-run) |
| Billing / Stripe | `/billing/*`, `/credits/balance` | V1 (IAP) | BillingView / PaywallSheet | **Wired** (IAP unverified in TestFlight — C5) |
| Agents/runs/logs/artifacts | `/agents`, `/runs/*`, `/runs/*/artifacts` | **V2 hosted exec** | HostedProvisioning/RunnerStatus (orphaned 0-ref) | **Deferred-V2** |
| Quotas/usage | `/quotas/{p}`, `/usage/ingest` | V1/V2 | QuotaGuardView (daemon path) | **Wired** (daemon) / backend (cloud) |
| Schedules/orgs/device-bindings | `/schedules/*`, `/orgs/*`, `/device-bindings` | V2 / partial | DeviceManagementView (bindings) | **Partial** |
| Webhooks (GitHub CI) | `/webhooks/github`, `/webhooks/recent` | V2 | (CI not wired in app) | **Backend-only** |
| agent-runner | cloud executor | V2 | — | **Deferred-V2** |

## Summary — coverage

- **45 lancerd RPCs:** ~36 have Swift callers; **27 have a direct user-facing trigger**.
- **Backend-only / no UI:** `agent.git.clone`, `agent.ci.recent`, `agent.schedule.*`, `agent.loop.*`, `agent.secret.request` (correctly backend-initiated), `agent.pause/resume` (internal, no button).
- **Deferred-V2 (intentional, code retained):** hosted-cloud execution (`/agents`,`/runs`,`/run/artifacts` + HostedProvisioning/RunnerStatus/ProviderDetail/SelfHostVsHosted UI, ~900 LOC 0-refs).
- **Orphaned UI present but unwired:** LoopDetailView, WorktreesFeature.
- **Missing-state risks (to confirm in Phase 4/7):** loading/empty/error states for FleetView (relay-host "loads a million conversations after 30s" per prior session), ObservedSessionView, QuotaGuardView.
- **Biggest gap class:** the backend is materially broader than the V1 UI. The simplification mandate (defer schedules/loops/hosted-cloud/worktrees/CI; expose only what the core loop needs) is well-supported by this matrix.
