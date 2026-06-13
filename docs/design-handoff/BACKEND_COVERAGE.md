# Backend → Frontend Coverage Matrix

Every backend capability (conduitd resident-daemon RPC, push-backend hosted-cloud HTTP route)
is inventoried below with its iOS frontend surface. Generated for the design-handoff review.

**Status legend:** ✅ built & reachable in shipping UI · 🔶 gallery-only / debug surface ·
🟦 intentional (RPC retained, UI archived on product pivot) · ❌ no frontend surface.

The product is a **passive approval loop** ("approve agent actions from your phone"), not a
dispatch console. The SSH→resident-daemon path (`conduitd`) is the shipping core; the
push-backend (hosted Conduit Cloud) is gated behind a paid entitlement and partially built.

---

## A. conduitd resident-daemon RPC (`daemon/conduitd/server.go` dispatch switch)

iOS bridge: `DaemonChannel` (`Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift`),
surfaced through `BridgeSessionActions` + `ApprovalRelay`.

| Capability | Backend (file:line) | Frontend surface (view + tap path) | Status |
|---|---|---|---|
| `ping` (liveness) | server.go:376 | `DaemonChannel.start()` handshake — no user UI | ✅ |
| `agent.approval.response` (approve/deny/edit) | server.go:379, resident.go:144, approval.go | **Inbox** → approval card → APPROVE/DENY/ALLOW ALWAYS/EDIT&RUN. Wired via `ApprovalRelay.respond` → `DaemonChannel.respond` | ✅ |
| `agent.approval.pending` (queue tail) | approval.go:124 | **Inbox** pending list (`InboxViewModel`); also feeds APNs push | ✅ |
| `agent.audit.tail` (while-you-were-away) | server.go:388 | **Activity** tab → `ActivityView` (`tailAudit`); also Settings → Security audit log (`AuditView`) | ✅ |
| `agent.policy.get` (read policy) | server.go:400 | `DaemonChannel.fetchPolicy` exists; policy editor uses YAML variant (`fetchPolicyYAML`) instead — see note | ✅ (via YAML) |
| `agent.policy.reload` | server.go:412 | **Settings → Edit bridge policy.yaml** → "Reload policy on bridge" (`PolicyEditorBridgeScreen.reloadPolicy`) | ✅ |
| `agent.policy.set` (write YAML) | server.go:423 | **Settings → policy editor** → save (`savePolicyYAML`, enabled only when SSH-connected) | ✅ |
| `agent.status` (vendors/sessions/spend) | server.go:438 | **Fleet** tab summary card (vendors / sessions / $today) via `FleetStore.fetchAgentStatus`; **Library → Agents** count | ✅ |
| `conduit.device.register` (APNs token) | server.go:448, server.go:174 | Auto-registered on connect (`AppRoot` → `registerDevice`); no explicit UI | ✅ |
| `agent.dispatch` (start an agent run) | server.go:483 | RPC retained; the dispatch **composer UI was intentionally archived** (`archive/conduitkit-dead-views/DispatchComposerView.swift`) on the pivot to the passive approval loop. `dispatchAgent` still callable from `AppRoot`. | 🟦 intentional |
| `agent.cancel` (stop a run) | server.go:491 | **Library → Agents → run detail** → cancel (`AgentRunDetailView` / `AgentStore.cancelRun`) — cloud-entitlement gated | ✅ (gated) |
| `agent.schedule.add` | server.go:498 | No add-schedule composer (archived with dispatch). `addSchedule` callable but no UI. | 🟦 intentional |
| `agent.schedule.list` | server.go:506 | **Library → Agents** reads schedules (`AgentStore.listSchedules`) — cloud-gated | 🔶 cloud-gated |
| `agent.schedule.remove` | server.go:509 | No remove-schedule UI (archived). `removeSchedule` callable but unwired. | 🟦 intentional |

**Note (policy.get):** the editor loads/saves the *raw YAML* (`fetchPolicyYAML`/`savePolicyYAML`,
RPCs `agent.policy.get`/`set`) rather than the structured `fetchPolicy` decode — both hit the same
daemon methods. `fetchPolicy` (structured) has no direct caller; not a gap, the YAML path supersedes it.

---

## B. push-backend hosted-cloud HTTP routes (`daemon/push-backend/*.go`)

These power **Conduit Cloud** (hosted agents, billing, usage). The whole surface is gated behind a
paid entitlement (`PurchaseManager.cloudEntitlement`); free BYO-host users never hit it.

### Approval relay & device (core push loop)

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /register` | main.go:88 | `DaemonChannel.registerDevice` / `ApprovalRelay.configureBackend` on connect | ✅ |
| `POST /approval` (enqueue from daemon) | main.go:89 | Server-side ingest from conduitd; phone receives via APNs → **Inbox** | ✅ |
| `POST /approval/decision` | main.go:91 | `ApprovalRelay.postDecisionToBackend` — phone's approve/deny when relayed via cloud | ✅ |
| `GET /decisions` (poll) | main.go:92 | Daemon-side poll; phone publishes decisions (see above) | ✅ |
| `POST /run-complete` | main.go:90 | Server ingest → drives "run complete" push notification | ✅ |
| `GET /health` | main.go:93 | Ops/liveness only — no UI (correct) | ✅ |

### Billing (Stripe)

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /billing/checkout` | billing.go:77 | **Settings → Billing & usage** / **Paywall** → purchase (`BillingView`, `PaywallSheet`) | ✅ |
| `POST /billing/portal` | billing.go:78 | **Settings → Billing** → manage subscription / restore | ✅ |
| `GET /billing/subscription-status` | billing.go:79 | **Billing** "Cloud active / status" row | ✅ |
| `GET /billing/entitlement` | billing.go:80 | `PurchaseManager.refreshCloudEntitlement` gates all cloud UI | ✅ |
| `POST /billing/webhook` | billing.go:81 | Stripe→server only; no UI (correct) | ✅ |
| `GET /billing/return` | billing.go:82 | Post-checkout redirect landing; no app UI (web) | ✅ |
| `GET /billing/quota` | quotas.go:168 | **Billing → AI usage today** / quota display | ✅ |
| `GET /billing/credits` | credits.go:182 | **Billing** credits balance (when present) | ✅ |

### Hosted agents & runs (Conduit Cloud)

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /agents` (create) | agents.go:94 | No create-agent composer in shipping UI (archived with dispatch). `AgentStore` can create but no tap path. | 🟦 intentional |
| `GET /agents` (list) | agents.go:95 | **Library → Agents** (`AgentsView`, cloud-entitlement gated) | 🔶 cloud-gated |
| `GET /agents/{id}` | agents.go:96 | **Library → Agents → detail** | 🔶 cloud-gated |
| `DELETE /agents/{id}` | agents.go:97 | **Agents → swipe/delete** (`AgentStore.deleteAgent`) | 🔶 cloud-gated |
| `POST /runs` (start run) | agents.go:98 | No run-launch composer (archived). | 🟦 intentional |
| `GET /runs/{id}` | agents.go:99 | **Agents → run detail** (`AgentRunDetailView`) | 🔶 cloud-gated |
| `GET /runs` (list) | agents.go:100 | **Agents → runs list** | 🔶 cloud-gated |
| `POST /runs/{id}/logs` (append) | run_logs.go:58 | Agent-side ingest; phone reads via GET — no write UI (correct) | ✅ |
| `GET /runs/{id}/logs` | run_logs.go:59 | **Run detail → log stream** (`AgentRunDetailView`) | 🔶 cloud-gated |
| `PATCH /runs/{id}` | run_logs.go:60 | Server/agent status update; not a phone action | ✅ |
| `POST /runs/{id}/cancel` | run_logs.go:61 | **Run detail → cancel** (`cancelRun`) | 🔶 cloud-gated |
| `GET /runs/{id}/control` | run_logs.go:62 | Agent-side poll for cancel signal; no UI (correct) | ✅ |

### Run artifacts

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /runs/{id}/artifacts` | artifacts.go:62 | Agent-side upload; no phone write UI (correct) | ✅ |
| `GET /runs/{id}/artifacts` | artifacts.go:63 | No artifact browser in shipping run-detail UI yet | ❌ |
| `DELETE /runs/{id}/artifacts/{artifactId}` | artifacts.go:64 | No artifact management UI | ❌ |
| `GET /runs/{id}/artifacts/{artifactId}/download` | artifacts.go:65 | No artifact download UI | ❌ |

### Schedules (hosted)

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /agents/{id}/schedules` | schedules.go:64 | No schedule-create UI (archived with dispatch). | 🟦 intentional |
| `GET /agents/{id}/schedules` | schedules.go:65 | **Agents** reads schedule list (`AgentStore.listSchedules`) | 🔶 cloud-gated |
| `POST /schedules/{id}/trigger` | schedules.go:66 | No manual-trigger UI | 🟦 intentional |
| `PATCH /schedules/{id}` | schedules.go:67 | No edit-schedule UI | 🟦 intentional |
| `DELETE /schedules/{id}` | schedules.go:68 | No delete-schedule UI | 🟦 intentional |

### Usage & orgs

| Route | Backend (file:line) | Frontend surface | Status |
|---|---|---|---|
| `POST /usage` (cross-vendor ingest) | usage.go:42 | Agent/server-side metering ingest; phone reads aggregate via `/billing/quota` → **Billing → AI usage today**. No write UI (correct) | ✅ |
| `GET /orgs/{id}/members` | orgs.go:61 | **Settings → team org** members (only when `cloudEntitlement.teamOrg` present) | 🔶 cloud-gated |
| `POST /orgs/{id}/members` (invite) | orgs.go:62 | No invite-member composer in shipping UI | ❌ |

---

## Summary

- **Capabilities inventoried:** 49 (14 conduitd RPC + 35 push-backend routes)
- ✅ built & reachable: **27**
- 🔶 cloud-gated (built, behind paid entitlement): **11**
- 🟦 intentional (RPC retained, composer UI archived on pivot): **8**
- ❌ no frontend surface: **4** — run-artifact list/delete/download, org-member invite

### ❌ gaps (documented, NOT built — all non-trivial)

1. **Run artifact browser** (`GET/DELETE/download /runs/{id}/artifacts*`) — needs a new artifact-list
   view + secure download/preview pipeline inside the cloud run-detail screen. Non-trivial (new feature).
2. **Org-member invite** (`POST /orgs/{id}/members`) — needs an invite composer + email/role flow.
   Non-trivial; only relevant once team billing ships.

These are hosted-cloud (paid) features still under construction, not shipping-path regressions.

### Trivial gaps built this pass

None required. Every shipping-path (free BYO-host) capability already had a reachable surface —
the nav audit's 6 confirmed reachable screens (policy editor, while-you-were-away audit feed,
cross-vendor usage/spend, Keys+Snippets library, Billing, paywall) all verified present and captured.
The only un-surfaced backend capabilities are either intentional (archived dispatch composer) or
non-trivial hosted-cloud features. No `feat(ios):` wiring commit was warranted.
