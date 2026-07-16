# Dogfood ready — owner iPhone tonight (2026-07-16 sweep tip)

**Audience:** Roshan (owner phone dogfood)  
**Written:** 2026-07-16 ~16:25 ET  
**Sweep integration branch:** `integration/2026-07-16-untested-sweep`

---

## Build from this tip

| Field | Value |
|---|---|
| **Worktree** | `/Users/roshansilva/Documents/command-center/.worktrees/untested-sweep-2026-07-16` |
| **Branch** | `integration/2026-07-16-untested-sweep` |
| **Current HEAD** | `b8bb778c0cad118c3d19834ba44950bf39eb3508` (`b8bb778c`) |
| **FX merge baseline** | `7707e4fa` — still an ancestor; tip advanced **+1** doc-only commit (`b8bb778c`: Simurgh/orchestrator doc sync). FX7 + FX5 + Lane P code is on this tip. |

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/untested-sweep-2026-07-16
git log -1 --oneline   # expect b8bb778c
```

---

## Ground truth right now (preflight)

Run these **before** trusting the phone UI:

```bash
# Resident daemon up?
launchctl print gui/$(id -u)/dev.lancer.lancerd | rg "state|pid"
~/.lancer/bin/lancerd doctor

# Current production pairing slot (single slot — one code for all phones)
python3 -c "import json; d=json.load(open('$HOME/.lancer/relay-pairing.json')); print('code:', d.get('code'), 'relay:', d.get('relayURL', d.get('url')))"

# Has a phone completed pairing on the *current* code?
grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -3
```

**As of brief write:** production slot is code **`310440`** on `wss://conduit-push.fly.dev`; `lancerd doctor` reports relay pairing **unconfirmed**; last `paired with phone` log lines are from **09:44** (likely sim sweep). **Assume the physical iPhone is orphaned** until you re-pair and see a fresh `paired with phone` **after** your new code.

**Sweep daemons:** sim lanes use `LANCER_STATE_DIR=/tmp/sweep-*` — they must **not** touch `~/.lancer`. Production dogfood uses the real resident daemon at `~/.lancer` only. Do **not** run bare `lancerd pair` on a test daemon without `LANCER_STATE_DIR` isolation — it will rotate the production slot and orphan the phone again.

---

## 1 — Rebuild host daemon (optional but recommended)

Shipped prebuilt `lancerd` can lag; build from the sweep worktree:

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/untested-sweep-2026-07-16/daemon/lancerd
go build -o lancerd . && go test ./...
./lancerd install
launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist 2>/dev/null || true
launchctl load   ~/Library/LaunchAgents/dev.lancer.lancerd.plist
test -S ~/.lancer/lancerd.sock && ~/.lancer/bin/lancerd version
```

---

## 2 — Build + install on physical iPhone

**Device:** Roshan's iPhone — UDID `557A7877-F729-5031-9606-0E04F2B67822`  
**Scheme / project:** `Lancer` / `Lancer.xcodeproj` (from `project.yml` via `xcodegen`)  
**Bundle ID:** `dev.lancer.mobile`  
**Team:** `39HM2X8GS6` (Automatic signing)

Use a **device-only** DerivedData path so sim sweep work (C4) is not stomped:

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/untested-sweep-2026-07-16
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

**Xcode GUI alternative:** open the worktree's `Lancer.xcodeproj` → select **Roshan's iPhone** → Run (⌘R). Set a custom Derived Data location in Xcode if you want to avoid sharing with sim builds.

**First launch:** accept **Notifications** when prompted (required for approval push path).

---

## 3 — Re-pair after the `310440` incident

### What happened

An accidental bare `lancerd pair` rotated `~/.lancer/relay-pairing.json` to fly.dev code **`310440`**, reconnecting the production resident daemon. Any phone still bound to an older code is **orphaned** (daemon has exactly **one** pairing slot — see `docs/KNOWN_ISSUES.md` P1 2026-07-04).

### Safe production re-pair (documented path)

**Only when sim sweep work is done** (or you accept orphaning sim pairings):

1. **Mac — mint a fresh code** (intentional; this replaces the slot):
   ```bash
   ~/.lancer/bin/lancerd pair
   ```
   - Run **`lancerd pair` exactly** — never `lancerd pair --help` (CLI treats unknown flags as a real re-pair).
   - Note the **6-digit code**; it expires in ~5 minutes.
   - Optional: read current code without rotating: `python3 -c "import json; print(json.load(open('$HOME/.lancer/relay-pairing.json'))['code'])"` — but if the phone is orphaned, you need a **new** `lancerd pair` anyway.

2. **iPhone — enter the code:**
   - **Profile → Trusted Machines → Add a machine → Pair over relay** (same sheet as onboarding).
   - Or **Settings → Trusted Machines** (embedded navigation).
   - Enter the 6-digit code from step 1 → tap **Connect**.
   - **FX5 fix:** Connect button should stay visible above the number pad; if occluded, scroll the form slightly (old bug; code merged, visual proof still owed on sim C4).

3. **Verify pairing succeeded:**
   ```bash
   grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1
   ```
   Timestamp must be **after** your `lancerd pair` command.

4. **Phone UI:** Trusted Machines shows your Mac **Connected** (green). Workspaces header should not sit on **Reconnecting…** / **No connected machine**.

5. **Stale machines:** If old relay hosts show **offline** / **pairing invalid**, remove them (Trusted Machines → swipe/remove or clear dead pairings) so you are not at the 3-machine cap.

### What NOT to do

| Don't | Why |
|---|---|
| `lancerd pair` on a sweep daemon without `LANCER_STATE_DIR` | Rotates **production** `~/.lancer/relay-pairing.json` |
| `lancerd pair --help` | Silently runs a real re-pair |
| Re-use an old code after phone Keychain drift | Relay returns key-mismatch / hijack rejection |
| Assume sim pairing = phone pairing | Sim and phone share one daemon slot; sim sweep orphans the phone |

Canonical references: `docs/LIVE_LOOP_RUNBOOK.md` Phase 5b, `docs/test-runs/2026-07-16-daily-use-audit/L6-device-pass.md`, `RelayPairingSheet.swift`.

---

## 4 — 10-minute smoke checklist (tonight)

Do these in order. Capture screenshots under `docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/` if anything fails.

| # | Step | Pass bar |
|---|---|---|
| 1 | **Pair** — steps in §3 | Daemon `paired with phone` after your code; phone **Connected** |
| 2 | **Send turn** — Workspaces → composer → pick repo + Claude → `List files in the current directory, then stop.` | Run starts; no immediate **Couldn't get a reply — No connected machine** |
| 3 | **Approve if asked** — in-thread card and/or push | Tap **Approve** → agent continues within seconds; `tail -1 ~/.lancer/audit.log` shows `approve` |
| 4 | **No stale error** — after approve + turn completes | Transcript shows result; composer not stuck on **Couldn't get a reply** / **Awaiting your approval** with a dead **Retry** loop (LC2/LC3 failure mode) |
| 5 | **Follow-up** — same thread: `How many .swift files are there?` | Same conversation continues (not a blank new thread) |
| 6 | **Policy** — Settings → **Policy** (Policy editor) | Editor loads; save does not silently wipe rules (LA2 had save/reopen bug — retest) |
| 7 | **Audit** — Settings → **Audit feed** | Feed loads over relay (Lane P merged; was SSH-gated before) |
| 8 | **Connect visible** — Profile → Trusted Machines → Pair over relay (or onboarding pair sheet) | With number pad up, **Connect** button visible without scroll (FX5) |
| 9 | **Emergency Stop** (30s) — Settings → Emergency Stop | Reports stopped count or honest error (never fake success) |
| 10 | **Optional stretch** — swipe app away, trigger gated tool, check lock-screen push | Historical PASS 2026-07-08 evening; **not** claimed green on this tip |

**Daemon tail during smoke:**
```bash
tail -f ~/.lancer/lancerd.stderr.log
```

---

## 5 — What is NOT claimed green (do not over-promise)

| Item | Status |
|---|---|
| **Lane C4 live sim re-test** | **In flight** — post-merge proof for #7 chain (#8/#9/#17/#23), #2/#3 Policy/Audit over relay, FX5 keypad screenshot |
| **#10 Background-tasks pill** | **FAIL** on sim (LF-final) — pill never appeared on completed Bash turn; not re-proven on device |
| **#14 Tool-call chips** | **BLOCKED** on sim — `bashCount=0` transcript hydration gap |
| **Publish / TestFlight / App Store** | **Not done** — B3 archive, beta validation, owner store ops remain (`docs/PUBLISH_READINESS_CHECKLIST.md`) |
| **Checkpoint 5c (lock-screen approve, app killed)** | Historical PASS on older tip; **pending re-proof** on sweep tip |
| **Merge sweep → master** | **Owner-ordered IN PROGRESS** (2026-07-16 ~16:29 ET; supersedes C4-wait stop) |

Tonight's bar: **pair → dispatch → approve → follow-up without stale errors** on the real iPhone against production `~/.lancer` + `conduit-push.fly.dev`.

---

## Quick copy-paste block (minimal path)

```bash
# A. Confirm tip
cd /Users/roshansilva/Documents/command-center/.worktrees/untested-sweep-2026-07-16 && git log -1 --oneline

# B. Re-pair (after sim sweep quiesced)
~/.lancer/bin/lancerd pair    # → enter code on phone: Profile → Trusted Machines → Pair over relay

# C. Build + install device app
xcodebuild -project Lancer.xcodeproj -scheme Lancer -configuration Debug \
  -destination 'platform=iOS,id=557A7877-F729-5031-9606-0E04F2B67822' \
  -derivedDataPath /tmp/lancer-device-dogfood-dd build
xcrun devicectl device install app --device 557A7877-F729-5031-9606-0E04F2B67822 \
  /tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app

# D. Smoke: send low-risk prompt → approve → follow-up → Settings Policy/Audit
```

---

## Build status (device install)

| Field | Value |
|---|---|
| **Status** | PENDING (this dogfood session) |
| **Built from** | (fill after install — expect `origin/master` tip post-merge) |
| **.app path** | `/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app` |
| **Install** | PENDING |

## Evidence to paste back

When done (PASS or FAIL), write sibling `DOGFOOD_SMOKE.md` and optionally note here:

- Screenshot: Trusted Machines **Connected**
- `grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1`
- Screenshot: completed turn (no **Couldn't get a reply**)
- Policy/Audit screens if reached
- Any FAIL: exact UI string + daemon log window
