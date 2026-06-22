# APP_AUDIT.md — Lancer Codebase Audit

> This audit reflects the codebase state as of the agent/ws-a-docs branch (master HEAD 24b80e5a).
> CORRECTED facts from earlier audits are explicitly flagged where prior audits were wrong.

---

## 1. Architecture Overview

Lancer is organized as a Swift Package (`LancerKit`) with multiple modules plus a thin Xcode app target. Key architectural rules enforced throughout:

- **Engine modules contain NO UIKit/SwiftUI** — clean separation of concerns
- **Feature modules NEVER depend on each other** — only on engines + DesignSystem
- **All async types are Sendable** — Swift 6 strict concurrency complete (zero warnings)
- **292 Swift tests passing across 44 suites** — reliable baseline

### Module Map

| Module | Role | Key Files |
|---|---|---|
| **LancerCore** | Shared models + protocols | `LancerDProtocol.swift`, `Approval.swift`, `Snippet.swift`, `SessionSummary` |
| **SSHTransport** | SSH connection, PTY, DaemonChannel (JSON-RPC over SSH), SessionPool | `SSHConnection.swift`, `PTYChannel.swift`, `DaemonChannel.swift` |
| **SessionFeature** | Terminal UI, block rendering, live prompt input | `ToolCardView.swift`, `BlockRenderer.swift`, `ChatTranscriptView.swift`, `LivePromptInputView.swift`, `PTYBridge.swift`, `SnippetPaletteSheet.swift`, `LiveActivityManager.swift` |
| **InboxFeature** | Approval Inbox: list + Allow/Reject actions | `InboxView.swift`, `InboxViewModel.swift` (LiveInboxViewModel with real Allow/Reject) |
| **AgentKit** | Risk scoring, workflow engine, AI clients, provisioners | `RiskScorer.swift`, `WorkflowEngine.swift`, `AnthropicClient.swift`, `OpenAIClient.swift` |
| **NotificationsKit** | Push registration | `Notifications.swift` |
| **SyncKit** | CloudKit sync engine (LWW, gated) | `SyncEngine.swift`, `CloudSync.swift` |
| **PersistenceKit** | GRDB migrations + repositories | `ApprovalRepository.swift`, `SessionSnapshotRepository.swift`, `SnippetRepository.swift` |
| **DesignSystem** | Tokens, reusable components | `Tokens.swift`, `DSButton`, `DSQuoteBlock`, `DSLink`, `DSDiffChips`, `PixelBox`, `PixelAvatar`, `DSBlockCard`, `Composites.swift` |
| **AppFeature** | App root, home view, approval ingest, gallery | `AppRoot.swift`, `SessionsHomeView.swift`, `AgentsView.swift`, `ApprovalIngest.swift`, `DebugGalleryView.swift` |
| **SettingsFeature** | Snippet editor, billing | `SnippetEditorView.swift`, `BillingView.swift` (StoreKit + Stripe) |
| **DiffKit** | Unified diff parser + diff view | `UnifiedDiffParser.swift`, `DiffView.swift` |

### External Components

- **LancerWatch** — watchOS multi-tab app (Inbox, Activity, Session, Snippets tabs)
- **LancerLiveActivityWidget** — Dynamic Island + Lock Screen Live Activity
- **LancerWatchWidget** — watchOS complication

### Go Layer

- **`daemon/lancerd`** — hook ingest, approve/reject routing (pure-Go hook gateway)
- **`daemon/push-backend`** — APNs + Stripe billing (~482 lines `billing.go`)

---

## 2. Feature Maturity Table

| Feature | Status | Notes |
|---|---|---|
| SSH connect + TOFU | ✅ Complete | Ed25519, password auth, BiometricGate |
| Block-mode terminal | ✅ Complete | OSC 133 A/B/C/D, PTYBridge, BlockRenderer |
| Raw PTY (SwiftTerm) | ✅ Complete | vim, htop, tmux via alt-screen path; block-embedded (no full-screen overlay) |
| Auto-reconnect | ✅ Complete | NWPathMonitor + backoff, AutoReconnectEngine |
| GRDB persistence | ✅ Complete | Hosts, blocks, snippets, approvals — migrations in PersistenceKit |
| Approval Inbox + RiskScorer | ✅ Complete | Low/medium/high/critical bands, Allow/Reject wired end-to-end |
| Live Activity / Dynamic Island | ✅ Complete (scaffold) | Scaffolded — needs deepening (Stage 2 work) |
| watchOS multi-tab app | ✅ Complete | Inbox, Activity, Session, Snippets tabs in LancerWatch |
| SFTP browser | ✅ Complete | `SFTPFilesView`, `SFTPClient` |
| DiffKit unified-diff | ✅ Complete | Hunk approval UI — ready for structured tool_use |
| BYOK AI clients | ✅ Complete | Anthropic + OpenAI, streaming |
| Snippets / workflows | ✅ Complete | Full CRUD, `{{arg}}` literal/enum/dynamic-shell templates, palette (235 ln), editor (371 ln), library (212 ln) — needs QA + seed default library |
| StoreKit purchase | ✅ Complete | Non-consumable IAP ($14.99 lifetime) |
| lancerd MVP | ✅ Complete | `agent-hook` command, risk mapping, auto-approve fallback |
| **Snippets default library** | ⚠️ Needs QA | Built but needs seeding + testing before ship |
| **Managed-compute Provisioners** | 🔶 Partial | `FlyProvisioner` makes real Fly.io Machines API calls; key-injection TODO at `FlyProvisioner.swift:44` |
| **APNs alert loop** | ❌ Gap | `lancerd` never POSTs to `push-backend`; alert loop unclosed — agent waits, phone stays silent |
| **Token-routing** | ❌ Gap | iOS registers push token with `identifierForVendor`; lancerd keys approvals by agent session → device↔session mismatch |
| **Structured tool_use** | ❌ Gap | `lancer-hook.sh:18-25` flattens `tool_input` to 500-char string; no `toolName`/`toolUseID`/`input` fields in wire protocol |
| **Always-approve persistence** | ❌ Gap | `DaemonChannel.swift:52` collapses `.approvedAlways` → `"approve"`; rule never stored |
| **Multi-agent fleet** | ❌ Gap | `AppRoot.swift:587-691` wires exactly ONE session; new session replaces old — no fleet |
| **Ship gate** | ❌ Blocked | `project.yml` uses `DeviceTesting.entitlements`; needs paid Apple Developer account ($99/yr) to activate CloudKit + Push |

---

## 3. CORRECTED Facts (Earlier Audits Were Wrong On These)

**Read this section before starting any implementation work.**

### 3.1 Snippets Are COMPLETE, Not Stubs
Earlier audits described Snippets as a stub or partial feature. **This is wrong.** The Snippets system is fully implemented:
- Full CRUD (create/read/update/delete) at `SnippetRepository.swift`
- Parameterized templates with `{{arg}}` placeholders: literal, enum, and dynamic-shell resolution types
- 371-line editor (`SnippetEditorView.swift`), 235-line palette (`SnippetPaletteSheet.swift`), 212-line library view
- `WorkflowEngine.swift` handles multi-step composition
- **Do NOT rebuild Snippets.** The only remaining work: QA pass + seed a default library.

### 3.2 Managed-Compute Provisioners Are Partial-But-Real (Not Vaporware)
Earlier audits implied Provisioners were skeleton/placeholder code. **This is wrong.** `FlyProvisioner` makes real Fly.io Machines API calls. There is one concrete TODO: key injection at `FlyProvisioner.swift:44`. The provisioner infrastructure exists and works up to that point.

### 3.3 The Approval Wire Protocol Is Lossy (Structural Problem)
`lancer-hook.sh:18-25` reads Claude Code's hook payload and flattens the entire `tool_input` into a single 500-character truncated string. **No structured fields** — `toolName`, `toolUseID`, `sessionId`, structured `input` — flow through the wire protocol. This means:
- InboxView cannot show the tool name in the card header from real data
- DiffKit cannot render a real file diff from a Write tool call
- "Edit & run" cannot return a structured edited input
This is the highest-priority structural gap before Stage 3 work.

### 3.4 Always-Approve Is Never Persisted
`DaemonChannel.swift:52` collapses `.approvedAlways` to the plain string `"approve"` before sending the decision. The "always" semantics are silently discarded. No rules are stored anywhere. Every "Allow always" tap is functionally identical to "Allow once."

### 3.5 There Is No Fleet — Single Session Only
`AppRoot.swift:587-691` wires exactly one `DaemonChannel` and one `ApprovalIngest`. `SessionsHomeView` shows one live session plus static recents. There is no `FleetStore`, no agent slot management, no fleet-wide Inbox. The fleet UI designs exist but have no backing implementation.

---

## 4. Strengths

- **Swift 6 strict concurrency complete** — zero warnings; production-grade safety baseline
- **292 tests passing (44 suites)** — reliable regression safety net
- **Block-mode terminal is architecturally sound** — OSC 133 + PTYBridge pipeline is correct; alt-screen (vim/htop/tmux) renders block-embedded with no full-screen overlay regression
- **Reconnect engine is well-designed** — NWPathMonitor + exponential backoff + AutoReconnectEngine
- **Design system is mature and consistent** — DesignSystem module used throughout; PixelBox, PixelAvatar, DSBlockCard, DSButton all production-ready
- **Live Activity / Dynamic Island / Watch scaffolding exists** — no greenfield work needed; Stage 2 is deepening, not building from scratch
- **TOFU + Secure Enclave + BiometricGate** — security primitives are complete and correct
- **DiffKit is ready** — unified diff parsing + hunk UI exists; blocked only on structured wire protocol to feed it real data

---

## 5. Weaknesses / Gaps (Prioritized)

### P0 — Blocks Ship

1. **Ship gate: paid Apple Developer account required** — `DeviceTesting.entitlements` in `project.yml` prevents CloudKit + Push entitlements from activating. External blocker ($99/yr account). Owner-action required.

### P1 — Blocks Core Value Proposition

2. **Approval wire protocol is structurally lossy** — `lancer-hook.sh` flat-string problem (see §3.3). Until fixed, approval cards show truncated text; DiffKit is unused on real data; edit-before-run is impossible.

3. **APNs alert loop is open** — `lancerd` never POSTs to `push-backend`; token-routing mismatch (`identifierForVendor` vs. agent session key). The #1 user complaint ("I missed the moment") is unresolved while this gap exists.

### P2 — Limits Differentiation

4. **Always-approve never persisted** — every "Allow always" is functionally "Allow once"; a promised feature doesn't work (see §3.4).

5. **No fleet** — single-session only; multi-agent steering (the headline use case for power users) requires `FleetStore` (see §3.5).

### P3 — Polish / Distribution

6. **lancerd is not open-sourced** — harder for security-conscious developers to trust and self-host. Open-sourcing is the highest distribution leverage action available (see ROADMAP.md §4).

7. **Snippets default library not seeded** — the palette launches empty; first-run experience is poor.

---

## 6. Go Layer Detail

### lancer-hook.sh (the lossy layer)
File: `daemon/lancer-hook.sh` lines 18-25.
Current behavior: reads stdin JSON from Claude Code's PreToolUse hook; extracts only `tool_name` and flattens `tool_input` into a 500-char string; POSTs to lancerd. Structured fields are lost before lancerd ever sees them.

### push-backend billing.go
File: `daemon/push-backend/billing.go` (~482 lines).
Status: Stripe billing wired; APNs send path exists in the binary but lancerd never calls the `/approval` endpoint. The push-backend is deployed and reachable (HTTPS via Caddy auto-TLS per commit 293bcd3b); the gap is on the lancerd side.

### lancerd
Status: hook ingest + risk mapping + auto-approve fallback complete. Missing: POSTing pending approvals to push-backend; persisting always-approve rules.
