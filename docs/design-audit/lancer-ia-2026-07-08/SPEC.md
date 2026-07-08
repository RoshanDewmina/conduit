# Lancer IA Wireframe Spec — Approach A (2026-07-08)

Design source of truth for the Cursor-style 3-root shell rebuild. Interactive prototype: `prototype.html`. Board: `index.html`.

## Information architecture

Three persistent roots via bottom tab bar:

| Root | Purpose | Composer |
|------|---------|----------|
| **Home** | Blocked-on-you interrupt queue | Yes |
| **Workspaces** | Repo list, attention badges, add repo | Yes (pill) |
| **Settings** | Pairing, policy, LA prefs, account, danger | **Never** |

Depth surfaces push on a stack (back chevron). Composer appears on Home, Workspaces (when in repo context), and Work Thread only — never on Settings, Review/Diff, PR detail, Search, or Onboarding.

## Home

### Full state
- Connection banner when relay degraded
- **Needs you** group: interrupt rows with chips (Approve / Question / Failed)
- Low-risk Approve rows support **swipe Approve/Deny** (Home only)
- **Today** group: running + completed threads
- **Quiet runs** collapsed strip: "N agents running quietly" — tap expands list
- Persistent composer above tab bar

### Empty state
- **All clear** hero copy
- Quiet-run count ("2 agents running quietly")
- Composer remains — user can start new work without leaving Home

### Demo triggers
- Fire approval → adds high/low risk row
- Ask question → adds Question chip row
- All clear → switches to empty Home
- Toggle risk → flips current approval between low (swipe) and high (Review only)

## Workspaces

- **All Repos** aggregate row with attention badge
- Per-repo rows with attention badges (needs-you count)
- **Add Repo** row → onboarding/pairing sheet
- Tap repo → **thread list** (Yesterday / This Week sections)
- Status icons: Needs you · Running · Checks · Merged
- Composer pill at bottom when viewing repo thread list

## Work Thread (artifact family)

Shared visual language — bordered cards, not chat bubbles:

| Artifact | Role | Motion |
|----------|------|--------|
| Prompt | User instruction | enter stagger |
| Streaming | Agent output in progress | cursor pulse |
| Question | Agent blocked on input | spring-in; answered state syncs from Home |
| Receipt | Command + exit code | spring-in |
| Proof Reel | Scrubbable log timeline | scrub interaction |
| Changes peek | File list + diff stats | enter stagger |
| Approval banner | Risk + action rail | warn tint |

**Action rail:** Review · Deny · jump-to-bottom chevron (visible while streaming)

**Follow-up composer** at bottom (same rules as Home).

Answered Question cards show green "answered" state when resolved from Home swipe or thread reply.

## Review / Diff

- Real approval bind mock: command `git apply`, target file, risk hero
- Approve / Deny / Reply decision bar
- Full diff view with +/- lines
- **No composer**
- High-risk only path from Home/DI — low-risk never lands here

## PR / Ship detail

- Open PR link, check status rows
- Create PR / branch actions
- **No merge from phone**
- **No composer**

## Overlays

### Composer expanded
- Repo · branch picker
- Model selector
- **+ Context** sheet: photos, screenshots, camera, files

### Search
- Filter chips: All · Needs you · per-repo
- Result rows deep-link to thread or review

### Onboarding (5 steps)
1. Welcome + value
2. Pair machine (6-digit code)
3. Notifications permission
4. Policy / risk threshold
5. Account / plan choice

## Live Activity + Dynamic Island

**One selective activity** per active run (not per-agent Islands).

| State | LA lock screen | DI compact | DI expanded |
|-------|----------------|------------|-------------|
| Running | repo + elapsed | blue dot + "Running" | progress, Open |
| Needs-you (low) | approve prompt | warn dot | **Approve / Deny** on Island |
| Needs-you (high) | review prompt | warn dot | **Open Review** only |
| Done | checks passed | green dot | Open thread |

**Trust line** (shown on LA widget): "Lancer never executes without your approval on this device."

**Emergency stop:** in-app confirm sheet only — Island deep-links to app, does not silent-stop.

**Morph demo:** Running → Needs-you steals Island with animation.

## Settings additions

- **Decisions while locked** explainer row (LA prefs section)
- Live Activity risk threshold toggle
- Pairing, policy/audit, notifications, account/plan, diagnostics, danger zone
- No composer anywhere in Settings subtree

## Motion bar

- UI transitions: 180–240ms
- Sheets: ~320ms cubic-bezier spring
- Question/receipt: spring arrival
- Artifact enter: staggered fade-up
- DI: compact ↔ expanded morph; Running → Needs-you interrupt
- Proof Reel: scrub with thumb
- `prefers-reduced-motion`: opacity-only fallbacks

## Visual reference

- Cursor Mobile App screenshots (`~/Downloads/Cursor Mobile App/`) for chrome fidelity
- Jul 5 audit prototype for phone frame + theme toggle patterns (content rebuilt, not copied)

## Out of scope

- Real `lancerd` / APNs integration
- SwiftUI implementation
- Watch, merge-from-phone, Return-to-Desk, per-agent Islands

## Success criteria

- [ ] Every screen reachable in `prototype.html`
- [ ] Composer presence matches rules per surface
- [ ] Work Thread artifacts share visual system + motion
- [ ] LA/DI trust line + low/high risk actions correct
- [ ] Owner approves before Swift implementation
