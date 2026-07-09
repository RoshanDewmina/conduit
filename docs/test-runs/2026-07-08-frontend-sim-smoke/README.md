# Frontend sim smoke — 2026-07-08

**Branch:** `fix/frontend-audit-p0` (`9a6632d6`)  
**Simulator:** iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`)  
**Launch seams:** `LANCER_CURSOR_SHELL=1`, `LANCER_SKIP_CURSOR_ONBOARDING=1`, `LANCER_SKIP_NOTIFICATION_PROMPT=1`

## Method

1. `session_show_defaults` — Lancer / iPhone 17 Pro confirmed.
2. `build_run_sim` — **PASS** (mock shell env via XcodeBuildMCP `session_set_defaults`).
3. Manual `snapshot_ui` walk **blocked** by iOS system notification-permission alert (known iOS 27 headless sim limitation — HID taps no-op on system alerts; see `docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md`).
4. **UITest smoke** (5 tests, mock shell launch env from `CursorAppShellExhaustiveTests`): **4/5 PASS**.

| Test | Result | Evidence |
|------|--------|----------|
| `testWorkspacesRoot_HeaderAndRows` | FAIL (profile drawer close `xmark` id drift) | `01-workspaces-root.png`, `06-profile-drawer.png` |
| `testRepoThreadList_RowPushesWorkThreadAndComposer` | PASS | `02-work-thread.png`, `03-thread-list-composer.png` |
| `testReviewDiff_Approve` | PASS | `05-review-approve.png` |
| `testComposerChain_RunOnAndModelNestedSheets` | PASS | `04-composer-sheet.png`, `07-composer-chain-workspaces.png` |
| `testSettings_SupportFeedbackRows` | PASS | (no attachment; covered via profile → App Settings path in other tests) |

Full xcresult attachments: `xcresult-attachments/`

## Surfaces walked (mock shell)

| Surface | Reachable | Screenshot |
|---------|-----------|------------|
| Workspaces root | ✅ | `01-workspaces-root.png` |
| Thread list → Work thread | ✅ | `02-work-thread.png`, `03-thread-list-composer.png` |
| Composer sheet + Run on / Model | ✅ | `04-composer-sheet.png`, `07-composer-chain-workspaces.png` |
| Review / approval (mock route) | ✅ | `05-review-approve.png` |
| Profile drawer (Settings entry) | ✅ | `06-profile-drawer.png` |
| Home root (IA) | N/A — not implemented (P0-1) | — |
| Live bridge / pairing | Not exercised (mock shell) | needs-device |

## Audit P0 status (sim)

| P0 | Issue | Sim verdict |
|----|-------|-------------|
| P0-1 | No dedicated Home root | **still-broken** (IA scope; Workspaces-only root by design) |
| P0-2 | Dismissed Review → no recovery banner | **fixed-in-sim** (code landed; live `pendingApprovalID` banner not exercised in mock) |
| P0-3 | Review stale binding after decision | **needs-device** (mock approve passes; live relay race per #66) |
| P0-4 | Run-target picker no-op | **still-broken** (sheet opens; selection not wired to dispatch) |

## Live shell note

`LANCER_CURSOR_SHELL_LIVE=1` was **not** re-proven this pass (no paired `lancerd` in sim). Owner device walkthrough follows in `~/Downloads/2026-07-08-phone-workflow-walkthrough-prompt.md`.
