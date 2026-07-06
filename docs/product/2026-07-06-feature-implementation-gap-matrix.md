# Lancer Feature Implementation Gap Matrix

Compiled: 2026-07-06  
Canonical source: [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md)  
Scope: Tier 0 phone-usable loop + Cursor shell coverage audit

> **Away Mode pivot descoped (2026-07-06):** Rows below may use legacy "Away …" feature names from
> wireframes. The underlying capabilities remain tracked; only the Away Mode brand/pivot is retired.
> See `docs/_archive/away-mode-2026-07/README.md`.

## Executive summary

| Layer | Status |
|-------|--------|
| **Real backend (master)** | Governed loop shipped: pair → dispatch → approve → audit. Chat, relay, policy, biometric gate all wired. |
| **Cursor UI shell (worktree)** | 34 Swift files, 22 UI tests, 100% mock data, DEBUG-only entry. |
| **Gap** | Cursor shell needs Tier 0 wiring to existing `AppFeature`/`RelayKit`/`InboxFeature` seams. |

**Tier 0 exit criteria:** send prompt from phone → receive approval → approve → follow-up works through Cursor shell with real `lancerd`.

---

## Tier 0 — Phone-usable today (wire first)

| Feature | Master (real code) | Cursor shell | Action |
|---------|-------------------|--------------|--------|
| Pairing (E2E relay + `lancerd pair`) | **Shipped** — `OnboardingRedesignGalleryView`, `E2ERelayClient` | **Mock** — `CursorOnboardingView` step counter | Wire real pairing |
| Workspaces list | **Partial** — `FleetView` host-first, no `CursorWorkspacesView` on master | **Mock** — seeded repos | Wire `FleetStore`/`RelayFleetStore` |
| Thread list | **Shipped** — `ChatConversationRepository` | **Mock** — seeded threads | Wire conversation repo |
| Composer → dispatch | **Shipped** — `NewChatTabView.performDispatch` | **Mock** — local sheet only | Wire dispatch path |
| Approvals | **Shipped** — `InboxViewModel`, `ApprovalRelay`, `ApprovalDecisionAuth` | **Mock** — local `@State` | Wire `decide()` + biometric |
| Follow-up / continue | **Shipped** — `performContinueConversation` | **Mock** — composer no-op send | Wire continue path |
| Settings / policy | **Shipped** — `SettingsWithLibraryView`, `PolicyHomeView` | **Mock** — `CursorSettingsView` rows | Embed real settings |

---

## Tier 1 — MVP UI already mocked in Cursor shell

| Feature | Shell status | UI tests |
|---------|-------------|----------|
| Onboarding flow (5 steps) | wireframed-mock | 4 tests |
| Workspaces → thread list → work thread | wireframed-mock | 8 tests |
| Approval review (approve/deny/reply) | wireframed-mock | 4 tests |
| PR detail + inline diff | wireframed-mock | 1 test |
| Search overlay | wireframed-mock | 1 test |
| Profile drawer + settings sheet | wireframed-mock | 3 tests |
| Composer chain (run-on, model) | wireframed-mock | 2 tests (2 failing) |

---

## Tier 2 — MVP not in Cursor shell

| Feature | Master | Cursor shell |
|---------|--------|--------------|
| Away Digest home (needs-you-first) | Partial — `LancerHomeView` attention cards | `CursorHomeView` exists but **not wired** |
| Away Launch Composer + launch contract | Missing | Generic composer only |
| Proof Suite / Proof Reel | Missing (design stub only) | Mock artifact cards in work thread |
| Mobile QA Annotation | Missing | Not present |
| Question Cards + Ladder | Missing | Not present |
| Git/PR/Merge ship actions | Missing | PR detail mock only |
| Flight Recorder + Work Search | Missing | Search overlay mock only |

---

## Tier 3 — Post-MVP / rejected

Per master plan §6–§8. See [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md).

---

## Correctness gaps (must fix before MVP ships)

| Gap | Severity | Status |
|-----|----------|--------|
| Biometric gate degrades open on no-passcode devices | P0 | Open |
| Emergency Stop not atomic | P0 | Open |
| JWT HS256-only | P1 | Open |
| Dormant StoreKit vs Stripe entitlement | P1 | Open |
| Watch app not embedded | P1 | Open |
| Daemon single pairing-slot ceiling | P2 | Open |

---

## Operational checklist cross-check

| Checklist | Master | Cursor shell |
|-----------|--------|--------------|
| LIVE_LOOP_RUNBOOK SSH subset | Proven sim + device C2 | Not wired |
| chat-device-test-checklist §1–6 | Shipped in sidebar app | Mock only |
| chat-device-test-checklist §7 (APNs lock-screen) | Proven 2026-06-23 | Not wired |

---

## Recommended sequencing

1. Fix 2 failing UI tests → 22/22 green
2. Commit + merge Cursor shell to master
3. Wire Tier 0 (7 screens → real backend)
4. Simulator E2E: pair → dispatch → approve → follow-up
5. Physical device: APNs lock-screen approve (stretch)
