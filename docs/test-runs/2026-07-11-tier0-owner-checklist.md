# Tier 0 owner checklist — device re-proof on current tip (2026-07-11)

**Tip under proof:** `master` @ post-#69 integration (W0.A shell + master backend; see
STATUS_LEDGER "Integration resolution").
**Device:** Roshan's iPhone 17 (`557A7877-F729-5031-9606-0E04F2B67822`) — was **unavailable**
(not connected) at prep time; connect + unlock it, then the orchestrator installs the build.
**Daemon:** redeployed from this tip 2026-07-11 (`stop → mv → bootstrap`), `state = running`.
**Install note:** owner authorized reinstall 2026-07-11 (wipes pairing — step 0 re-pairs).

## Owner steps (~7 minutes)

0. **Re-pair after install** — fresh install wipes pairing state: Settings → pairing, pair with
   the Mac daemon (QR/code). Trusted machine row should appear; Remove works.
1. **Daemon health** — `launchctl print gui/$(id -u)/dev.lancer.lancerd | grep state` →
   `state = running` (already verified at prep; re-check if hours passed).
2. **Connection banner** — open Lancer: connected, no persistent "Can't reach your machine".
3. **Composer dispatch** — send a prompt that triggers a **gated** action on the Mac.
4. **In-app approve** — approval banner → Review → **Approve**; action completes; follow-up
   resumes in the **same thread** (not a new session).
5. **APNs lock-screen approve (5c)** — background/force-quit Lancer, trigger a second gated
   action, push arrives, **Approve from the lock screen while locked**. Screen-record per
   `docs/LIVE_LOOP_RUNBOOK.md` Phase 5c.
6. **In-thread question (new since 07-08 proof)** — have the agent ask a question
   (AskUserQuestion); confirm the phone surfaces it and an answer resumes the same turn.
   ⚠️ Known risk: the master-line M1 Question *card* UI was dropped in the #69 integration —
   if no usable question surface appears, log it in `docs/dogfood-log.md` (it is queued as a
   Phase 1 re-port lane) and mark this step BLOCKED, not FAIL.
7. **Record results** — new file `docs/test-runs/2026-07-11-tier0-device-proof-results.md`
   with pass/fail per step + recording path.

## If push does not arrive

`docs/LIVE_LOOP_RUNBOOK.md` triage row **E** (APNs env, token registration, sessionId parity).
