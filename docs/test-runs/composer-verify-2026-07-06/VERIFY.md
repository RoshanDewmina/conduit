# Composer + shell verification — 2026-07-06

Simulator: iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`)  
Build: `amazing-mayer` worktree, `/tmp/lancer-amazing-dd`

## Screenshots

| File | What it shows |
|------|----------------|
| `01-workspaces.png` | **Live shell** — Workspaces root, `command-center` repo, compact `Plan, ask, build...` composer |
| `mock-02-workspaces-root.png` | Mock shell — seeded repos (lancer-ios, push-backend, …) |
| `mock-07-workthread-top.png` | Mock work thread — transcript + action rail |
| `mock-07c-workthread-composer-bottom.png` | **Follow-up composer** — `+` \| `Follow up...` \| mic (Cursor-style) |
| `03-lancer-ios-thread-list.png` | Mock shell workspaces (navigation reference) |

## UI tests (all PASS)

```
LegacyUIRemovalTests (5)          — no legacy sidebar chrome; composer opens with Haiku model + cloud
HomeButtonTapTests (2)            — Workspaces header + profile drawer
CursorShellLiveApprovalTests (1)  — live approval banner → approve
LegacyUIRemovalTests/testComposerOpensFloatingSheet — live expanded composer
```

**Commands:**
```bash
xcodebuild build -scheme Lancer -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' -derivedDataPath /tmp/lancer-amazing-dd
xcodebuild test ... -only-testing:LancerUITests/LegacyUIRemovalTests -only-testing:LancerUITests/HomeButtonTapTests -only-testing:LancerUITests/CursorShellLiveApprovalTests/testLiveShell_PendingApprovalBannerApprove
```

## Verified

- [x] No legacy sidebar (Home / Machines / POLICY BRIDGE) on default launch
- [x] Workspaces is production root
- [x] Collapsed workspaces composer: placeholder-only pill
- [x] Collapsed thread composer: `+` / `Follow up...` / mic
- [x] Expanded live composer: repo row, cloud target, Claude Haiku 4 model chip, send when live
- [x] Live approval flow on simulator

## Known flake

`CursorAppShellExhaustiveTests` composer-chain tests occasionally fail on iOS 27 sim tap timing (mock shell only); work-thread collapsed composer screenshot above is from passing `testWorkThread_FullPass`.
