# REL-1 rebase — outcome: no-op, feature already on master

## Finding

The 5-commit REL-1 relay-robustness feature (`ae89d334`, `642c3b96`, `82634190`,
`032c46cc`, `99108eb3` — old branch tip `feat/rel1-relay-robustness`) was **already
merged into `origin/master`** on 2026-07-12 as the squashed commit `0e0b9eba`
("fix(relay): REL-1 session robustness — structured errors, re-mint, first-send
gate (#110)").

Proof:

```
git diff --stat 99108eb3 0e0b9eba
```

returns **zero output across the entire repo** — the rel1 branch tip and the
already-merged master commit are tree-identical. `git merge-base --is-ancestor
0e0b9eba origin/master` confirms `0e0b9eba` is on master's mainline, 229 commits
back from the current tip (`265b62e1`).

There was nothing to rebase. `git rebase origin/master` would have replayed
5 commits that are already contained in master's history and produced either
empty commits or immediate no-op conflicts. Per the task's own guidance
("if the drift makes rebase hopeless... re-apply as fresh commits"), the correct
action given zero net diff is: **do nothing** — reset this branch to
`origin/master` and verify the feature's mechanisms are still intact and
correctly superseded where master evolved further.

## Verification that REL-1's intent survives on current master

All four REL-1 pieces were independently confirmed present in `origin/master`
(`265b62e1`) by grep of the actual mechanism names, not just the commit message:

- **REL-1 A (structured error codes + expiresAt TTL)** —
  `daemon/push-backend/websocket_relay.go`: `code_expired`, `key_mismatch`,
  `pairConfirmWindow`, `expiresAt` all present, unchanged in mechanism.
- **REL-1 B (daemon auto re-mint on dead unconfirmed code)** —
  `daemon/lancerd/e2e_liveness.go`: `decideExpiryAction`, `everConfirmed`-gated
  remint-vs-give-up logic present, unchanged.
- **REL-1 C (phone stops churning, truthful dead-pairing state)** —
  `Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift`:
  `.codeExpired` state, `stopReconnectingDeadCode()`, `pairingExpiresAt`
  all present, unchanged.
- **REL-1 D (first-send readiness gate) — SUPERSEDED, correctly, by a strictly
  better mechanism.** The original REL-1 D shipped a 5s wall-clock window
  (`isFirstSendRace(attemptedAt:lastReadyAt:)`) that only covered a first send
  within 5 seconds of re-key. PR **#111** (`5c7edd24`, "fix(relay): reset relay
  seq state on re-key and bound stale RPC waits") replaced it with an
  **event-based one-shot post-rekey retry** (`armPostRekeyMutatingRetry` /
  `claimPostRekeyMutatingRetry` / `withPostRekeyOneShotRetry` in
  `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`) that stays
  armed until claimed rather than expiring after 5 seconds — the surviving
  test file's own docstring says it plainly:
  `Packages/LancerKit/Tests/LancerKitTests/E2ERelayBridgeFirstSendTests.swift`:
  > "REL-1: event-based one-shot post-rekey eligibility for gated mutating RPCs
  > (`sendDispatch` / `relayAppendConversation`). Replaces the prior 5s
  > wall-clock window — a first send 16s after pair must still be eligible."

  This is a strict improvement (no expiry-window edge case) and was **not**
  re-applied — re-applying the old wall-clock helpers would regress a fixed bug.

No hunks were dropped silently: the one piece of REL-1 that master changed
(D's wall-clock retry window) was replaced by master with a better mechanism
covering the same failure mode, verified by symbol-level grep above, not just
commit-message trust.

## Branch state

`feat/rel1-relay-rebased` was reset (`git reset --hard origin/master`) to
`origin/master` @ `265b62e1`. Zero commits ahead of `origin/master`. Nothing to
review/merge from this branch — the feature is already live on master.

## Acceptance command output

See session report for verbatim tails of:
1. `cd daemon/lancerd && go test ./...`
2. `cd daemon/push-backend && go test ./...`
3. `cd Packages/LancerKit && swift build && swift test --filter 'Relay|RelayClient|E2E'`
4. `cd Packages/LancerKit && swift test` (full, unfiltered)
