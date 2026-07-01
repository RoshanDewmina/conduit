# 15 — Implementation Roadmap

> Incremental plan to reach Direction A ([14](14-recommended-direction.md)). **No production code is changed by this audit.** Phases are ordered by dependency and user impact. Verification uses the project's authoritative gates (Xcode app-target build for iOS UI; `swift build`/`swift test` for LancerKit logic; `go test ./...` from `daemon/lancerd`). Sequence the **trust-integrity fixes first** — Direction A amplifies whatever state the home shows, so the home must stop showing fiction before it becomes the hero.

## Phase 0 — Preparation

- **Scope:** baseline + guardrails before any visual change.
- Preserve baseline screenshots (the 10 in `screenshots/current/` + capture the missing states: light, live-terminal w/ SSH harness, Dynamic Type AX5, Increase Contrast). Use the XcodeBuildMCP harness + env seams in [02](02-screen-and-component-inventory.md).
- **Add the 3 CI lints first** (cheapest, highest-leverage; stop debt growth): fail on `Color(.sRGB`/`Color(red:` and `.font(.system` outside `DesignSystem/`; warn on literal `cornerRadius:`/`.padding(<number>)` in feature code. ([12](12-design-system-recommendations.md))
- Inventory reusable components vs. duplicates (the consolidation list in [12](12-design-system-recommendations.md) §Consolidation).
- Add a visual-regression strategy (snapshot the core flows per scheme).
- **Dependencies:** none. **Risk:** low. **Verification:** lints run in CI; baseline screenshots committed. **DoD:** lints green on current tree (with the existing 152/155/142 grandfathered), baselines captured.

## Phase 0.5 — Trust-integrity fixes (do before the redesign)

These are the P0/P1 findings from [03](03-current-ui-audit.md); they are prerequisites because Direction A makes the home the hero.

- Remove **stubbed Governance numbers** (`AppRoot.swift:1390`) → bind to live stores or render "—"/empty. (P0-1)
- Reconcile **machine state** to one source (`connectionState(for:)`) across header/row/top-bar. (P0-2)
- Replace the **hard-coded sidebar footer** "Relay connected · 3 hosts" with live state. (P1-2)
- Fix **trust/billing copy** (SwiftData/RevenueCat → GRDB/StoreKit/Stripe). (P1-3)
- Resolve the **DEBUG billing contradiction** + load the StoreKit config. (P1-4)
- Pick **one pairing mental model** and use it everywhere. (P1-1)
- **Dependencies:** none. **Risk:** low-medium (touches wiring, not architecture). **Verification:** app-target build + screenshot each fixed surface shows live/empty state, not fiction. **DoD:** no surface displays a number/label the app can't back.

## Phase 1 — Core design system

- **Scope:** the token/component spine Direction A is built on.
- Collapse `DSButton.primary`→`.accent` (one filled brand button); **de-glass buttons** ([12](12-design-system-recommendations.md) §Liquid Glass).
- Deprecate `sp*`/`radius*` aliases → `s*`/`r1…r5`; cap content-card radius at `r2`.
- Standardize `DSMachineStatus` (glyph+word+last-seen, +`running`) and one severity-driven `RiskBadge` (word+glyph, never color-only).
- Body type → 17pt; confine mono to code surfaces; constrain all-caps.
- Consolidate headers (`DSDetailHeader`/`DSStatusHeader`) and fix the double back-chevron.
- Decide light/dark: ship `light/dark/system` default-dark, or ship dark-only-with-toggle-disabled but keep the light palette (verify the runtime force-override question in [12](12-design-system-recommendations.md) §On-device).
- **Dependencies:** Phase 0 (lints). **Expected files/modules:** `DesignSystem/Tokens.swift`, `Typography.swift`, `Components/DSButton.swift`, `Components/Primitives.swift`, `LancerGlassChrome.swift`. **Risk:** medium (broad but mechanical; lints prevent regression). **Verification:** app-target build + before/after screenshots of buttons, status rows, badges in both schemes + AX5. **DoD:** one filled accent button, status never color-only, glass only on chrome, ≥1/3 of raw-literal debt burned down.

## Phase 2 — First core workflow: the governed approval

**The single highest-value flow to redesign first** — it's the product's core loop, the differentiator, and the place current friction is most under-gated.

- **Scope:** one shared approval anatomy; severity-sentence layer (risk×kind); **up-gate high/critical Approve** (action-sheet / mandatory biometric; Deny as default); **patch diff drill-in**; "Allow for this session" scope; notification-action gating (`.authenticationRequired`, critical=Review-only); Watch = low/med approve + universal deny + stop; freshness/expired + already-resolved states; audit records decidedBy/biometricConfirmed/matchedRule.
- **Dependencies:** Phase 1 (`RiskBadge`, sheets, buttons). **Expected files:** `InboxFeature/InboxView.swift`, `DesignSystem/Components/InboxApprovalDetail.swift`, `PersistenceKit/ApprovalRepository.swift`, `SecurityKit/BiometricGate.swift`, `LancerCore/{Approval,ApprovalSummary,WatchApprovalTransfer}.swift`, notification handler. **Risk:** medium-high (security-sensitive; behavior changes need `swift test`). **Verification:** app-target build + `swift test` (`ApprovalParity`/`Reliability`/`ColdLaunch`/`WatchApprovalTransfer`); manual: high/critical can't be one-tap-approved; diff drill-in opens; session scope expires; already-resolved shows "Already handled". **DoD:** every consequential action is risk-tiered, accessible (icon+word, VoiceOver consequence hints), and audited.

## Phase 3 — Remaining primary flows (ordered by impact + dependency)

1. **Command Home** — Act Now / Continue / Machines bands + live status + New-run CTA + calm zero-state. (Depends on Phase 0.5 + 1 + 2.)
2. **Machines / Fleet** — adaptive board/switcher; RELAY/DIRECT capability anchor; per-machine activity. (Depends on `DSMachineStatus`.)
3. **Run (chat) thread** — context chips, work timeline, evidence cards, block transcript + follow-up + Stop, collapsible long output. (Reuses the rich `NewChatTabView`/`ChatConversation` model.)
4. **Activity / audit** — contextual (global + per-machine), `{actor}{action}{target}`, `DSDiffChips`, date grouping, link-back-to-session; export stays in `AuditView`.
- **Risk:** medium. **Verification:** app-target build + per-flow screenshots (both schemes, AX) + relevant `swift test`. **DoD:** each flow matches [14](14-recommended-direction.md), no dead/inert controls, status integrity preserved.

## Phase 4 — Onboarding and monetization

- **Scope:** rebuild first-run as the trust checklist ([10](10-onboarding-and-pairing.md)); shared setup-checklist component (onboarding + Home empty + Settings → Connection); contextual permissions; **wire the dead paywall** at scale/automation triggers + persistent Settings row; enable Family Sharing; ensure restore always reachable.
- **Dependencies:** Phase 2 (demo approval), Phase 3 (Home). **Validation requirements:** **prove StoreKit sandbox purchase + restore before App Review** (outstanding per §0.1); device proof of the push-while-closed approval loop (already passed once — re-verify post-redesign); decide the Free/Pro split and gate features. **Risk:** medium (App Review exposure). **Verification:** app-target build; sandbox purchase + restore on device; onboarding time-to-value measured (<3/<6 min). **DoD:** first run reaches a governed approval without a paywall; Pro gates the agreed scale/automation features; restore + manage paths visible.

## Phase 5 — Polish and accessibility

- **Scope:** finish the raw-literal burn-down; full Dynamic Type (AX5) + VoiceOver + contrast pass in both schemes + Increase Contrast; Smart Invert handling for destructive controls; Reduce Motion/Transparency fallbacks; motion/haptics map; native-vs-custom cleanup; running-agent Live Activity (post-V1 glance, HIG-bounded) once relay→push latency is proven.
- **Device Hub test configs:** small iPhone, large iPhone, iPad split-view; light/dark; default + AX5 Dynamic Type; Increase Contrast; Reduce Motion; Reduce Transparency; Smart Invert; offline/disconnected; long agent/host names. (APNs/Watch/lock-screen require physical-device proof.)
- **Dependencies:** Phases 1–4. **Risk:** low-medium. **Verification:** app-target build + the Device Hub matrix screenshots diffed against baselines + reference. **DoD:** zero color-only status, zero `.font(.system…)`/raw-color in feature code, all four reduce-* paths verified, core flows pass the matrix.

## Cross-phase definition of done

For every phase: scope stated · dependencies satisfied · expected files identified · authoritative gate run with **output shown** (not "should work") · required screenshots captured (both schemes where visual) · no dead code / inert controls / back-compat shims introduced.

## Sequencing rationale (one line)

Lints → trust-integrity → design-system spine → the approval loop (core differentiator) → the surfaces that depend on it → onboarding/monetization (App-Review-gated) → accessibility polish. Each phase ships independently and is screenshot-verifiable; nothing later blocks on hosted-cloud (V2).
