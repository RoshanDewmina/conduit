# Lancer Feature Implementation Gap Matrix

Compiled: 2026-07-06  
Updated: 2026-07-06 — Cursor shell landed on master; live bridge wiring has begun.  
Canonical source: [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md)  
Scope: Tier 0 phone-usable loop + Cursor shell coverage audit

## Executive summary

| Layer | Status |
|-------|--------|
| **Real backend (master)** | Governed loop shipped: pair → dispatch → approve → audit. Chat, relay, policy all wired. No biometric gate — removed entirely 2026-07-07 (permanent). |
| **Cursor UI shell (master)** | Merged under `AppFeature/CursorStyle`; seeded prototype remains under `LANCER_CURSOR_SHELL=1`. |
| **Live Cursor shell** | `LANCER_CURSOR_SHELL_LIVE=1` routes through `AppRoot` for pairing, conversation-backed workspace/thread hydration, dispatch, continue, approval decisions, and real Settings handoff. |
| **Gap** | Tier 0 live-shell proof still needs real daemon/relay E2E: pair → dispatch → approval → follow-up. |

**Tier 0 exit criteria:** send prompt from phone → receive approval → approve → follow-up works through Cursor shell with real `lancerd`.

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
| Biometric gate degrades open on no-passcode devices | P0 | **Moot** — removed entirely 2026-07-07 (`9e18d679`); nothing left to validate |
| Emergency Stop not atomic | P0 | **Fixed** (`531685b6`) — daemon latch + RPC |
| JWT HS256-only | P1 | Open |
| Dormant StoreKit vs Stripe entitlement | P1 | Open |
| Watch app not embedded | P1 | Open |
| Daemon single pairing-slot ceiling | P2 | Open |

---

## Operational checklist cross-check

| Checklist | Master | Cursor shell |
|-----------|--------|--------------|
| LIVE_LOOP_RUNBOOK SSH subset | Proven sim + device C2 | Needs live-shell rerun |
| On-device QA (legacy chat-device checklist, purged 2026-07-06) §1–6 | Shipped in legacy sidebar; Cursor live shell partial | Needs live-shell rerun |
| On-device QA §7 (APNs lock-screen) | Proven 2026-06-23 (`ARCHITECTURE.md` §0.1) | Needs live-shell rerun |

---

## Recommended sequencing

1. Keep Tier 2/Away/Proof expansion frozen until Tier 0 live shell is proven.
2. Complete live-shell E2E on simulator: pair → dispatch → approve → follow-up.
3. Fix or formally gate the remaining P0 beta blocker: atomic Emergency Stop (biometric gate P0 is moot — removed entirely 2026-07-07).
4. Physical device: APNs lock-screen approve through the live shell before external beta.

---

## Consolidated status notes (folded from `2026-07-06-lancer-consolidated-status.md`, deleted 2026-07-08)

**Core product decision:** V1 wedge is phone steers/reviews/approves/continues — not a phone IDE.
Tier 0 exit: pair → dispatch → approval → follow-up against real `lancerd`. Freeze Tier 2 until proven.

**Worktree warning:** do **not** wholesale-merge `.claude/worktrees/amazing-mayer-246fef` — deletion-heavy
diff; cherry-pick verified slices only. See
[`docs/design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md`](../design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md).

**Stale doc reminders:** iOS deployment target is **26.0** (`project.yml`); Cursor shell is merged on
`master`; tab bar / Control / Activity roots are vestigial; legacy sidebar / Command Home is **deleted**.

**Recommended next actions:**
1. Owner manual proof on physical iPhone with live shell + `lancerd` ([`LIVE_LOOP_RUNBOOK.md`](../LIVE_LOOP_RUNBOOK.md)).
2. Device-tolerant live-shell UI test; relay E2E for Cursor-shell approval surface.
3. Cherry-pick from `codex/tier-0-live-cursor-shell` — do not wholesale-merge `amazing-mayer`.
4. Hold Tier 2 until B10 in publish checklist is closed.
