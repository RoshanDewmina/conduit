# Dogfood smoke — owner iPhone (2026-07-16)

**Written:** 2026-07-16 ~16:50 ET  
**`origin/master`:** `fbc85191` (PR #140 sweep + PR #141 FX10)  
**FX10 included:** YES (`5a3fce93` ancestor)  
**.app path:** `/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app`  
**Device:** `557A7877-F729-5031-9606-0E04F2B67822` (Roshan's iPhone)

---

## Results

| Step | Status | Notes |
|---|---|---|
| 0. Install FX10 tip | **PASS** | `xcodebuild` BUILD SUCCEEDED; `devicectl install` SUCCEEDED (`dev.lancer.mobile`); launched |
| 1. Pair | **BLOCKED → owner tap** | Fresh production code **`347051`** (minted after install; prior `300552` expired unused). `confirmedAt` null. C4 uses `/tmp/sweep-C4` — safe. |
| 2. Send low-risk turn | **BLOCKED** on pair | |
| 3. Approve if prompted | **BLOCKED** on pair | |
| 4. No stale "Couldn't get a reply" | **BLOCKED** on pair | |
| 5. Background-tasks pill (FX10) | **live owed** | Code FIXED; needs Bash turn after pair |

---

## Owner — exact 3 steps (code **347051**, ~5 min TTL)

1. If this code expired: on Mac run `~/.lancer/bin/lancerd pair` and note the new 6-digit code (never `pair --help`).
2. On iPhone: **Profile → Trusted Machines → Add a machine → Pair over relay** → enter the code → tap **Connect**.
3. Confirm: `grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1` is **after** your Connect; phone shows Mac **Connected**.

Then smoke: Workspaces → `List files in the current directory, then stop.` → Approve if asked → confirm no stale **Couldn't get a reply**. Optional: Bash turn → check background-tasks pill.

---

## Ground truth

- Relay: `wss://conduit-push.fly.dev`
- Doctor earlier: resident OK; pairing unconfirmed until step 2
- Do **not** bare-pair a sweep daemon without `LANCER_STATE_DIR`
