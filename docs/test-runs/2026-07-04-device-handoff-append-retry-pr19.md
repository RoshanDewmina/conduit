# PR #19 — conversation append retry live verification

Date: 2026-07-04  
Branch: `fix/conversation-append-retry` (PR #19)  
Append to: `docs/test-runs/2026-07-03-cross-device-sync-release-gate.md` when complete.

## Preconditions

- [ ] PR #19 build on physical iPhone
- [ ] Paired relay + daemon running on Mac host
- [ ] Active conversation with at least one prior message

## Test 1 — transient failure recovers (no false offline)

1. Open conversation on phone; confirm connected.
2. Send follow-up message.
3. **During send**: briefly degrade connection (restart relay WS, throttle network, or daemon reconnect window).
4. **Expected**: message succeeds after retry (up to 3 attempts); **no** false `hostOffline` banner.

| Step | Pass/Fail | Notes |
|------|-----------|-------|
| Transient degrade + follow-up send | | |

## Test 2 — genuine outage still surfaces offline

1. Stop daemon entirely (or disconnect host network for > retry window).
2. Send message from phone.
3. **Expected**: `hostOffline` (or equivalent) after retries exhaust — retry must **not** paper over real outage.

| Step | Pass/Fail | Notes |
|------|-----------|-------|
| Persistent outage | | |

## Test 3 — Mac-terminal chat appears on phone

1. Start or continue run from Mac terminal (not phone dispatch).
2. **Expected**: conversation / messages appear on phone promptly under normal connectivity.

| Step | Pass/Fail | Notes |
|------|-----------|-------|
| Cross-source sync | | |

## Gate

- [ ] All three pass → `gh pr merge 19 --merge --delete-branch`
- [ ] If 3 retries insufficient in real reconnect windows, fix parameters in PR before merge

Owner sign-off: _______________
