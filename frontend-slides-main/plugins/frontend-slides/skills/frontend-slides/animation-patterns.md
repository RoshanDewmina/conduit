# Animation Patterns Reference

Use this reference when generating presentations. Match animations to the intended feeling.

## Animation Engine: GSAP vs. CSS-only

**Default to GSAP** for any deck beyond a single-slide style preview — multi-step reveals, more than ~4 staggered elements, or slide-to-slide continuity all outgrow CSS `transition-delay`, which has no real sequencing, can't be paused/reversed/resynced, and silently stops staggering past however many `:nth-child()` rules were hand-written.

**CSS-only is fine for**: a single-slide style preview (Phase 2 discovery), or when the user explicitly asks for zero external scripts / a locked export-only file.

Loading GSAP does not violate the zero-build-step principle — it's the same CDN-script pattern already used for Google Fonts: a `<script>` tag, no npm, no bundler.

```html
<script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/SplitText.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/Flip.min.js"></script>
<script>gsap.registerPlugin(SplitText, Flip);</script>
```

Only load the plugins actually used. SplitText and Flip are both free — no Club GSAP membership required since Webflow's acquisition of GSAP retired the paid tier — but each is still a separate script tag and a separate `registerPlugin()` call.

**Version floor: never pin below 3.13.** Club plugins (SplitText included) only exist in the public npm/CDN package from 3.13 onward — a 3.12.x SplitText URL 404s, `registerPlugin(SplitText)` throws, and the whole deck script dies. `SplitText.create()` is also 3.13+ API. Keep the exact pin above (currently 3.15.0) and bump it deliberately.

## Effect-to-Feeling Guide

| Feeling | Animations | Visual Cues |
|---------|-----------|-------------|
| **Dramatic / Cinematic** | Slow fade-ins (1-1.5s), large scale transitions (0.9 to 1), parallax scrolling | Dark backgrounds, spotlight effects, full-bleed images |
| **Techy / Futuristic** | Neon glow (box-shadow), glitch/scramble text (GSAP `ScrambleTextPlugin`), grid reveals | Particle systems (canvas), grid patterns, monospace accents, cyan/magenta/electric blue |
| **Playful / Friendly** | Bouncy easing (`"back.out(1.7)"`, `"elastic.out(1, 0.3)"`), floating/bobbing | Rounded corners, pastel/bright colors, hand-drawn elements |
| **Professional / Corporate** | Subtle fast animations (200–300ms, `"power2.out"`), clean slides | Navy/slate/charcoal, precise spacing, data visualization focus |
| **Calm / Minimal** | Very slow subtle motion (`"power1.out"`, 0.8–1.2s), gentle fades | High whitespace, muted palette, serif typography, generous padding |
| **Editorial / Magazine** | SplitText line/word reveals staggered `from: "start"`, image-text interplay | Strong type hierarchy, pull quotes, grid-breaking layouts, serif headlines + sans body |

## Slide-Reveal Timeline (replaces `.reveal:nth-child()` CSS delays)

Give every slide a single GSAP timeline, built once and played on activation, instead of relying on CSS `transition-delay` — which caps out at however many `:nth-child()` rules were written and can't be paused, reversed, or resynced:

```javascript
function revealSlide(slide) {
  const targets = slide.querySelectorAll(".reveal");
  gsap.killTweensOf(targets); // rapid navigation otherwise strands elements mid-tween at partial opacity
  const tl = gsap.timeline({ defaults: { duration: 0.65, ease: "power3.out" } });
  tl.from(targets, {
    autoAlpha: 0,
    y: 24,
    stagger: 0.12
  });
  return tl;
}
```

Call `revealSlide(slide)` from the slide controller's `showSlide()`. Use **autoAlpha**, not `opacity`, so hidden reveal elements don't intercept clicks before they animate in. The `killTweensOf()` line is not optional — without it, fast arrow-key navigation leaves `from()` tweens fighting over the same elements. Store the returned timeline per slide (e.g. in a `WeakMap`) if it needs to be reversed on backward navigation.

**GSAP must be the sole owner of `.reveal` motion.** Never leave CSS `transition` rules on properties GSAP animates (opacity/transform) — every GSAP tick re-triggers the CSS transition and motion turns smeared and laggy. The CSS fallback block in the template is gated behind `html.no-gsap` for exactly this reason.

**Use `stagger` objects for spatial reveals** — e.g. a tile grid revealing from its center outward, matching how the eye actually scans a grid:

```javascript
tl.from(".tile", { autoAlpha: 0, y: 20, stagger: { amount: 0.4, from: "center" } });
```

## SplitText Headline Reveals (signature move — free since the Webflow/GSAP merger)

The single highest-impact upgrade over a block-level fade: split a headline into words or lines and stagger them in. Split right before a slide's timeline plays:

```javascript
const split = SplitText.create(headlineEl, { type: "words, lines" });
gsap.from(split.lines, { autoAlpha: 0, y: "60%", stagger: 0.08, duration: 0.7, ease: "power3.out" });
```

Only split what's animated — `type: "words"` alone if not also revealing per line. For a serif display headline with an `<em>` emphasis phrase (a pattern used throughout editorial-style decks), split `type: "lines"` so the whole line — including the emphasis color — moves as one unit rather than each character tumbling separately, which reads as gimmicky at editorial type scales rather than elegant.

## Flip: Continuity Across Slide Changes (optional, higher craft)

For a shared element that appears on both the outgoing and incoming slide (a monogram, a running total, a persistent label), `Flip` animates it smoothly from its old position/size to its new one instead of a hard cut:

```javascript
const state = Flip.getState(".monogram");
showSlide(nextIndex); // DOM/class change happens here
Flip.from(state, { duration: 0.5, ease: "power2.inOut" });
```

Reserve this for one or two recurring elements per deck — using it on everything reads as busy, not elegant.

## Reduced Motion

Wrap the reveal setup in `gsap.matchMedia()` so one code path handles both cases — don't duplicate timelines for a "reduced" branch. Use `globalTimeline.timeScale()`, not `gsap.defaults({duration: 0.01})`: shrinking durations alone leaves stagger offsets intact, so a dense slide still plays ~1s of staggered pops for reduced-motion users. Time-scaling collapses durations AND staggers together:

```javascript
gsap.matchMedia().add("(prefers-reduced-motion: reduce)", () => {
  gsap.globalTimeline.timeScale(1000); // collapses durations AND stagger offsets
  return () => gsap.globalTimeline.timeScale(1); // revert if preference changes
});
```

Keep the `viewport-base.css` `@media (prefers-reduced-motion: reduce)` block too — it's the fallback if GSAP fails to load from the CDN (e.g. offline use), so reduced motion still degrades gracefully either way.

## Background Effects

Unchanged, CSS-only — no animation library needed for static backgrounds.

```css
/* Gradient Mesh — layered radial gradients for depth */
.gradient-bg {
    background:
        radial-gradient(ellipse at 20% 80%, rgba(120, 0, 255, 0.3) 0%, transparent 50%),
        radial-gradient(ellipse at 80% 20%, rgba(0, 255, 200, 0.2) 0%, transparent 50%),
        var(--bg-primary);
}

/* Noise Texture — inline SVG for grain */
.noise-bg {
    background-image: url("data:image/svg+xml,..."); /* Inline SVG noise */
}

/* Grid Pattern — subtle structural lines */
.grid-bg {
    background-image:
        linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
    background-size: 50px 50px;
}
```

## Interactive Effects

```javascript
/* 3D Tilt on Hover — GSAP quickTo avoids creating a new tween on every mousemove event */
function addTilt(el) {
  el.style.transformStyle = "preserve-3d";
  el.style.perspective = "1000px";
  const rotY = gsap.quickTo(el, "rotationY", { duration: 0.4, ease: "power3" });
  const rotX = gsap.quickTo(el, "rotationX", { duration: 0.4, ease: "power3" });
  el.addEventListener("mousemove", (e) => {
    const r = el.getBoundingClientRect();
    rotY((((e.clientX - r.left) / r.width) - 0.5) * 10);
    rotX((-(((e.clientY - r.top) / r.height) - 0.5)) * 10);
  });
  el.addEventListener("mouseleave", () => { rotY(0); rotX(0); });
}
```

`quickTo()` reuses a single tween instead of creating one per `mousemove` event — the plain CSS-transform version works but is measurably choppier under fast mouse movement.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Fonts not loading | Check Fontshare/Google Fonts URL; ensure font names match in CSS |
| GSAP not loading / `gsap is not defined` | Check the CDN `<script>` tags are before any code that calls `gsap.*`; confirm network access (offline dev needs a local fallback copy) |
| Animations not triggering | Verify the timeline is actually played from `showSlide()`, not just built; check `.reveal` elements exist on that slide |
| SplitText re-splitting mid-animation | Use `autoSplit: true` with `onSplit()` and return the tween from it, so GSAP resyncs instead of fighting itself |
| Scroll snap not working | Ensure `scroll-snap-type: y mandatory` on html; each slide needs `scroll-snap-align: start` |
| Mobile issues | Disable heavy effects at 768px breakpoint; test touch events; reduce particle count |
| Performance issues | Prefer `x`/`y`/`scale`/`autoAlpha` over `width`/`height`/`top`/`left`/`opacity`; use `will-change` only on elements actually animating |
