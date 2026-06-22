# Hosted Agents Overhaul — Design Spec

**Date:** 2026-06-03
**Branch:** `feat/hosted-agents-rc`
**Status:** Approved direction (phased), pending spec review

## 1. Problem

The hosted-agent experience (Lancer Cloud) is high-friction, hard to find, and
leaks plumbing as UX:

- **Create flow** (`CreateAgentSheet`) is a raw SwiftUI `Form` — visually
  inconsistent with the app — asking five technical fields: Name, free-text
  model slug (`anthropic/claude-sonnet-4`), runtime (`SSH host`/`Fly.io`/`GCP
  Cloud Run`), free-text **Host ID**, free-text **command** (`claude`).
- **Discoverability:** agents live only at Library → Agents. The Hosts page —
  the natural home — doesn't surface them.
- **Navigation bug (fixed in this branch):** `AgentDetailView` and
  `AgentRunDetailView` rendered `DSDetailHeader` with no `onBack` while setting
  `.navigationBarHidden(true)` → no way back → app restart required.
- **No codebase concept:** an agent is `{model, runtime, command}` with nothing
  to work on — no repo, working dir, or secrets.
- **Billing/limits invisible:** metering, credits, and quota exist in the data
  layer but aren't surfaced or enforced in the UI.

## 2. Goals / Non-goals

**Goals**
- Make agent creation a ~2-tap, frictionless flow that exposes *decisions*, not
  plumbing.
- Surface agents on the Hosts page.
- Give agents a real working surface (chat-of-blocks) and a codebase to act on.
- Surface usage, credits, and rate limits, and gate at the limit (upgrade / buy
  credits), Claude-style.
- Consistent back navigation everywhere.

**Non-goals**
- Re-architecting the push-backend control plane (we define the *contract* it
  must satisfy; backend work is tracked separately).
- Building a bespoke chat-bubble UI (we reuse the existing block transcript).
- Native multi-provider model integrations (OpenRouter remains the model layer).

## 3. Architecture decisions

### 3.1 Two orthogonal choices, each presented simply
An agent is the composition of **where it runs** (compute) and **its brain**
(model). The redesign presents each as one curated choice and hides the rest.

- **Compute / runtime ("a VM of their choice"):**
  - **Lancer Cloud** (managed sandbox, zero-setup, metered) — default.
    Power-user disclosure: region / size. Backend chooses Fly vs GCP internally;
    `HostedRuntimeKind.fly`/`.gcpCloudRun` become an internal detail, not a
    user-facing toggle.
  - **My SSH host** (BYO, free) — chosen from saved hosts via a real picker, not
    a typed Host ID.
- **Model / brain → OpenRouter.** Single integration → any model, unified
  metering/billing (already wired: `UsageRecord` → `/usage` → `/billing/credits`).
  UX: **smart default per agent + curated picker** (Claude, GPT, Gemini, top
  coders), not a free-text slug. The managed OpenRouter sub-key
  (`CloudEntitlement.openRouterAPIKey`) is the credential; BYO-host users may use
  their own key.

### 3.2 Agent presets
The "command" is replaced by an **agent type** preset that sets command + a
sensible default model:
- **Claude Code** (`claude`, default Anthropic Claude Sonnet) — primary
- **Codex** (`codex`, default OpenAI) — secondary
- **Custom command** — advanced escape hatch (free-text command + model)

### 3.3 Billing model (Claude-style hybrid)
Market standard in 2026 (Claude included) is two layers, both of which we already
have primitives for:
- **Subscription plan = allowance + rate limits.** Lancer Cloud (Stripe
  `hasCloudEntitlement`). Quota via `HostedQuotaSnapshot`
  (agents/runs/concurrency/daily-USD).
- **Prepaid credits for overage.** `CreditBalance` (prepaidUSD / overageUSD /
  allowOverage). Buy more (min purchase), optional auto-reload, draws down with
  metered usage.
- **At the limit:** a wall offering *upgrade plan* or *buy credits*. Rate-limit
  feedback surfaced inline.

References: Claude usage/length limits and Max plan (5-hour windows + weekly
caps); Anthropic prepaid credits with auto-reload and spend-scaled tiers; Cursor/
Codex/Devin all run sandboxed cloud machines.

### 3.4 Work surface = block UI as chat
Reuse `BlockRenderer` → `ChatTranscriptView`/`ToolCardView` (already a
Warp-style "chat of commands + tool cards") as the agent run surface: a
compose/prompt bar at the bottom, streaming command/tool/diff blocks, inline
approvals (existing Inbox approval flow). No separate chat UI; no full terminal.

### 3.5 File navigation
Reuse `FilesFeature` (SFTP browser). BYO host: works today. Cloud sandbox: the
control plane must expose SFTP/exec into the container; the same UI is reused.

## 4. Phased plan

### Phase 1 — Foundation & friction
**Outcome:** creating and finding agents is effortless; billing is visible.

1. **Create flow redesign** — replace `CreateAgentSheet`'s `Form` with a
   design-system sheet (`DSDetailHeader` + cards), structured as:
   - Agent type cards (Claude Code / Codex / Custom).
   - Runtime: segmented **Lancer Cloud** / **My SSH host**; Cloud → optional
     region/size disclosure; host → `Host` picker bound to `hostRepo`.
   - Model: smart default chip + "Change model" → curated `ModelPicker`
     (OpenRouter-backed list; Phase-1 list can be static-curated).
   - Name: auto-defaulted (PixelAvatar-style seed), editable.
   - Primary "Create agent" CTA + haptics; entitlement-gated with paywall/credits
     wall when not entitled.
2. **Hosts placement** — add a `Connections / Agents` `DSSegmentedPicker` to
   `HostsView`'s header. "Agents" lists agents (reusing `AgentStore`) with a
   create entry. Library's Agents card stays as a secondary entry (kept, not
   removed, to avoid breaking existing nav).
3. **Back navigation** — `onBack`/`dismiss` on `AgentDetailView` and
   `AgentRunDetailView` (done in this branch).
4. **Usage/credits surfacing** — a usage meter strip (today's spend vs daily
   limit, credits remaining) on the Agents surface and in `BillingView`; a
   reusable `UsageMeter` component. Limit → `HostedLimitWall` (upgrade / buy
   credits).

**Files (Phase 1):**
- Modify: `AppFeature/AgentsView.swift` (rewrite `CreateAgentSheet`; nav done),
  `AppFeature/HostsView.swift` (segment), `AppFeature/AppRoot.swift` (wiring),
  `SettingsFeature/BillingView.swift` (credits/buy surfacing).
- Create: `AppFeature/Agents/AgentCreateSheet.swift` (new DS-based flow),
  `AppFeature/Agents/AgentTypePreset.swift`, `DesignSystem/.../UsageMeter.swift`,
  `AppFeature/Agents/HostedLimitWall.swift`, `AppFeature/Agents/ModelPicker.swift`.
- Model: extend `HostedAgent` with `agentType`/`region` (additive, optional,
  back-compat) and a `HostedModelCatalog` (curated list).

### Phase 2 — The work surface
**Outcome:** you give an agent a task and watch it work.

- Agent run view = block-as-chat: embed `ChatTranscriptView` driven by a
  `BlockRenderer` fed from run log/stream; bottom compose bar posts a
  prompt/turn; inline approvals via existing approval components.
- Stream run output (control-plane SSE/poll → `BlockRenderer.append`); map
  `RunApproval` to the block approval card.
- Reuse `FilesFeature` SFTP browser from the run surface (toolbar entry).
- Backend contract: run log streaming endpoint; exec/SFTP into cloud sandbox.

**Files:** new `AppFeature/Agents/AgentRunChatView.swift`; adapt `AgentStore`
run streaming; reuse `SessionFeature/Chat/*`, `FilesFeature`.

### Phase 3 — Codebase
**Outcome:** agents act on a real repo and you review the diff.

- **Workspace** concept: attach a git repo (clone URL + branch) or a host dir;
  secrets/env injected into the sandbox.
- **Diff/PR review:** view agent changes via `DiffFeature`; push branch / open PR.
- Data model: `AgentWorkspace { repoURL, branch, dir, secretsRef }`; control-plane
  endpoints for workspace provisioning + diff retrieval.

**Files:** new `AgentKit/AgentWorkspace.swift`, `AppFeature/Agents/WorkspaceSetup*`,
diff review reusing `DiffFeature`; `AgentStore` workspace methods.

## 5. Data model changes

Additive and back-compatible (decode defaults so existing agents keep working):

```
HostedAgent (extend):
  + agentType: AgentTypePreset = .claudeCode   // derives command + default model
  + region: String?                            // cloud only
  (model/command remain; preset populates them)

new HostedModelCatalog: curated [ModelOption{ slug, displayName, provider, recommendedFor }]
new AgentTypePreset enum: claudeCode | codex | custom { command, defaultModel, displayName, icon }
Phase 3:
new AgentWorkspace { repoURL: URL?, branch: String?, dir: String?, secretsRef: String? }
```

`HostedRuntimeKind` keeps `fly`/`gcpCloudRun` for backend mapping but the UI only
exposes Cloud vs SSH host; the create flow maps Cloud → backend-chosen runtime.

## 6. Control-plane contract (backend, tracked separately)

The app assumes these from push-backend (some exist):
- Agents/runs/usage/credits/quota/schedules/artifacts (exist).
- Phase 2: run **log streaming** (SSE or poll) and **exec/SFTP** into cloud
  sandbox.
- Phase 3: **workspace provisioning** (git clone/branch, secrets) and **diff**
  retrieval / PR creation.
- Cloud runtime selection (Fly vs GCP) and region handled server-side from
  `runtime=cloud` + optional `region`.

## 7. Billing / credits / rate-limit UX

- `UsageMeter`: today's spend vs `dailyUsageLimitUSD`, credits remaining, subtle
  warn/danger tones near limits.
- `HostedLimitWall`: shown when a run is blocked by quota/credits — two CTAs:
  **Upgrade plan** (Stripe, via existing eligibility/links) and **Buy credits**
  (prepaid top-up; auto-reload toggle later).
- Run start (`AgentStore.startRun`) checks quota/credits and throws a typed
  `quotaExceeded` / `outOfCredits` error → wall instead of a silent failure.

## 8. Error handling & security

- Typed errors surfaced (no silent catches on user-facing paths); metering stays
  best-effort/non-blocking.
- Secret redaction reused (`AgentKit/Redactor`) in run logs.
- SSH host runtime keeps TOFU host-key prompts (debug harness auto-trust stays
  debug-only). Cloud secrets stored server-side, never logged.
- Entitlement gating preserved (`hasCloudEntitlement`); debug bypass stays
  `#if DEBUG`.

## 9. Testing

- Unit: `AgentTypePreset` → command/model derivation; create-flow VM validation;
  `HostedModelCatalog` defaults; quota/credit gating logic; DTO mapping for any
  new fields (back-compat decode).
- Snapshot/visual: new create sheet (light/dark), Hosts segment, UsageMeter,
  LimitWall, run chat surface — verified in simulator per CLAUDE.md.
- Regression: existing 276 tests stay green; full Xcode app build each phase.

## 10. Open questions / risks

- **Backend readiness:** Phases 2–3 depend on control-plane endpoints (streaming,
  exec/SFTP, workspace, diff). App work can proceed against the `#if DEBUG`
  in-memory store and a defined contract, but end-to-end needs backend.
- **OpenRouter model list:** Phase 1 uses a static curated catalog; a live
  `/models` fetch can come later.
- **Plan tiers:** exact plan names/prices/limits (Pro/Max-equivalent) are a
  product decision; spec assumes "Lancer Cloud subscription + prepaid credits."
- **Cloud SFTP:** reusing `FilesFeature` for cloud sandboxes assumes the backend
  exposes SFTP/exec; otherwise file nav is SSH-host-only until then.
```
```

## 11. Immediate (already in this branch)
- Back navigation fix on `AgentDetailView` / `AgentRunDetailView`.
- "Use hosted runtime" opens the Agents surface (prior commit).
