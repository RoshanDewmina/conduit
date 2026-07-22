# 2026-07-21 dogfood website — status

## Goal
Phone dispatch: build `index.html` in `/Volumes/LancerDev/lancer-dogfood-site`, reply `DOGFOOD-SITE-OK`.

## What we learned

### False-positive UITest pass (uitest5)
- `** TEST SUCCEEDED **` but **no** daemon `conversation-append`, **no** `index.html`.
- Assertion `sawOK || sawWorking` matched a stale **"Working"** badge, not a live run.
- Screenshot `screenshots/dogfood-website-device.png`: thread opened with the prompt, then:
  - **Couldn't get a reply**
  - `cwd does not exist: /Users/roshansilva/Documents/command-center`
- Root cause: composer defaults to `repos.first` (`command-center`), not the newly added dogfood repo. Stale path is missing on this host.

### Fix in `DogfoodWebsiteDispatchUITests`
- Force-select `lancer-dogfood-site` in the composer repo picker before send.
- Fail-fast on Couldn't get a reply / Retry / bad cwd / no machine.
- Pass only on `DOGFOOD-SITE-OK`.

### uitest6
- Failed: **Unlock Roshan's iPhone to Continue** (device locked during launch).

## Host facts
- Dogfood cwd exists: `/Volumes/LancerDev/lancer-dogfood-site` (README only so far).
- Stale cwd missing: `/Users/roshansilva/Documents/command-center`.
- Prod `lancerd` running; pair code **676174** must not be reminted.
- Last real audit dispatch still `B1-LOCK-SCREEN` (echo auto-allowed — not lock-screen proof).

## Next
1. Unlock phone → re-run device UITest.
2. Or manual: Workspaces → composer → select **lancer-dogfood-site** → paste website prompt → Approve file write → expect `DOGFOOD-SITE-OK` + `index.html`.

## uitest9 (phone unlocked) — 2026-07-21 22:33
- Repo select worked: `lancer-dogfood-site` @ `/Volumes/LancerDev/lancer-dogfood-site`.
- Real dispatch: audit `conversation-append-launched` (approvalId `b31238c4-…`).
- Escalate pending: `ls -la /Volumes/LancerDev/lancer-dogfood-site` (`fa5cde33-…`) — still in `queue.json`.
- UITest **false pass again**: prompt text contains `DOGFOOD-SITE-OK`; CONTAINS matcher hit the user bubble in ~1s. Assertion fixed to `label ==` exact only.
- **Owner action:** Approve the pending ask on the phone (then file-write) so the live run can finish `index.html`.
