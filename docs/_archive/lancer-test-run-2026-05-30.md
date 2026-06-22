# Lancer — Manual QA Run (2026-05-30)

Branch `feat/warp-style-agent-blocks` @ `b0374cb`. iPhone 17 Pro simulator (dark; app pins its
own Theme), plus one live SSH session against `127.0.0.1` (real shell, 3 tmux sessions present).
Build: `BUILD SUCCEEDED`; unit tests 203/203 (parallel, verified 3×). Screenshots in `/tmp/qa-*.png`.

## Pass/fail by screen

| Screen / state | Result | Notes |
|---|---|---|
| Onboarding | ✅ PASS | "How Lancer works" BYO card, full-width DS buttons, "Provision a new Fly.io VM · Beta" caption (no dead-end CTA) |
| Sessions tab | ✅ PASS | Empty-state guidance + "Go to Hosts" link; explains no-account model |
| Hosts tab | ✅ PASS | Tag-grouped rows (HOME/LOCAL/WORK), PixelAvatars, timestamps; **REVIEW pill removed** (C3) |
| Inbox tab | ✅ PASS | **Autonomy preset bar live** (Auto-reads / Always ask / Agent); HIGH/MED approval cards; decided row |
| Settings tab | ✅ PASS | **DS segmented Theme control** (no iOS-blue tint, C3); status header correctly absent (contextual) |
| Typed Inbox (gallery `inbox-typed`) | ✅ PASS | `DSAskQuestionCard` (lettered A–D + gated SUBMIT), `DSMCPCallCard` (`read_file`), risk-tagged RunCommand |
| Agent Features (gallery `features`) | ✅ PASS | Shortcut/approval banner + composer, media paperclip menu, typed cards (subagent #9 a–c) |
| Blocks (gallery `blocks`) | ✅ PASS | Full `DSBlockCard` language; `✓ exit 0` / `✗ exit 1` chips + ANSI colors intact; no prompt noise |
| **Live SSH session** | ✅ PASS | Real `echo` block: `✓ exit 0`, 1.27s, no `~ %` noise, no echoed command — OSC-133 works on a real shell; empty top integration block **suppressed** |
| **Tmux picker (live)** | ✅ PASS | Redesign confirmed against 3 live tmux sessions — themed dark sheet, accent glyphs, mono names, ATTACH, ghost Skip (was stock-iOS gray list) |

## New findings

### 🔴 A11Y-1 — Dynamic Type not supported (fixed-point fonts)
**Evidence:** `Sources/DesignSystem/Typography.swift` — `dsSansPt`/`dsMonoPt`/`dsDisplayPt` (used
pervasively across all views) call `.custom(face, size:)` **without `relativeTo:`**, producing
fixed-size fonts. At `accessibility-extra-extra-extra-large` the Inbox rendered identically to the
default size — the UI does not scale with the user's text-size preference. The style-based variants
(`dsSans(style:)`, `Typography.swift:10/20/25`) *do* use `relativeTo:`, but views use the `*Pt` forms.
**Impact:** real accessibility gap; affects low-vision users and is a quality signal in App Store review.
**Severity:** medium–high (accessibility). **Not** a quick fix — see task below.

This also **reframes the earlier "BUG-4"**: since text never grows, the leading-edge clip the prior
QA agent saw was the genuinely-wide *fixed* content (the gallery button strip — BUG-1, already fixed).
The Inbox `.frame(maxWidth: .infinity)` guard added in `b0374cb` is a harmless robustness improvement,
not the root fix for an AX-type clip.

### A11Y-2 — Light mode not independently re-verified
The app pins its own Theme preference over the system appearance (correct behavior), so toggling the
simulator to light had no effect. Light palette exists in `Tokens.swift` and was verified in the gallery
by subagents; independent re-check requires tapping the in-app Theme → Light/System.

## Still device-only (not exercisable in the simulator)
Biometric gate · TOFU prompt on first **production** connect (harness auto-trusts) · Ctrl-C and
vim/htop raw-screen escalation interaction · real Wi-Fi↔cellular reconnect/handoff · landscape ·
Live Activity / Dynamic Island while backgrounded · low-memory eviction.

## Net assessment
All screens render cleanly and on the design system; every subagent workstream (reliability, typed
approvals, autonomy bar, onboarding education, settings scope-down, tmux redesign) is visually
verified, and the live block pipeline + tmux picker work against a real host. The one substantive new
issue is **Dynamic Type support**.

---

## Backlog task — A11Y: Dynamic Type support

**Objective:** make the app respect the user's preferred text size end-to-end.
**Scope:** convert the `*Pt` font helpers (`Sources/DesignSystem/Typography.swift`) to scale with
Dynamic Type — either give them a `relativeTo:` TextStyle mapping (map each pt size to the nearest
`Font.TextStyle`) or wrap call sites with `@ScaledMetric`. Then audit every screen for overflow/clipping
at the largest accessibility sizes and add `.frame(maxWidth: .infinity, alignment:)` / `fixedSize`/
`lineLimit` where rows would otherwise clip (Inbox already guarded). Cap scaling where it would break
fixed-geometry layouts (e.g. the session-row badge slot, terminal block gutters) via
`.dynamicTypeSize(...partialRangeThrough:)`.
**Files:** `Sources/DesignSystem/Typography.swift` (core), then a sweep of feature views.
**Acceptance:** at AX5 the UI grows legibly with no leading-edge clip, no overlap, no truncated
controls, on every tab + the session screen, light and dark. Verify in the gallery at multiple
content sizes (`xcrun simctl ui booted content-size <size>`).
**Complexity:** Medium–High (core change is small; the layout re-audit is the work).

### Subagent prompt (ready to hand off)
> "Add Dynamic Type support to the Lancer iOS app (`Packages/LancerKit`). READ-ONLY context first:
> `Sources/DesignSystem/Typography.swift` defines `dsSansPt`/`dsMonoPt`/`dsDisplayPt` as
> `.custom(face, size:)` with **no `relativeTo:`**, so all text is fixed-size and ignores the user's
> text-size setting (confirmed: UI does not grow at AX5). Make these helpers scale — map each point
> size to the nearest `Font.TextStyle` and pass `relativeTo:` (or introduce `@ScaledMetric` at call
> sites). Then sweep every feature view (Sessions, Hosts, Inbox, Settings, Onboarding, Diff, Files,
> Preview, the session/block screen) and fix overflow at large accessibility sizes: constrain scroll
> content with `.frame(maxWidth: .infinity, alignment:)`, add `fixedSize(horizontal:false, vertical:true)`
> to multiline text, and cap scaling on fixed-geometry elements (session-row badge slot per the
> CLAUDE.md layout invariant, terminal block gutters) with `.dynamicTypeSize(...DynamicTypeSize.accessibility3)`
> where growth would break layout. Build after each step (`cd Packages/LancerKit && swift build`) and
> verify in the gallery at several sizes via `xcrun simctl ui booted content-size <size>` in light and
> dark. Acceptance: legible growth at AX5 with no clipping/overlap/truncation on any screen. Never
> `git add -A`; stage only source. Keep the TOFU prompt in production paths."
