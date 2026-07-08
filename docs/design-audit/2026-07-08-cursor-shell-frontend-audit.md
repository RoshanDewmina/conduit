# Lancer iOS Cursor Shell — Frontend Audit (2026-07-08)

**Auditor:** Composer 2.5 (frontend audit pass)  
**Repo tip:** `732071a7` + branch `fix/frontend-audit-p0`  
**Reference:** A3 screen-map `docs/design-reference/cursor-mobile-2026-07-08/screen-map.md` (commit `c461d56b`); A3 merges #63–#66  
**Launch seams:** `LANCER_CURSOR_SHELL=1` (mock), `LANCER_CURSOR_SHELL_LIVE=1` (live bridge via `AppRoot` → `CursorAppShell(liveBridge:)`)  
**Build evidence:** XcodeBuildMCP `build_sim` ✅ (iPhone 17 Pro, 2026-07-08); mock shell `build_run_sim` with `LANCER_CURSOR_SHELL=1`

---

## Executive summary

The **production Cursor shell is reachable and mostly wired** for Tier-0 dogfood (Workspaces → thread list → work thread → composer/dispatch, live bridge, approval sheet, pairing, settings). A3 token rebuilds (#57, #63–#66) landed; several surfaces still **force light** or are **IA-incomplete** vs the approved 3-root wireframe kit (`docs/design-audit/lancer-ia-2026-07-08/`).

**Top P0 (blocks dogfood):**

| # | Issue | Status this pass |
|---|--------|------------------|
| P0-1 | **No dedicated Home root** — shell is a single `NavigationStack` rooted at Workspaces; wireframe/Home attention module only appears inside thread lists, not as a tab/root | Open (IA scope) |
| P0-2 | **Dismissed Review sheet → no recovery** on Workspaces/thread list when `pendingApprovalID` still set | **Fixed** (`onOpenReview` + banners on Workspaces + thread list) |
| P0-3 | **Review stale "Approved" + blank Request** after decision clears live binding | **Mitigated in #66** (`boundApproval` snapshot); re-verify on device |
| P0-4 | **Run-target picker no-op** — `CursorRunOnSheet.onSelect` dismisses without changing machine | Open |

**Top P1:**

| # | Issue |
|---|--------|
| P1-1 | Hardcoded `.light` / `CursorColors.light` in onboarding step internals, some stub sheets |
| P1-2 | Settings stub destinations + Reset app data button are placeholders (no-op) |
| P1-3 | PR detail / ship / squash flows are mock-only (not live-wired) |
| P1-4 | Composer context sheet opens but Photos/Camera/Files/MCP are no-ops |
| P1-5 | `+` header on Workspaces opens pairing, not composer (differs from wireframe #1) |

---

## Navigation topology (actual vs spec)

```
AppRoot (live)
  └─ cursorShellRoot
       └─ CursorAppShell(liveBridge: cursorLiveBridge)
            ├─ [onboarding] CursorOnboardingView  → hasCompletedOnboarding
            └─ NavigationStack (root = CursorWorkspacesView)
                 ├─ push: CursorWorkspaceThreadListView
                 ├─ push: CursorWorkThreadView
                 ├─ push: CursorPRDetailView → CursorFileDiffScreen
                 ├─ push: CursorReviewDiffView (mock path)
                 ├─ sheet: CursorProfileDrawer → CursorSettingsView
                 ├─ sheet: CursorSearchOverlay
                 ├─ sheet: CursorRepoPickerSheet
                 ├─ sheet: CursorComposerSheet → CursorContextSheet / RunOn / Model
                 └─ sheet: CursorWorkspaceDetailSheet (long-press repo)

AppRoot (parallel sheets, live only)
  ├─ showingApprovalReview → CursorReviewDiffView
  ├─ showingCursorRelayPairing → CursorRelayPairingSheet
  └─ showingCursorSettings → cursorSettingsSheet (legacy seam)

DEBUG mock: LANCER_CURSOR_SHELL=1 → CursorAppShell() without liveBridge (seed data)
```

**IA drift:** `ARCHITECTURE.md` §4.1 and `lancer-ia-2026-07-08` specify **Home / Workspaces / Settings** tab roots. Shipped code deliberately has **no `TabView`** (`CursorAppShell` comment) — Workspaces is the only root. `CursorHomeView` is **referenced in comments only** (never implemented).

---

## Surface inventory

| Surface | File(s) | Live / Mock / Half | Tokens post-A3 | Broken interactions | Sev |
|---------|---------|-------------------|----------------|---------------------|-----|
| **Workspaces root** | `CursorWorkspacesView.swift` | Live: `liveBridge.workspaces`; Mock: seed rows | ✅ `@Environment(\.cursorScheme)` | `+` → pairing not composer; Add Repo sheet is stub | P1 |
| **Connection banner** | `CursorConnectionBanner.swift`, wired in Workspaces | Live: `connectionPhase` from `AppRoot.refreshCursorLiveBridge` | ✅ | "Reconnecting" with 0 machines (sim fresh install) — expected until paired | P2 |
| **Pending approval banner** | `CursorApprovalBanner.swift` | Live: `pendingApprovalID`; Mock: always on Work Thread | ✅ | Was only on Work Thread — **fixed** on Workspaces + thread list | P0→fixed |
| **Workspace thread list** | `CursorWorkspaceThreadListView.swift` | Live threads + Needs-you ordering via `CursorThreadAttention` | ✅ | Needs-you only when `threadStates` populated from refresh | P2 |
| **Home attention copy** | `CursorThreadAttention.swift` `homeAttentionStatusMessage` | Live | ✅ | "All clear" suppressed when `!relayHealthy` | ✅ |
| **Work thread** | `CursorWorkThreadView.swift` | Live: `activeThread*` bridge fields | ✅ | Overflow menu mostly no-op; View PR is mock navigation | P1 |
| **Review / Diff** | `CursorReviewDiffView.swift` | Live: `pendingApproval` + `lookupApproval`; sheet via AppRoot | ✅ (sheet gets `cursorResolvedScheme`) | `boundApproval` fix #66; Reply button sets local state only (`relay: nil`) | P1 |
| **PR detail** | `CursorPRDetailView.swift` | **Mock** hardcoded PR | ✅ | Squash/merge not wired to daemon | P1 |
| **Composer** | `CursorComposerSheet.swift`, `CursorBottomComposer.swift` | Live: `onSend` → dispatch/continue | ✅ | Contract chips persist; run-target pick no-op | P0/P1 |
| **Context sheet** | `CursorContextSheet.swift` | UI wired from composer `+` | ✅ | All "Add" rows no-op | P1 |
| **Repo picker** | `CursorRepoPickerSheet.swift` | Live: `liveRepoOptions` | ✅ | Works for cwd switch | ✅ |
| **Run on** | `CursorRunOnSheet.swift` | Live lists `runTargets` | ✅ | **Selection ignored** | P0 |
| **Model picker** | `CursorModelSheet.swift` | Live: updates `composerModelSlug` | ✅ | Works | ✅ |
| **Search** | `CursorSearchOverlay.swift` | Live: `onSearch` → FTS | ✅ | Scope chips UI-only in mock | P2 |
| **Profile drawer** | `CursorProfileDrawer.swift` | Mock charts/stats | ✅ | Sign out resets onboarding in shell | P2 |
| **Settings** | `CursorSettingsView.swift` | Live pairing counts | ✅ **fixed** dark inheritance | Most rows → stub sheets; Reset no-op | P1 |
| **Pairing** | `CursorRelayPairingSheet.swift` | Live `E2ERelayClient` | ✅ **fixed** scheme inheritance | Single-slot cap `relayFleetMaxMachines`; Reconnecting UX from relay state | P1 |
| **Onboarding** | `CursorOnboardingView.swift` | Visual mock; pairing step calls `onRequestPairing` | ⚠️ root bg fixed; **steps still `CursorColors.light`** | Not a real account flow | P1 |
| **Observed sessions** | `CursorObservedSessionsSection.swift` | Live when `relayHealthy` | ✅ | Import via `onImportObservedSession` | ✅ |
| **Return packet** | `CursorReturnPacketView.swift` | Live from receipt artifacts | ✅ **fixed** | Read-only by design | ✅ |
| **Commits / Diff** | `CursorCommitsSheet.swift`, `CursorDiffView.swift` | Mock via PR detail | ✅ | Not on main nav path live | P2 |
| **Ship action sheet** | `CursorShipActionSheet.swift` | **Orphan** — 0 nav refs | ✅ | Dead view (safe to delete later) | P2 |

---

## Known issues re-verified

### Review sheet stale binding (screen-map 12.05.34)
- **Code:** `CursorReviewDiffView` `boundApproval` + `syncBoundApproval()`; AppRoot injects `pendingApproval` on Observable bridge (#66).
- **Verdict:** Fix present in tree; **needs live relay re-test** to confirm no regression when `onPendingApprovalsChanged(count:0)` races.

### Dismissed approval banner recovery
- **Before:** Banner only on `CursorWorkThreadView`; closing AppRoot Review sheet left user on Workspaces with no affordance.
- **After this pass:** `CursorShellLiveBridge.onOpenReview` → `showingApprovalReview`; banners on Workspaces + thread list when `pendingApprovalID != nil`.

### Pairing / Reconnecting
- Simulator live launch (no `LANCER_CURSOR_SHELL`) showed **Reconnecting…** + empty workspaces — consistent with `connectionPhase` when relay fleet not connected (`AppRoot.connectionPhase`).
- Pairing sheet uses live `E2ERelayClient`; cap message when `existingMachineCount >= relayFleetMaxMachines`.

### Hardcoded `.environment(\.cursorScheme, .light)`
- **Removed/fixed:** `CursorSettingsView`, stub sheets, `CursorRelayPairingSheet`, `CursorReturnPacketView`, `CursorOnboardingView` root, mock shell now uses `.cursorTheme()`.
- **Remaining:** `CursorOnboardingView` inner step structs still use `CursorColors.light` literals.

### Composer contract / context
- Contract disclosure + draft persistence: **wired** (`CursorComposerDraftStore`, `ProofReceipt.Contract` on send).
- Context sheet: **presented**; attachment actions not implemented (documented in `CursorContextSheet`).

### Home needs-you vs All-clear on stale relay
- `homeAttentionStatusMessage` returns `"As of … — reconnecting"` when `!relayHealthy` — **correct**.
- Needs-you section driven by `threadStates` + pending approval flags in `refreshCursorLiveBridge` — **wired**.

---

## Dead / orphan views (do not delete without confirmation)

| View | Evidence |
|------|----------|
| `CursorShipActionSheet` | Only self-reference + PRDetail comment; no `NavigationLink`/sheet |
| `CursorHomeView` | **Does not exist** — comment-only reference in `CursorWorkspaceThreadListView` |
| Legacy `SettingsView` / sidebar | Deleted 2026-07-06 per ARCHITECTURE |

---

## Verification performed

| Command | Result |
|---------|--------|
| XcodeBuildMCP `session_show_defaults` | Lancer / iPhone 17 Pro configured |
| XcodeBuildMCP `build_sim` | ✅ |
| XcodeBuildMCP `build_run_sim` + `LANCER_CURSOR_SHELL=1` | ✅ (mock shell; notification permission alert on first launch) |
| `swift build` (this pass) | pending |
| `swift test` ThreadAttention + Review-related | pending |

---

## Fixes in `fix/frontend-audit-p0`

1. `CursorShellLiveBridge.onOpenReview` + AppRoot wiring to `showingApprovalReview`
2. Pending approval `CursorApprovalBanner` on **Workspaces** and **thread list** roots
3. Remove forced light scheme on Settings, Relay pairing, Return packet, Onboarding root; mock shell `.cursorTheme()`
4. Copy archived to `docs/design-audit/2026-07-08-cursor-shell-frontend-audit.md`

---

## Recommended next (owner / device)

1. **Tier-0 device pass:** live shell `LANCER_CURSOR_SHELL_LIVE=1` — dispatch → approval → Review → deny/approve → continue
2. **IA decision:** implement Home tab + bottom chrome per `lancer-ia-2026-07-08` or update ARCHITECTURE to match Workspaces-only root
3. **Wire run-target selection** to dispatch agent transport
4. **Device test Review** after approval decision (confirm `boundApproval` holds)
