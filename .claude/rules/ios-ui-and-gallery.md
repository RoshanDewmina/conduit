---
paths:
  - "Packages/LancerKit/Sources/AppFeature/**"
  - "Packages/LancerKit/Sources/DesignSystem/**"
---
# iOS UI: gallery harness, screenshots, design system

The only way to see Lancer UI is the iOS Simulator — there is no web renderer.

## Debug gallery (mock UI, no SSH)

`DebugGalleryView` renders screens without a live connection. `AppRoot.swift` reads
`LANCER_GALLERY`; `simctl` strips the `SIMCTL_CHILD_` prefix:

```bash
xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
SIMCTL_CHILD_LANCER_GALLERY=review xcrun simctl launch booted dev.lancer.mobile
```

Routes (`switch route` in `DebugGalleryView.swift`): `review` (default), `components`, `chat`,
`diff`, `filepreview`, `onboarding`, `orb-connecting`, `orb-connected`, `blocks` (static mock),
`session` (real live SSH — see `terminal-blocks` rule). Prefer
`mcp__XcodeBuildMCP__launch_app_sim` with an `env:` map — it adds the `SIMCTL_CHILD_` prefix
itself and sidesteps the propagation gotcha.

## Screenshots

Wait ~1–2 s after launch before `xcrun simctl io booted screenshot` (or
`mcp__XcodeBuildMCP__screenshot`) — earlier frames are blank or mid-animation. Wrong sim booted →
`xcrun simctl list devices booted`. Check both appearances:
`xcrun simctl ui booted appearance dark|light`. For tap targets / on-screen assertions use
`mcp__ios-simulator__ui_describe_all` / `ui_find_element`, not a bare PNG.

## Verify a component change

1. Edit the component in `DesignSystem/Components/`.
2. `cd Packages/LancerKit && swift build` — zero errors.
3. Relaunch the gallery (`SIMCTL_CHILD_LANCER_GALLERY=review …`).
4. Screenshot and check **both** appearances (`xcrun simctl ui booted appearance dark|light`).

## Design system

- Tokens: `DesignSystem/Tokens.swift`. Components: `DesignSystem/Components/`. Canonical visual
  reference for every component: `AppFeature/DebugGalleryView.swift`.
- **Use the existing components — don't reinvent:**
  - `DSButton` — primary/accent/secondary/ghost/destructive; pass `mono: true` for terminal-context labels.
  - `DSQuoteBlock` — left-bar callout (title/tags/body); tone maps to severity (ok/warn/accent/danger).
  - `DSLink` — underlined accent inline link; needs a real action to be meaningful.
  - `DSDiffChips` — "X → Y" status-transition chips. `PixelBox` — animated agent-state grid.
    `PixelAvatar` — deterministic pixel avatar seeded by a string (host name, etc.).
- **Layout invariant:** list rows reserve a fixed-width trailing slot for the unread badge even
  when empty (`ZStack(alignment: .trailing) { … }.frame(width: 20, alignment: .trailing)`) so the
  animated `PixelBox` never shifts horizontally between rows. Reference: `ReviewSessionRow` in
  `DebugGalleryView.swift`.
