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

- **`LANCER_DESTINATION`** — land directly in the Cursor shell, onboarding skipped. Values:
  `inbox` / `approval` / `review` (open the approval Review sheet) · `settings` / `governance`
  (open the Settings sheet); anything else → the Workspaces root.
- **`LANCER_SEED_DEMO=1`** — populate demo hosts/approvals/snippets so screens aren't empty.

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

- Tokens: `DesignSystem/Tokens.swift`. Components: `DesignSystem/Components/` and
  `DesignSystem/Cursor/Components/` (the Cursor shell's own set).
- **Use the existing components — don't reinvent:**
  - `DSButton` — `.primary` (WHITE) / `.accent` (ORANGE, brand CTA) / secondary / ghost / destructive;
    pass `mono: true` for terminal-context labels. Use `.accent` for brand CTAs, not `.primary`.
  - Cursor shell surfaces use `CursorPillButton` / `CursorDrawer` / `CursorArtifactCard` etc. from
    `DesignSystem/Cursor/Components/`.

## Verify a component change

1. Edit the component in `DesignSystem/Components/`.
2. `cd Packages/LancerKit && swift build` — zero errors.
3. Relaunch with a seam that shows it (`SIMCTL_CHILD_LANCER_SEED_DEMO=1 SIMCTL_CHILD_LANCER_DESTINATION=…`).
4. Screenshot and check both appearances via the in-app appearance toggle.
