# Lancer Feature Implementation Gap Matrix

Compiled: 2026-07-06  
Updated: 2026-07-08 (evening) — Layers 0–4 + A3 R1–R4 merged on `master` (`732071a7`); D0.2 / 5c physical-device gate **PASS**.  
Canonical source: [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md)  
Scope: Tier 0 phone-usable loop + Cursor shell coverage audit

## Executive summary

| Layer | Status |
|-------|--------|
| **Real backend (master)** | Governed loop shipped: pair → dispatch → approve → audit. Receipt pipeline (`lancer.proof/v0`), question/Ladder events, gated ship actions, observed-session relay mirror on tree. No biometric gate — removed entirely 2026-07-07 (permanent). |
| **Cursor UI shell (master)** | Merged under `AppFeature/CursorStyle`; A3 design tokens (#57) + A2 dead-code cleanup (#55) + R1–R4 surface rebuild (#63–#66) landed. |
| **Live Cursor shell** | `LANCER_CURSOR_SHELL_LIVE=1` routes through `AppRoot` for pairing, conversation-backed workspace/thread hydration, dispatch, continue, approval decisions, receipts, question cards, and real Settings handoff. |
| **Gap** | **D0.2 / 5c closed** — evening PASS ([`test-runs/2026-07-08-tier0-5c-retest-results.md`](../test-runs/2026-07-08-tier0-5c-retest-results.md)); fix committed `732071a7`. Next: Away Launch Composer. |

**Tier 0 exit criteria:** send prompt from phone → receive approval → approve (including lock-screen 5c) → follow-up works through Cursor shell with real `lancerd` on physical device.

---

## Tier 0 — Phone-usable today (wire first)

| Feature | Master (real code) | Cursor shell | Action |
|---------|-------------------|--------------|--------|
| Pairing (E2E relay + `lancerd pair`) | **Shipped** — `OnboardingRedesignGalleryView`, `E2ERelayClient` | **Live bridge callback** opens real `E2ERelayPairingView` | E2E verify from live shell |
| Workspaces list | **Shipped** — `ChatConversationRepository` + relay fleet state elsewhere | **Partial live** — conversation-backed repo rows + `All Repos` aggregate | Add relay host health when needed |
| Thread list | **Shipped** — `ChatConversationRepository` | **Live** — per-repo and all-repo rows from recent conversations | E2E verify select → continue |
| Composer → dispatch | **Shipped** — `AppRoot.performDispatch` | **Live callback** calls `performDispatch` | E2E verify daemon launch |
| Approvals | **Shipped** — `InboxViewModel`, `ApprovalRelay` (no biometric gate — removed 2026-07-07) | **Live callback** calls `decide()` | E2E verify |
| Follow-up / continue | **Shipped** — `performContinueConversation` | **Live callback** calls `performContinueConversation` | E2E verify follow-up |
| Settings / policy | **Shipped** — `SettingsWithLibraryView`, `PolicyHomeView` | **Live handoff** opens real Settings from Cursor settings rows | Keep policy edits in real Settings |

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
| Away Digest home (needs-you-first) | **Shipped** — attention ordering (#34 Lane C) | Wired in live shell |
| Away Launch Composer + launch contract | Missing | Generic composer only — **next lane** (D0.2 gate closed) |
| Proof Suite / Proof Reel | **Shipped** — Proof Reel H1 (#51) over run receipts | ReceiptCardView + replay scrubber |
| Mobile QA Annotation | Missing | Not present |
| Question Cards + Ladder | **Shipped** — E1 events (#49) + E2 QuestionCardView (#44) + E3 voice-answer (#45) | Wired in live shell |
| Git/PR/Merge ship actions | **Shipped** — gated branch/commit/PR (G, #50) | Daemon RPC; UI partial |
| Flight Recorder + Work Search | Partial — CoreSpotlight I2 (#41) | Search overlay still mock-heavy |
| Siri fast-follow (I1–I3, D2/D3) | **Shipped** — #38, #41, #43, #46, #45 | iOS 27 APIs gated `swift(>=6.4)` |
| Observed sessions + Return-to-Desk | **Shipped** — J1 (#54), J2 (#58), J3 (#59) | "On your Mac" + continuity packet |

---

## Tier 3 — Post-MVP / rejected

Per master plan §6–§8. See [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md).

---

## Correctness gaps (must fix before MVP ships)

| Gap | Severity | Status |
|-----|----------|--------|
| Biometric gate degrades open on no-passcode devices | P0 | **Moot** — removed entirely 2026-07-07 (`9e18d679`); nothing left to validate |
| Emergency Stop not atomic | P0 | **Fixed** (`531685b6`) — daemon latch + RPC |
| JWT HS256-only | P1 | Open |
| Dormant StoreKit vs Stripe entitlement | P1 | Open |
| Watch app not embedded | P1 | **Cut** — owner decision Jul 8 |
| Daemon single pairing-slot ceiling | P2 | Open |

---

## Operational checklist cross-check

| Checklist | Master | Cursor shell |
|-----------|--------|--------------|
| LIVE_LOOP_RUNBOOK SSH subset | Proven sim + device C2 | Needs live-shell rerun |
| On-device QA (legacy chat-device checklist, purged 2026-07-06) §1–6 | Shipped in legacy sidebar; Cursor live shell partial | Needs live-shell rerun |
| On-device QA §7 (APNs lock-screen) | **PASS** (2026-07-08 evening) — [`test-runs/2026-07-08-tier0-5c-retest-results.md`](../test-runs/2026-07-08-tier0-5c-retest-results.md) | Fix committed `732071a7` |

---

## Recommended sequencing

1. **Away Launch Composer** — dedicated launch-setup surface + contract chips (`04-launch-setup.html`).
2. Layer 4 exit bar gaps: `relay-approval-e2e.sh` question round-trip, owner device question-loop proof, dual-SDK build check, fresh exhaustive UI screenshots post-A3.
3. P1 billing reconciliation (StoreKit vs Stripe) before external beta.

---

## Consolidated status notes (folded from `2026-07-06-lancer-consolidated-status.md`, deleted 2026-07-08)

**Core product decision:** V1 wedge is phone steers/reviews/approves/continues — not a phone IDE.
Tier 0 exit: pair → dispatch → approval (incl. 5c lock-screen) → follow-up on physical device — **5c PASS** 2026-07-08 evening (`732071a7`). Most Tier 2 lanes merged Jul 7–8; Away Launch Composer next; Watch cut.

**Worktree warning:** do **not** wholesale-merge `.claude/worktrees/amazing-mayer-246fef` — deletion-heavy
diff; cherry-pick verified slices only. See
[`docs/design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md`](../design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md).

**Stale doc reminders:** iOS deployment target is **26.0** (`project.yml`); Cursor shell + Layers 0–4 + A3 on
`master` (`732071a7`); tab bar / Control / Activity roots are vestigial; legacy sidebar / Command Home is **deleted**.

**Recommended next actions:**
1. Away Launch Composer lane (`04-launch-setup.html`).
2. Layer 4 exit bar: question round-trip e2e + owner device question-loop proof.
3. Do not wholesale-merge `amazing-mayer`.
4. P1 billing reconciliation before external beta.
