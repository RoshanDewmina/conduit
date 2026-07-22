# Dogfood ready — owner iPhone (2026-07-16 master tip)

**Audience:** Roshan (owner phone dogfood)  
**Written:** 2026-07-16 ~16:25 ET; **synced** ~18:15 ET (`SESSION_HOP_REPORT.md`)  
**Branch:** `origin/master`

---

## Build from this tip

| Field | Value |
|---|---|
| **Tip** | `origin/master` @ `62b4424dc39df78d1a823bc33d7b597829ddc0e6` (`62b4424d`, PR #149) |
| **Includes** | Sweep (#140–#143), FX10 (#141), auth-preflight (#145), Proof menu (#147), ISO tests (#148), All Repos cache (#149) |
| **Phone install** | **Claimed SUCCEEDED** @ `62b4424d` ~18:05 ET (CoreDevice 4000 retry OK) |

```bash
git fetch origin && git log -1 --oneline origin/master   # expect 62b4424d
```

---

## Ground truth right now (preflight)

Run these **before** trusting the phone UI:

```bash
# Resident daemon up?
launchctl print gui/$(id -u)/dev.lancer.lancerd | rg "state|pid"
~/.lancer/bin/lancerd doctor

# Has a phone completed pairing on the current slot?
grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -3
```

**As of session-hop sync (~18:15 ET):**

| Check | Status |
|---|---|
| `lancerd doctor` | Relay pairing **confirmed** on `wss://conduit-push.fly.dev` |
| Phone pair | **Confirmed** — live slot ends `…9884`; last `paired with phone` through **17:43 ET** |
| Auth smoke (#145) | `"Hi"` → `conversation-append-launched allow` @ **21:20:25Z** |
| Re-pair needed? | **No** — do not remint unless pair breaks |

**Redaction:** live pairing codes are not reproduced in docs. Historical incident codes (`310440`, `758455`, `347051`, `149884`) are incident history only.

**Sweep daemons:** sim lanes use `LANCER_STATE_DIR=/tmp/sweep-*` — they must **not** touch `~/.lancer`. Production dogfood uses the real resident daemon at `~/.lancer` only. Do **not** run bare `lancerd pair` on a test daemon without `LANCER_STATE_DIR` isolation.

---

## 1 — Rebuild host daemon (optional)

Post-#145 auth-preflight fix is already on master and was installed during dogfood. Rebuild only if you need a fresher binary:

```bash
cd daemon/lancerd   # from a checkout @ 62b4424d
go build -o lancerd . && go test ./...
./lancerd install
launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist 2>/dev/null || true
launchctl load   ~/Library/LaunchAgents/dev.lancer.lancerd.plist
test -S ~/.lancer/lancerd.sock && ~/.lancer/bin/lancerd version
```

---

## 2 — Build + install on physical iPhone

**Device:** Roshan's iPhone — UDID `557A7877-F729-5031-9606-0E04F2B67822`  
**Scheme / project:** `Lancer` / `Lancer.xcodeproj`  
**Bundle ID:** `dev.lancer.mobile`  
**Team:** `39HM2X8GS6` (Automatic signing)

Use a **device-only** DerivedData path:

```bash
# from repo root @ 62b4424d
xcodegen generate   # only if Lancer.xcodeproj is missing or stale

xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -configuration Debug \
  -destination 'platform=iOS,id=557A7877-F729-5031-9606-0E04F2B67822' \
  -derivedDataPath /tmp/lancer-device-dogfood-dd \
  build
```

Install + launch:

```bash
APP=/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app
xcrun devicectl device install app --device 557A7877-F729-5031-9606-0E04F2B67822 "$APP"
xcrun devicectl device process launch --device 557A7877-F729-5031-9606-0E04F2B67822 dev.lancer.mobile
```

**First launch:** accept **Notifications** when prompted (required for approval push path).

---

## 3 — Pairing status (confirmed — no remint)

Pairing is **live and confirmed** as of ~18:15 ET. Trusted Machines should show Mac **Connected** (green). Workspaces header should not sit on **Reconnecting…** / **No connected machine**.

If pair breaks later, see `docs/LIVE_LOOP_RUNBOOK.md` Phase 5b and the historical `310440` incident note in `LC3-report.md` (bare `lancerd pair` without `LANCER_STATE_DIR` orphans the phone).

### What NOT to do

| Don't | Why |
|---|---|
| `lancerd pair` without cause | Rotates the single production slot |
| `lancerd pair --help` | Silently runs a real re-pair |
| `lancerd pair` on a sweep daemon without `LANCER_STATE_DIR` | Rotates **production** `~/.lancer/relay-pairing.json` |

---

## 4 — 10-minute smoke checklist

Do these in order. Capture screenshots under `docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/` if anything fails.

| # | Step | Pass bar | Status |
|---|---|---|---|
| 1 | **Pair** | Daemon `paired with phone`; phone **Connected** | **PASS** (confirmed through 17:43 ET) |
| 2 | **Send turn** — `"Hi"` or low-risk prompt | Run starts; no auth-preflight deny | **PASS** post-#145 (audit @ 21:20:25Z) |
| 3 | **Approve if asked** — in-thread card and/or push | Tap **Approve** → agent continues | **Not fully evidenced** |
| 4 | **No stale error** — after approve + turn completes | Transcript shows result; no dead Retry loop | **Not fully evidenced** |
| 5 | **Follow-up** — same thread | Same conversation continues | **Not fully evidenced** |
| 6 | **Policy** — Settings → **Policy** | Editor loads; save does not wipe rules | **Not fully evidenced** (phone UI) |
| 7 | **Audit** — Settings → **Audit feed** | Feed loads over relay | **Not fully evidenced** (phone UI; sim PASS) |
| 8 | **Connect visible** — Pair over relay sheet | Connect above number pad (FX5) | Code on master; sim PASS |
| 9 | **Emergency Stop** (30s) | Honest stopped count or error | **Not fully evidenced** |
| 10 | **Optional stretch** — lock-screen push | Historical PASS 2026-07-08 | **Not claimed** on this tip |

**Daemon tail during smoke:**
```bash
tail -f ~/.lancer/lancerd.stderr.log
```

---

## 5 — What is NOT claimed green (do not over-promise)

| Item | Status |
|---|---|
| **Lane C4 #7 chain** (#8/#9/#17/#23) | **Still live-owed** — harness never got `paired with phone`; FX7 awaiting-card not observed |
| **#10 Background-tasks pill** | **Code FIXED** (FX10 `5a3fce93`); live re-proof owed on phone |
| **#14 Tool-call chips** | **BLOCKED** on sim — `bashCount=0`; live owed |
| **#147 Proof under menu / #149 All Repos** | **Code on master**; UX **CLAIMED-UNVERIFIED** (no screenshots tonight) |
| **Publish / TestFlight / App Store** | **Not done** (`docs/PUBLISH_READINESS_CHECKLIST.md`) |
| **Full 10-step smoke** | Launch **PASS**; approve + follow-up + Policy/Audit UI screenshots **not fully evidenced** |

Tonight's verified bar: **pair confirmed → `"Hi"` launch without auth-preflight deny** on production `~/.lancer` + `conduit-push.fly.dev`.

---

## Build / install history (this day)

| When | SHA | Event |
|---|---|---|
| ~16:34 ET | `b8bb778c` | First device build + install |
| ~16:50 ET | `ec3565f7` | FX10 reinstall |
| ~17:36 ET | `655232eb` | Proof-under-menu (#147) install |
| ~18:05 ET | `62b4424d` | All Repos (#149) install — **current claimed tip** |

`.app` path: `/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app`

---

## Evidence to paste back

When extending smoke (PASS or FAIL), update `DOGFOOD_SMOKE.md`:

- Screenshot: Trusted Machines **Connected**
- `grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1`
- Screenshot: completed turn (no **Couldn't get a reply**)
- Policy/Audit screens if reached
- Any FAIL: exact UI string + daemon log window

Canonical session summary: `SESSION_HOP_REPORT.md`.
