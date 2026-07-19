# Live Activity sim proof — 2026-07-18

**Leases:** `lease-220` (prior) then `lease-222` (iPhone 17 Pro `AC112E74-FEAC-44B7-8FA7-D0C695B6EC38`)  
**Worktree:** `/Volumes/LancerDev/worktrees/lancer/device-build` @ `69a6f490`  
**Daemon:** resident `~/.lancer/bin/lancerd`

## Goal 1 — Live Activity console + Island / Lock Screen

### Prior session (lease-220) — console only
```
2026-07-18 21:15:24.440 I  … start() called, isEnabled=true
2026-07-18 21:15:24.505 I  … Activity.request succeeded, id=BA85B5EF-…
2026-07-18 21:15:25.619 I  … pushTokenUpdates delivered token, len=256
```
Island capture then failed: Home pressed before `startConversation` returned → `ActivityAuthorizationError.visibility`.

### Visual-proof run (lease-222) — **PASS**
Pair: production daemon, code **190799** (see Side effects). Trusted Machines: Relay host `6A75211D` **connected** (`goal1/08-trusted-after-190799.png`).

Dispatch: `LiveActivityIslandCaptureUITests` with `sleep 90` prompt; host watcher screenshots on `Activity.request succeeded` **before** Home.

Exact LiveActivity lines (`goal1/live-activity-exact-lines-visual-proof.txt`, `--level info`):
```
2026-07-18 22:16:15.122 I  Lancer[6191:…] [dev.lancer.mobile:LiveActivity] start() called, isEnabled=true
2026-07-18 22:16:15.197 I  Lancer[6191:…] [dev.lancer.mobile:LiveActivity] Activity.request succeeded, id=F593D5C9-F297-46BD-809E-B7EF1F792AC0
2026-07-18 22:16:15.197 I  Lancer[6191:…] [dev.lancer.mobile:LiveActivity] startTokenMonitor watching pushTokenUpdates for activityKey=conv_300ec2aa-17e2-4996-9433-50a59a3bd55c
2026-07-18 22:16:16.409 I  Lancer[6191:…] [dev.lancer.mobile:LiveActivity] pushTokenUpdates delivered token, len=256
```

### Screenshots (Live Activity chrome)
| File | What it shows |
|------|----------------|
| `goal1/10-foreground-during-activity.png` | In-app thread “Working…”; Dynamic Island shows blue LA stop indicator |
| `goal1/12-lock-screen.png` | Lock Screen Live Activity banner (“Claude Code” / Relay host) + “Allow Live Activities from Lancer?” |
| `goal1/13-after-allow-tap.png` | Same LA banner with **Needs approval** / High risk Approve·Deny + Allow prompt |
| `goal1/16-uitest-lock-attachment.png` | UITest lock-screen attachment (same LA chrome) |
| `goal1/11-springboard-island.png` | SpringBoard after Home — Island idle (compact LA not visible in sim shot; Lock Screen is the clear chrome proof) |

**Done-when:** met — Lock Screen PNG shows Live Activity chrome for the same run as `Activity.request succeeded` (`F593D5C9-…`).

## Goal 3 — SET-failure alert

| Check | Result | Evidence |
|-------|--------|----------|
| `+` menu / Permission presets / no alert on hydration | **PASS** (prior) | `goal3/20-`…`22-` |
| User SET failure → alert | **NOT obtained** | See below |

### SET-alert attempts this pass (stopped; no thrash)
1. **Prior:** unpair swipe did not remove machine; LaunchAgent `bootout` + `PermissionSetAlertUITests` hung SpringBoard.
2. **This pass:** `kill`/`pkill -9` daemon **without** unloading LaunchAgent, then `PermissionSetAlertUITests` — failed at Workspaces wait (`PermissionSetAlertUITests.swift:14`); 100s watchdog killed xcodebuild (`goal3/42-watchdog.txt`). Screenshots `goal3/43-`…`46-` show blank/gray sim UI, **no** “Couldn't change permission mode” alert.
3. Commands tried: `kill <pid>`; `pkill -9 -f 'lancerd daemon'`; `xcodebuild … -only-testing:…PermissionSetAlertUITests/testSetFailureShowsAlertWhenDaemonDown`; watchdog `pkill` after 100s.

LaunchAgent left loaded; daemon restored (`goal3/45-daemon-restored.txt`).

## Side effects / cleanup
- **WARN — phone re-pair needed:** accidental `lancerd pair --help` rotated production relay identity `297960` → **`190799`** (known footgun; orphans phones). Do **not** run `lancerd pair` / `pair --help` casually.
- Isolated `LANCER_STATE_DIR=/tmp/la-proof-lancerd-state` daemon (code `981416`) was tried first; token register HTTP 401 / host offline for dispatch — stopped; production path used instead. Dead pairing `75A6B9FD` may remain in sim Trusted Machines.
- LaunchAgent `dev.lancer.lancerd` was **not** unloaded this pass (only process kill); restored/running.
- Leases: `lease-220` released earlier; `lease-222` released at end of this pass.
