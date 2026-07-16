# Dogfood smoke — owner iPhone (2026-07-16)

**Written:** 2026-07-16 ~16:40 ET  
**App tip on device (target):** master after FX10 fold (rebuild/reinstall this session)  
**Prior install:** `b8bb778c` (pre-FX10) — superseded by FX10 reinstall  
**.app path:** `/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app`  
**Device:** `557A7877-F729-5031-9606-0E04F2B67822` (Roshan's iPhone)

---

## Results

| Step | Status | Notes |
|---|---|---|
| 0. Install FX10 tip | PENDING / in progress | Rebuild+reinstall required after folding `5a3fce93` |
| 1. Pair | **BLOCKED → owner tap** | Production code minted **`300552`** (`lancerd pair`); `confirmedAt` still null; last `paired with phone` log is 09:44 (stale). C4 uses isolated `/tmp/sweep-C4` — safe to pair production. |
| 2. Send low-risk turn | **BLOCKED** on pair | |
| 3. Approve if prompted | **BLOCKED** on pair | |
| 4. No stale "Couldn't get a reply" | **BLOCKED** on pair | |
| 5. App launch | **PASS** (earlier) | `devicectl device process launch … dev.lancer.mobile` succeeded |

---

## Owner — exact 3 steps to unblock pair (code **300552**, ~5 min TTL)

1. On Mac, if code expired: run `~/.lancer/bin/lancerd pair` and note the new 6-digit code (never `pair --help`).
2. On iPhone: **Profile → Trusted Machines → Add a machine → Pair over relay** → enter the code → tap **Connect** (FX5: Connect should stay above the keypad).
3. Confirm: `grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1` shows a timestamp **after** your pair; phone shows Mac **Connected**.

Then: Workspaces → send `List files in the current directory, then stop.` → Approve if asked → confirm no stale **Couldn't get a reply** / dead Retry. Optionally trigger a Bash turn and check the background-tasks pill (FX10).

---

## Ground truth at write time

- `origin/master` pre-FX10-fold: `99fd4526` (PR #140)
- FX10 source: `fix/background-tasks-pill` @ `5a3fce93`
- Relay: `wss://conduit-push.fly.dev`, code `300552`, **unconfirmed**
- Doctor: relay pairing paired with relay (**unconfirmed**)
