# Conduit — Project Dossier (State of the Project)

> ⚠️ **ARCHIVED 2026-06-18 — superseded by [`ARCHITECTURE.md`](../../ARCHITECTURE.md) §0.1 + §4.1.**
> This dossier was compiled 2026-06-11 and predates the **sidebar / New Chat IA pivot**; its
> "tabs Inbox/Fleet/Activity/Settings" navigation and several §4 gap statuses are now stale.
> Kept for the strategy/market analysis (§5–§9) and historical context only. For current state,
> read `ARCHITECTURE.md`. Do not cite this file as source of truth.

> **Compiled:** 2026-06-11 · branch `feat/product-depth-sprint` (13 commits ahead of `master`, 0 behind).
> **Purpose:** a single, self-contained briefing for an external agent (or human) with **zero prior context**, so they can (a) understand the product and codebase deeply, (b) advise on strategic direction, and (c) run grounded competitor research. Every architectural claim is backed by source `file:line`; every market claim carries a confidence tag and (where known) a source URL. **Verification status is flagged** — and where this dossier corrects an older in-repo audit doc, it says so explicitly.
>
> **Reading note for the advising agent:** several in-repo docs (`docs/_archive/APP_AUDIT.md`, `docs/_archive/cloud-execution-engine-plan.md`, parts of `docs/_archive/current-state-audit.md`, `docs/_archive/remaining-work.md`) were written 1–3 weeks ago and are **partially stale** — they describe gaps that have since been closed. Where they conflict with this dossier, trust this dossier's *Verified* items (§4) — they were re-checked against current source on 2026-06-11. The strategy/market docs (`PRODUCT_RESEARCH.md`, `ROADMAP.md`, `FRONTEND_DESIGN_BRIEF.md`) remain current and are summarized faithfully in §5–§8.

---

## 0. TL;DR (one screen)

**Conduit is an iOS "mission control" for AI coding agents (Claude Code, OpenAI Codex, opencode) that run on the developer's own machines or servers.** The phone is not where code is written — it's where you're **notified the instant an agent needs a human decision, approve/deny/edit it in seconds, watch your fleet, see spend, and dispatch/schedule new work.**

The defining mechanism — and the big architectural pivot the owner flagged — is that Conduit is **no longer SSH-only**. A small **resident daemon (`conduitd`) is installed on the developer's host**. It survives SSH disconnects, enforces the developer's **approval policy automatically** (auto-allow safe, auto-deny dangerous, escalate only the ambiguous), records an **audit log**, and queues approvals while the phone is away. On top of that, a **hosted cloud control plane (`push-backend`)** adds Stripe billing, prepaid credits, quotas, schedules, team orgs, and **multi-cloud agent execution** (Fly / GCP Cloud Run / AWS Lightsail) via a real `agent-runner` binary.

So there are **three products fused into one**: (1) a power-user SSH/block terminal, (2) a **self-hosted agent control plane** (privacy/enterprise wedge), and (3) a **hosted cloud agent-execution business** (credits/compute). The current `feat/product-depth-sprint` branch is simultaneously (a) redesigning the UX away from "terminal-first" toward "command-center" (a Next.js prototype with chosen screen variants) and (b) wiring the cloud/fleet/billing layer into the native app.

**The central strategic question** (what the owner wants an agent to weigh in on): the market shifted under this product. **Anthropic Remote Control** and **OpenAI Codex mobile** now ship the core "steer your agent from your phone" use case *first-party and free*. Conduit's defensible lane is narrower than when it started: **"you control the bridge; your code stays on your host"** + cross-vendor + cost-visibility — i.e. the security-conscious/self-host/enterprise segment. Yet the most recent engineering investment is in the *hosted cloud* direction (which competes on the crowded, low-WTP side). **Reconciling those two bets is the decision to make.** See §9.

---

## 1. What Conduit is, and the pivot

### 1.1 One-breath definition
An iOS app for **steering** AI coding agents that run elsewhere (your laptop, your server). The phone gets a notification when an agent needs a decision; you allow/allow-always/edit-then-run/deny; you review what ran autonomously while you were away; you watch a fleet and its cost; you start or schedule new work. (`docs/FRONTEND_DESIGN_BRIEF.md:7-13`)

### 1.2 The pivot the owner flagged: SSH-only → "software on the machine" → hosted cloud
- **Then:** a mobile SSH client that pipes a terminal to a remote host. The phone was a *remote control*; if the SSH session dropped (iOS backgrounding, signal loss), agent context and approval state were lost.
- **Now (pivot #1 — resident daemon):** a **helper program runs on the host** (`conduitd`). It owns approval state and a Unix socket that **outlives any single SSH session**. The phone attaches/detaches; the daemon keeps enforcing policy and queuing approvals in between. The phone became a **decision tool**, not a pipe. (`docs/conduitd-resident.md`, `docs/FRONTEND_DESIGN_BRIEF.md:10`)
- **Now (pivot #2 — hosted cloud):** a **control-plane backend** (`push-backend`) lets Conduit *also* run agents on cloud infra it provisions (Fly/GCP/Lightsail), metered by **prepaid credits** with **Stripe** billing, **quotas**, **schedules**, and **team orgs**. This turns "steer agents on YOUR machine" into "…or on machines we run for you," a different (compute-resale) business.

The product's own framing of the through-line (from the owner's memory): **"a mobile control plane for agent loops, not a notification layer"** — show loop status (step 6/8, blocked on test failure), build *escalation* rules (not just notification rules), and treat *evaluation* (did the loop pass its own test?) as first-class.

---

## 2. Timeline — the eras of development

| Era | Roughly | What landed |
|---|---|---|
| **1. SSH terminal** | pre-2026 | SwiftUI SSH client (Citadel/NIO): TOFU host keys, Ed25519/password auth, GRDB persistence, auto-reconnect (NWPathMonitor + backoff). |
| **2. Block terminal (Warp-style)** | ~May 2026 | iOS 26 / Swift 6.2 migration; unified PTY → `PTYBridge` (OSC 133/7 markers) → `BlockRenderer`; commands render as discrete blocks; alt-screen TUIs (vim/htop/tmux) render *inside* their block; tmux auto-attach/resume. |
| **3. Resident daemon + policy/audit** | May–Jun 2026 | `conduitd` Go daemon installed on host; hook ingest for Claude Code / Codex / opencode; risk scoring; **policy engine (deny→ask→allow, fail-closed default=ask)**; **audit log**; allow-always; blast-radius; offline `queue.json`; InboxView + ApprovalIngest round-trip. |
| **4. Hosted cloud + billing** | May–Jun 2026 | `push-backend` control plane: Stripe checkout/webhooks, prepaid credits + overage, `/usage` metering, quotas, orgs, schedules (cron ticker), artifacts (GCS); multi-runtime dispatch (`ssh-host`/`fly`/`gcp_cloud_run`/`lightsail`) with per-run scoped runner tokens; **`agent-runner` binary**. |
| **5. Product-depth sprint (current)** | Jun 2026 | (a) Next.js/shadcn **UX prototype** re-imagining the app as "command center" — chosen screens **inbox-B / checkpoint-B / loop-A / report-A**, `/final` reference, `/grid`; (b) native Swift wiring of **FleetStore** (multi-slot ≤3), **CreditBalance**, **BillingView**, **PolicyEditorBridgeScreen**, **BridgeSessionActions**, **CloudSync** (CloudKit). |

Git: current branch `feat/product-depth-sprint`; its 13 commits are mostly the prototype (`feat(prototype): …`) plus the uncommitted native-wiring working set (see §4.4).

---

## 3. System architecture — the three layers

```
   ┌──────────────────────────────────────────────────────────────────────┐
   │ iOS app  (Packages/ConduitKit — SwiftUI, 22 SPM targets)             │
   │  • SSH/block terminal   • approval inbox   • fleet/billing   • policy │
   └───────────┬───────────────────────────────┬──────────────────────────┘
               │ SSH stdio (conduitd serve)     │ HTTPS (Bearer)
               ▼                                ▼
   ┌───────────────────────────┐    ┌─────────────────────────────────────┐
   │ conduitd  (Go)            │    │ push-backend  (Go control plane)     │
   │ RESIDENT on dev's machine │    │ • Stripe billing + prepaid credits   │
   │ • policy / audit / queue  │    │ • quotas / orgs / schedules          │
   │ • approval socket         │───▶│ • APNs push  ◀── /approval POST      │
   │ • dispatch + schedules    │    │ • multi-cloud dispatch ──┐           │
   └────────┬──────────────────┘    └──────────────────────────┼──────────┘
            │ unix socket                                       ▼
        agent hooks                                   ┌───────────────────┐
   (claude/codex/opencode                             │ agent-runner (Go) │
    PreToolUse → ~/.conduit/conduitd.sock)            │ on Fly/GCP/AWS VM  │
                                                       └───────────────────┘
```

### 3.1 iOS app — `Packages/ConduitKit/` (SwiftUI, 22 targets)
**Engines (no UIKit/SwiftUI):** `ConduitCore` (core types: Host/Session/Approval/Block + `ConduitDProtocol`, `FleetSlotManager`, `BridgeSessionActions`, `CreditBalance`), `SecurityKit` (Citadel SSH, Keychain, TOFU), `SSHTransport` (`DaemonChannel` JSON-RPC client), `TerminalEngine` (SwiftTerm + block store), `AgentKit` (AI clients + **`HostedAgent`**/`AgentRun`/`AgentSchedule`/quota/entitlement + REST client), `NotificationsKit` (APNs/Live Activity models), `PersistenceKit` (GRDB), `DiffKit`, `SyncKit` (`CloudSync` CloudKit).
**Feature modules (UI):** `AppFeature` (`AppRoot` composition root + `FleetStore`), `SessionFeature` (`SessionViewModel`, live terminal), `InboxFeature` (approvals), `SettingsFeature` (`BillingView`, `PolicyEditorView`/`PolicyEditorBridgeScreen`, `PurchaseManager`), `OnboardingFeature`, `WorkspacesFeature`, `KeysFeature`, `DiffFeature`, `FilesFeature`, `DesignSystem` (tokens + components), `PreviewKit`/`PreviewFeature`.

**Key types** (with file refs):
- `HostedAgent` / `HostedRuntimeKind` (sshHost·fly·gcpCloudRun·lightsail) / `AgentRun` / `HostedQuotaSnapshot` — `AgentKit/HostedAgent.swift`.
- `CreditBalance` (prepaidUSD/overageUSD/allowOverage) — `ConduitCore/CreditBalance.swift`.
- `FleetSlotManager<T>` (≤3 slots, platform-independent) — `ConduitCore/FleetSlotManager.swift`.
- `FleetStore` + `FleetStore.Slot` (MainActor; each slot = SessionVM + DaemonChannel + ApprovalIngest + InboxVM + bridgeStatus) — `AppFeature/FleetStore.swift`.
- `DaemonChannel` (actor; 4-byte length-prefixed JSON-RPC; approve/policy/audit/dispatch/schedule) — `SSHTransport/DaemonChannel.swift`.
- `BridgeSessionActions` (struct of closures; decouples policy/dispatch UI from the live channel) — `ConduitCore/BridgeSessionActions.swift`.
- `AppRoot` / `AppEnvironment` (tabs: hosts·inbox·library·settings; sheets; routes notifications + fleet slots; **debug gallery** via `CONDUIT_GALLERY`) — `AppFeature/AppRoot.swift`.

**Navigation reality:** real tabs are `hosts / inbox / library / settings`, terminal-as-home. Billing and the bridge policy editor are wired into **real** Settings navigation (gated by `showPaidSurfaces` + cloud entitlement / live SSH connection), not gallery-only. The `CONDUIT_GALLERY` env routes render mock UI for visual review (see `CLAUDE.md`).

### 3.2 `conduitd` — the resident daemon (Go, `daemon/conduitd/`)
**Commands** (`main.go`): `daemon` (persistent resident), `serve` (per-SSH attach client, falls back to self-host with a warning), `install` (binary + launchd/systemd unit), `agent-hook` (called by PreToolUse hooks), `version`.

**Resident model** (`resident.go`, `server.go`): `daemon` listens on `~/.conduit/conduitd.sock`. Two connection types by first byte: **hook** (raw JSON `ApprovalEvent`) vs **attach** (`{"op":"attach"}`, then 4-byte length-prefixed JSON-RPC frames). On attach, pending approvals **drain** to the phone; decisions relay back. State survives SSH drops.

**Approval/policy/audit:**
- A hook submits an `ApprovalEvent` (agent, kind, command, cwd, risk, toolName/Id, sessionId, toolInput) → `policyEngine.evaluate()`.
- **Policy** = ranked effects **deny > ask > allow**, default **ask** (fail-closed). Sources: repo-local `<cwd>/.conduit/policy.yaml` (walked up), global `~/.conduit/policy.yaml`, and **`~/.conduit/policy-always.yaml`** override (allow-always). Rule fields: id/effect/agent/tool/kind/match-glob/cwd-glob/min-max-risk (`policy/types.go`).
- `EffectAllow` → audit auto-allow + return; `EffectDeny` → audit auto-deny + return; `EffectAsk` → compute **blast radius** (files, touchesGit, touchesNetwork), enqueue, notify phone, **POST to push-backend `/approval`** (`server.go:532` → `postApprovalPush` `server.go:594-614`), and **block up to 120 s** for a decision (timeout → deny).
- **Audit log** `~/.conduit/audit.log` (JSONL 0600, secret-redacted): `audit.go`.
- **Allow-always now persists**: on `approveAlways`, `appendAllowAlways` writes a rule to `policy-always.yaml` (truncates command prefix, dedupes).

**Fail-closed** (`hook.go`): if the daemon is unreachable, mutating kinds (command/patch/fileWrite/fileDelete/network/credential/browser/callMCP/unknown) **exit 1** (hold); read-only (read/grep/list/search) fail-open only if `CONDUIT_HOOK_READONLY_FAIL_OPEN=1`; critical risk always holds.

**JSON-RPC to the phone** (`server.go`): `ping`, `agent.approval.response`, `agent.audit.tail`, `agent.policy.get/reload/set`, `agent.status` (per-vendor usage), `conduit.device.register` (push backend URL + session), `agent.dispatch` / `agent.cancel`, `agent.schedule.add/list/remove`. Plus an unsolicited `agent.approval.pending` notification.

**State dir** `~/.conduit/` (override `CONDUIT_STATE_DIR`): `conduitd.sock`, `queue.json` (0600), `policy.yaml`, `policy-always.yaml`, `schedules.json`, `audit.log`, `bin/conduitd`. Smoke test: `scripts/validation/resident-bridge-smoke.sh`. Tests: 47 Go test funcs.

### 3.3 `push-backend` — hosted cloud control plane (Go, `daemon/push-backend/`)
**HTTP surface** (`main.go` mux): device push (`/register`, `/approval`, `/run-complete`, `/health`); agents/runs (`/agents` CRUD, `/runs` create/get/list, `/runs/{id}/logs|cancel|control` PATCH, `/runs/{id}/artifacts` + `/download`); **billing** (`/billing/checkout|portal|subscription-status|entitlement|webhook|return`); **credits** (`/billing/credits`); **usage** (`POST /usage` → deduct, `402` if blocked); **quota** (`/billing/quota`); **schedules** (`/agents/{id}/schedules`, `/schedules/{id}` PATCH/DELETE, `/schedules/{id}/trigger`); **orgs** (`/orgs/{id}/members`).

- **Billing/credits:** `CreditBalance{prepaidUSD, overageUSD, allowOverage}` (`credits.go`); `/usage` deducts from prepaid, then overage ledger (if `CREDITS_ALLOW_OVERAGE`), else `402 + X-Credit-Overage`. Stripe wired via `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET`/`STRIPE_PRICE_*`; webhook caches a `subscriptionEntitlement`; **Bearer client tokens** minted server-side (`entitlements.go`), file- or Redis-backed.
- **Runtimes** (`dispatch.go` `RuntimeProvider{Launch,Cancel}`): `ssh-host`→nil (on-device), `gcp_cloud_run`→`gcpCloudRunProvider`, `lightsail`→`lightsailProvider`, `fly`→`flyProvider`, `CONDUIT_LOCAL_RUNNER=1`→`processProvider`. **`handleCreateRun` fires `go dispatchRun()` (`agents.go:315`)** — the dispatch **spine is wired** (mints runner token, builds `RunnerEnv`, calls provider `Launch`, persists handle). Provider depth varies: Fly makes real Machines API calls; GCP records spec + needs a real image; Lightsail bootstraps a VM that downloads the runner.
- **agent-runner** (`daemon/agent-runner/`): the binary cloud VMs run — polls `/runs/{id}/control` for cancel, PATCHes status, appends logs, uploads artifacts, all under its **per-run scoped token** (never the app's bearer).
- **Quotas/orgs/schedules:** `QUOTA_MAX_AGENTS` (20), `QUOTA_MAX_CONCURRENT_RUNS` (5), `QUOTA_DAILY_USD` (100); org scoping via entitlement `OrgId`; cron ticker (`@hourly/@daily/@weekly/every:<sec>`) every minute. **Persistence:** JSON files per store (or Redis for entitlements); optional GCS for artifacts. Tests: 42 Go test funcs (`phase2_phase3_test.go` et al.).

### 3.4 End-to-end flows
- **Approval (the daily heartbeat):** agent PreToolUse hook → `conduitd.sock` → policy eval → if *ask*: blast-radius + queue + phone notify + `push-backend /approval` → APNs → phone decides (`allow|allowAlways|editAndRun|deny`) → relayed back → hook exits 0/1 → agent proceeds/blocks. Offline → queued in `queue.json`, drains on next attach.
- **Hosted run:** app `POST /runs` (Bearer) → run persisted → `go dispatchRun` mints runner token → provider `Launch` on Fly/GCP/Lightsail → `agent-runner` executes, streams logs/artifacts, honors cancel → `/usage` meters cost → credits deducted → `run-complete` push.

---

## 4. Current state — verified 2026-06-11 (✅ works / 🔶 partial / ❌ gap / ⏸ owner-blocked)

### 4.1 Corrections to older in-repo audit docs (important for the advising agent)
`docs/_archive/APP_AUDIT.md`, `docs/_archive/cloud-execution-engine-plan.md`, and `docs/_archive/remaining-work.md` list gaps that are **now closed**. Verified against current source:
- ❌→✅ **"`handleCreateRun` never calls `dispatchRun`"** — it does: `agents.go:315` `go dispatchRun(...)`.
- ❌→✅ **"`.approvedAlways` collapsed to `approve` in `DaemonChannel.swift`; rule never persisted"** — `DaemonChannel.swift:111` sends `"approveAlways"`; conduitd `appendAllowAlways` writes it to `policy-always.yaml`.
- ❌→✅ **"conduitd never POSTs approvals to push-backend (APNs loop open)"** — `server.go:532-533` `go s.postApprovalPush()` → `{PushBackendURL}/approval` (`server.go:613`). (APNs key + paid account + deployed backend all exist now; only a real-device delivery smoke test remains — see §10/§11.)
- ❌→✅ **"no agent-runner binary"** — `daemon/agent-runner/` exists.
- 🔶→✅ **"single session only; no FleetStore backing"** — `FleetStore` + `FleetSlotManager` exist (≤3 slots) on this branch (still being wired into AppRoot — see §4.4).
- ✅ **Ship-gate external deps mostly met** — `project.yml:74-80` uses `Conduit.entitlements` with `aps-environment: production` + iCloud/CloudKit; paid account (team `39HM2X8GS6`), APNs `.p8` (`L8LVU9X82W`), and a live push-backend (`/health` 200) all exist. Remaining gate is **App Store Connect setup + TestFlight**, not obtaining account/key/backend (see `ship-gate-owner-steps.md`).

### 4.2 Works today (✅)
SSH + TOFU auth (password/Ed25519); block terminal + raw PTY + alt-screen TUIs; auto-reconnect + tmux resume; GRDB persistence; ANSI rendering; `DaemonChannel` JSON-RPC; SFTP browser; diff reviewer; snippets (full CRUD); Watch app / Live Activity / widgets scaffolding; biometric gate + audit redaction; **conduitd**: policy engine, audit log, allow-always persistence, blast radius, offline queue, fail-closed, dispatch + schedules, push POST; **push-backend**: Stripe billing + credits + overage + `402`, quotas, orgs, schedules + cron ticker, artifacts, run-logs, **dispatch spine + runner-token auth**; StoreKit IAP ($14.99 lifetime).

### 4.3 Partial / stubbed (🔶)
- **Cloud provider depth:** Fly real; **GCP Cloud Run** records spec but needs a real container image to actually launch; **Lightsail** accepted, bootstrap path exists. Managed-compute key-injection (`FlyProvisioner.swift`) still has a TODO.
- **Structured tool_use richness:** the hook still flattens some tool input; full structured `toolName`/`toolUseID`/typed `input` end-to-end (for richer approval cards + reliable edit-before-run) is the Stage-3 "approval spine" (`ROADMAP.md` 2.1a/b).
- **Org/team:** invite/list only (no email delivery).
- **Native fleet/billing UI:** types + screens exist; final AppRoot wiring + multi-slot UX is in progress on this branch.

### 4.4 In-flight working set on `feat/product-depth-sprint` (uncommitted)
Modified: `Package.swift`, `AppRoot.swift`, `FleetStore.swift`, `ConduitDProtocol.swift`, `FleetSlotManager.swift`, `DaemonChannel.swift`, `BillingView.swift`, `PolicyEditorView.swift`, `SettingsView.swift`, `CloudSync.swift`, `HostedAgent.swift`, `HostedAgentPhase2Tests.swift`, `daemon/conduitd/server.go`, several docs. New (untracked): `BridgeSessionActions.swift`, `CreditBalance.swift`, `PolicyEditorBridgeScreen.swift`, `docs/FRONTEND_DESIGN_BRIEF.md`, `docs/PRODUCTION_READINESS_PLAN.md`, `docs/conduit-brief/`, `scripts/validation/resident-bridge-smoke.sh`. **Interpretation:** native wiring of cloud/fleet/billing/policy-bridge, alongside the committed UX prototype.

### 4.5 Tests
51 Swift test files (~327 tests per project docs; Swift Testing `@Test` style). Go: 47 conduitd + 42 push-backend test funcs. CI intent (`PRODUCTION_READINESS_PLAN.md`): `swift build && swift test`, `go build/test ./...` for each daemon, `xcodegen generate`, semgrep, zero new Swift 6 concurrency warnings. **Note:** the full Xcode app scheme historically embeds a watchOS app whose runtime may be missing in CI — build the iOS app target, not the full scheme, if that bites.

---

## 5. Product vision & UX direction

### 5.1 The mental model the UI must teach (`FRONTEND_DESIGN_BRIEF.md §3`)
Four concepts: **Agents** (vendor·model·cwd·status), **the Bridge** (`conduitd`: connected vs running-without-you), **Approvals** (allow / allow-always / edit-then-run / deny), **Policy** (the rules that mean *most things never reach the human*). Emotional target: **calm confidence** — "I'm in control precisely because I'm not asked about everything." Context of use: **interrupt-driven, one-handed, glancing**, occasionally deep-focus.

### 5.2 Jobs-to-be-done, ranked (`§4`)
1. **"An agent needs me — decide fast."** (the #1 flow, many times/day) 2. "What happened while I was away?" (autonomous-decision audit) 3. "How are my agents / what are they costing?" (fleet + cross-vendor spend) 4. "Start/schedule a task." 5. "Set the rules." (policy) 6. "Get set up." (install bridge, pair, choose caution) 7. "Go deep." (power-user terminal/diff/SFTP/preview).

### 5.3 The 11 surfaces (`§5`)
Decision/approval; the inbox queue; the **while-you-were-away activity feed** (trust surface + enterprise selling point); the **agents/fleet + usage** view ("usage & cost across every vendor in one place" = most-requested feature); start-task/dispatch+schedule; agent detail/run history; **policy editor** (global + per-repo, presets, default=ask); hosts & connection (bridge install/pair/trust); onboarding (the "aha" = auto-detect running agents + today's spend); the **terminal power-user surface** (demoted to depth); settings.

### 5.4 The prototype and chosen design (current branch)
`docs/conduit-ui-prototype/` — **Next.js 16 + React 19 + shadcn/ui + Tailwind 4**, rendered in 390×844 iPhone frames, dark Geist palette. Routes: `/` (variant selector), `/final` (chosen reference), `/grid` (all variants), and A/B/C variants per screen. **Chosen variants** (commit `1c718c84`): **inbox-B** (compact cards), **checkpoint-B** (bottom sheet over inbox context), **loop-A** (timeline of steps with progress), **report-A** (audit-style proof card: goal, diff, files, commands, tests, risks). **It is a design reference, not a shipping app** — the handoff target is SwiftUI ("Plan 2"). It does **not** connect to the backend or bridge.

### 5.5 Information-architecture shift — ✅ SHIPPED (2026-06)
The IA restructure is **done**. The earlier `hosts/inbox/library/settings` terminal-first IA has been replaced by the four shipped tabs **Inbox / Fleet / Activity / Settings** (`AppFeature/AppRoot.swift` `enum Tab { case inbox; case fleet; case activity; case settings }`). Approvals (Inbox), the agent fleet (Fleet), and history (Activity) are the everyday top level; the **chat-based session/terminal surface is now the *deep* surface** reached by depth from Fleet/Inbox — not a top-level tab.

---

## 6. Business model & pricing (`ROADMAP.md §4`, `PRODUCT_RESEARCH.md §5`)
- **Fixed decision:** **do NOT build the business on consumer recurring revenue.** Consumer willingness-to-pay looks ~zero (see Omnara, §7.3).
- **Consumer tier:** free app + a **$14.99 lifetime IAP** (already in StoreKit) — top-of-funnel only.
- **Paying tier:** **enterprise / self-host** — team seats + on-prem bridge + SLA. Precedent for real WTP: Termius $10/mo, Blink $20/yr (transport-grade tooling). Compliance-driven buyers pay.
- **Tension (note for advisor):** the hosted-cloud build (prepaid credits, Stripe metering, multi-cloud execution) implies a **usage/compute-resale** revenue model that the roadmap doc does *not* endorse. The code and the written strategy point in different monetization directions. See §9.

---

## 7. Market & competitive landscape (`PRODUCT_RESEARCH.md`)
> Confidence tags are the doc's own (HIGH/MED). Data is dated ~2026-06-04 — **re-verify before citing** (today 2026-06-11). Don't treat any star count or pricing as current without a fresh check.

### 7.1 Demand signals (HIGH unless noted)
"Phones are where software is **steered**, not written." Pieter Levels publicly SSH-ing into a VPS to run Claude Code from Termius popularized the use case (x.com/levelsio, ~Aug 2025). Verified pain points: session loss on backgrounding; **approval fatigue** (rubber-stamping every tool call); decision fatigue; "tmux on touch is miserable"; **notifications that lack context / don't fire** (the single most-repeated complaint, MED).

### 7.2 Competitors (snapshot — re-verify)
| Product | Scale (as of doc) | Model | Note |
|---|---|---|---|
| **Happy** | 21.6k★ | MIT, native iOS, E2E | thin client — approve every action, raw JSON. Trust via OSS. |
| **cmux** | 20.9k★ | macOS orchestrator + iOS | feed-style approval cards. |
| **CloudCLI / claudecodeui** | 11.6k★ | cross-vendor, self-host/Docker/managed | web UI. |
| **Omnara** (YC S25) | native iOS | pricing **$9→$20→free** | routes sessions through their cloud; pricing collapse = WTP signal. |
| **Anthropic Remote Control** | first-party | free for Pro+/Team/Enterprise | up to 32 concurrent sessions, push, Dispatch, Channels. **Direct competitor.** |
| **OpenAI Codex mobile** | first-party | all plans incl. free | approve commands, streams diffs/tests/screenshots, Remote SSH GA. |
| Cursor / GitHub Copilot cloud agents | announced | mobile companions | MED confidence. |
| **Termius / Blink** | incumbents | $10/mo / $20/yr | dumb terminals, no agent semantics. |
| OSS long tail | — | — | Paseo, Companion, Happier, Catnip, Sled, CC Pocket… |

Combined OSS stars (Happy+cmux+CloudCLI) ≈ **54k** — a strong "free and trusted" headwind.

### 7.3 Disconfirming evidence / threats (HIGH)
1. **First-party Anthropic Remote Control** now does multi-session + push + dispatch, free — exactly Conduit's core use case, for anyone already paying for Claude. 2. **OSS field is crowded and free.** 3. **Consumer WTP ≈ 0** (Omnara arc). 4. **"Better free Claude Code client" is a lost lane.** 5. **Cross-vendor alone is table-stakes, not a moat** (CloudCLI etc. already multi-vendor).

### 7.4 The re-aimed strategy the docs land on
**Positioning:** *"The secure, native, cross-vendor cockpit for steering AI agents — for developers/teams who can't or won't route their code through someone else's cloud."* **Beachhead:** security-conscious / enterprise / regulated developers (the one segment with WTP and the one Anthropic Remote Control structurally **can't** serve — it routes code through Anthropic infra). **Anti-lock-in tagline that first-party can't undercut:** **"You control the bridge. Your code stays on your host."** **Biggest risk = distribution** (best-built, least-known); **mitigation = open-source `conduitd`** (low-IP plumbing, high-trust; Happy/CloudCLI earned 11–21k★ that way).

---

## 8. Roadmap & invariants

### 8.1 Fixed decisions (`ROADMAP.md §1`)
SSH-only near-term (WS relay deferred); pure-Go hooks near-term (Node Agent-SDK `canUseTool` bridge deferred); freemium funnel + enterprise/self-host as the paying tier; slice order re-aimed to market data.

### 8.2 Staged plan (`ROADMAP.md §2`)
- **0+1** docs + ship-gate + validation foundation — *largely done in code; external blockers remain.*
- **2** reliability + native notifications (the #1 differentiator: close APNs loop end-to-end, token routing, Live Activity/DI/Watch, notification filtering).
- **3** the **approval spine**: structured tool_use wire protocol + real allow-always + edit-before-run.
- **4** multi-agent **fleet** (FleetStore N slots, jump-to-unread, fleet-wide inbox).
- **5** security / self-host + **open-source `conduitd`** + enterprise pricing.
- **6** cross-vendor breadth (Codex → Cursor/Gemini).

### 8.3 Architecture invariants — must NOT regress (`docs/agent-contract.md`, `CLAUDE.md`)
- **Module discipline:** engines hold zero UIKit/SwiftUI; features never depend on each other (route through `AppFeature`).
- **Platform:** iOS 26 / Swift 6.2, strict concurrency, **zero new concurrency warnings**.
- **Glass chrome:** all translucent surfaces via `View.conduitGlassChrome(...)` (single source).
- **Terminal:** the **unified PTY is the single byte source** — never spawn a second SSHShell for raw mode; OSC 133/7 markers (not heuristics) drive block↔alt-screen; PTYBridge strips OSC before block mode; belt-and-suspenders TUI escalation fires only for `.submitted` blocks, never an idle prompt; connect-time commands wait on `unifiedIntegrationReady`.
- **Security:** TOFU via HostKeyStore; keys in Keychain + BiometricGate; **production paths keep the TOFU prompt** (only debug harnesses auto-trust); secrets never logged; audit redaction holds; **fail-closed** autonomy default.
- **Testing:** engines unit-tested with no network/Keychain/real-host deps.

---

## 9. Strategic tensions & open questions (the heart of what to advise on)

These are unresolved forks where the **code and the written strategy diverge**, or where the **market has shifted under the plan**. An advising agent should weigh in here:

1. **Self-host control plane vs. hosted-cloud business.** The *strategy docs* say the moat is "your code never leaves your host" + open-source the bridge, beachhead enterprise/compliance. The *recent code* invests heavily in the opposite: we **run** the agents on **our** provisioned cloud, metered by prepaid credits — which competes on the crowded, low-WTP, "routes through someone's cloud" side that the strategy says to avoid (and that Omnara already retreated from). **Which is the lead bet?** Can both coexist without diluting the positioning, or does hosted-cloud undercut the "your host" story?
2. **Defensibility vs. first-party.** Anthropic Remote Control + Codex mobile now own the consumer "steer my agent" job, free. Is the **cross-vendor + self-host + cost-visibility** triad enough of a wedge in 2026, or has the window narrowed? What is the *single* claim a buyer can't get first-party?
3. **Ship now vs. build depth.** Ship-gate is one paid-Apple-account + live-host validation away from submittable (§11). The current sprint instead expands scope (UX redesign + cloud/fleet/billing). **Submit the focused enterprise/self-host MVP now, or keep building?**
4. **The "loop control plane" framing.** The owner's memory frames Conduit as *the mobile surface for agent loops* (loop status, escalation rules, eval-as-first-class, loop-template marketplace). The current prototype encodes some of this (loop-A timeline, report-A proof card) but the backend has no first-class "loop" object or `conduit_loop_start`/`conduit_step_complete` MCP tools yet. **Is "loop engineering" the headline, and should the data model add a Loop primitive?**
5. **Pricing model coherence.** Lifetime $14.99 IAP + enterprise seats (roadmap) vs. prepaid usage credits (code). **Pick the revenue architecture.**
6. **IA reset.** The brief says restructure away from terminal-first. **What is the new top-level IA** (e.g. Inbox / Fleet / Activity / Settings, terminal as depth)?
7. **Open-sourcing `conduitd`.** Highest-leverage distribution move per the roadmap, but it exposes the policy/bridge plumbing. **When, and with what license/boundary** (bridge OSS, app proprietary)?

---

## 10. Ship-gate / owner action items (external blockers)
(`docs/ship-gate-owner-steps.md`, `docs/_archive/remaining-work.md`, `PRODUCTION_READINESS_PLAN.md`)
1. ✅ **Paid Apple Developer account** (team `39HM2X8GS6`) + **APNs `.p8`** (`L8LVU9X82W`, at `~/Downloads/Personal-Docs/`) — both confirmed present. No longer a blocker.
2. ⏸ **App Store Connect setup** (app record, enable Push + CloudKit, IAP, privacy nutrition label, screenshots) — the main remaining gate.
3. ⏸ **Live-host validation** — full hook→policy→inbox→approve→audit round-trip + TUI/Ctrl-C/alt-screen/OSC-133 on a real SSH host (`docs/validation-playbook.md` TC-1..TC-7), plus a physical-device APNs smoke test.
4. 🔶 **Backend deploy** — `push-backend` is **live** (`https://35.201.3.231.sslip.io/health` 200). Remaining: confirm APNs + live Stripe secrets are set on the running instance, then repoint to a vanity domain (`push.conduit.dev`) before public release (`push-backend-deploy-env.md`, `docs/cloud-run-production-cutover.md`).
5. **DNS** for conduit.dev (`scripts/update-dns.sh`).
6. **TestFlight/release** via existing `fastlane/` lanes once creds exist.

---

## 11. Glossary (use these exact objects in any design/spec)
**Agent** = a coding tool (claudeCode|codex|opencode) on a host (vendor·name·model·cwd·status·spendToday). **Bridge** = `conduitd` on the host (states: notInstalled|installed|running|attached). **Approval** = actionKind (command|patch|fileWrite|fileDelete|network|credential|browser) + content + risk (low|med|high|critical) + blastRadius (files[]·touchesGit·touchesNetwork) + matchedRule → decision (allow|allowAlways|editAndRun|deny). **Policy rule** = effect (allow|ask|deny) + matchers (agent·tool·kind·glob·risk band); global + per-repo; unmatched ⇒ ask. **Audit entry** = ts·action·agent·kind·command·effect·rule. **Run** = status (running|succeeded|failed|cancelled)·logLines·exitCode·duration·artifacts. **Schedule** = agent·cwd·prompt·interval·budget·last/next. **Credits** = prepaidUSD·overageUSD·allowOverage. **Slot/Fleet** = up to 3 concurrent sessions, each its own bridge channel + inbox.

---

## 12. Appendix

### 12.1 Where things live
- iOS: `Packages/ConduitKit/Sources/{AppFeature,ConduitCore,SSHTransport,AgentKit,SettingsFeature,SyncKit,SessionFeature,InboxFeature,DesignSystem,…}`; tests `Packages/ConduitKit/Tests/ConduitKitTests/`.
- Daemons: `daemon/conduitd/` (resident), `daemon/push-backend/` (control plane), `daemon/agent-runner/` (cloud runner).
- Hooks: `docs/conduit-hook.sh` (Claude), `docs/codex-conduit-hook.sh`, `docs/opencode-conduit-hook.sh`.
- UX prototype: `docs/conduit-ui-prototype/` (Next.js). Sales brief: `docs/conduit-brief/index.html`.
- Build/run: `CLAUDE.md` (MCP tooling, gallery routes, live block-session harness), `project.yml` (xcodegen).

### 12.2 Doc index (read order for a new agent)
**Strategy/current:** `FRONTEND_DESIGN_BRIEF.md`, `PRODUCT_RESEARCH.md`, `ROADMAP.md`, `PRODUCTION_READINESS_PLAN.md`, this dossier. **Architecture:** `agent-contract.md`, `block-terminal-implementation.md`, `conduitd-resident.md`, `hosted-agents-phase2.md`, `docs/_archive/cloud-execution-engine-plan.md` (treat its "missing" list as partly **stale** per §4.1). **Ops:** `ship-gate-owner-steps.md`, `resident-daemon-owner-steps.md`, `validation-playbook.md`, `cloud-run-production-cutover.md`. **Caveat:** `docs/_archive/APP_AUDIT.md` + `docs/_archive/current-state-audit.md` are point-in-time and **partly superseded** by §4.

### 12.3 Competitor deep-research brief (concrete, verifiable questions for the advising agent)
Re-verify each with a primary source dated **after 2026-06-04**:
1. **Anthropic Remote Control** — current plan gating (still free for Pro+? max concurrent sessions?), does it support **self-hosted/BYO-infra execution** or only Anthropic-hosted? Any enterprise/compliance (SOC2, on-prem, audit) story? (code.claude.com/docs/en/remote-control)
2. **OpenAI Codex mobile** — does Remote SSH let code stay on the user's host, or is execution OpenAI-cloud? Cross-vendor? Approval-policy depth? (developers.openai.com/codex)
3. **Happy / cmux / CloudCLI** — current ★, release cadence, do any add **policy-based auto-approval** (vs manual tap-by-tap)? Native iOS quality (Live Activity/Watch)? E2E/self-host claims? Monetization, if any.
4. **WTP evidence** — any agent-mobile product sustaining *paid* revenue (not free)? Enterprise/compliance buyers paying for agent governance/audit? Pricing of adjacent "agent control/observability" tools.
5. **The compliance wedge** — who sells "AI coding agent governance / audit / policy" to regulated orgs? Is "code never leaves your host" a stated buying criterion anywhere citable?
6. **Loop/agent-ops framing** — does any competitor expose **loop status / step progress / eval-as-gate** (the owner's "control plane for loops" thesis), or is that white space?
7. **Distribution** — how did Happy/CloudCLI actually acquire users (HN, OSS, Show HN, Reddit)? What worked?

---
*End of dossier. Maintained as the single source of truth for "what Conduit is and where it stands." When a §4 gap closes or a strategic fork (§9) is decided, update here first.*
