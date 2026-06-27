---
name: lancer-design-handoff
description: Use when generating, regenerating, or updating the Lancer design handoff or screen/page inventory — listing every screen the app actually has, capturing screenshots, and writing per-page descriptions. Especially when an old handoff has gone stale (screenshots show the old design) and must be rebuilt from current code.
---

# Lancer Design Handoff

## Overview

Regenerate the design handoff so it **cannot go stale**. The screen list is always derived
from current Swift source and gallery routes — never from an old doc or memory. Screenshots are
captured fresh for everything the gallery can render; everything else is listed with source +
purpose so a human can shoot it. This is the task from the 2026-06-24 session where the prior
handoff showed the *old* design and had to be rebuilt by hand.

**Why this skill exists:** the recurring failure is a handoff whose page list and screenshots
drift from the shipped UI. Deriving both from code each run removes the drift at the root.

## Hard rules

- **Derive the screen set from code, not from the existing handoff.** The old doc is suspect.
- **Delete the old screenshots dir before capturing** — never let a stale PNG survive a rerun.
- **The old `LANCER_GALLERY` debug gallery was deleted (2026-06-24).** Do not reference it.
  Screenshots now come from the **real app**, seeded and deep-linked via env (below). **Re-verify
  the env knobs against `AppRoot.swift` before each run** — they drift.
- Screens with no deep-link land via in-app navigation; if you can't reach one, mark it
  `screenshot: manual`, not a guessed image. In the source session the owner explicitly said
  "I'll get the screenshots myself, just make the list" — honor that split.

## Workflow

1. **Build the live screen inventory (from code).**
   - List every view: `rg -n 'struct \w+: View' Packages/LancerKit/Sources/AppFeature` (and
     `DesignSystem` if documenting components).
   - List the deep-link destinations: read the `LANCER_DESTINATION` switch in `AppRoot.swift`
     (at time of writing: `inbox`, `governance`, `machines`, `sessions`, `settings` — **re-grep,
     don't trust this list**). These are root screens reachable in one launch.
   - Mark each view: **deep-linkable** (a `LANCER_DESTINATION` case) vs **nav-depth** (reached by
     tapping into a deep-linked root) vs **onboarding** (seen before the shell).

2. **Capture screenshots from the real app.** Build the app target once (XcodeBuildMCP app-target
   build, after `session_show_defaults`), then per root screen, both appearances:
   - `mcp__XcodeBuildMCP__launch_app_sim` with
     `env: { LANCER_SEED_DEMO: "1", LANCER_DESTINATION: "<dest>" }` — seeds demo data (via
     `DebugSeeder`) and lands directly in that screen, skipping onboarding.
   - Wait ~1–2 s, then `mcp__XcodeBuildMCP__screenshot`. For the other appearance, change it
     **in-app** (Settings → Appearance) — the app forces `.preferredColorScheme`, so
     `simctl ui appearance` has **no effect**. Default is `.light`. One appearance is usually
     enough for a handoff unless the owner asks for both.
   - For nav-depth screens: from the seeded root, drive in with
     `mcp__ios-simulator__ui_find_element` / `ui_tap`, then screenshot.
   - For onboarding screens: launch without `LANCER_DESTINATION` (onboarding not yet seen).

3. **Write one handoff section per screen**, in screen order:
   - Name · source file (`file_path:line`) · how reached (`LANCER_DESTINATION=x` / `nav from x` /
     `onboarding`) · one-line purpose · key states · DesignSystem components used (`DSButton`,
     `DSQuoteBlock`, `PixelBox`, …) · screenshot path or `manual`.

4. **Save** to the handoff doc the owner names (recent: `~/Downloads/lancer-audit-*/design-handoff/`).
   Screenshots into a sibling `screenshots/` dir that you emptied in step 0.

5. **Verify the inventory is complete:** every `struct …: View` in `AppFeature` is either in the
   handoff or explicitly excluded (preview providers, row subviews). State the count covered.

## Done when

A handoff doc exists with a section per current screen, fresh screenshots for every deep-linkable
root in both appearances, nav-depth/unreachable screens listed with source + `manual`, and a
stated count of views covered vs. excluded.
