# 12 — Design System Recommendations

> Source: Wave-2 design-system/accessibility/identity research (Apple HIG + WWDC25 + App Store Connect + Mobbin GitHub-iOS + repo grounding). Toolchain: Xcode 27 / iOS 27 beta (Liquid Glass era). **Beta caveat:** treat specific `glassEffect` behavior as subject to change; re-verify against shipping iOS 27.

## Executive thesis

**Lancer's design problem is not missing primitives — it is uneven adoption of a system that is already good.** The `DesignSystem` module ships a complete, semantic, scheme-adaptive token set, a relative-scaled type system, and ~30 components. The known debt (~152 `.font(.system…)`, ~155 raw `Color(.sRGB…)`, ~142 literal `cornerRadius: N`) is **bypass, not absence**. The primary recommendation is **consolidation and enforcement**, not new design. Three substantive decisions sit on top: ship light + dark (default dark); pull Liquid Glass back to the navigation layer; adopt one recognizable identity.

> **Correction to a stale assumption:** prior notes call the app "fixed-dark." The code actually ships a **complete tuned light palette** plus a `LancerAppearance { light, dark, system }` enum. The runtime may currently force dark, but the light system is built and maintained (see §Light/Dark).

## Identity thesis — "the warm control room"

| Product | Identity |
|---|---|
| Claude / ChatGPT | conversational warmth; warm off-white/near-black, rounded bubbles, a clay/terracotta accent **very close to Lancer's current accent** |
| Linear | cold precision; graphite + indigo/violet, tight grid, hairlines |
| Raycast | neon-on-black launcher; saturated multicolor, glow |

**The risk:** Lancer's current defaults (terracotta accent + warm sand + conversational chat shell + rounded 16–20pt radii) read as "Claude for agents." The five-theme accent picker makes it worse — indigo/violet land on Linear, neon emerald near Raycast.

**The thesis (Confidence: High):**

> **"The warm control room."** A calm, paper-and-sand chrome surrounds one intentionally darker, technical *working surface* (the terminal/code). Warmth signals trust and human judgment; the dark terminal signals real machinery. Editorial restraint signals a serious operations product.

Ownable because: warm-neutral (not cold like Linear); a first-class **always-dark terminal "hero" framed by calmer chrome** (neither Claude nor Linear has this surface-hierarchy contrast — protect it); **monotone + shape status language** (not Raycast's rainbow); one restrained editorial serif cue used sparingly.

**Differentiation: Claude = chat warmth · Linear = cold precision · Raycast = neon launcher · Lancer = warm operations room with a dark machine at its center.**

**Accent picker (Confidence: Med-High):** drop indigo + violet (they pull onto Linear); keep **terracotta as the canonical brand accent**, offer at most one non-neon cool alternate, and frame it as accessibility, not "themes."

## Semantic colours

The token set is good: 8 surface roles, a 4-step text ramp + on-dark, an explicit accent family, soft-fill pairs for every semantic, and — notably — a **monotonic `risk(0…3)` ramp deliberately independent of `accent`** so a medium-risk badge can't be confused with an affirmative CTA. **Keep the risk ramp exactly as is.**

Rules:
- **Freeze the palette; ban new raw color literals in feature code.** Allowed raw sites: `Tokens.swift` + the always-dark `DI`/`term`/`hud` families only.
- **Drive migration with a CI lint** (`Color(.sRGB`/`Color(red:` outside `DesignSystem/` fails), not a one-time sweep — the lint stops regression immediately.
- **Verify dark-mode contrast** specifically: `text3 #7e7a6e` on `bg #191917` is the row most at risk — confirm ≥4.5:1 body / ≥3:1 large, and again under Increase Contrast. Keep `info #2f43ff` out of status contexts (competes with the warm accent).

## Typography roles

The scale and `relativeTo:` Dynamic-Type pattern are correct. Five custom faces is over-rich. **Three load-bearing roles + one rare accent:**
1. **Sans (Hanken)** — body, controls, lists. Make primary reading body **17pt** (Apple default); keep 16 only for dense secondary contexts.
2. **Mono (JetBrains)** — terminal/code/diff/paths/hashes/IDs/kbd **only**. Never UI chrome. *This single rule is the strongest guard against the "cyberpunk console" failure mode.*
3. **Display (Bricolage)** — large screen titles + empty-state headlines only.
4. **Serif (Instrument Serif italic)** — **rare** editorial accent, ≤~3 screen types. Identity spice, not a role.

**Ban `.font(.system…)` in feature code** via lint → route through `dsSans/dsMono/dsDisplay` (highest-leverage type fix). **Constrain all-caps** to short section labels (≥11pt, via `.textCase` over normal-case strings — already correct, VoiceOver-safe). Audit `dsSize` against AX5 sizes (verify side-by-side header buttons + fixed-width badge slot degrade gracefully).

## Spacing scale

4-based `s0…s9` is sound. **Deprecate the `sp*` aliases** (two vocabularies invite drift); canonical = `s*`. Document 3 layout rhythms: row padding (`s4`/12), card padding (`s5`/16), section gap (`s6`–`s7`).

## Corner-radius strategy

**Two radius languages by surface role:**
- **Chrome / floating / glass** (sidebar, AgentIsland, sheets, primary buttons): soft/continuous `r4`–`r5`, capsule where apt (matches Liquid Glass concentricity).
- **Content / technical surfaces** (terminal blocks, diff cards, list rows): tighter `r1`–`r2` (10–12).

**Cap content-card radius at `r2`/12** — reserve 16–30 for chrome only. Cheap, high-impact move against the "soft Claude" read. Delete stale `radius*` aliases. Always `.continuous`.

## Surface hierarchy

Border-and-value elevation (not shadows) is the right, Liquid-Glass-compatible choice. **Codify 4 levels, forbid arbitrary shadows:** (0) page `bg`; (1) `surface` cards + `border`; (2) `surface2` raised + `borderStrong`; (3) **glass chrome only**. **No nested cards** (a card is a leaf; group rows with dividers). Inputs use `surfaceSunk` (sunk inputs, raised controls).

## Liquid Glass / materials policy

Glass is well-contained (8 call sites) **except** `DSButton` applies `glassEffect` to **every button** — a direct HIG "don't use Liquid Glass in the content layer." HIG: glass is for the **navigation layer**, used **sparingly**, never glass-on-glass.
- **Remove glass from `DSButton`** → solid accent fill (a primary action should read solid/confident).
- **Reserve glass for chrome only:** sidebar/Command Home shell, floating **AgentIsland**, **PersistentStatusBar**, sheet grabber.
- **Honor Reduce Transparency** → glass falls back to solid `surface`/`hudBg`; verify the iOS path (the macOS branch already falls back to `.ultraThinMaterial`).

## Button hierarchy

`primary` and `accent` are **visually identical** (dead redundancy + the documented "white-button" footgun). **Collapse to one filled brand variant:** keep `.accent` (solid terracotta, white fg) as the single high-emphasis CTA; remove/alias `.primary`. **Final 4-level hierarchy:** `accent` (filled, one per view) → `secondary` (line) → `ghost` (bare) → `quiet`/`destructive`. **Destructive = outline danger, never filled-danger** (filled red invites mis-taps and is what Smart Invert flips wrong). 44×44 min already enforced — keep.

## Status / severity / badges

**Every status carries icon + shape + (optional) label — color is reinforcement, never the sole channel.** Fix the flagged color-only dots: pair each with an SF Symbol (`checkmark.circle.fill` ok, `exclamationmark.triangle.fill` warn, `xmark.octagon.fill` danger). **One severity vocabulary app-wide** (risk 0–3 → ok/warn/orange/danger across approvals, drift, blast-radius, CI). **Badges quiet by default** (soft fill + small label); reserve saturated solid fills for the one thing demanding action (a pending approval). Keep the fixed-width trailing badge slot invariant.

## List / card rules

**Default to native-feeling grouped lists (rows + dividers), not stacks of cards.** Card surface only for standalone tappable objects (a host, an approval, a session). **Row anatomy standard:** leading status glyph (24pt) · title (sans) · optional mono metadata · trailing fixed-width badge/chevron. **Card budget ≤2 distinct card types visible at once.** One level of caps section headers.

## Sheets / modals

**Use native `.sheet` + detents** for approvals/reviews (half/large, grabber, swipe-dismiss) — the approval flow is the core loop and native mechanics + accessibility beat a custom drawer. Glass on sheet chrome/grabber only, solid content within. **Destructive confirmations** → native `confirmationDialog`/alert (system handles VoiceOver focus, Smart Invert, destructive role). **Consolidate `DSDetailHeader`/`DSStatusHeader` into one header** and fix the **double back-chevron** polish bug.

## Code / terminal / diff presentation

- **Mono is a domain signal, not a style** (terminal/code/diff/paths/refs/SHAs/IDs/kbd only).
- **Diffs:** background tint (`okSoft`/`dangerSoft`) **plus** a leading `+`/`-` gutter glyph — never color-only (deuteranopia + Smart Invert). `DSDiffChips` for compact transitions; full +/- view on the detail surface.
- **Terminal typography:** mono ~13–14pt, scales via `relativeTo:` but **caps** the top AX sizes so column alignment survives (document the cap). **Horizontal scroll** for long code/log lines (don't wrap mid-token/path/hash). **Selectable + copyable** everywhere (also a VoiceOver win).

## Empty / loading / error / offline states

Four templates, one component family: **Empty** (icon + display headline + one `accent` action), **Loading** (skeleton rows matching real row geometry — not a center spinner for list content), **Error** (cause + retry, never a dead end), **Offline** (explicit "hold on unreachable" — matches the fail-closed posture; tell the user the agent is held, don't fake success). Route `DSOfflineState`/`DSApprovalBanner`/`InboxApprovalCard`/`ChatInputBar` through `dsSans/dsMono` (lint burn-down). Copy is calm and specific ("Can't reach mac-mini — approval held").

## Motion & haptics

**Motion is functional, not decorative** — show state change (agent idle→working→awaiting-approval on AgentIsland/PixelBox) and spatial continuity (sheet, list insert). No ambient glows/pulsing accents/animated gradients ("cyberpunk", battery). Durations ~0.12–0.2s control feedback (already), spring for sheets/island. **Honor Reduce Motion** (cross-fades, static PixelBox, no parallax). **Haptics map to governance gravity, sparingly:** `.success` = approval granted/step complete; `.warning` = approval *requested*; `.error` = stopped/failure/revoke; light `.impact` = toggles. **No haptic on routine streaming tokens** — restraint is part of "calm authority."

## Icons

**SF Symbols by default** (free Dynamic Type, weight matching, accessibility names), hierarchical/monochrome tuned to the text ramp. **Custom glyphs only for identity:** `PixelAvatar` (host identity differentiator — keep) and `PixelBox` (agent-state — keep, but add a Reduce-Motion static state + text/VoiceOver equivalent). Match symbol weight to adjacent text; label meaningful icons, `.accessibilityHidden` decorative ones.

## Light / dark — ship both, default dark

App Store Connect's Dark Interface criteria **do not require a light mode** (claim Dark Interface if dark-by-default or user-controllable). But light is a **product/accessibility asset** and the cost is mostly paid (the tuned light palette already exists): some low-vision users find gray-on-black harder; one-handed daylight use favors light. **Ship `light/dark/system`, default dark; keep terminal/HUD/island always-dark in both schemes.** Gate on: full contrast pass on light + dark-with-Increase-Contrast, Smart Invert handling for destructive controls, both-scheme screenshot QA (in-app `LancerAppearance` toggle — `simctl ui appearance` changes the system setting but has no effect because the app currently forces `.preferredColorScheme(.dark)` at scene level; to test light mode, use the in-app toggle). If timeline forces dark-only at V1: keep the light palette in-tree, ship the toggle disabled, claim Dark Interface, re-enable light shortly after.

## Native vs custom decision table

| Element | Verdict | Rationale |
|---|---|---|
| Lists / grouped rows | **Native** (restyled) | Free a11y/Dynamic Type/swipe |
| Sheets / detents / dialogs | **Native** | Approval loop needs bulletproof focus/dismiss/Smart-Invert |
| Buttons | **Custom `DSButton`** | Brand fill + mono/kbd + governance variants; de-glass + collapse primary/accent |
| Navigation (sidebar/Command Home) | **Native split/nav + glass** | The legit glass navigation layer |
| Status badges/dots | **Custom, thin** | icon+color+severity the system lacks; enforce icon redundancy |
| Terminal / code / diff | **Custom** (identity-critical) | No native primitive; the hero surface |
| AgentIsland / PersistentStatusBar | **Custom + glass** | Distinctive, floats over content = correct glass use |
| PixelAvatar / PixelBox | **Custom** (identity) | Differentiators; need a11y fallbacks |
| Toggles / steppers / pickers / fields | **Native** | Tint accent, sink inputs |
| Progress / charts | **Native** (`ProgressView` / Swift Charts) | Don't hand-roll; theme with tokens |

**Rule:** custom only for (a) technical hero surfaces iOS has no answer for, (b) brand-identity controls, (c) governance semantics the platform lacks. Everything else native, restyled with tokens.

## Consolidation plan

**Merge:** `DSButton.primary`→`.accent`; `sp*`→`s*`, `radius*`→`r1…r5`; `DSDetailHeader`+`DSStatusHeader`→one (fix double chevron); status surfaces → one severity-driven badge/dot API; approval surfaces (`DSApprovalBanner`/`InboxApprovalCard`/`InboxApprovalDetail`/`DSReviewSheet`) → one shared anatomy.
**Cut/restrict:** glass on buttons; indigo/violet themes; serif beyond ~3 moments; nested cards; the 152/155/142 raw literals.
**Enforce (CI lints — do first):** (1) fail on `Color(.sRGB`/`Color(red:` outside `DesignSystem/`; (2) fail on `.font(.system` outside `DesignSystem/`; (3) warn on literal `cornerRadius:`/`.padding(<number>)` in feature code.

## On-device verifications (beta caveats)

Does the runtime force `.preferredColorScheme(.dark)` despite `LancerAppearance`? · `glassEffect` Reduce-Transparency fallback on shipping iOS 27 · `text3`/`text4` on dark under Increase Contrast (measure) · AX5 behavior of side-by-side header buttons + badge slot.

## Sources

[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [WWDC25 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · [WWDC25 New design system](https://developer.apple.com/videos/play/wwdc2025/356/) · [App Store Connect Dark Interface criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria/) · [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography) · [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color) · Mobbin GitHub-iOS PR/CI screens · repo `Tokens.swift`/`Typography.swift`/`DSButton.swift`/`LancerGlassChrome.swift`.
