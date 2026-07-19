# Device-proof + publish — Status
**Updated:** 2026-07-19 ~11:25 ET  
**Plan / context:** `docs/plans/orchestrator-state.md` (2026-07-19 entry) + PR #176  
**Prior Claude session:** `4a99e68d-58b0-4b43-89c5-ad22740e7475` (died on org subscription disable)  
**Continued by:** Cursor Grok (this session)  
**Branch:** `fix/apns-live-activity-device-proof-2026-07-18`  
**Worktree:** `/Volumes/LancerDev/worktrees/lancer/device-build`  
**HEAD:** `c1bfbe4e` + **uncommitted** Edit-tool diff sheet work

## Done
- APNs app-closed push: root-caused, fixed, proven live.
- PR #176 rescued + reviewed; App-Group DB migration data-loss risk fixed.
- Live Activity push-to-start plumbing merged into tip.
- **Edit-tool red/green diff sheet restored (this session):**
  - `EditToolDiffModels.swift` — parse Edit/Write/MultiEdit `old_string`/`new_string`/`content` from chip `inputJSON`
  - `EditToolDiffSheet.swift` — sheet using existing `DiffLineRow` (red/green)
  - `ToolCallChipView` — expanded Edit chips get **View diff** → sheet (no CursorStyle resurrection)
  - Tests: `EditToolDiffParserTests` **6/6 PASS**
  - iOS: `xcodebuild -scheme AppFeature` (generic iOS Simulator) **BUILD SUCCEEDED**

## Remaining
- **Next:** Live-verify Edit sheet on sim/phone (expand an Edit chip → View diff).
- Merge Goal 3 fix `127d956f` (`test/goal3-set-alert-2026-07-19`) into device-proof; live-verify.
- Diagnose observed-session Live Activity auto-start miss.
- Un-draft / merge PR #176 after gates.
- Commit Edit-sheet work when owner asks.

## Commands run
```bash
cd Packages/LancerKit && swift test --filter EditToolDiffParserTests
# 6 tests, 0 failures

xcodebuild -scheme AppFeature -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Volumes/LancerDev/lancer-tmp/DerivedData/edit-diff-sheet \
  build CODE_SIGNING_ALLOWED=NO
# ** BUILD SUCCEEDED **
```

## Dirty tree (device-build)
```text
 M Packages/LancerKit/Sources/AppFeature/Chat/ToolCallChipView.swift
 M Packages/LancerKit/Sources/AppFeature/Review/ReviewModels.swift
?? Packages/LancerKit/Sources/AppFeature/Chat/EditToolDiffModels.swift
?? Packages/LancerKit/Sources/AppFeature/Chat/EditToolDiffSheet.swift
?? Packages/LancerKit/Tests/LancerKitTests/EditToolDiffParserTests.swift
# (+ Package.resolved churn — discard unless intentional)
```

## Blockers
- Live Activity auto-start for local observed sessions: code merged, live FAIL.
- Goal 3 fix committed but unmerged.
- Single relay pairing slot — do not orphan production phone.

## Next agent instruction
Commit Edit-sheet when owner asks; then live-verify on device/sim. Optionally merge Goal 3 `127d956f`. Do not start App Store submission.
