# Aggressive cleanup spec (Option B)

**Branch:** `claude/amazing-mayer-246fef` · **2026-07-06**

## Status on this branch

Most of Option B is **already implemented** in the lean-sweep commit:

- Default launch: `CursorAppShell(liveBridge:)` — no sidebar
- `CursorSettingsView` replaces `SettingsWithLibraryView` (cream Policy Bridge UI removed from default path)
- Legacy DS components deleted; tokens under `DesignSystem/Cursor/`
- `LegacyUIRemovalTests` guards against sidebar chrome returning

## Remaining work

| Phase | Task | Owner |
|-------|------|-------|
| 0 | Land + push `amazing-mayer` branch | Agent |
| 1 | Doc hygiene — remove `LANCER_CURSOR_SHELL_LIVE` claims (live is default) | Agent |
| 2 | Wire `CursorSettingsView` rows per `10-settings.html` (security, notifications, plan) | T1 lane |
| 3 | Prune any leftover DS exports after grep=0 | Agent |
| 4 | Delete dormant StoreKit paywall path or wire to Stripe-only copy | Billing decision |

## Verify gates

```bash
rg -l 'LancerSidebarView|SettingsWithLibrary' Packages LancerUITests  # expect 0
cd Packages/LancerKit && swift build && swift test
xcodebuild -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -only-testing:LancerUITests/LegacyUIRemovalTests
xcodebuild test -only-testing:LancerUITests/CursorShellLiveApprovalTests
```

## Do not delete

`InboxViewModel`, `FleetStore`, `SettingsViewModel`, `PurchaseManager`, `CursorShellLiveBridge`, SSH session stack (escape hatch).
