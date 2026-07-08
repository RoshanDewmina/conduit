# Tier 0 device proof results — D0.2 owner physical-device run (2026-07-08)

**Repo tip:** `2e33b434` (includes `9e18d679` Face ID removal + Cursor shell live data)  
**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**Daemon:** `dev.lancer.lancerd` running, `APPROVAL_RELAY_SECRET` in launchd env  
**Push backend:** `https://conduit-push-y4wpy6zeva-ts.a.run.app`  
**Build:** Debug-iphoneos from master, signed `Apple Development: dewminaimalsha2003@gmail.com (2X93YVJ4G4)`, Team `39HM2X8GS6`  
**DerivedData:** `/Users/roshansilva/Library/Developer/XcodeBuildMCP/SharedDerivedData/Lancer` — `BUILD SUCCEEDED` in 196s  

**Session:** Interactive owner + agent run ~10:02–12:54 local (UTC-4).

---

## Summary

| Step | Description | Result |
|------|-------------|--------|
| 0 | Preflight | **PASS** |
| 1 | Build + install | **PASS** |
| 2 | Connection + kill/relaunch | **PASS** (after re-pair) |
| 3 | Notifications + token registration | **PASS** |
| 4 | In-app approve | **PASS** (functional) / **UI regression** |
| 5 | Relay-only 5b | **PASS** (on retry with manual Review Approve) |
| 6a | Background + lock-screen approve | **FAIL** (5c) |
| 6b | Force-quit + lock-screen approve | **FAIL** (5c) — phone UX OK, host no decision |
| 7 | Force-quit + lock-screen reject | **FAIL** — same delivery gap |

**D0.2 / checkpoint 5c: NOT PASSED.** Layers 0–3 last gate remains open.

---

## Step 0 — Preflight

- `git merge-base --is-ancestor 9e18d679 HEAD` → OK (`2e33b434`)
- `launchctl print … dev.lancer.lancerd` → `state = running`, `APPROVAL_RELAY_SECRET` present
- `lancerd doctor` → 12 OK, relay paired `wss://conduit-push-y4wpy6zeva-ts.a.run.app`
- `~/.lancer/policy.yaml` → default-ask (fileWrite escalates)
- Go daemon confirmed (not stale Swift 0.1.0 shim)

---

## Step 1 — Build + install

- `xcodebuild` device build → **SUCCEEDED** 196.3s
- `install_app_device` → installed on `557A7877-…`
- Owner: app icon updated / launches

---

## Step 2 — Connection

**Initial:** Workspaces showed **"Reconnecting…"** (screenshot `Screenshot_2026-07-08_at_11.58.53_AM.png`).

**Cause:** Stale/orphaned phone pairing (host still on code `194990` from 2026-07-03).

**Fix:** `lancerd pair` → code `054921`; owner entered in Settings → Pair machine.

**After re-pair + force-quit/relaunch:** Connected — **PASS**.

---

## Step 3 — Notifications + APNs token

- Owner: notifications **on** in iOS Settings
- Background + re-foreground once
- Cloud Run log: `registered session C3D36704-733B-4790-83B1-A117BF97AEC8 (apns=true relay=false)` @ 16:04:21Z — **PASS**

---

## Step 4 — In-app approve

**Trigger:** `agent-hook` fileWrite `a7d64afe-…` @ 16:04:52Z

**Owner:** Approved in Review; screenshot showed **"No pending approval"** with empty scope but footer **"Approved · Decided by You"**.

**Host:** `approve` @ 16:05:23Z — **functional PASS**

**Regression:** `CursorReviewDiffView` did not bind `Approval` for display (`pendingApproval` / `lookupApproval` nil) while `pendingApprovalID` was set. See `AppRoot.swift` comment ~line 212.

---

## Step 5 — Relay-only (5b)

**Precondition:** No `lancerd serve` / SSH session.

| Attempt | approvalId | Owner action | Host |
|---------|------------|--------------|------|
| 1 | `20e3fdae-…` | Body tap → stale "Approved" UI | No approve |
| 2 | `1e2b0cbd-…` | Dismissed banner | — |
| 3 | `007c9933-…` | Banner → Review → **Approve** | `approve` @ 16:13:04Z **PASS** |

**Findings:**
- Review `@State decision` can show stale **Approved** after notification body tap without sending decision (Step 5 attempt 1).
- Dismissed banner has no recovery surface (Activity/Inbox under Workspaces) — product gap.

---

## Step 6 — Checkpoint 5c (APNs, app closed)

### 6a — Backgrounded

- Trigger: `667d36c4-…` @ 16:14:26Z
- Owner: push arrived fast; **regular notification only** (no DI/LA); no Approve/Reject on plain view; body tap unlocked phone → opened app
- In-app approve @ 16:17:32Z unblocked host — **not 5c** (app foregrounded)
- Cloud Run: `BadDeviceToken` on `api.push.apple.com` @ 16:14:28Z (sandbox fallback path)

### 6b — Force-quit

- Trigger: `f8e24db0-…` @ 16:18:46Z
- Owner: long-press → **Approve** on lock screen; **no Face ID/passcode**; **Lancer did not open**
- Host @ 16:32+ still: **only escalate, no approve**; pending in `queue.json` — **FAIL**

### Dynamic Island / Live Activities

Not observed. Separate from 5c bar: requires ActivityKit push-to-start / activity token registration + backend `pushLiveActivityApproval`. Dev build + production `BadDeviceToken` on alert path; LA lane (I4) not verified this session.

---

## Step 7 — Lock-screen Reject

- Trigger: `98e45e0e-…` @ 16:54:23Z
- Owner: long-press → **Reject**; Lancer did not open
- Host: **only escalate, no deny/reject**; still pending in `queue.json` — **FAIL**

Same delivery hop as 6b: notification action → (app background handler / `ApprovalActionBuffer` / relay) → daemon — **decision not arriving** when app force-quit.

---

## Triage hop (5c / 7 failure)

| Hop | Status |
|-----|--------|
| Push delivery (notification arrives) | **Partial** — banner arrives; production APNs `BadDeviceToken`, likely local or sandbox alert |
| Lock-screen actions visible (long-press) | **PASS** (owner confirmed 6b/7) |
| Phone handles action without foreground | **PASS** (owner: app did not open) |
| Decision → relay/backend → `lancerd` → `audit.log` | **FAIL** for `f8e24db0`, `98e45e0e` |
| Agent hook unblocks | **FAIL** (no approve/deny lines) |

**Inspect:** `LancerNotificationDelegate` (`approval.approve` / `approval.reject`), `ApprovalActionBuffer` cold-launch drain, `ApprovalRelay.postDecisionToBackend` / `forwardDecisionOnly`, `sessionId` parity on decision POST.

---

## Evidence index

| Artifact | Path / ID |
|----------|-----------|
| Build log | `BUILD SUCCEEDED` 196s, SharedDerivedData/Lancer |
| Re-pair code | `054921` (replaced `194990`) |
| Session ID (APNs register) | `C3D36704-733B-4790-83B1-A117BF97AEC8` |
| Screenshots | `assets/Screenshot_2026-07-08_at_11.58.53_AM.png`, `…12.05.34_PM.png`, `…12.07.50_PM.png` |
| Audit approve (in-app) | `a7d64afe` 16:05:23Z, `007c9933` 16:13:04Z, `667d36c4` 16:17:32Z |
| Audit missing (lock-screen) | `f8e24db0`, `98e45e0e` — escalate only |

---

## Repro — lock-screen decision not reaching host

1. Pair phone + host (`lancerd pair`), verify connected.
2. Force-quit Lancer; lock phone.
3. `lancerd agent-hook --agent claudeCode --kind fileWrite --command "…" --cwd … --risk medium`
4. Long-press notification → Approve or Reject.
5. **Expected:** `audit.log` `approve` or `deny` within ~30s without opening app.
6. **Actual (2026-07-08):** notification action completes on phone; `audit.log` stays at `escalate`; `queue.json` remains pending.

---

## Checklist impact

- **C2 / D3:** 2026-07-08 owner re-run **FAILED** checkpoint 5c (decision delivery). Prior 2026-06-23 pass not revalidated.
- **D0.2:** **Not closed.**
