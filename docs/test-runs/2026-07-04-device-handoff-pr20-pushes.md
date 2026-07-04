# PR #20 — needs-you notifications device test plan

Date: 2026-07-04  
Branch: `cursor/pr20-redaction-9257` (rebased PR #20 + APNs redaction fix)  
Runner: _owner, physical iPhone_

## Preconditions

- [ ] Build from `cursor/pr20-redaction-9257` (or updated PR #20 head)
- [ ] Push-backend deployed with matching build
- [ ] APNs working (development or production token env)

## Test 1 — background run-complete push

1. Start a short agent run from phone.
2. Background the app (home button / swipe up).
3. Wait for run to complete on host.
4. **Expected**: push arrives; tapping opens correct thread (not generic Inbox).

| Pass/Fail | Lock screen title/body | Tap destination | Notes |
|-----------|------------------------|-----------------|-------|

## Test 2 — askQuestion smoke (redaction)

1. Trigger `askQuestion` via Claude/Codex hook (`--kind askQuestion`).
2. **Lock screen**: body must **not** contain full raw question text — expect generic e.g. "Your agent needs your input".
3. **In-app (unlocked)**: full question visible in `DSAskQuestionCard` / Inbox.

| Pass/Fail | Lock screen body (redacted?) | In-app full question? | Notes |
|-----------|------------------------------|----------------------|-------|

## Test 3 — force-quit + push routing

1. Force-quit Lancer completely.
2. Trigger run-complete **or** askQuestion event.
3. **Expected**: push arrives; tap opens **originating thread**, not wrong destination.

| Pass/Fail | Notification kind | Deep link correct? | Notes |
|-----------|-------------------|-------------------|-------|

## Regression (automated — already run in CI)

- [x] `TestAskQuestionApprovalAlertBodyRedacted` — alert body ≠ raw question

## Gate

- [ ] All manual tests pass → `gh pr ready 20` → CI → merge

Owner sign-off: _______________
