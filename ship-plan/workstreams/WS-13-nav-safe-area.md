# WS-13 — Navigation / safe-area polish  (post-launch; low risk)

> Depends on WS-0. Mostly verification + small spacing fixes. Best done on a device/sim with a notch + home indicator.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. Read `CLAUDE.md` "Visual verification".

**Areas to audit:** the bottom `DSTabBar` (fixed 64pt, `DesignSystem/Components/Composites.swift:570–622`) and its `safeAreaInset(.bottom)` + `safeAreaPadding(.bottom)` wiring in `AppFeature/AppRoot.swift:488–519`; the session composer inset (`SessionView.swift:137–141`). Source marks this **SUSPECTED — needs on-device confirmation** (code respects insets; real-device check pending).

## Tasks
1. On a notch / home-indicator device (or matching simulator), confirm no control sits too high or collides with the Dynamic Island / home indicator, and that pushed detail views inherit correct insets.
2. Fix any spacing/inset issues found; capture before/after screenshots.
3. Confirm tab-bar height is correct across device classes.

## Acceptance
- Consistent spacing, no safe-area overlap, correct tab-bar height across devices; detail views inherit insets. Before/after screenshots. Build + suite green.

## Report Template (fill in, return)
```
## WS-13 Report
### Device(s) checked: <model/sim>
### Findings: <tab bar / composer / detail views — overlap? fixed?>
### Before/after screenshots: <paths>
### Build/Suite: <green/red> · Files changed: <list> · Deviations/risks:
```
