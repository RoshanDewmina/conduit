# Phase 9 — UX Simplification Recommendations

> Ranked, evidence-backed. Objective problems separated from subjective preferences.
> Cross-refs: feature-matrix, screen-inventory, IA, onboarding, visual-consistency reports.

## CRITICAL

### C1 — Value is gated behind an account/auth wall
- **Problem:** First-run shows an account fork (5 concepts) + auth form before the value hero. (onboarding-audit §1)
- **Evidence:** `AccountEntryView` copy; screenshots/onboarding.
- **Impact:** Highest drop-off risk; users decide before they understand.
- **Fix:** Value screen first; default to offline pairing; account becomes optional after setup.
- **Screens:** AccountEntry, OnboardingRedesign. **Backend change:** none (account-free pairing already supported).
- **Risk:** Low.

### C2 — Demo/seed data leaks into real empty states
- **Problem:** Home shows "2 agents need you / 2 conversations blocked" with **no machines connected**. (visual §V-4)
- **Evidence:** `screenshots/system-states/live-boot.png`.
- **Impact:** First impression is fake/confusing; undermines trust in the attention count (the core value signal).
- **Fix:** Gate demo counters behind `LANCER_SEED_DEMO`; show true zero-state ("Connect a machine to begin").
- **Backend change:** none.  **Risk:** Low.

## HIGH

### H1 — Agent-detail view sprawl (8 → 1)
- **Problem:** RunDetail, AgentDetail, AgentRunDetail, AgentExec, AgentFiles, AgentOrg, AgentWorkspace, Agents — overlapping. (screen-inventory §9)
- **Impact:** Maintenance + navigation confusion; unclear which opens when.
- **Fix:** One run view (transcript + files tab). Remove AgentOrg. **Backend:** none. **Risk:** Medium (verify call sites).

### H2 — Duplicate surfaces
- **Problem:** Keys vs SSH-keys; Settings-Audit vs Inbox-Activity; Paywall vs Premium-comparison; BridgeAuditFeed vs ActivityView. (IA-1)
- **Fix:** Merge each pair. **Backend:** none. **Risk:** Low.

### H3 — Inbox competes with Home for the same attention queue
- **Problem:** Two roots for "what needs you." (IA-6)
- **Fix:** Fold Inbox into Home as a filter/section; keep deep approval detail. **Backend:** none. **Risk:** Medium.

### H4 — DSButton `.primary` == `.accent`
- **Problem:** Identical render, stale "blue" doc; caused a past white-button bug. (visual §V-1)
- **Fix:** Collapse to one filled variant. **Backend:** none. **Risk:** Low.

## MEDIUM

### M1 — Settings overload (~20 → ~12 in 4 groups)
- One-action/no-op screens: Appearance (fixed-dark no-op), Sync status, Shortcut bar, Policy simulator. (IA-3, V-8)
- **Fix:** Group into Connection / Governance / Account&Billing / Advanced; drop Appearance; fold simulator into policy editor.

### M2 — Policy split across 3 places
- Onboarding preset, Settings→Autonomy, Settings→Policy editor/simulator. (IA-7)
- **Fix:** One Governance surface; preset is the friendly front, YAML editor the advanced tail.

### M3 — Async screens render blank >1.5 s
- New Chat, redesign onboarding, chat-overlays. (visual §V-3)
- **Fix:** Skeleton/placeholder component.

### M4 — SSH-setup wall-of-text in onboarding
- ~85 words of terminal instructions in first-run. (onboarding §6)
- **Fix:** Make contextual to "Add an SSH machine."

### M5 — Accessibility gaps
- ~30–50 unlabeled icon-only buttons; reduce-motion unwired. (visual §V-5)
- **Fix:** Labels + `\.accessibilityReduceMotion`. **Risk:** Low.

## LOW

- **L1** Two onboarding flows in code (remove legacy `OnboardingView`).
- **L2** `conduit→lancer` infra/string drift (migration-careful sweep).
- **L3** Off-scale paddings → snap to s0–s9 scale.
- **L4** 1× `.font(.system(size:))` regression in `E2ERelayStatusBadge`.

## Explicit action lists

**Remove (candidates):** legacy OnboardingView; AgentOrgView; Appearance settings (no-op); Premium-comparison (merge into paywall); BridgeAuditFeed (merge into Activity).

**Merge:** Keys↔SSH-keys; Settings-Audit↔Inbox-Activity; the 8 agent-detail views→1; Inbox→Home.

**Defer (V2, retain in code, unwire from nav):** hosted-cloud (Provisioning/RunnerStatus/RunnerSetup/SelfHostVsHosted/ProviderDetail); Loops (LoopDetail); Worktrees (Board/New/Conflicts); SFTP Files.

**Text to eliminate:** account fork tradeoff paragraph; SSH terminal instructions (→contextual); duplicated policy explanations.

**Reveal contextually:** account creation (after setup); SSH setup (when adding SSH host); YAML policy editor (advanced); secrets broker (when an agent requests one).

**Primary navigation change:** 6 roots → 4 (Home, New Chat, Machines, Settings); Inbox folds into Home.

**Onboarding reduction:** 5–7 → 3 required + 2 optional/contextual; value first.

**Core user journey (make unmistakable):** open → "N agents need you" → tap → approve/deny (or continue) → done. Everything else is secondary.

**Component consolidation:** one filled button; skeleton loader; true empty-state component.

## Subjective (flagged as preference, not defect)
- Editorial serif accents (Instrument Serif) — distinctive; keep. Whether "Good evening/your machines, in your pocket" tone fits a developer tool is a brand-voice call for Design, not an objective defect.
- Terracotta accent vs a cooler developer palette — brand decision.
