# Install + smoke checklist — 2026-07-17 dual-product dogfood run

## SHAs

- **Lancer `origin/master`:** `c85f4a7e`
- **Simurgh `origin/master`:** `4fe7e53`
- **Simurgh CLI:** `~/bin/simurgh` (rebuilt from `4fe7e53`; previous backed up to `~/bin/simurgh.bak-2026-07-17`)
- **Production daemon:** `~/.lancer/bin/lancerd` (rebuilt from `c85f4a7e`; previous backed up to `~/.lancer/bin/lancerd.bak-2026-07-17`)
- **Phone:** Lancer reinstalled + relaunched at `c85f4a7e` on `Roshan's iPhone` (UDID `557A7877-F729-5031-9606-0E04F2B67822`). Pair kept — no remint.

## What changed this session (10 Lancer PRs + Simurgh publish)

Per-chat autonomy pill now actually scopes escalation to that chat's repo (not global) with
daemon audit proof. Stale "Running" chip closed with a live-stream regression test. Emergency
Stop now actually kills pending approval hook gates (was silently leaving them alive). Three
measured perf fixes: live-follow no longer re-renders the whole transcript on unchanged polls,
transcript-item assembly is cached, thread list is 10x faster to load. A real production bug
(push registration file getting clobbered by test runs) was found and fixed. Simurgh's 96
pending commits are now public and the CLI is current.

## Smoke steps (5 min)

1. **Open Lancer.** Confirm Workspaces loads instantly (perf fix — should feel snappy, no
   blank-screen pause on a repo with history).
2. **Open an existing long thread.** Should open scrolled to the latest message, no visible
   spinner hang. Scroll up/down — should stay smooth.
3. **Send a message that needs approval** (e.g. ask the agent to run a shell command).
   Approve it. Confirm the thread's "Running" indicator clears to Completed **without leaving
   the thread** — this was the WT-B bug.
4. **Tap the permission pill in that same chat.** Change it to a different autonomy level.
   Open a DIFFERENT chat (different repo) — confirm its pill is unaffected (this is the new
   per-chat scoping; previously changing one chat silently changed every chat).
5. **Settings → Policy & Governance → Emergency Stop.** If you have anything running, confirm
   Stop actually halts it (this was silently not working before today).
6. **Leave the app running in the background, then trigger an approval from another session
   (or ask an agent to do something risky).** Watch for a lock-screen push notification.
   **This is the one item NOT independently confirmed this session** — the daemon-side fix is
   deployed and the phone has relaunched to pick it up, but nobody watched the phone's lock
   screen live. If it doesn't arrive, check `~/.lancer/lancerd.stderr.log` for
   `push: rehydrated` / `e2e: device registered for push` lines and report back.

## If something looks wrong

- **Pair shows disconnected:** run `~/.lancer/bin/lancerd doctor` — should show `relay pairing
  … confirmed`. If not, do NOT remint; ping for diagnosis first (relay pairing survived a
  binary swap + restart in this session, so a fresh disconnect points at something new).
- **Anything behaves like the OLD build:** the app may not have picked up the reinstall —
  force-quit and relaunch from the home screen.

## Where the evidence lives

- Perf: `docs/test-runs/2026-07-17-perf/README.md`
- Gap re-proof (GAP #10/#14, C4 #7, Emergency Stop): `docs/test-runs/2026-07-17-gap-reproof/evidence-log.md`
- Simurgh dogfood ledger (frictions found building Lancer with Simurgh): `~/Documents/simurgh/docs/DOGFOOD_FROM_LANCER.md`
- Full session narrative: `docs/plans/orchestrator-state.md` (⚡ 2026-07-17 ~12:05 ET entry, top of file)
