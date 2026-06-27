# ROADMAP.md — Lancer Staged Execution Plan

> Derived from verified §2.7 market data (see PRODUCT_RESEARCH.md) and codebase audit (`docs/_archive/APP_AUDIT.md`).
> Product decisions are fixed; slice order is re-aimed per verified competitive analysis.

---

## 1. Fixed Product Decisions

These are not up for re-evaluation without new disconfirming data:

1. **SSH-only near-term; WebSocket relay deferred.** SSH is the authoritative transport. WS relay enables locked-phone approval + compute/teams but adds infrastructure complexity; deferred to managed-compute phase.

2. **Pure-Go hooks near-term; Node Agent-SDK bridge deferred.** The hook gateway (`lancer-hook.sh` + `lancerd`) is the near-term approval path. The Claude Code Agent SDK `canUseTool` callback (edit-before-run, richer semantics) requires a Node sidecar; deferred to managed-compute phase.

3. **Business model: freemium funnel + enterprise/self-host as paying tier.** Consumer WTP is ~zero per Omnara pricing collapse (omnara.com/pricing — HIGH confidence). The segment with real WTP is security-conscious / enterprise / regulated developers. Precedent: Termius $10/mo, Blink $20/yr for transport-grade reliability. Do not build the business model around consumer recurring revenue.

4. **Slice order re-aimed per verified market data:**
   - Stage 1: ship-gate + validation foundation
   - Stage 2: reliability + native notifications (the universal #1 differentiator)
   - Stage 3: structured tool_use + always-approve + edit (the approval spine)
   - Stage 4: multi-agent fleet
   - Stage 5: security/self-host + open-source bridge
   - Stage 6: cross-vendor breadth

---

## 2. Staged Execution Plan

| Stage | Goal | Workstreams | Gate Criteria |
|---|---|---|---|
| **0+1** | Docs + ship-gate + validation foundation | WS-A (docs), WS-B (ship-gate), WS-F (validation) | 4 strategy docs present; xcodegen clean build; owner-steps written; validation harness runnable locally |
| **2** | Reliability + native notifications — NEW #1 differentiator | Close APNs loop + token-routing fix (1.2); Live Activities/DI/Watch polish (3.6); reconnect hardening; notification filtering (3.4) | Push path wired + tested end-to-end; notification reliability demonstrably better than rivals; all tests green |
| **3** | Structured approval cards — the approval spine | Structured tool_use wire protocol (2.1a); always-approve persistence + edit-before-run (2.1b) | Round-trip test passes (hook → lancerd → iOS → approve → unblocks agent); `.approvedAlways` persisted and re-applied; edit-before-run returns edited input to agent |
| **4** ✅ *shipped* | Multi-agent fleet (as craft, not headline) | FleetStore; jump-to-unread; fleet-wide Inbox (2.2) — **Fleet tab shipped** (`AppFeature/FleetView.swift`, `enum Tab.fleet`; `store.slots` + `loopStore.activeLoops`) | ≥2 independent agent slots; restore-after-reconnect test passes; no new Swift 6 warnings *(verify the multi-slot/reconnect criterion before closing)* |
| **5** | Security / self-host + distribution | E2E/on-prem hardening; open-source lancerd bridge (4.6); enterprise pricing | Bridge packaged + documented; security posture written; first enterprise customer or partnership |
| **6** | Cross-vendor breadth | Codex → Cursor/Gemini; extend hook ingest | Codex parity behind same security framing; cross-vendor integration tests pass |

---

## 3. Roadmap Buckets

### Bucket 1 — MVP Ship-Blockers

These block App Store submission or make the app functionally broken on a real device.

| ID | Item | Size | Risk | Deps | Stage |
|---|---|---|---|---|---|
| **1.1** | Flip `DeviceTesting.entitlements` → `Lancer.entitlements`; enable CloudKit + Push in `project.yml` | S | High | **EXTERNAL: paid Apple Developer account ($99/yr)** | 0+1 |
| **1.2** | Close APNs alert loop: lancerd POSTs pending approvals to push-backend `/approval`; fix token-routing mismatch (`identifierForVendor` → agent-session key); wire `didReceiveRemoteNotification` in iOS app | M | High | dep 1.1 | **2** |
| **1.3** | ATS/HTTPS compliance: remove `http://` fallback in network calls; add `ITSAppUsesNonExemptEncryption: false` to Info.plist | S | Med | — | 0+1 |
| **1.4** | Add `remote-notification` to `UIBackgroundModes` in Info.plist | S | Low | dep 1.1, 1.2 | 0+1 |
| **1.5** | CloudKit first real sync (SyncKit LWW hosts/snippets) | M | Med | **EXTERNAL: paid account + container activation** | 0+1 |
| **1.6** | Real-host validation harness (full end-to-end pass on live SSH host) | M | High | **EXTERNAL: live host required** | 0+1 |
| **1.7** | Snippet QA + seed default library | S | Low | — | 0+1 |
| **1.8** | DNS for conduit.dev (`scripts/update-dns.sh`) | S | Low | — | 0+1 |

### Bucket 2 — Differentiators

The features that make Lancer worth choosing over first-party Anthropic Remote Control and free OSS alternatives.

| ID | Item | Size | Risk | Deps | Stage |
|---|---|---|---|---|---|
| **2.1a** | **Structured tool_use wire protocol** — un-flatten `lancer-hook.sh`; add `toolName`/`toolUseID`/`sessionId`/structured `input` to `ApprovalEvent` (Go) + `ApprovalPendingParams`/`Approval` (Swift) + DB migration | L | Med | — | **3 (SPINE)** |
| **2.1b** | **Real "Allow always" + edit-before-run** — persist always-rules in lancerd (`rules.go`); stop discarding `.approvedAlways` in `DaemonChannel.swift:52`; decision payload carries edited input; "Edit & run" + per-rule "Always allow" in InboxView | L | Med | dep 2.1a | **3** |
| **2.1c** | Agent-SDK bridge (Node sidecar for `canUseTool`) | XL | High | dep 2.1a | **DEFERRED to managed-compute phase** |
| **2.1d** | WebSocket relay transport | L | High | — | **DEFERRED; SSH stays authoritative** |
| **2.2** | **Multi-agent Fleet dashboard** — hoist single-session ownership out of `AppRoot` into `FleetStore` (N slots, each with own `DaemonChannel`/`ApprovalIngest`); per-agent status pills; jump-to-unread; fleet-wide Inbox; git/PR metadata (`GitMetadataProbe.swift`) | XL | High | dep 2.1a | **4** |

### Bucket 3 — Polish

Items that improve quality and retention but don't block ship or core differentiation. Items 3.4 and 3.6 are promoted to Stage 2 because they directly serve the "reliability + notifications" differentiator.

| ID | Item | Size | Risk | Stage |
|---|---|---|---|---|
| **3.1** | Multi-step workflow runner UI + Warp-YAML import | S | Low | Later |
| **3.2** | Block affordances — share + re-run-with-edit | S | Low | Later |
| **3.3** | Session timeline scrubber | M | Med | Later |
| **3.4** | **Notification filtering** — per-risk/agent/quiet-hours | S | Med | **Stage 2** |
| **3.5** | Global command palette | S | Low | Later |
| **3.6** | **Watch/widget + Live Activity/Dynamic Island deepening** — approve from lock screen or wrist, PixelBox in compact DI, approval count complication | M | Med | **Stage 2 differentiator** |

### Bucket 4 — Later / Enterprise

| ID | Item | Size | Risk | Stage |
|---|---|---|---|---|
| **4.1** | Managed compute — close Provisioners one-tap + key injection (`FlyProvisioner.swift:44`); deploy control plane | XL | High | 5+ |
| **4.2** | Team seats / multi-tenant approval hierarchy | L | High | 5 |
| **4.6** | **Open-source lancerd bridge** — highest distribution leverage; Happy (21.6k★) + CloudCLI (11.6k★) model | M | Low | **Stage 5** |

---

## 4. Pricing Direction

| Tier | Model | Rationale |
|---|---|---|
| **Consumer (free)** | Free app; lifetime IAP at $14.99 (already in StoreKit) | Consumer WTP ~zero per Omnara collapse; use free to build top-of-funnel |
| **Enterprise / self-host** | Team seats + on-prem bridge; SLA | This segment has real WTP; Termius $10/mo + Blink $20/yr precedent; compliance-driven buyers pay |

**Do not build recurring consumer subscription into the business model.** The Omnara pricing arc (HIGH confidence — omnara.com/pricing) is a clear market signal.

---

## 5. Distribution Plan (Critical Path)

Distribution is the biggest execution risk — Lancer will be the best-built and potentially the least-known app in a crowded field.

### 5.1 Open-Source the lancerd Bridge (Stage 5)
Happy (21.6k★, github.com/slopus/happy) and CloudCLI (11.6k★, github.com/siteboon/claudecodeui) both earned developer trust by going open-source. The bridge is low-IP (hook plumbing; the iOS app stays proprietary) and high-trust (security-conscious developers won't self-host a black box). Open-sourcing in Stage 5 is the single highest-leverage distribution action.

### 5.2 Beachhead a Specific Niche First
Target: **security-conscious / enterprise / regulated developers** — NOT a broad consumer launch.

Why this segment:
- Has demonstrable WTP (enterprise SSH tooling precedent)
- Cannot use first-party Anthropic Remote Control for compliance reasons (routes code through Anthropic's infrastructure)
- Values on-premises bridge + audit log + Secure Enclave

### 5.3 Anti-Lock-In Positioning
Tagline that cannot be undercut by Anthropic Remote Control:
**"You control the bridge. Your code stays on your host."**

Anthropic Remote Control requires Anthropic's infrastructure. Lancer's lancerd bridge runs on the developer's own host. This is a structural advantage for the compliance/enterprise segment and is not replicable by first-party tools.

### 5.4 Risk Register

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| Anthropic Remote Control captures all Claude users | High | High | Pivot positioning to cross-vendor + self-host; compliance segment can't use first-party |
| OSS rivals (Happy/cmux) improve faster than Lancer | Med | High | Native iOS quality (Live Activities, DI, Watch) is structurally harder for OSS to match |
| Consumer WTP stays near zero | High | Med | Don't depend on consumer recurring revenue; beachhead enterprise |
| Apple Developer account delays ship | High (external) | High | Owner-action required; no engineering mitigation |
| lancerd trust gap (closed source) | Med | Med | Open-source in Stage 5 mitigates; interim: publish architecture docs |
