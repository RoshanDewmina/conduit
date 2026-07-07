# Tier 0 owner checklist — physical device proof (2026-07-07)

**Status:** Engineering gates green on `master` (`8ca4445a` + pending live-approval sync fix).  
**Device:** Roshan's iPhone (`557A7877-F729-5031-9606-0E04F2B67822`, available paired).  
**Daemon:** `dev.lancer.lancerd` launchd job (verify with command below).

Automated coverage already proven:
- `CursorAppShellExhaustiveTests` **21/21 PASS** (mock shell)
- `relay-approval-e2e.sh` **PASS** (live shell, synthetic tap)
- Physical device **build** PASS (`xcodebuild build -destination 'platform=iOS,id=557A7877…'`)
- Workspace row hydration UITest PASS on physical device (see `2026-07-06-tier0-device-proof.md`)

## Owner steps (~5 minutes)

1. **Daemon health**
   ```bash
   launchctl print gui/$(id -u)/dev.lancer.lancerd | grep state
   ```
   Expect `state = running`. If not: `launchctl kickstart -k gui/$(id -u)/dev.lancer.lancerd`

2. **Connection banner** — Open Lancer on the phone. Workspaces should show **connected** (not persistent "Can't reach your machine").

3. **Composer dispatch** — Send a prompt that triggers a **gated** action on the Mac (e.g. a command the daemon will hold for approval).

4. **Face ID approve (cannot be automated)** — When the approval banner appears on the work thread, tap through to Review and **Approve with Face ID**. Confirm the action completes and a follow-up in the **same thread** resumes (not a new session).

5. **APNs lock-screen approve (cannot be automated)** — Background or force-quit Lancer, trigger a second gated action from the Mac, confirm push arrives, tap **Approve** on the lock-screen notification while locked. Screen-record per `docs/LIVE_LOOP_RUNBOOK.md` Phase 5c.

6. **Record results** — Update this file or add `docs/test-runs/2026-07-07-tier0-device-proof-results.md` with pass/fail + screen recording path.

## If push does not arrive

See `docs/LIVE_LOOP_RUNBOOK.md` triage row **E** (APNs env, token registration, sessionId parity).
