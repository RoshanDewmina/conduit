# Lancer feature backlog

**Living tracker** — update status when code or tests change.  
**Scope decisions:** [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md)  
**Implementation gaps:** [`2026-07-06-feature-implementation-gap-matrix.md`](2026-07-06-feature-implementation-gap-matrix.md)  
**Owner hub:** [`../STATUS_LEDGER.md`](../STATUS_LEDGER.md)

Columns: **Feature | Tier | Status | Source session(s) | Wireframe | Evidence | Owner-gated?**

---

## 1. Tier 0 engineering gate (`019f3763`)

Freeze Tier 2 until these pass.

| Feature | Tier | Status | Source | Wireframe | Evidence | Owner? |
|---------|------|--------|--------|-----------|----------|--------|
| E2E relay pairing from live shell | T0 | Partial live | `019f3763` | `01-onboarding.html` | `CursorShellLiveBridge` → `E2ERelayPairingView` | E2E verify |
| Workspaces / thread list hydration | T0 | Partial live | `019f3763` | `03-workspaces.html` | `ChatConversationRepository` via bridge | Sim verify |
| Composer → `performDispatch` | T0 | Partial live | `019f3763` | `04-launch-setup.html` | Live callback wired | E2E verify |
| Approval → `decide()` | T0 | Partial live | `019f3763` | `06-review-diff.html` | `InboxViewModel` + bridge | E2E + biometric |
| Follow-up / `performContinueConversation` | T0 | Partial live | `019f3763` | `05-work-thread.html` | Live callback | E2E verify |
| Settings / policy handoff | T0 | Live | `019f3763` | `10-settings.html` | `SettingsWithLibraryView` sheet | — |
| Relay E2E harness (Cursor nav) | T0 | **PASS** | `019f3763` | — | `relay-approval-e2e.sh` through live Cursor shell — [`test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`](../test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) | — |
| Physical device governed loop | T0 | Open | `019f3763` | — | [`test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`](../test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) | **Yes** |

---

## 2. V1 Away Mode core (`019f2dec` → `019f2ebf` → master plan §5)

| Feature | Tier | Status | Source | Wireframe | Evidence | Owner? |
|---------|------|--------|--------|-----------|----------|--------|
| Away Launch Composer + thin launch contract | V1 | Not started | `019f2ebf` | `04-launch-setup.html` | Generic composer only in shell | — |
| Mobile attachments (photo/screenshot/video/voice) | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | Picker UI incomplete (D15) | — |
| Share Sheet / Universal Link intake | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Smart Default Target | V1 | Wireframed | `019f2ebf` | `02-home.html`, `03-workspaces.html` | — | — |
| Away Mode Setup (progressive checklist) | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Repo Playbook | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | D4: add Workspace Detail row | — |
| Agent Readiness Check | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Run Mode | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Run Budget | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Interruption Budget | V1 | Wireframed | `019f2ebf` | `04-launch-setup.html` | — | — |
| Minimal Away Status | V1 | Partial | `019f2ebf` | `02-home.html`, `05-work-thread.html` | Live Activity code exists | — |
| Session-survives-disconnect UI signal | V1 | Not started | `019f2dec` | `02-home.html` | Daemon supports; UI not surfaced | — |
| Question Cards | V1 | Not started | `019f2ebf` | `05-work-thread.html` | — | — |
| Question Ladder (5 levels) | V1 | Wireframed thin | `019f2dec` | `05-work-thread.html` | Full ladder needs drawing | — |
| Stop and Snapshot | V1 | Partial | `019f2ebf` | `06-review-diff.html` | UI exists; atomic RPC on branch | — |
| Voice Everywhere | V1 | Wireframed | `019f2ebf` | footnotes | iOS 26 speech APIs | — |
| Proof Suite base layer | V1 | Mock only | `019f2ebf` | `05-work-thread.html` | Mock artifact cards | — |
| Proof Timeline | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Proof Reel (staged after thin proof) | V1 | Deferred staging | `019f2ebf` | `05-work-thread.html` | Per `v1-paid-away-workflow-spec.md` | — |
| Visual Diff Review | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | Must gate Mark Ready (D8) | — |
| Device Matrix Proof | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Auto Bug Replay | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Mobile QA Annotation | V1 | Not started | `019f2ebf` | `05-work-thread.html` | Headline differentiator | — |
| Error Autopsy | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Away Digest as Home | V1 | Partial | `019f2ebf` | `02-home.html` | `CursorHomeView` not wired | — |
| Git / PR / Merge Actions | V1 | Mock only | `019f2ebf` | `08-ship-history.html` | PR detail mock | — |
| Contextual Command Cards | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Changed Files Review (free-text V1) | V1 | Wireframed | `019f2ebf` | `06-review-diff.html` | Hunk-threading Post-MVP | — |
| Flight Recorder + Work Search | V1 | Mock only | `019f2ebf` | `08-ship-history.html` | Search overlay mock | — |
| Return-to-desk context (in Work Thread) | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | Not standalone packet | — |
| Web Preview / Preview Cockpit | V1 | Wireframed | `019f2ebf` | `05-work-thread.html` | — | — |
| Light Automations (4 variants) | V1 | Partial wireframe | `019f2ebf` | `05-work-thread.html` | 2 of 4 drawn | — |
| Provider Capability Badges | V1 | Wireframed | `019f2ebf` | `03-workspaces.html` | Time permitting | — |
| Governance: policy engine + audit + drift | V1 | **Shipped** | `019f2f6d` | `10-settings.html` | `lancerd` + Settings | — |
| Governance: risk-tiered biometric gate | V1 | **Shipped** (P0 fix on branch) | `019f2f6d` | `06-review-diff.html` | `695d2440`; fail-closed on branch | Device matrix |
| Workspaces (repo-first IA) | V1 | Partial | master §5 | `03-workspaces.html` | Code host-first — open §9 | **Decision** |
| Onboarding / Pairing | V1 | Shipped + mock shell | `019f2ebf` | `01-onboarding.html` | Resequence D1–D3 pending | — |
| Settings (native grouped list) | V1 | Shipped | `019f2ebf` | `10-settings.html` | Real Settings wired in live shell | — |
| LancerMac thin companion | V1 | Shipped | master §5 | — | Phase A+B; keep thin | — |
| 3-root IA (Home / Workspaces / Settings) | V1 | Partial | master §2 | `lancer-workflows-2026-07-05/` | Cursor shell (`CursorAppShell`); legacy sidebar deprecated | — |

---

## 3. Tier 1 Cursor shell (mock / live surfaces)

| Feature | Tier | Status | Source | Wireframe | Evidence | Owner? |
|---------|------|--------|--------|-----------|----------|--------|
| Onboarding flow (5 steps) | T1 | Mock + UI tests | gap matrix | `01-onboarding.html` | 4 UITests | — |
| Workspaces → thread → work thread | T1 | Mock + partial live | gap matrix | `03`, `05` | 8 UITests | — |
| Approval review sheet | T1 | Mock + live callback | gap matrix | `06-review-diff.html` | 4 UITests + live test | — |
| PR detail + inline diff | T1 | Mock | gap matrix | `06-review-diff.html` | 1 UITest | — |
| Search overlay | T1 | Mock | gap matrix | `08-ship-history.html` | 1 UITest | — |
| Profile drawer + settings sheet | T1 | Mock + live handoff | gap matrix | `10-settings.html` | 3 UITests | — |
| Composer chain (run-on, model) | T1 | Mock | gap matrix | `04-launch-setup.html` | 2 UITests (2 failing) | — |
| Connection health ladder | T1 | Planned | `2026-07-06-competitor-borrow` | `03-workspaces.html` | Orca pattern — P0 borrow | — |
| Approval banner above composer | T1 | Planned | competitor borrow | `05-work-thread.html` | T3 pattern — P0 | — |

---

## 4. Post-MVP fast-follows (master plan §6)

Ship **Cross-Vendor Second-Agent Review** first after MVP.

| Feature | Tier | Status | Source | Wireframe | Evidence | Owner? |
|---------|------|--------|--------|-----------|----------|--------|
| Cross-Vendor Second-Agent Review | Post-MVP | Wireframed | `019f2dec`, §6 | `07-fast-follows.html` | Highest differentiation | — |
| Proof Becomes Regression / Regression Watchlist | Post-MVP | Discussed | `019f2dec` | — | — | — |
| Time-Travel Scrubber + Fork-From-Timestamp | Post-MVP | Approved design | consolidation §4 | `07-fast-follows.html` | — | — |
| Clips integration + `lancer.proof` schema | Post-MVP | Discussed | `019f2dec` | — | — | — |
| Run Comparison (single-vendor A/B) | Post-MVP | Wireframed | `019f2ebf` | `07-fast-follows.html` | — | — |
| Weekly Away Mode Digest | Post-MVP | Discussed | `019f2dec` | — | — | — |
| Siri / View Annotations question cards | Post-MVP | Wireframed | §6 | `07-fast-follows.html` | PR #16/#24 not on master | — |
| StandBy / full-screen proof widgets | Post-MVP | Discussed | §6 | `09-platform-gaps.html` | iOS 27 | — |
| True Handoff (Continuity) | Post-MVP | Discussed | §6 | — | — | — |
| Watch app embed in iOS target | Post-MVP | Not started | `019f2f6d` | — | `project.yml` excludes | CI fix |
| Policy Diff Review | Post-MVP team | Wireframed | §6 | prototype | Team-tier | — |
| Cross-host policy consistency | Post-MVP | Wireframed | §6 | prototype | — | — |
| On-device audit digest | Post-MVP | Wireframed | §6 | prototype | — | — |
| Compliance Export | Post-MVP team | Wireframed | §6 | prototype | — | — |
| Terminal / SSH escape hatch | Post-MVP | Built, hidden | §6 | — | Unwired from V1 nav | — |
| Whole-thread context ingestion | Post-MVP | Discussed | §6 | — | — | — |
| Slack/Teams-triggered missions | Post-MVP | Discussed | §6 | — | — | — |
| On-device Foundation Models compression | Post-MVP | Discussed | §6 | `09-platform-gaps.html` | iOS 27 gated | — |

---

## 5. Correctness / security (`019f2f6d` + master plan §7)

| Gap | Severity | Status | Source | Evidence | Owner? |
|-----|----------|--------|--------|----------|--------|
| BiometricGate fail-open (no passcode) | P0 | Fixed on branch | `019f2f6d` | `531685b6` on `codex/tier-0-live-cursor-shell` | Device verify |
| Emergency stop non-atomic | P0 | Fixed on branch | `019f2f6d` | Daemon latch + RPC same branch | — |
| JWT HS256-only | P1 | Open | `019f2f6d` | `push-backend/auth.go` | — |
| Dormant StoreKit vs Stripe entitlement | P1 | Open | `019f2f6d` | Two billing mechanisms | **Decision** |
| Watch not embedded | P1 | Open | `019f2f6d` | `project.yml:138-143` | — |
| Daemon single pairing slot | P2 | Open | `019f2f6d` | `relaypair.go` by design | — |
| Audit chain no external anchor | P1 | Open | `019f2f6d` | `audit.go:135-180` | — |

---

## 6. Business / validation

| Item | Status | Source | Evidence | Owner? |
|------|--------|--------|----------|--------|
| Positioning: govern + verify across vendors | Locked | `019f2dec`, `019f2f6d` | Master plan §3 | — |
| Pricing: $25/mo solo · $99/mo team | Unreconciled | `019f2dec` | vs StoreKit + Stripe | **Yes** |
| Validation gate 10/5/3/1 | **Unrun** | `019f2dec` | No local evidence | **Yes** |
| Deadline | **2026-07-21** | `019f2dec` | STATUS_LEDGER | **Yes** |
| Workspaces repo-first vs host-first | Open | master §9 | Data model decision | **Yes** |
| Billing consolidation (3 mechanisms) | Open | master §9 | Settings billing copy blocked | **Yes** |
| Return-to-desk single recap surface | Design check | master §9 | Work Thread | — |

---

## 7. Rejected / superseded (do not re-propose)

| Feature | Rationale | Source |
|---------|-----------|--------|
| Needs-Me Queue as Home restructure | Same job as Away Digest ledger | master §8 |
| Evidence Inbox (standalone) | Redundant with composer | `019f2ebf` |
| Heavy Mission Draft / plan clone | Agent already plans | `019f2ebf` |
| Big Agent Router | → Smart Default Target | `019f2ebf` |
| Live Activity Risk Meter | Owner cut | master §8 |
| Haptic Risk Language | Owner cut | master §8 |
| Live Shadow Second Opinion | Owner cut | master §8 |
| Break-Point-Aware Nudges | Owner cut | master §8 |
| Live Camera Bug Repro | Owner cut | master §8 |
| Frustration Signal Missions | Cut in redundancy pass | master §8 |
| Micro Editor | Conflicts non-goal | master §8 |
| Developer App Drawer | Conflicts 3-root IA | master §8 |
| Terminal as primary V1 surface | Escape hatch only | strategy doc |
| Hosted-cloud execution as V1 story | V2 retained code | ARCHITECTURE §0.1 |
| Proof-to-ship Needs-Me Queue IA | Rejected rename | master §3 |
| Tab bar root navigation | Vestigial `enum Tab` | ARCHITECTURE §4.1 |

---

## Cross-check record

Union of master plan §5, strategy doc §Accepted Feature Set, and Codex chain `019f2dec`/`019f2ebf` mapped to sections 1–7 above.  
Verifier output: [`docs/audits/2026-07-06-feature-crosscheck.md`](../audits/2026-07-06-feature-crosscheck.md)
