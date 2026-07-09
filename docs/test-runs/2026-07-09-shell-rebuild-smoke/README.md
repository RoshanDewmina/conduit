# Shell rebuild smoke — 2026-07-09

**Branch:** `feat/chat-overhaul-w0a`  
**Brief:** `docs/plans/2026-07-09-fable-frontend-shell-rebuild-brief.md`  
**Design note:** `docs/plans/2026-07-09-orca-shell-port-design.md`

## Mock shell (`LANCER_CURSOR_SHELL=1`)

| Gate | Result | Evidence |
|------|--------|----------|
| D4 3 roots | PASS | `02-three-roots.png`, `02b-home-root.png`, `CursorAppShellExhaustiveTests/testThreeRootsVisible` |
| D6 named-workspace start chat | PASS (mock) | `03b-named-workspace-start-chat.png`, UITest send → workThread |
| D7 docked composer | PASS | `03-thread-list-docked-composer.png` — text field on-screen, no sheet |
| D9 in-app approve path | PASS (seeded live Review) | `CursorShellLiveApprovalTests/testLiveShell_PendingApprovalBannerApprove` |

## Live daemon / device (D5 / D8 / live D6)

**Sim live launch** (`LANCER_CURSOR_SHELL_LIVE=1`): `live-shell-sim-reconnecting.jpg` — 3-root shell + "1 pending approval" banner with DENY/APPROVE, but **Reconnecting…** and **No conversations yet** (relay not hydrated on sim).

**Owner stop:** physical-device reinstall/re-pair not run (AGENT_READ_FIRST: do not reinstall paired device without owner approval; prior slice1 live flap from code rotation). Host `lancerd` is up; phone `557A7877-…` available+paired at OS level, but shell rebuild tip not installed/proven on-device this session.

Nth-turn live update (D8) covered by unit test `Nth-turn live overlay with new prompt becomes a pending row` + mapper fix; visual live proof still needs a stable paired session.

## Owner walkthrough

**Mock:** launch with `LANCER_CURSOR_SHELL=1` + `LANCER_SKIP_CURSOR_ONBOARDING=1` → Home / Workspaces / Settings tabs; Workspaces → lancer-ios → docked composer; send opens thread.

**Live:** `LANCER_CURSOR_SHELL_LIVE=1` after `lancerd` running + one pair (do not rotate mid-run). Post-pair should land Workspaces. Named workspace send needs `repoPaths` hydrated from host ledger.
