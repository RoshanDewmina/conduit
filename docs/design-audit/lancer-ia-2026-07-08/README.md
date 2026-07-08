# Lancer IA Wireframe Kit — 2026-07-08

Near-final interactive HTML wireframes for Approach A (3-root Cursor shell).

## Open these files

| File | Purpose |
|------|---------|
| **[prototype.html](prototype.html)** | Primary interactive app — tap through every screen |
| **[index.html](index.html)** | Board with static phone frames + theme toggle |
| **[SPEC.md](SPEC.md)** | Design spec (IA, LA/DI, composer rules, motion) |
| [tokens.css](tokens.css) | Shared light/dark design tokens |
| [motion.css](motion.css) | Animation system |

Canvas map (open beside chat):  
`/Users/roshansilva/.cursor/projects/Users-roshansilva-Documents-command-center/canvases/lancer-ia-wireframe-map.canvas.tsx`

## Quick start

```bash
open docs/design-audit/lancer-ia-2026-07-08/prototype.html
```

Or serve locally if your browser blocks file:// interactions:

```bash
cd docs/design-audit/lancer-ia-2026-07-08 && python3 -m http.server 8765
# → http://localhost:8765/prototype.html
```

## prototype.html — what to click

### Tab bar (always visible on roots)
- **Home** · **Workspaces** · **Settings**

### Demo bar (below phone)
- **Fire approval** — inject interrupt row
- **Ask question** — inject question row
- **All clear** — switch Home to empty state
- **Toggle risk** — flip approval low ↔ high
- **Show LA** — lock screen Live Activity overlay
- **Morph DI** — Running → Needs-you Island animation

### Home
- Tap interrupt rows → Work Thread or Review (high risk)
- Swipe low-risk Approve rows left → Approve/Deny actions
- Tap quiet-runs strip → expand running agents
- Composer → expanded composer + context sheet
- Search icon (top right) → Search overlay

### Workspaces
- Tap repo → thread list → thread
- Add Repo → pairing sheet

### Work Thread
- Proof Reel scrubber — drag or click track
- Review / View PR pills in action rail
- Jump-to-bottom chevron while streaming

### Settings
- No composer — verify absence
- "Decisions while locked" under Live Activity section

## Theme + accessibility

- System light/dark via `prefers-color-scheme`
- Manual override on `index.html` board (Light / Dark / System)
- `prefers-reduced-motion` disables animations (opacity fallbacks remain)

## Screen inventory

1. Home (full + empty)
2. Workspaces
3. Settings
4. Repo thread list
5. Work Thread
6. Review / Diff
7. PR / Ship detail
8. Composer + Context sheet
9. Search
10. Onboarding (5 steps)
11. Live Activity lock screen
12. Dynamic Island (compact + expanded)

## Archive note

Does not overwrite `docs/design-audit/lancer-workflows-2026-07-05/` — that folder remains the Jul 5 audit archive.
