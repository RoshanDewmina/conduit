# Device-proof + publish — Status
**Updated:** 2026-07-19 ~11:15 ET  
**Plan / context:** `docs/plans/orchestrator-state.md` (2026-07-19 entry) + PR #176  
**Prior Claude session:** `4a99e68d-58b0-4b43-89c5-ad22740e7475` (died on org subscription disable)  
**Branch:** `fix/apns-live-activity-device-proof-2026-07-18`  
**Worktree:** `/Volumes/LancerDev/worktrees/lancer/device-build`  
**HEAD:** `c1bfbe4e` (matches `origin`; clean)  
**Do not use:** primary checkout is currently on unrelated `cursor/desktop-history-and-terminal-3510` @ `67fb18d9`

## Done
- APNs app-closed push: root-caused (`requestAuthorization()` missing), fixed (`a848a6ba`), proven live on locked phone.
- PR #176 rescued + reviewed (SAFE WITH NITS); App-Group DB migration data-loss risk fixed (`b861f0ec`).
- Live Activity push-to-start plumbing: `postRunStartPush` helper + dispatch trigger + observed-session trigger merged into device-proof tip (`64762f96` / `29c58517` / `cb8fdccc` → merges `43e05c1b` / `c1bfbe4e`).
- Goal 3 SET-failure alert: root-caused (embedded permission menu tears down before async error) + fix committed on **side branch** `test/goal3-set-alert-2026-07-19` @ `127d956f` — **not yet merged** into device-proof.
- Publish checklist reconcile branch exists: `docs/publish-checklist-reconcile-2026-07-19` (WP-B).

## Remaining
- **Next:** Restore the missing **Edit tool red/green diff sheet** (owner video evidence in Claude session). Regression from CursorStyle/`CursorWorkThreadView` deletion (`6b97da65`). DiffKit still exists (`Packages/LancerKit/Sources/DiffKit/UnifiedDiff.swift`). Archaeology was mid-flight when session died — recover deleted `CursorReviewDiffView` / `DiffView` from `6b97da65^`, port into Workspaces shell (not resurrect CursorStyle wholesale).
- Merge Goal 3 fix `127d956f` into device-proof; live-verify permission-mode SET failure alert.
- Diagnose why observed-session Live Activity auto-start did **not** appear on phone after local Claude session (owner confirmed no LA).
- Un-draft / merge PR #176 after remaining gates.
- Broader publish path: archive/TestFlight, App Store Connect (owner-only).

## Commands run (session-verified)
```bash
# device-proof tip + clean
git -C /Volumes/LancerDev/worktrees/lancer/device-build rev-parse --short HEAD  # c1bfbe4e
git -C /Volumes/LancerDev/worktrees/lancer/device-build status -sb             # clean, tracking origin

# Goal 3 NOT on tip yet
git merge-base --is-ancestor 127d956f fix/apns-live-activity-device-proof-2026-07-18  # NO
```

## Dirty tree (primary checkout — unrelated)
```text
# /Volumes/LancerDev/lancer on cursor/desktop-history-and-terminal-3510 @ 67fb18d9
# many unrelated dirty docs/test-runs — leave alone
```

## Blockers
- **Claude Code org subscription disabled** — session `4a99e68d…` ends with: “Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead…”. `--resume` will fail until API key / admin re-enable.
- Live Activity auto-start for local observed sessions: code merged, **live proof FAIL** (no LA on phone).
- Goal 3 fix committed but **unmerged**.
- Single relay pairing slot — do not `lancerd pair` / orphan production phone while using Simurgh.

## Next agent instruction
Work in `/Volumes/LancerDev/worktrees/lancer/device-build` on `fix/apns-live-activity-device-proof-2026-07-18`.  
Do **not** read prior chat transcripts as source of truth — use this Status + git.  
**Next milestone only:** port the Edit-tool red/green diff sheet into the current Workspaces chat chrome (DiffKit + recovered pre-`6b97da65` UI patterns).  
Done when: unit/build green for touched Swift; sim or device screenshot of Edit sheet; Status updated; STOP (do not start publish submission).
