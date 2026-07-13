# Phone test checklist — Session 4 (master + post-REL-1)

**Build:** `origin/master` @ `86b7a767` or later (#105–#109 + #107 G2). Install to owner iPhone; daemon = master (`lancerd` resident). **Do not** run bare `lancerd pair` while owner holds the slot.

**Record:** pass/fail + one-line note per row in `docs/dogfood-log.md` or a dated `docs/test-runs/` file.

---

## Test now (master)

| # | Tap / action | Pass | Fail |
|---|--------------|------|------|
| 1 | Open Lancer — connected banner, no stuck "Can't reach your machine" | Shows connected / paired machine | Persistent unreachable or reconnect loop |
| 2 | Workspaces → search **"fix triple"** → open the long **command-center** thread | Finds thread titled ~"Fix triple command-center rows…" | Missing, wrong title, or wrong repo |
| 3 | Same thread — count turns / scroll | **~35 turns**, segmented user/assistant rows, scroll stays responsive | 1 turn, garbage blob, or UI jank/freeze |
| 4 | Same thread — if empty on first paint, wait ~3s (fetch-on-open) | Transcript fills from host without leaving thread | Stays empty after refresh |
| 5 | Scroll up in long thread → tap **↓** jump arrow | Arrow appears when not at tail; tap lands at bottom clear of follow-up bar | Arrow missing, untappable, or tail hidden under bar |
| 6 | Open a completed run thread (live or reopened) | **Proof/receipt chip** visible under assistant turn | No chip where a receipt exists |
| 7 | Thread **⋯** menu → **Flight Recorder** | Timeline opens with stdout/tool/receipt steps | Missing menu item or empty timeline |
| 8 | Start a new prompt that edits files (e.g. tiny doc change) — watch live thread | **Status pill** shows Thinking / tool name / Editing… with elapsed; clears when run ends | Stuck "Working…" only, or pill never appears |
| 9 | Same editing thread — after turn completes | **Turn diff card** ("N files +A −D"); **session pill** above composer; tap pill → **review sheet** (Modified \| All Files, hunks, file tree) | No diff UI, sheet empty, or crash |
| 10 | In review sheet — long-press a diff line → **Attach** comment | Comment chip queues in composer; removable before send | No attach flow or auto-send |
| 11 | Composer **+** → Context → pick **Photo** or **File** → send with short prompt | Attachment chip in composer; Mac agent/daemon sees file path in dispatch | Picker dead, chip missing, or upload error |
| 12 | Workspaces — **command-center** repo rows | Exactly **one** command-center row (not 2–3 duplicates) | Multiple command-center buckets |
| 13 | Agents row → tap a recent Mac session | Opens chat **directly** (no "Continue in Lancer" interstitial) | Extra interstitial or wrong thread |
| 14 | Send a low-risk prompt from composer (not immediately after reinstall) | Round-trip completes; transcript updates | "Machine didn't respond" with no recovery *(known pre-#110 — note if Retry fixes)* |

---

## Re-test after #110 (REL-1) merges

| # | Tap / action | Pass | Fail |
|---|--------------|------|------|
| R1 | Force-quit Lancer → reopen (pairing should auto-restore) → send **first** prompt immediately | Agent responds **without** tapping Retry | "Machine didn't respond" on first send; Retry required |
| R2 | Repeat R1 after toggling airplane mode off (reconnect) | First send after reconnect succeeds automatically | Same first-send failure |
| R3 | Pairing sheet while waiting for Mac code | **TTL countdown** visible from `expiresAt` | No countdown / stale "waiting" forever |
| R4 | Let an **unconfirmed** code expire (~10 min) or use an expired code | Phone shows **"Pairing code expired"**, stops reconnect churn; re-pair affordance | Endless reconnect loop or generic failure |
| R5 | After R4 — generate fresh code on Mac, re-pair | Pairs once; connected; send works | Daemon stuck on dead code (owner must check `lancerd status` / logs for re-mint) |
| R6 | Re-run rows **1–4** (35-turn fetch-on-open) on integrated build | Still passes on master+#110 build | Regression in backfill or long-thread open |

**REL-1 acceptance source:** `docs/plans/2026-07-12-rel1-relay-robustness-spec.md` (PR #110).

---

## Priority order (owner, ~15 min now)

1. **#2–4** — 35-turn "Fix triple…" fetch-on-open (session-4 hold item)
2. **#11** — context attachment round-trip (#109)
3. **#9–10** — G2 review sheet + line comment (#107)
4. **#8** — G3 live status pill (#108)
5. **#5–6** — scroll arrow + proof chips (#105)

After #110 lands: **R1–R2** first (tester blocker #1).
