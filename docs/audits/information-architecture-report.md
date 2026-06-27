# Phase 5 — Information Architecture Report

> Current hierarchy vs a proposed simplified one. Structural recommendations only (no visual redesign).
> Evidence: AppRoot.swift nav model, screen-inventory.md, screenshots.

## Current hierarchy (as built)

```
Lancer (iOS)
├── Onboarding (first run, AppStorage-gated)
│   ├── Account entry (Supabase)
│   ├── Value hero
│   ├── Pair bridge (6-digit / QR)
│   ├── Policy preset
│   └── SSH setup (optional)
│   └── [legacy 7-step OnboardingView — gallery only]
│
├── Sidebar drawer (primary nav)
│   ├── Home (.home)                 ← dashboard: attention, machines, recent, observed sessions, relay
│   ├── New Chat (.newChat)          ← dispatch composer
│   ├── Recent threads → Thread (.thread)
│   ├── Inbox / Needs Attention (.needsAttention)
│   ├── Machines (.machines)         ← Fleet
│   │     ├── Machine detail → SSH Session (fullScreenCover)
│   │     ├── Quota guard / usage
│   │     ├── Drift findings
│   │     └── Relay file browser
│   ├── Archived → Chat archive
│   └── Settings (.settings)
│         ├── Trust & privacy → (E2E relay pairing, Device management)
│         ├── Autonomy level
│         ├── Appearance / Accent
│         ├── Provider keys
│         ├── Notifications
│         ├── Terminal settings
│         ├── SSH keys  ⟷ (duplicate) Keys/KeyImport
│         ├── Policy editor / Policy simulator
│         ├── Audit  ⟷ (duplicate) Inbox→Activity
│         ├── Secrets
│         ├── Shortcut bar editor
│         ├── Doctor
│         ├── Sync status
│         └── Billing → Paywall ⟷ Premium comparison
│
├── Global actions
│   ├── New Chat (+)
│   └── Add machine (relay vs SSH) → Add host / Host editor
│
├── Sheets/modals (AppDrawerRoute)
│   └── addMachine, relayPairing, addHost, editHost, activity
│
└── Orphaned / not in nav (code present)
    ├── Hosted-cloud: Provisioning, RunnerStatus, RunnerSetup, SelfHostVsHosted, ProviderDetail
    ├── Loops: LoopDetail
    ├── Worktrees: Board, New, Conflicts
    ├── Files (SFTP)
    └── Agent-detail sprawl: RunDetail, AgentDetail, AgentRunDetail, AgentExec, AgentFiles, AgentOrg, AgentWorkspace, Agents
```

## Problems

| # | Problem | Evidence | Severity |
|---|---|---|---|
| IA-1 | **Duplicate surfaces.** Keys (KeysView) vs SSH keys (SSHKeysView); Audit (Settings) vs Activity (Inbox); Paywall vs Premium comparison; BridgeAuditFeed vs ActivityView. | screen-inventory §7/§8 | High |
| IA-2 | **Agent-detail sprawl.** 8 near-duplicate agent/run detail views. | inventory §9 | High |
| IA-3 | **Settings overload.** ~20 sub-screens, many one-action (Appearance no-ops on fixed-dark; Sync status; Shortcut bar). | inventory §7 | High |
| IA-4 | **Orphaned destinations in build** (hosted-cloud, loops, worktrees, SFTP) inflate surface, risk dead links. | feature-matrix §G/H | Medium (defer) |
| IA-5 | **Two onboarding flows** coexist (legacy + redesign). | inventory ON-L | Medium |
| IA-6 | **Home vs Inbox overlap.** Home surfaces "2 conversations blocked" AND Inbox is the approvals system-of-record — two entry points to the same attention queue. | home.png, inbox | Medium |
| IA-7 | **Policy lives in 3 places:** onboarding preset, Settings→Autonomy, Settings→Policy editor/simulator. | inventory | Medium |
| IA-8 | **Power-user depth mixed with core.** SSH terminal, YAML policy editor, secrets broker sit beside the core approve loop with equal prominence. | nav model | Medium |

## Proposed simplified hierarchy (V1)

```
Lancer
├── Onboarding (3 screens max — see onboarding-audit.md)
│
├── Home (.home)              ← single attention surface: "needs you" + machines + recent
│   └── (Inbox folds in here OR becomes a filtered view of Home, not a separate root)
│
├── New Chat (.newChat) → Thread (.thread)   ← the core dispatch/approve/continue loop
│
├── Machines (.machines)      ← fleet; detail = health + quota + drift + (power-user) terminal
│
└── Settings (.settings)  — regrouped into 4 groups:
    ├── Connection       (relay pairing, devices, SSH keys [merged], hosts)
    ├── Governance       (policy preset + editor + autonomy + audit, all in one)
    ├── Account & Billing(account, subscription, secrets, provider keys)
    └── Advanced         (terminal, doctor, sync, shortcuts) — power-user, de-emphasized

Deferred-V2 (retain in code, NOT in nav): hosted-cloud, loops, worktrees, SFTP files, agent-detail sprawl (consolidate to 1 run view).
```

### Net effect
- **Primary destinations: 6 → 4** (Home, New Chat, Machines, Settings). Inbox folds into Home.
- **Settings sub-screens: ~20 → ~12** grouped into 4 sections.
- **Agent-detail views: 8 → 1.**
- **Onboarding: 5–7 → ≤3.**
- **Duplicates removed:** Keys, Audit, Premium-comparison, BridgeAuditFeed.

## Is the primary value obvious?
Partially. Home's "N agents need you" + the approve loop is the value, and it reads well. But it competes with Inbox, Machines, terminal, and a deep Settings tree. Collapsing to 4 destinations and folding Inbox into Home makes "approve your agents from your phone" the unmistakable spine.
