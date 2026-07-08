# Tier 0 / 5c re-test results — D0.2 lock-screen Approve + Reject (2026-07-08 evening)

**Prior morning run:** [`2026-07-08-tier0-device-proof-results.md`](2026-07-08-tier0-device-proof-results.md) — 5c **FAIL** (phone UX OK, host no decision).  
**Root cause / #52:** [`2026-07-08-5c-root-cause.md`](2026-07-08-5c-root-cause.md) — delivery via `ApprovalRelay.enqueue` without needing `AppRoot` scene.  
**This re-test:** force-quit + lock-screen Approve **and** Reject after content-hash echo + race fixes.

**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**Relay:** `wss://conduit-push-y4wpy6zeva-ts.a.run.app`  
**Pairing code (final):** `865601`  
**Repo tip at proof:** `3fd6674f` + this commit (content-hash / race fixes)  
**Pass bar:** host `~/.lancer/audit.log` shows `approve` / `deny` for the exact `approvalId`; hook unblocks. Never PASS from phone UX alone.

---

## Verdict

| Gate | Result |
|------|--------|
| Checkpoint **5c** (lock-screen Approve) | **PASS** |
| Force-quit + lock-screen **Reject** | **PASS** |
| **D0.2** (physical-device governed loop last gate) | **PASS** (host evidence) |

---

## Session narrative (what we did today)

### Morning — D0.2 FAIL on 5c

Owner physical-device run recorded in [`2026-07-08-tier0-device-proof-results.md`](2026-07-08-tier0-device-proof-results.md):

- Steps 0–5 (preflight, install, connect, APNs token, in-app approve, relay 5b) **PASS**.
- Steps 6a/6b/7 (background / force-quit lock-screen Approve + Reject): phone UX OK, host `audit.log` only showed `escalate` for `f8e24db0…` / `98e45e0e…` — **5c FAIL**.

### Midday — #52 delivery fix

[`2026-07-08-5c-root-cause.md`](2026-07-08-5c-root-cause.md) / PR #52: force-quit lock-screen actions relaunch the process **without** connecting a `WindowGroup`, so `AppRoot` never drained `ApprovalActionBuffer`. Fix: `LancerNotificationDelegate.didReceive` delivers via `ApprovalRelay.enqueue` + background task.

### Evening — re-test found a second bug (content hash)

With #52 installed, lock-screen decisions **did reach** `lancerd`, but resolve failed:

```text
security: approval <id> decision rejected — content hash mismatch (stale UI, race, or forged decision)
```

Also seen retroactively for morning ids `f8e24db0` / `98e45e0e` — morning FAIL was likely **hash + delivery**, not delivery alone.

| Failure mode | Detail |
|--------------|--------|
| Missing hash on force-quit | No local Approval DB row → `enqueue` sent `contentHash: nil` |
| APNs payload incomplete | Push carried `approvalId` / `sessionId` / `risk` but not `contentHash` to echo |
| Replace race | Hash-bearing POST (~689 B) overwritten by warm buffer/AppRoot drain POST (~608 B without hash); push-backend replace-by-`approvalId` stripped the hash |

Failed evening trials (host rejected): `f1f0b4c2…`, `7d379587…`, `aed695c1…`, `eb9b59e5…`.

### Fixes shipped in this commit

| Area | Change |
|------|--------|
| APNs payload | `lancerd` `postApprovalPush` + push-backend `approvalAPNsPayload` include `contentHash` |
| Lock-screen action | `LancerApp` reads `userInfo["contentHash"]`; `PendingApprovalAction` / NC post / `deliverDecision` → `ApprovalRelay.enqueue(..., contentHash:)` prefer caller hash over DB |
| Decision replace race | `handlePostDecision` keeps existing non-empty `ContentHash` when replacing same `approvalId` |

Files: `Lancer/LancerApp.swift`, `Notifications.swift`, `ApprovalRelay.swift`, `AppRoot.swift`, `daemon/lancerd/server.go`, `daemon/push-backend/{main,decisions}.go`.

Deployed during session: local `~/.lancer/bin/lancerd` rebuilt; Cloud Run push-backend revision live; Debug app rebuilt/installed on device (binary contained `contentHash` strings).

### Pairing / reconnect chaos (test-session only)

Repeated `lancerd pair` + daemon restarts orphaned phone codes → Workspaces **Reconnecting**. Relay logged `phone key mismatch for code X, rejecting hijack attempt` when a code was already bound to a different phone public key. App delete does **not** clear Keychain pairing keys → reinstall still hit hijack on old codes. Stale `queue.json` caused `re-sending N pending approval(s) after (re)pair` floods that dropped the phone WS. UI gaps noted: Settings → Trusted machines only opens Pair sheet; Reset app data is a no-op stub.

**Product note:** normal users pair once; tonight’s churn was agent-driven pair rotations. Final working code: **`865601`**.

### Final proof trials

See [Trial evidence](#trial-evidence) below — Approve `79137ae4…` + Reject `461bc3e0…` both accepted on host with no hash mismatch.

---

## Trial evidence

### Approve (force-quit + lock)

| Field | Value |
|-------|-------|
| **approvalId** | `79137ae4-8eba-4fc6-b4b0-6383926aa946` |
| escalate | `2026-07-08T23:36:33Z` |
| **approve** | `2026-07-08T23:36:48Z` |
| hook | exit **0** (unblocked) |
| stderr | sent over relay; **no** content-hash mismatch |
| Decision POST size | ~689 bytes (hash-bearing) |

### Reject (force-quit + lock)

| Field | Value |
|-------|-------|
| **approvalId** | `461bc3e0-a6ec-408a-b13a-d76956380390` |
| escalate | `2026-07-08T23:41:45Z` |
| **deny** | `2026-07-08T23:42:03Z` |
| hook | `lancerd agent-hook: denied by user` → exit **1** (expected for reject) |
| stderr | sent over relay; **no** content-hash mismatch |

---

## Residual notes (non-blocking for 5c)

- `queue.json` still listed the decided ids briefly after audit `approve`/`deny` — pass bar is audit + hook, not queue clear timing.
- Pairing churn / `phone key mismatch` / stale pending re-send floods were **test-session** artifacts from repeated `lancerd pair`; product path is pair-once.
- Production APNs `BadDeviceToken` → sandbox fallback remains a known separate issue; pushes still arrived for these trials.
- Mid-session: uncommitted fix edits were briefly wiped from the working tree; re-applied before final proof. Prefer committing hash/race fixes promptly after device proof.

---

## Follow-ups

1. Optional: screen recording for runbook Phase 5c archive (owner-gated).
2. Consider product fixes for Trusted machines remove-list + Reset app data stub (pairing recovery UX).
3. A3 R1–R4 already merged (#63–#66); Away Launch Composer + Watch embed no longer frozen on D0.2.
