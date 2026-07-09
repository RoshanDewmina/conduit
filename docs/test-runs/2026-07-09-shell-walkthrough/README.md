# Shell rebuild walkthrough — 2026-07-09 (afternoon)

**Branch:** `feat/chat-overhaul-w0a` (WIP uncommitted; not committed this session)  
**Brief:** `docs/plans/2026-07-09-fable-frontend-shell-rebuild-brief.md`  
**Design:** `docs/plans/2026-07-09-orca-shell-port-design.md`  
**Prior pack:** `docs/test-runs/2026-07-09-shell-rebuild-smoke/`

## What was tested

| Path | How | Result |
|------|-----|--------|
| Mock shell | `LANCER_CURSOR_SHELL=1` + `LANCER_SKIP_CURSOR_ONBOARDING=1` via `simctl` / UITests | **PASS** |
| Live shell (sim) | `LANCER_CURSOR_SHELL_LIVE=1` (+ headless `LANCER_RELAY_CODE` attempt) | **BLOCKED** — Reconnecting + empty workspaces |
| Live shell (device) | Physical iPhone available+paired at OS level; tip **not** reinstalled this session | **OWNER STOP** |

## D4–D9

| Gate | Result | Evidence |
|------|--------|----------|
| **D4** 3 roots | **PASS** | `d4-three-roots.png`, `d4-home-root.png`, `d4-settings-root.png`; UITest `testThreeRootsVisible` + `testSettingsRoot_TrustedMachinesRowVisible` |
| **D5** live pair → workspace | **FAIL / OWNER STOP** | `d5-live-shell-launch.png`, `d5-live-after-headless-relay-code.png` — 3-root chrome + pending-approval banner, but **Reconnecting…** and **No conversations yet** |
| **D6** named-workspace start chat | **PASS (mock)** | `d6-named-workspace-start-chat.png` — send opens Thread ("Starting…") with docked composer; UITest `testWorkspaceThreadList_DockedComposerVisible` |
| **D7** docked composer | **PASS** | `d7-docked-composer.png` — `Follow up…` field on thread list, no sheet |
| **D8** Nth-turn live update | **PASS (unit)** / live visual still blocked | `swift test` — `Nth-turn live overlay with new prompt becomes a pending row` |
| **D9** in-app approve | **PASS (seeded mock Review)** | `d9-reviewdiff-approved.png`; UITest `testReviewDiff_Approve`. Live banner Approve on sim not exercised end-to-end (no stable pair) |

## Verification commands (this session)

- App build/run: XcodeBuildMCP `build_run_sim` (scheme `Lancer`, iPhone 17 Pro)
- Mock UITests: `CursorAppShellExhaustiveTests` — **8 passed / 0 failed** (~132s)
- Unit: `CursorShellLaunchSeamTests|CursorComposerContractTests|CursorThreadTranscriptModelTests` — **19 passed**
- Host: `lancerd` running (`launchctl` / pid); relay `/health` → 200 at time of check

## Fixes this session

**None.** No smoke-blocking mock/UI bug found; WIP left uncommitted.

## Owner next click (D5)

1. Confirm Mac `lancerd` is up and relay-connected (`tail -f ~/.lancer/lancerd.stderr.log` should show `connected to relay as daemon`, not repeated DNS/`no route to host` flaps).
2. On **Roshan’s iPhone** (available/paired; Lancer already installed): install **this tip** of `feat/chat-overhaul-w0a` when ready (do **not** wipe pairings unless you intend to re-pair).
3. Launch with live shell (`LANCER_CURSOR_SHELL_LIVE=1` in scheme env, or production path once shell is default).
4. Open **Settings → Trusted machines** (or onboarding pair). Scan QR / enter code from the host pairing sheet — **do not rotate the host pairing code mid-run**.
5. Expect post-pair land on **Workspaces** with hydrated repos (not empty + Reconnecting). Then re-try live D6/D8.

Sim-only live remains insufficient for D5: headless `LANCER_RELAY_CODE` still left **Reconnecting…** / empty workspaces in this run.
