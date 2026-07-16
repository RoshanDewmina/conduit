# L6 — Owner device pass (push + Emergency Stop)

**Date:** 2026-07-16  
**Status:** **BLOCKED** — awaiting owner  
**Tip under test:** `origin/integration/2026-07-15-night` @ `b17b6172`  
**Sim audit worktree:** `.worktrees/daily-use-audit-2026-07-16`

---

## Why BLOCKED

Sim-first L1–L4 used the single Fly relay pairing slot. Orchestrator + L1 ran
`lancerd pair` (codes `587341` → `583514`). Daemon log warned:

```text
lancerd: REPLACING existing relay pairing identity — phones on the previous identity are orphaned and must re-pair
```

Active sim pair proof: `2026/07/16 05:30:21 e2e: paired with phone` (code `583514`).

**Owner action required before any L6 PASS:** re-pair the physical iPhone to the
resident daemon (Profile → Trusted Machines → Add a machine → Pair over relay)
using a fresh `~/.lancer/bin/lancerd pair` code generated **after** sim work is
done. Never `lancerd pair --help`.

Until the owner confirms the phone shows **Connected** and daemon log shows a
new `paired with phone` **after** that re-pair, L6 remains BLOCKED — do not invent PASS.

---

## Owner checkpoints (exact)

### Prep
1. Finish / ignore sim (sim Keychain will keep dead identity — fine).
2. On Mac: `~/.lancer/bin/lancerd pair` — note 6-digit code; use within ~5 min.
3. On phone: install tip build if needed (XcodeBuildMCP device path from night plan Part B), open Lancer → Profile → Trusted Machines → Pair over relay → enter code.
4. **✅ Expect:** green Connected; daemon: `e2e: paired with phone` after code generation time.
5. Paste daemon log window + screenshot of Trusted Machines into this file when done.

### Checkpoint A — Tier-0 / §3 on device (MVP pieces 3–5)
1. Workspaces → composer → low-risk prompt: `List the files in the current directory, then stop.`
2. **✅ Expect:** approval card in-thread and/or push; daemon `sent approval … over relay`.
3. Tap **Approve**.
4. **✅ Expect:** agent continues; transcript shows result; `audit.log` `approve` entry.
5. Same-thread follow-up: `Now count how many .swift files there are.`
6. **✅ Expect:** same conversation continues (not a new thread).
7. Record PASS/FAIL + screenshots `screenshots/L6-A-*.png` + log excerpts.

### Checkpoint B — §4b Push while app CLOSED (MVP piece 5 / publish C2)
1. Fully swipe away Lancer.
2. Trigger gated action (dispatch from another surface or agent hits gated tool).
3. **✅ Expect:** lock-screen push with **redacted** summary (risk + host; never raw command/paths).
4. Approve from notification if possible.
5. Record PASS/FAIL + notification screenshot `screenshots/L6-B-push.png`.

### Checkpoint C — §4 Emergency Stop on device (MVP piece 6)
1. Start a longer run.
2. Settings → Emergency Stop → confirm destructive dialog.
3. **✅ Expect:** stopped-run count reported OR clear error (never fake success). Stop-only (no in-app re-enable) is **accepted**.
4. Record PASS/FAIL + `screenshots/L6-C-stop.png` + daemon log.

---

## Results (owner fills)

| Checkpoint | Result | Evidence |
|---|---|---|
| Re-pair Connected | **BLOCKED** | awaiting owner |
| A — §3 device loop | **BLOCKED** | — |
| B — push while closed | **BLOCKED** | — |
| C — Emergency Stop | **BLOCKED** | — |

---

## Verification

```text
Verification:
- SwiftPM: skipped (audit)
- Xcode app target: sim build SUCCEEDED (see L1 / preflight); device build owner-gated
- Go daemon: go test PASS (preflight)
- Hook/resident bridge: L1 sim functional approve proven; device re-proof owner-gated
- Owner-gated: L6 BLOCKED — phone orphaned by sim pair 583514; owner must re-pair
- Warnings: sim pairing orphans phone; never lancerd pair --help
```
