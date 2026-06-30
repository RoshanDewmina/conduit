# 02 — Onboarding value-prop screen treatment

> Follow-up to [`01-onboarding-pairing-workflow.md`](01-onboarding-pairing-workflow.md), which
> already merged the old "value" and "pair" steps into one scrollable screen (`valuePair`). This
> doc is scoped narrowly to the owner's specific complaint: *"i dont like the 3 bullet points and
> the design there, change it [to] something more informational, maybe even a video in the
> background."* Research only — no Swift changes. Ground truth pulled from source, not just the
> screenshot, per the project's working rules.

## 1. Current state

Source: `Packages/LancerKit/Sources/OnboardingFeature/OnboardingRedesignGalleryView.swift`,
private struct `OnboardingValueRows` (lines 374–404), rendered inside `primaryBlock` for the
`.valuePair` step (line 216), directly below the shared terracotta `hero` (lines 125–178) and
above the pairing code block on the same screen.

**What's actually on screen, verbatim:**

- Hero (gradient `t.accent` → `t.accentInk`, faint horizontal line texture, one large soft white
  circle bottom-trailing, `UnevenRoundedRectangle` bottom corners): eyebrow "your machines,",
  title "in your pocket.", body "Lancer is mission control for the coding agents running on your
  own machines. Here's what you get:"
- Three rows, each `RoundedRectangle` 44×44 icon tile (`t.surface2` fill) + title (semibold 15pt)
  + detail (12.5pt, `t.text4`), 40pt vertical spacing between rows:
  1. SF Symbol `checkmark` — "Approve actions from afar" / "Allow or deny risky steps in a tap"
  2. Literal text glyph `"›_"` in mono — "Watch the terminal stream live" / "Every command, as it runs"
  3. SF Symbol `shield.fill` — "Policy guardrails per machine" / "Rules apply to every machine"
- Below that on the same scroll: the pairing code entry block (mono "ON YOUR DESKTOP, RUN
  lancerd pair", 6-digit field, expiry copy, status line).

**Why the owner doesn't like it — specific, not vague:**

1. **The icons don't show the product, they decorate a sentence.** A checkmark glyph, a `›_`
   text string standing in for "terminal," and a generic SF Symbols shield are abstract
   illustrations of the *words* "approve," "terminal," and "policy" — not the actual UI the user
   will use seconds later (the real `InboxApprovalCard`, the real terminal block renderer, the
   real policy radio cards three steps away in this same onboarding flow). A user can't tell from
   this screen what the approval card looks like, what the live terminal actually renders, or what
   a guardrail decision screen feels like. The app already has all three of those built and
   screenshot-able; none of that visual equity is spent here.
2. **Equal visual weight on three claims of unequal importance.** All three rows get an identical
   44×44 tile, identical type scale, identical 40pt rhythm. But per `AGENTS.md` and the live-loop
   runbook, **the approval loop is the #1 V1 priority and the core differentiator** — it is not a
   peer of "watch the terminal" (a feature) or "policy guardrails" (a configuration option). The
   layout has no mechanism to say "this one is the actual product," so first-time impression
   reads as a flat feature checklist, the most generic onboarding pattern that exists, rather than
   "this is the one thing that matters."
3. **It's a static wall of text-with-icon above an unrelated pairing form**, with nothing moving,
   nothing alive, nothing that looks like software actually running. For an app whose entire pitch
   is "watch your agents work, approve from anywhere," a flat icon list is the least on-brand way
   to make that case — it tells, it doesn't show.
4. **The hero gradient is decorative, not informative.** The orange/terracotta panel above the
   rows (lines 161–178: gradient + faint scanlines + one translucent circle) is pure brand
   texture — it doesn't reference the product at all. It's not bad on its own, but combined with
   point 3, the entire screen is 100% illustration/typography and 0% product, in an app whose
   actual product (a live terminal + an approval card) is unusually visual and demo-able compared
   to most onboarding value props.

## 2. Mobbin research

### Video/motion backgrounds behind onboarding value-prop content

| App | What's moving | Legibility treatment | Premium or padding? |
|---|---|---|---|
| [How We Feel](https://mobbin.com/screens/de41603d-6756-42da-b861-5be2f3a03a11) | Real captured close-up video of a person's face, slow subtle motion | Fixed-position white serif headline + pill CTA bottom-anchored over a dark/vignetted frame, no scrim gradient needed because the footage itself is already low-contrast and dark | **Premium** — but it's selling an emotional/therapeutic experience where a human face *is* the value prop. Doesn't transfer to a tool. |
| [Pliability](https://mobbin.com/screens/d791586a-4e9b-4899-8467-28d580219cc5) | Real lifestyle video of a woman doing yoga in a loft | Bottom scrim bar (semi-opaque rounded rect) holding the headline text, video plays full-bleed behind | **Padding-leaning.** Generic stock-feeling fitness-influencer footage; the video isn't *demonstrating the product*, it's mood-setting. Three more screens later it switches to a flat icon+title+detail list (`Tailor Your Content` / `Take your first Mobility Test`) — i.e. even Pliability itself drops video once it needs to explain real app mechanics. |
| [Tabby](https://mobbin.com/screens/e31700fa-88d9-45d7-bcd5-4d5c184128f8) | Static photo (not moving) of a person lying in branded packaging, looks like a posed product-photography frame, not actual video | Bold white display type stacked directly over the image, no scrim, relies on the photo having an already-dark zone | Reads as a marketing poster, not a demo. Borderline padding — it sells brand mood, not the product mechanic (installments). |
| [Tonal](https://mobbin.com/screens/324a84c7-4545-4012-8812-4c422d5f1c2f) | Static hero photo of equipment + a person mid-workout | Centered wordmark + bold headline over a naturally dark studio background, two outlined pill buttons | This is genuinely the product (a real Tonal machine) — closer to honest than lifestyle stock, but it's a $4,000 hardware object that *is* visually impressive by default. Lancer's "product" is a terminal and a push notification — not a comparable hero shot. |
| [Airbnb](https://mobbin.com/screens/e6f9140b-7fba-46fc-b7ff-3f1828e97c1a) | Real talking-head video of the CEO, with inline play/mute/captions controls visible | Video occupies the top ~45% only, not full-bleed-behind-text — text sits in the solid-black lower zone, completely separate from the video, zero legibility risk because there's no overlap | Honest and premium for its purpose (a personal thank-you message), but it's a founder-letter pattern, not a value-prop pattern, and it requires a literal CEO video shoot. |

**Honest read:** every full-bleed-video-behind-text example here is either (a) selling an
emotional/lifestyle mood unrelated to what the app actually does (How We Feel, Pliability, Tabby),
or (b) showing a real, already-photogenic physical product (Tonal), or (c) a founder video used as
a controls-visible foreground element, not a background (Airbnb). **None of them demonstrate "this
is what using the software looks like."** That's the pattern Lancer actually needs, and it's
notably absent from every video-background reference found — which is itself a useful finding:
video-behind-text is a lifestyle/consumer-app convention, not a dev-tool one. No dev tool, SaaS
app, or technical product in this research used a full-bleed video background on its onboarding
value screen.

### "More informational" — richer-than-bullets, dev-tool-leaning

| App | Pattern | Read |
|---|---|---|
| [Vibecode — "Introducing Pinch to Build"](https://mobbin.com/screens/f165f181-cefa-422c-ac22-1a07ba570835) | A real screenshot of the actual app's UI (a grid of in-progress AI-built apps) placed inside a simple rounded device-frame card, with a headline below explaining one specific interaction (pinch-to-exit) | **Premium and directly transferable.** This is an AI coding/app-building tool — same category as Lancer — proving its product visually instead of describing it. The screenshot is the app's real UI, not a mockup or stock photo. This is the strongest single reference found for "show, don't tell" in this exact product category. |
| [Vibecode — RevenueCat setup step list](https://mobbin.com/screens/5fec9551-d5c3-4f66-93e1-cefa90d7d0af) | Four numbered steps, each with a small icon, connected by a vertical line (a literal "process" visual, not just a bullet list), each step name + one-line detail | A step-by-step *process* visual reads as more "informational" than three independent bullets because the connecting line implies sequence and causality — useful pattern even without video. |
| [Granola — "Welcome to Granola"](https://mobbin.com/screens/5de8fd45-4580-4191-8cbd-0008a01b8b1e) | Top: a layered screenshot pair (a desktop meeting-notes window + a phone showing the same data) inside soft rounded device frames on a tinted background panel. Below: three feature rows in pill-shaped cards (icon + 2-line description), each visually grouped as its own card rather than a flat list | Genuinely strong reference for "technical-but-approachable." Granola is an AI meeting-notes tool — same "calm B2B tool, not consumer app" register as Lancer. The screenshot-pair at top does the demonstrating; the rows below do the explaining. It doesn't abandon the bullet-row pattern, it **earns it** by putting a real product screenshot above it first. |
| [Linear Mobile — "Meet the command menu"](https://mobbin.com/screens/167c768d-0970-44c7-b769-e7fb6073e9d5) | One feature per screen (not three at once), each with a literal interactive instruction ("Try opening the command menu by: Tapping with two fingers") inside a bordered card, real product chrome at top (linear.app title bar) | Different shape of solution: instead of "richer per-bullet," Linear goes the other way and **does one concept per screen**, makes it interactive/literal rather than a static row. Notable because Linear is the closest brand-register comparable to Lancer (technical, calm, dark-capable, developer-facing) of anything found in this research. |
| [Brilliant](https://mobbin.com/screens/553ab0aa-4c92-46a3-a22a-5213827f9666) | A real, slightly-blurred code-editor screenshot (with a visible cursor click) behind a bold black headline + supporting copy, full-bleed at top fading into white | Code-as-texture: the actual artifact of the product (code) is the background image, not a generic photo. The blur keeps it from competing with the headline contrast-wise. Closest "real-product-as-backdrop, not stock-video" pattern found for a technical product. |

## 3. Cost/risk read — video vs. motion-graphic vs. real screen-recording

None of the video-background examples found are confirmed Lottie/motion-graphics loops — they all
read as real captured video (live-action lifestyle/portrait footage). That itself is informative:
**the "rich background" pattern in the wild is overwhelmingly real video, which is the
expensive/non-transferable option for Lancer** (would require either stock lifestyle footage that
doesn't show the product — explicitly the wrong move, see §4 — or a one-off shoot of someone using
a laptop, which is production overhead this app doesn't need).

The pattern that *does* solve "more informational" cheaply is **Vibecode's and Brilliant's
approach: a real screenshot/recording of the actual product UI**, not stock footage and not an
abstract motion-graphic. For Lancer specifically this is even more directly available than for
either of those apps:

- Lancer already has a real, shipping **terminal block renderer** (`SessionFeature` /
  `BlockRenderer`, per `terminal-blocks.md`) and a real **`InboxApprovalCard`** / approval-detail
  flow (already screenshotted for the design-audit folder). A **looping screen-recording of the
  terminal stream + an approval card receiving a tap** costs nothing to produce beyond a
  simulator recording and is literally true — it is not a mockup, not stock, not aspirational.
- This is strictly more honest than any video-background example found in this research: every
  lifestyle-video reference (How We Feel, Pliability, Tabby) is selling a mood the product doesn't
  literally deliver in that frame, where a Lancer screen-recording shows the exact UI the user
  taps into thirty seconds later.
- A short (3–6s) looping capture, autoplayed muted, is also the cheapest production path
  available: no videographer, no actor, no licensing, regenerate it for free whenever the UI
  changes (a static screenshot or stock asset goes stale; this doesn't, because it's pulled from
  the live app build).

## 4. Recommended pattern for Lancer

**Replace the three flat icon+title+detail rows with a single real product visual + one ranked
headline claim, not a video background behind the hero.**

Concretely:

1. **Lead with one real screen-recording-style loop of the approval flow**, framed inside a
   simple rounded device-style card (Vibecode's pattern, not full-bleed-behind-text): a muted,
   looping capture of an `InboxApprovalCard` receiving a tap → resolving, ideally with a glimpse
   of the terminal block scrolling above it. This single asset visually proves the #1 V1 claim
   (remote approval) instead of giving it the same 44×44 icon as two lesser features. This
   directly fixes finding §1.2 (unequal-importance claims given equal weight) by making the most
   important one literally the biggest thing on screen.
2. **Keep "watch the terminal" and "policy guardrails" as supporting copy, not three peer rows** —
   either fold them into one line of body copy under the recording ("...and watch every command as
   it runs, gated by rules you set per machine") or demote them to small caption-style text under
   the device-frame card, the way Granola's pattern uses a hero visual first and lighter
   supporting rows second. This keeps the screen's information hierarchy honest about what
   actually matters (fixes §1.2) while still surfacing the other two claims.
3. **Do not put video/motion in the hero gradient itself.** The terracotta hero (`heroBackground`,
   lines 161–178) is brand chrome — title/kicker/eyebrow — and should stay exactly what it is: a
   calm, static, on-brand surface. Motion belongs in the *value content area* below it (replacing
   `OnboardingValueRows`), not behind the headline text, which is the one place every example in
   §2 actually risks legibility problems video brings (scrims, fixed-card text, vignettes — all
   solved problems the research shows, but unnecessary complexity Lancer doesn't need to take on
   for a hero that's working fine as static brand color today).
4. **Reduce Motion fallback is mandatory and cheap.** `@Environment(\.accessibilityReduceMotion)`
   is already imported and used in this exact file (line 44, plus the step-dot transition at line
   201) — the same pattern extends trivially: when `reduceMotion` is true, swap the looping video
   for a single static frame from that same recording (literally the first frame, exported once).
   This is not new infrastructure, it's the existing pattern applied to one more element, and it
   means there's no real risk of shipping something that violates the project's accessibility bar.
5. **Production mechanism, concretely:** record a short MP4/HEVC loop via
   `XcodeBuildMCP`/`ios-simulator` screen capture of the existing approval-card + terminal UI
   (already-built, already-screenshotted elsewhere in `docs/design-audit/`), trim to 3–6 seconds,
   loop it muted with `AVPlayerLooper` or a simple `VideoPlayer` + manual loop, no audio, no
   captions needed since there's no spoken content. This is a same-day asset, not a production
   pipeline — closer in cost to taking another screenshot than to commissioning video.

**If a true looping screen-recording feels like too much for V1**, the fallback that's still a
real improvement over today and even cheaper: keep static screenshots, but replace the three
abstract icon tiles with **one real cropped screenshot of the actual `InboxApprovalCard`** (no
animation at all) the way Vibecode's reference does — same "show, don't tell" win, zero motion
code, zero Reduce Motion fallback needed because there's nothing to reduce. This is the
lowest-risk version of the same fix and should be the fallback if the looping-video version proves
fiddly to ship cleanly within V1 scope.

## 5. What NOT to do

- **Do not use lifestyle/stock video behind the hero or value text**, the way How We Feel,
  Pliability, or Tabby do. Every one of those examples sells an emotional mood unconnected to what
  the product actually does on tap — for Lancer that would mean stock footage of "someone looking
  at a laptop" or "a person coding," which is generic, says nothing the real product UI couldn't
  say better, and is the definition of "padding" the owner is trying to avoid by asking for
  something "more informational."
- **Do not commission a founder/talking-head video** (Airbnb's pattern). Beyond being wildly
  out of scope for V1, it creates an ongoing content-production dependency (re-shoot whenever the
  pitch changes) that directly fights the project's "no overbuild" constraint and the "ask
  first / smallest sensible IA" working rules already established in `01-onboarding-pairing-workflow.md`.
- **Do not build a multi-screen feature-tour-per-concept carousel** (Linear's one-screen-per-
  feature pattern, or Pliability's later "Tailor Your Content / Take your first Mobility Test"
  list). `01-onboarding-pairing-workflow.md` already found Lancer's *page count* was too high
  relative to its closest comparable (Raycast: one screen) and recommended collapsing screens, not
  adding more. A richer single screen is consistent with that prior finding; a tour with more taps
  is not.
- **Do not let the visual fix outrun the merged-screen decision already made.** The `valuePair`
  step already combines value content with the live pairing form on one scroll. Whatever replaces
  the three rows needs to stay compact enough that the pairing code field below it is still
  reachable without excessive scrolling on small devices — a large autoplaying video plus the full
  pairing block risks recreating the "too much on one screen" problem from the opposite direction.

---

## Summary

The current value screen (`OnboardingValueRows`) fails not because it's "plain" but for three
specific reasons: its icons (a checkmark, a `"›_"` glyph, a shield) illustrate words instead of
showing the real, already-built approval card and terminal UI; it gives the #1 V1 priority
(remote approval) the same visual weight as two lesser features; and it's 100% static
typography/iconography in an app whose actual product is unusually demo-able. Mobbin research
found no dev-tool or technical-SaaS example using a true video background — that pattern is a
lifestyle/consumer convention (How We Feel, Pliability, Tabby) that would read as padding for
Lancer. The strongest references are Vibecode's real-screenshot-in-a-device-frame and Granola's
screenshot-pair-above-feature-rows — both prove the product instead of describing it. Recommend
replacing the three rows with one real looping screen-recording (or, as a lower-risk fallback, a
single static screenshot) of the actual approval-card/terminal UI, which is both cheaper to
produce than stock video and more honest, with a mandatory Reduce Motion static-frame fallback
using the existing `accessibilityReduceMotion` pattern already in this file. The hero gradient
itself should stay static brand chrome — motion belongs in the value content area it currently
occupies, not behind the headline.
