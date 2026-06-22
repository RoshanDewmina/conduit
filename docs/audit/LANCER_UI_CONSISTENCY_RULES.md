# Lancer UI Consistency Rules

> **Status:** binding for the migration board **and** the iOS port. Every screen — header, footer,
> button row, heading, sub-heading, spacing, motion — must obey these. When a screen can't, the rule
> wins and the screen changes. Authored 2026-06-13 after the first-pass polish review.

The goal is a single, unmistakable rhythm so the app reads as one deliberate product, not a set of
screens drawn on different days. "Polished and professional" = **nothing is off by a pixel, and every
transition has the same weight.**

---

## 1. Screen skeleton (every full screen)

Three regions, always in this order, never improvised:

```
┌ HEADER ───────────────┐   StatusHeader (tab roots) or SubNav (pushed screens). Fixed, flex:none.
├ SCROLL ───────────────┤   .cc-scroll {flex:1; overflow-y:auto}. All content lives here.
│   .cc-pad (0 18px)     │   First block paddingTop:10 on SubNav screens; StatusHeader supplies its own.
│   …                    │
│   .cc-bottompad (96)   │   ONLY when there is no footer (lets last row clear the tab bar).
├ FOOTER ───────────────┤   .cc-foot — solid bar + 1px top hairline + safe-area padding. Optional.
└───────────────────────┘
```

**Rules**
- **R1.1** A primary CTA pinned to the bottom uses `.cc-foot` — never an ad-hoc `linear-gradient`
  footer. The gradient bled over scroll content and clipped the last card (the Bypass bug). Solid bar
  + hairline, like the sheet footer (`.sheetfoot`), is the only allowed treatment.
- **R1.2** Scroll content must fully clear the footer/tab bar. If a footer exists, the last content
  block needs ≥12px below it; if no footer, end the scroll with `.cc-bottompad`. A CTA may **never**
  overlap content.
- **R1.3** Horizontal padding is **always 18px** (`.cc-pad`, `.cc-foot`, `.sheetscroll`, `.sheetfoot`).
  No screen invents its own gutter.
- **R1.4** Pushed screens use `SubNav` (custom back chevron + mono title). Tab roots use
  `StatusHeader` + `PromptHeader`. Never mix.

## 2. Spacing scale

Use only these steps. No `margin: 9px`, no `13px` one-offs.

`4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 22 · 24 · 28`

- **R2.1** Section header (`.cc-sec`) to its card: 0 (the card follows immediately). Card to next
  section header: built into `.cc-sec` top margin — don't add ad-hoc gaps.
- **R2.2** Stacked cards: `margin-bottom: 10`. Stacked radio/option cards: `8`.
- **R2.3** Lead paragraph (`.cc-lead`) bottom margin: `12` (SubNav screens) / `16` (onboarding steps).

## 3. Buttons

- **R3.1** Any row of 2+ buttons uses `.cc-btnrow` (which sets `flex:1` on each `.cc-btn`). Buttons in
  a row are **always equal width** unless a deliberate emphasis ratio is set (then `flex:1 / 1.3`,
  never larger — beyond ~1.4 the label overflows its box, which caused the "Write rule & allow" clip).
- **R3.2** Button labels are **short enough to never wrap or overflow** at the narrowest frame (320pt
  → ~135pt per half-width button → ≤ ~13 mono chars incl. icon). Long verbs get shortened and the
  meaning carried by an adjacent icon/badge: `Face ID · Approve` → lock-icon + `Approve`;
  `Write rule & allow` → `Write rule`.
- **R3.3** Decision order is fixed everywhere: destructive **left** (`--danger`, outline), affirmative
  **right** (`--primary`, filled). Secondary actions (Edit & run / Allow always) sit in a **second
  row below**, never inline with the one-tap row.
- **R3.4** Heights: primary CTA `52`, in-row `.cc-btn` `46`, `.cc-btn--quiet` `40`. Icon size in
  buttons: `14–16`. Gap icon↔label: `8`.

## 4. Typography hierarchy

| Role | Family | Size | Weight | Notes |
|---|---|---|---|---|
| Screen title (SubNav) | mono | 17 | 600 | lowercase, trailing block cursor |
| Hero H1 | mono | 28–42 | 700 | onboarding only |
| Sheet H2 (`.cc-h2`) | mono | ~20 | 700 | |
| Section header (`.cc-sec`) | mono | 11 | 600 | UPPERCASE, `.2em` tracking, hairline rule |
| Row title (`.t`) | sans | 14–14.5 | 500 | |
| Row sub / `.s` / `.cc-note` | mono | 11–12.5 | 400 | `--ink-3/-4` |
| Body / lead | sans | 14.5–15.5 | 400 | `--ink-2`, line-height 1.5–1.6 |

- **R4.1** Mono is for identifiers, commands, headers, metrics, status. Sans is for sentences.
- **R4.2** Never set primary copy below **11pt**. Metric callouts (spend `$4.94`) may be large mono.

## 5. Color & risk (the headline rule)

- **R5.1 — Electric blue `--brand` (#2f43ff) is CTA-only.** It never encodes risk, state, or a data
  series. The current app's bug (`risk(2)` → brand blue) must be fixed: risk gets its **own** ramp.
- **R5.2 — Risk ramp is independent and monotonic:** `--r-low` green → `--r-med` amber → `--r-high`
  orange → `--r-crit` red. Risk is **always** paired with a text label, never color alone (a11y).
- **R5.3 — Data series (quota bars, spend) use the brand spectrum** (`#b5352a→#4f63c9`, the red→blue
  strip), not arbitrary vendor hues. Vendor-identity colors are allowed **only** in an explicit vendor
  legend with text labels next to them.
- **R5.4 — "Stays on host" / safe = `--r-low` green; "crosses the wire / cost" = neutral or brand.**
  Privacy-positive is green, consistently.

## 6. Motion & haptics

Smooth, consistent, never gratuitous. One spring, one set of haptics.

- **R6.1 — Sheets/drawers** (decision sheet, file viewer, paywall, TOFU) slide up with the canonical
  spring `cubic-bezier(.2,.85,.25,1)`, ~300ms, scrim fades 220ms. Dismiss: swipe-down + tap-scrim.
  iOS: `.presentationDetents` with a grabber; medium → large where content scrolls.
- **R6.2 — Haptics (iOS `UIFeedbackGenerator`):**
  - Approve / deny / write-rule → `.notification(.success)` / `.warning` / `.success`.
  - Tab switch, segment toggle, radio select → `.selection`.
  - Destructive confirm (stop run, deny critical) → `.impact(.heavy)`.
  - Pull-to-pair success, run-complete → `.notification(.success)`.
- **R6.3 — Tap feedback:** every `.cc-btn` scales to `.975` on press (already in CSS); iOS mirrors with
  a 0.08s ease. List rows highlight `--surface-2` on press.
- **R6.4 — State transitions** (status dot working→done, PixelBox) cross-fade ~180ms; never hard-cut.
- **R6.5 — Respect Reduce Motion:** springs collapse to a 120ms fade; no parallax.

## 7. Sheets & the file viewer drawer

- **R7.1** Bottom drawer = `.cc-sheetwrap` + `.cc-scrim` + `.cc-sheet` (grip, `.sheetscroll`,
  `.sheetfoot`). Max height 90–92%.
- **R7.2 — File viewer:** tapping any file reference (blast-radius chip, diff filename, a file in a
  listing) opens the **full file in a bottom drawer** — header (filename · path · line count ·
  read-only), line-numbered mono body that scrolls, footer with copy + dismiss. This is the single
  canonical full-file view; there is no separate file screen.

## 8. Per-screen checklist (run before calling a screen "done")

- [ ] Header is StatusHeader (root) or SubNav (pushed) — not improvised.
- [ ] If there's a bottom CTA, it's `.cc-foot`; nothing it covers is clipped.
- [ ] All button rows equal-width; no label wraps/overflows at 320pt.
- [ ] Destructive-left / affirmative-right; secondaries on their own row.
- [ ] Every margin/padding is on the §2 scale.
- [ ] Risk uses the ramp + a label; brand blue appears only on the CTA; bars use the spectrum.
- [ ] Sheets use the canonical spring; decision/destructive actions fire the right haptic.
- [ ] Mono vs sans per §4; nothing below 11pt.
