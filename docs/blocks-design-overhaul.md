# BLOCKS design overhaul

Branch: `feat/blocks-design-system` · Base: `feat/warp-style-agent-blocks`

A full re-skin of the Lancer iOS app to the **BLOCKS** visual language: a dark,
square-cornered, electric-blue, monospace-first terminal aesthetic. The overhaul
re-themes the design tokens and typography at the foundation, squares and recolors
every atomic component, and migrates each tab screen onto the BLOCKS layout
patterns — without touching the SSH/block-terminal pipeline.

## The look

| Axis | Before (mother-duck-2) | After (BLOCKS) |
|---|---|---|
| Primary surface | light | dark `#0a0b0d`, terminal always-dark |
| Accent | warm orange | electric blue |
| Corners | rounded | **square** — `r3`/`r4` = 0 (cards, buttons, inputs); chips/tags `r2` = 2 |
| Display face | sans | **Chakra Petch** (wordmark, titles, section heads, tab labels) |
| Mono/body face | Fragment Mono | **Fira Code** (body, UI, terminal, labels, code) |
| Body text | sans | monospace by design (`dsSans*` is now an alias onto Fira Code) |

## Phases

- **Phase 0 — checkpoint** (`971cf90`): committed pending work before the overhaul.
- **Phase 1 — foundation** (`20923ac`): re-theme `Tokens.swift` (radii → square,
  light/dark/DI palettes → blue, famicom spectrum tokens) and `Typography.swift`
  (faces → Chakra Petch + Fira Code, terminal mono references repointed to Fira
  Code). Old TTFs removed; `FontRegistration` updated.
- **Phase 2/3 — components** (`9ab2850`): square + recolor the atoms — `DSChip`,
  `RiskBadge`, `AgentBadge`, `AgentIdentityBadge`, search field (`$` terminal
  prompt), empty state (dot-matrix mood), tab bar (blue active state + 2px top
  indicator, raised surface). New composed pieces: `DSScreenHeader` (BLOCKS
  `Head1` pattern with breadcrumb + spectrum rule), square icon button.
- **Phase 4 — screen migration** (`d15f38d`): Sessions home (BLOCKS bordered block
  rows, dot-matrix empty state), Inbox, Settings, Onboarding, Hosts — each onto the
  screen-header pattern and BLOCKS structures.
- **Phase 5 — fixes + verify** (`561dcd5`):
  - `DSButton .primary` → accent blue (was near-black `text`); the single filled
    CTA is electric blue. Fixes the white "Save keys" button.
  - `DSSegmentedPicker` active segment → blue fill, white Fira Code text (was a
    subtle surface fill). Fixes the unhighlighted theme picker.
  - `DSAutonomyPresetBar` → `.fixedSize(horizontal: false, vertical: true)` on the
    segmented `HStack` so the 1px dividers hug content height instead of stretching
    the bar vertically.

## Verification

- `cd Packages/LancerKit && swift build` — clean.
- `xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS
  Simulator,name=iPhone 17 Pro' build` — **BUILD SUCCEEDED**.
- Driven live in the simulator (real app, not gallery): Settings (blue Save-keys +
  blue theme segmented control), Inbox (compact autonomy bar, no stretch), Sessions
  home — confirmed on-brand in light and dark.

Gallery routes used for component checks: `components`, `inbox-typed`, `settings`.
See `CLAUDE.md` → "Visual verification process" for the launch/screenshot harness.

## Scope boundary

The SSH/block-terminal byte pipeline (`PTYBridge` → `SessionViewModel` →
`BlockRenderer`) was **not** changed. `ToolCardView` / `DSBlockCard` inherited the
BLOCKS look for free via the token re-theme (`radiusMD` → 0, terminal surfaces →
BLOCKS dark values, `termPrompt` → blue); no structural edits were needed there.
