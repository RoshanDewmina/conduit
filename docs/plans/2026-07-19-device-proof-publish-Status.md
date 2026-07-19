# Device-proof + publish — Status
**Updated:** 2026-07-19 ~11:35 ET  
**Branch:** `fix/apns-live-activity-device-proof-2026-07-18`  
**Worktree:** `/Volumes/LancerDev/worktrees/lancer/device-build`  
**HEAD:** `64a0bb77` (ahead of origin; not pushed)  
**PR:** #176 (draft)

## Done this session
- Edit-tool red/green diff sheet committed (`873f412c`)
- Goal 3 SET-failure alert merged (`6fc095da`) + CHANGELOG conflict fixed (`64a0bb77`)
- Device Debug build SUCCEEDED; installed + launched on Roshan's iPhone (`557A7877-…`) as `dev.lancer.mobile`

## Owner live-test now
1. Confirm phone still paired (Trusted Machines / Workspaces).
2. Open a thread that already has an **Edit** tool chip (or send a prompt that edits a file).
3. Tap the Edit chip to expand → **View diff** → confirm red/green sheet with filename + counts.
4. Optional: + menu → change permission mode after making overrides file read-only on host (Goal 3) — expect "Couldn't change permission mode" alert.

## Remaining
- Live Activity observed-session auto-start miss (diagnose)
- Push + refresh PR #176; un-draft after live proof
- Publish / TestFlight (owner)

## Commands run
```bash
git commit 873f412c  # Edit sheet
git merge 127d956f → 6fc095da + 64a0bb77
xcodebuild -scheme Lancer -destination id=557A7877-… BUILD SUCCEEDED
devicectl install + launch → OK
```
