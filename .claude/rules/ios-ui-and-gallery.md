---
paths:
  - "Packages/LancerKit/Sources/AppFeature/**"
  - "Packages/LancerKit/Sources/DesignSystem/**"
---
# iOS UI: launch seams, screenshots, design system

The only way to see Lancer UI is the iOS Simulator — there is no web renderer. The old
The old mock-gallery harness was **deleted**; the seams below replace it.

## DEBUG launch seams (skip onboarding, seed state)

`AppRoot.swift` reads these env vars (all `#if DEBUG`):

- **`LANCER_DESTINATION`** — land directly in the sidebar shell, onboarding skipped. Values:
  `inbox` · `governance` · `machines` · `sessions` · `settings` (anything else → home).
- **`LANCER_SEED_DEMO=1`** — populate demo hosts/approvals/snippets so screens aren't empty.
- **`LANCER_FAKE_RELAY_HOST=<name>`** — simulate a paired, live relay host (Home's machine list
  renders without a real relay; the real bridge subscription early-returns so it isn't clobbered).
- Live SSH session: `LANCER_DAEMON_E2E=1` + `LANCER_TEST_HOST/USER/PW/PORT` — see `terminal-blocks` rule.

`simctl` strips the `SIMCTL_CHILD_` prefix when forwarding env to the app:

```bash
xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
SIMCTL_CHILD_LANCER_SEED_DEMO=1 SIMCTL_CHILD_LANCER_DESTINATION=governance xcrun simctl launch booted dev.lancer.mobile
```

Prefer `mcp__XcodeBuildMCP__launch_app_sim` with an `env:` map — it adds the `SIMCTL_CHILD_` prefix
itself and sidesteps the propagation gotcha (chaining env after build/install drops the vars).

## Screenshots

Wait ~1–2 s after launch before `mcp__XcodeBuildMCP__screenshot` (or `xcrun simctl io booted
screenshot`) — earlier frames are blank or mid-animation. Wrong sim booted →
`xcrun simctl list devices booted`. **Appearance is in-app, not `simctl`:** the app is
`@AppStorage`-driven and forces `.preferredColorScheme`, which overrides `simctl ui appearance`
(that command is a no-op here) — toggle light/dark via the in-app Settings control. For tap targets /
on-screen assertions use `mcp__ios-simulator__ui_describe_all` / `ui_find_element`, not a bare PNG.

## Design system

- Tokens: `DesignSystem/Tokens.swift`. Components: `DesignSystem/Components/`.
- **Use the existing components — don't reinvent:**
  - `DSButton` — `.primary` (WHITE) / `.accent` (ORANGE, brand CTA) / secondary / ghost / destructive;
    pass `mono: true` for terminal-context labels. Use `.accent` for brand CTAs, not `.primary`.
  - `DSQuoteBlock` — left-bar callout (title/tags/body); tone maps to severity (ok/warn/accent/danger).
  - `DSLink` — underlined accent inline link; needs a real action to be meaningful.
  - `DSDiffChips` — "X → Y" status-transition chips. `PixelBox` — animated agent-state grid.
    `PixelAvatar` — deterministic pixel avatar seeded by a string (host name, etc.).
- **Layout invariant:** list rows reserve a fixed-width trailing slot for the unread badge even
  when empty (`ZStack(alignment: .trailing) { … }.frame(width: 20, alignment: .trailing)`) so the
  animated `PixelBox` never shifts horizontally between rows.

## Verify a component change

1. Edit the component in `DesignSystem/Components/`.
2. `cd Packages/LancerKit && swift build` — zero errors.
3. Relaunch with a seam that shows it (`SIMCTL_CHILD_LANCER_SEED_DEMO=1 SIMCTL_CHILD_LANCER_DESTINATION=…`).
4. Screenshot and check both appearances via the in-app appearance toggle.
