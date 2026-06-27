# Phase 7 — Visual Consistency & Design-System Audit

> Compared against the strongest screens (Home, New Chat, Inbox-typed, the component catalog).
> Evidence: `DesignSystem/Tokens.swift`, `Typography.swift`, `Components/*` + screenshots. Read-only.

## Overall verdict
The design system is **strong and well-adopted** — a real, opinionated editorial dark theme with a
4-font system, a full token palette, and ~42 reusable components with high adoption on the critical
approval/inbox/status paths. The weak spots are **drift, not absence**: off-scale spacing, a
confusing button variant, late-loading screens, and accessibility gaps. This is a system to **tighten,
not replace.**

## Strengths (keep)
- **Color tokens** (`Tokens.swift`): full surface/text/accent/semantic ramps + independent risk ramp + 5 user accent themes + always-dark terminal/HUD contexts. Observed rendering is **dark** across all captured screens.
- **Typography** (`Typography.swift`): Bricolage Grotesque (display) · Hanken Grotesk (body) · JetBrains Mono (technical) · Instrument Serif italic (editorial accents like "Good evening"/"in your pocket"). All via `dsXxxPt(…, relativeTo:)` helpers → **Dynamic Type supported**, capped at `accessibility3` to protect layout.
- **Components:** DSButton, DSCard, DSChip, DSNavigationRow, DSSectionGroup, DSStatusHeader, DSDetailHeader, DSDecisionSheet widely adopted (DSButton 348+ uses). Approval/inbox/connection flows are highly componentized.
- **Strongest screens:** Home (editorial serif + warm attention card), New Chat (chat + code/diff/terminal cards), Inbox-typed (approval cards with risk ramp). These define the target language.

## Issues (ranked)

| # | Issue | Evidence | Severity |
|---|---|---|---|
| V-1 | **DSButton `.primary` == `.accent`** (both terracotta); the in-code doc still says "primary is electric blue." Two variants, identical render → misuse risk (this caused the past white-button bug per memory). | DSButton.swift | High |
| V-2 | **Off-scale spacing.** ~50–60% of `.padding` calls use non-token values (10/14/18/22) ±1–2 pt off the s0–s9 scale. 115× `padding(.horizontal,18)`, 57× `…,14`, 50× `…,10`. | grep counts | Medium |
| V-3 | **Late-loading / empty-on-entry.** Several core screens (New Chat, redesign onboarding, chat-overlays) render blank for >1.5 s (fade-in/async) — no skeleton/placeholder. Reproduced during Phase-4 capture. | coverage-note | Medium |
| V-4 | **Seed/demo data leaks into real empty states.** Live Home shows "2 agents need you / 2 conversations blocked" with **zero machines connected** ("Connect a machine"). | live-boot.png | High |
| V-5 | **Accessibility gaps.** ~30–50 icon-only buttons lack `accessibilityLabel` (terminal chrome, settings gears, copy/overflow); **reduce-motion not wired** (PixelBox, AttentionFlashRing, status bar animate regardless). | DS Explore pass | Medium |
| V-6 | **Branding drift (low, mostly non-visible).** Infra strings still `conduit-*` (RelaySettings `wss://conduit-push…`, HostServiceClient `~/.conduit` fallback, PurchaseManager `dev.conduit.appAccountToken`, stale comments). No user-visible "Conduit" copy found. | DS Explore pass | Low |
| V-7 | **One-off bypasses.** ~50 hard-coded colors (mostly intentional onboarding hero gradients + agent risk colors) and 1 `.font(.system(size:))` regression in `E2ERelayStatusBadge.swift`. | DS Explore pass | Low |
| V-8 | **Appearance setting likely a no-op.** App renders fixed-dark in practice; Settings exposes Appearance (light/dark/auto) + Accent — Appearance toggle has no visible effect. | live screenshots + inventory SET-3 | Low |

## Consistency across screens
- **Cards/sheets/headers** are consistent (DSCard, DSDetailHeader, DSDecisionSheet everywhere). No screen "feels like a different app" among the core surfaces.
- **Density drift** is the main cross-screen inconsistency (V-2): lists and settings rows vary by 1–2 pt paddings.
- **Text compensating for visuals:** onboarding account/SSH screens lean on paragraphs where an image/animation would do (ties to Phase 6).

## Recommended design-system actions (for the brief, not now)
1. Collapse DSButton `.primary`/`.accent` to one filled variant; fix the doc comment. (V-1)
2. Snap paddings to the s0–s9 scale; document any deliberate density exceptions. (V-2)
3. Add a standard skeleton/loading component; apply to async screens. (V-3)
4. Separate demo counters from real data; show true empty states. (V-4)
5. Label icon-only buttons; read `\.accessibilityReduceMotion` in animated components. (V-5)
6. Finish `conduit→lancer` string sweep (infra + keys, with migration care). (V-6)
