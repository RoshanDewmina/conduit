# B1 — Tier 0 re-proof on physical device (owner-run, 2026-07-19+)

**Purpose:** SHIP_PLAN §3 B1. Prove the governed loop on the owner's physical iPhone on a
coherent Debug tip (master + L1 reply + Home Screen widget polish), with **committed evidence**.
Procedure detail: `docs/LIVE_LOOP_RUNBOOK.md` (Phase 5b relay path is the V1 loop).

**Do NOT:** delete the app · run `lancerd pair` / remint · orphan production pairing with a sim pair.

---

## Build under test (recorded 2026-07-19 ~19:17 ET)

| Field | Value |
|---|---|
| **Install tip (app binary)** | `0d14d0c69ad2d76fd8ea8c9fe122cfc7ff545831` (`0d14d0c6`) — **reinstall not needed** for docs-only follow-up |
| **Checklist commit** | `13ef936b` on same branch (docs + launch PNG only) |
| **Branch / PR** | `fix/l5-pending-approvals-writer-test` · [PR #194](https://github.com/RoshanDewmina/conduit/pull/194) |
| **Why this tip** | One coherent Debug stack: `origin/master` (`7c4b1eca`) + L1 reply (#193 cherry-pick `66ad26ce`) + widget polish (#187 `960ee943`) + PendingApprovals TTL writer fix |
| **master tip (base)** | `7c4b1eca` (Merge #184 APNs JWT cache) — **not** what is on the phone; phone is ahead with open L1/widget fixes |
| **Open siblings (not installed alone)** | #193 L1-only `81503814` · #187 widgets `960ee943` · #190 Cursor CLI — merge-ack separate; only mention if dispatch vendor = Cursor |
| **App** | Debug `dev.lancer.mobile` 1.0.0 (2) · DerivedData `/tmp/lancer-b1-device-dd` · mtime `2026-07-19 19:17:35` |
| **Device** | Roshan’s iPhone CoreDevice `557A7877-F729-5031-9606-0E04F2B67822` |
| **Install** | **Upgrade-install SUCCEEDED** via `devicectl device install app` (no delete) · launched Workspaces |
| **Daemon** | `~/.lancer/bin/lancerd` `0.1.0-dev` · sha256 `0c0a83a225dd326b396beb5daba3bd6684103699886ac827e1133474be074edc` · mtime `2026-07-19 15:05:51` · launchd pid running |
| **Queue** | `~/.lancer/queue.json` → `"pending": []` (empty) |
| **Relay** | `lancerd doctor`: paired `wss://conduit-push.fly.dev` (**confirmed**) |
| **Pair after launch** | Daemon `e2e: paired with phone` + `device registered for push (apnsToken=true)` @ **19:17:56–57 ET** — production pair kept |
| **Push session** | `~/push-device.json` session `F0BC083A-7FA8-4F41-BF8D-AD5B53BC73F9` → `https://conduit-push.fly.dev` |

**Agent preflight done:** device build · upgrade-install · launch · daemon/queue/relay checks · this checklist refreshed.

---

## Evidence directory

Drop all owner/agent captures here:

```text
docs/test-runs/2026-07-19-b1-tier0-reproof/
├── CHECKLIST.md          ← this file
├── screenshots/          ← PNGs named below
└── *.txt                 ← audit / daemon tails named below
```

Agent can pull lock-screen PNGs with:

```bash
xcrun devicectl device capture screenshot \
  --device 557A7877-F729-5031-9606-0E04F2B67822 \
  --destination docs/test-runs/2026-07-19-b1-tier0-reproof/screenshots/<name>.png
```

---

## Paste-ready owner script (exact taps / phrases)

> **Start at step 1** (app is already installed + launched). First three actions right now:
> 1. Unlock phone → confirm **Workspaces** (not pairing sheet).
> 2. Confirm header/machine shows **Connected** (not Reconnecting… / No connected machine).
> 3. Open composer → type the Step-2 prompt below → Send.

Mark each row PASS/FAIL. 🙋 = needs your thumbs. 🤖 = agent can automate / verify from Mac.

| # | Who | Do this | Expect | Drop evidence |
|---|---|---|---|---|
| **1** | 🙋 | Glance Workspaces after launch | Machine **Connected**; no new pair code | `screenshots/01-pair-intact.png` |
| **2** | 🙋 | Composer → send (real repo): `Reply with exactly: B1-PONG` | Turn starts; live status / island may appear | `screenshots/02-dispatch.png` |
| **3** | 🙋+🤖 | **Force-quit Lancer** (app switcher swipe up) → **lock phone** → agent triggers an **ask** approval (or wait for one mid-run) | Lock-screen **APNs** approval notification (and/or Live Activity Approve/Reject) | `screenshots/03-lockscreen-push.png` |
| **4** | 🙋 | From **lock screen**, tap **Approve** (or Deny on a second trial) — do **not** open app first if possible | Audit `approve`/`deny` for that `approvalId`; hook unblocks | `04-audit-approve.txt` (agent greps `~/.lancer/audit.log`) |
| **5** | 🙋 | Let the run finish; open thread | Receipt / completed turn (exit OK) | `screenshots/05-receipt.png` |
| **6** | 🙋 | Same thread → Follow up: `Reply with exactly: B1-FOLLOWUP` | Second turn; same vendor session | `screenshots/06-followup.png` + `06-session-match.txt` (agent) |
| **7** | 🙋+🤖 | Start a longer run → tap **Emergency Stop** mid-run | Stop ≤ few s; no zombie agent; audit `run-stopped` / stop latch | `07-estop.txt` + `screenshots/07-estop.png` |

### Optional (short)

| # | Who | Do this | Expect | Evidence |
|---|---|---|---|---|
| **O1** | 🙋 | After a run / pending ask: Home Screen **Agents** + **Pending Approvals** widgets | Count/lines match phone truth (not stale corpses) | `screenshots/O1-widgets.png` |
| **O2** | 🙋 | Siri / Shortcuts: try any phrase that sounds like **Approve** | **No** Siri Approve path (negative) | `screenshots/O2-no-siri-approve.png` or note |

**Cursor [#190](https://github.com/RoshanDewmina/conduit/pull/190):** skip unless you deliberately dispatch Cursor Agent CLI — merge ack is a separate gate.

---

## Owner-only moments (cannot automate)

- Lock phone / Face-down / raise-to-wake for lock-screen notification
- Force-quit from app switcher
- Tap Approve / Deny on lock screen or Live Activity
- Confirm widgets visually on Home Screen
- Speak to Siri for negative Approve check
- Decide which real repo/workspace to dispatch into

---

## Gate

B1 passes only when rows **1–7** each have their evidence file committed (or linked from this dir), and the G2 line in `docs/SHIP_PLAN.md` §7 is updated. A claim without a committed link is not passed.

| Row | Status (fill live) |
|---|---|
| 1 Pair intact | PASS — launch `screenshots/00-workspaces-launch.png`; pair+push reconfirmed @ 19:17 ET |
| 2 Dispatch | PASS — `screenshots/02-dispatch.png` + `02-dispatch-audit.txt` (B1-PONG @ 23:20:26Z, approvalId `63117e13-…`) |
| 3 Lock-screen push | PENDING — B1-PONG did **not** escalate (reply-only / effect allow). Need a Bash ask while locked |
| 4 Approve/Deny | PENDING — blocked on row 3 |
| 5 Receipt | PASS — `screenshots/05-receipt.png` shows **B1-PONG** / Worked 3s |
| 6 Follow-up | PENDING |
| 7 Emergency Stop | PENDING (daemon B2 primitive already on master via #178) |
| O1 Widgets | OPTIONAL |
| O2 No Siri Approve | OPTIONAL |

---

## Agent cheat-sheet (while owner runs)

```bash
# Tail pair / push / stop
tail -f ~/.lancer/lancerd.stderr.log | rg -i 'pair|push|approval|stop|deny|approve'

# Audit for decisions
tail -n 50 ~/.lancer/audit.log | rg 'approve|deny|run-stopped|dispatch-launched'

# Queue should stay empty when idle
python3 -c 'import json;print(json.load(open("/Users/roshansilva/.lancer/queue.json")))'

# Re-foreground app without reinstall
xcrun devicectl device process launch --device 557A7877-F729-5031-9606-0E04F2B67822 --terminate-existing dev.lancer.mobile
```
