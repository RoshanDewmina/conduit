# WS-9 — UI standardization & accessibility  (covers 17-pt #4)

> Depends on WS-0. Quality pass; low risk; no behavior changes. Verify everything in the gallery, light AND dark.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. **Read `CLAUDE.md` "Visual verification process"** — exact simulator launch + screenshot commands + the fixed-geometry invariant. Design tokens: `Sources/DesignSystem/Tokens.swift`; components: `Sources/DesignSystem/Components/`; gallery: `AppFeature/DebugGalleryView.swift`. Dynamic Type already shipped (pt fonts scale via `relativeTo:`; terminal/fixed-geometry capped at `accessibility3`).

> ⚠️ **VERIFY FIRST — partially done already.** Recent commits `dafa6ba` ("…UI standardization") and `858b688` ("…approval-card header, PixelBox glow, a11y guards") overlap this list (PixelBox glow/#4, header placement, a11y). Audit current state before changing anything; only fix what's still broken, and verify the rest rather than redoing it. The "confirmed debt" below is from a draft audit that predates those commits.

**Confirmed debt (from the source audit — re-verify against current code):**
- **#4 Session row** (`SessionsHomeView.swift:261–337`): PixelBox is already a 3×3 grid with a `subdivisions` param (`PixelBox.swift:70–85`) — the owner's "dominant 3×3 + subtle subpixels + emphasized glow" is a **tuning** job, not a rebuild.
- `.system` fonts instead of DS in `AgentIsland` + `AgentStatusHeader` (extensive), `FilesView` (uses `.system` mono instead of `dsMonoPt`), and the debug **REVIEW** pill (hardcoded `.system`, **overlaps content** in screenshots — a debug affordance leaking into normal views).
- **Header placement inconsistent:** `AgentStatusHeader` sits *below* the title on Sessions but *above* it on Hosts/Inbox/Settings. Unify (below title on all).
- **"· Done"** on a freshly-connected idle session should read "Connected"/"Ready".
- Non-canonical raw padding instead of tokens; island `DI` colors live in a component enum instead of `Tokens.swift`. Settings Theme uses a stock segmented `Picker`.
- Stub rows that imply unfinished features: iCloud "Sync status" + "Billing & usage" — gate/hide for v1 where they imply non-working capability (Billing is real now via WS-4; **Sync is still push-only → hide it**).

## Tasks
1. **#4** Tune the session-row PixelBox: dominant 3×3, subtle subpixels, emphasized glow per state. Keep the **fixed-geometry invariant** — the unread slot is `ZStack(alignment:.trailing){…}.frame(width:20,alignment:.trailing)` so PixelBox never shifts horizontally between rows.
2. **Kill `.system` fonts** in `AgentIsland`, `AgentStatusHeader`, `FilesView` → DS fonts (`dsMonoPt` etc). Move island `DI` colors into `Tokens.swift`. Tokenize raw padding.
3. **Unify the status header** below the title on all tabs; relabel "· Done" → "Connected". Replace the Theme stock `Picker` with a DS segmented control.
4. **Remove/relabel the debug REVIEW pill** so it never overlaps content in normal views (gate behind `#if DEBUG` — coordinate with WS-7).
5. **Hide the iCloud Sync stub row** for v1 (keep code, gate UI — sync is push-only).
6. **Accessibility pass:** meaningful labels/traits on buttons, session rows, block cards, key rows; PixelBox/PixelAvatar decorative art `accessibilityHidden` or sensibly labeled; block transcript navigable. Verify Dynamic Type at `accessibility3`/`accessibility5` (no clipping; terminal stays capped) and that animations respect **Reduce Motion**.
7. **Light/dark audit** across routes (`review`, `components`, `chat`, `diff`, `onboarding`, `blocks`, `orb-connecting`, `orb-connected`): screenshot each in both appearances; flag contrast/clip/alignment issues.

## Constraints
- No behavior changes — visual/a11y only. · Verify in the gallery per CLAUDE.md (wait ~2s post-launch; correct simulator booted).

## Acceptance
- #4 PixelBox tuned, fixed-geometry invariant intact. · `.system` fonts gone from the three views; colors tokenized. · Header unified; "Connected" label; DS Theme control; REVIEW pill gated; Sync stub hidden. · a11y labels added; Dynamic Type + Reduce Motion verified. · Light+dark screenshots for each route. · Build + suite green.

## Report Template (fill in, return)
```
## WS-9 Report
### #4 PixelBox tuning: <changes + screenshot; fixed-geometry intact?>
### .system fonts removed: AgentIsland <y> AgentStatusHeader <y> FilesView <y> · colors tokenized <y>
### Header unified <y> · "Connected" label <y> · DS Theme control <y> · REVIEW pill gated <y> · Sync stub hidden <y>
### a11y: labels/traits added <where> · Dynamic Type a3/a5 <clipping?> · Reduce Motion <respected?>
### Light/dark audit: <routes covered + findings + screenshot paths>
### Build/Suite: <green/red, count> · Files changed: <list> · Deviations/risks:
```
