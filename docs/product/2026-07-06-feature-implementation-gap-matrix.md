# Lancer Feature Implementation Gap Matrix

Compiled: 2026-07-06 (refreshed end of phone-ready pass)  
Canonical features: [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md)  
Canonical implementation: [`ARCHITECTURE.md`](../../ARCHITECTURE.md) §0.1 + §4.1

> **Living tracker** — update here when code or tests change. Feature scope decisions stay in the master plan.

## Executive summary

| Layer | Status (2026-07-06) |
|-------|------------------------|
| **Production shell** | Cursor shell **only** (2026-07-06 cutover): `CursorAppShell` + `CursorShellLiveBridge`. Legacy sidebar / `NewChatTabView` / drawer IA **deleted**. |
| **Cursor DEBUG shell** | 34 Swift files; **20/20** mock UI tests (`LANCER_CURSOR_SHELL=1`); live bridge is now the default production root. |
| **Relay E2E** | **`scripts/validation/relay-approval-e2e.sh` PASS** (pairing wait fix). |
| **Gap** | Tier 1+ mock-only surfaces (Proof Suite, Away Launch, Git ship actions); P0 correctness items in master plan §7. |

---

## Tier 0 — Phone-usable loop

| Feature | Status | Evidence |
|---------|--------|----------|
| Pairing (E2E relay) | **Shipped** | `E2ERelayPairingView`, `LANCER_RELAY_CODE` seam; relay E2E PASS |
| Workspaces list | **Wired** | `CursorWorkspacesView` + `refreshCursorLiveBridge` |
| Thread list | **Wired** | `ChatConversationRepository` → bridge; seed fallback for empty |
| Composer → dispatch | **Wired** | `CursorComposerSheet` → `onDispatch` / `onContinue` |
| Approvals | **Wired** | `InboxView` + `CursorReviewDiffView` → `onDecide`; UITest biometric bypass |
| Follow-up / continue | **Wired** | `performContinueConversation` via bridge |
| Settings / policy | **Wired** | `CursorSettingsView(onOpenRealSettings:)` → `SettingsWithLibraryView` sheet |
| Work Thread approval banner | **Wired** | Shown when `pendingApprovalID != nil` on live bridge |

---

## Tier 1 — MVP UI mocked in Cursor shell

| Feature | Shell | UI tests |
|---------|-------|----------|
| Onboarding | wireframed + live pairing callback | 4 tests (mock suite) |
| Workspaces → thread → work thread | mock + live hydration | 8 tests |
| Approval review | mock + live `onDecide` | 4 tests + **live approval test** |
| PR detail + diff | mock | 1 test |
| Search / profile / composer chain | mock | 6 tests |

**Mock suite:** `CursorAppShellExhaustiveTests` **20/20 PASS** (~399s, iPhone 17 Pro sim).

---

## Tier 2 — Not in shell (deferred)

Per master plan §5–§6: Away Launch Composer, Proof Suite/Reel, Mobile QA Annotation, Question Cards, Git/PR/Merge ship actions, Flight Recorder. See master plan for rationale.

---

## Correctness gaps (master plan §7)

| Gap | Severity | Status |
|-----|----------|--------|
| Biometric degrade-open on no-passcode devices | P0 | Open — document in readiness checklist |
| Emergency Stop not atomic | P0 | Open |
| JWT HS256-only | P1 | Open |
| StoreKit vs Stripe entitlement | P1 | Open |
| Watch app not embedded | P1 | Open |

---

## Operational checklist

| Checklist | Status | Proof |
|-----------|--------|-------|
| LIVE_LOOP_RUNBOOK relay subset | **PASS** | `relay-approval-e2e.sh` 2026-07-06 |
| chat-device-test-checklist §1–6 (automated subset) | **PASS** | TapInjection + Cursor suites |
| §7 APNs lock-screen (5c) | **Owner-gated** | Needs unlocked physical device + recording |
| Physical device build/install | **PASS** | iPhone 17 `557A7877…` |

---

## Superseded claims (do not cite)

- ~~"Cursor shell mock only on master"~~ — merged; live bridge on `master` / this branch.
- ~~"2 failing UI tests"~~ — 20/20 mock + 4/4 TapInjection + live approval test.
- ~~"APNs proven in gap matrix"~~ — re-prove 5c per runbook before ship.
