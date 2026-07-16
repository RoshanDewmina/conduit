# Lane C3 — Review stack post-F4 (candidates #7/#8/#9/#17/#19/#23)

Date: 2026-07-16. Tip: `integration/2026-07-16-untested-sweep` @ `1f08c3c6`
(F4 approve→launch resume merged). Simurgh `lease-194`, `iPhone 17 Pro`,
udid `652AFCA1-2B70-4B66-83D2-49E4B5F30B27`. Isolated daemon
`LANCER_STATE_DIR=/tmp/sweep-C3`, binary `/tmp/lancerd-sweep-C3` rebuilt from tip.
F4 regression unit tests reconfirmed PASS before live run.

## Headline

**F4 server-side approve→launch is live-proven.** After tapping
`cursor.approval.approve`, Claude actually ran and committed
`474f104 sweep edit` in `/tmp/sweep-C3/target-repo` (greeting.txt + readme.md
each gained `sweep edit applied`). Daemon log:

```
12:50:08 e2e: paired with phone
12:50:32 e2e: sent approval ee37da6e-... over relay
(+ 4 more mid-run approval sends as tool gates fired)
```

**But the review-stack UI candidates still did not render.** The thread stayed on
the sync `needsApproval` terminal error ("Couldn't get a reply / Awaiting your
approval — check the Inbox. / Retry") even while the background resumed launch
succeeded. XCUITest assertion failed:
`session-diff-pill` / Proof chip never appeared (`approveTaps=5 sawRetry=true`).

## Candidate verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 19 | Repo display-name vs cwd | **PASS** | Add Repo with display `sc3-repo` + path `/tmp/sweep-C3/target-repo`; commit landed in that absolute path (`LC3-git-proof.txt`). |
| 7 | Review pill → ReviewSheetView | **FAIL** (UI) | Turn completed server-side; `session-diff-pill` never in a11y tree. Screenshots `LC3-04-thread-after-run.png`, `LC3-awaiting-approval-stale-ui.png`. |
| 8 | FileViewerView | **BLOCKED** | Blocked on #7 — Review sheet never opened. |
| 9 | AddCommentSheet | **BLOCKED** | Same. |
| 17 | Receipt `filesTouched` | **BLOCKED** | Proof chip never appeared in UI despite real file edits. |
| 23 | Flight Recorder | **BLOCKED** | Menu path not reached; no completed-turn UI surface. |

## F4 / env findings (load-bearing)

1. **F4 resume works** when Claude auth is available. First attempt with
   `HOME=/tmp/sweep-C3/home` hit `conversation-append-auth-preflight` deny
   (`loggedIn: false` under isolated HOME) — audit saved as
   `LC3-audit-auth-preflight-deny.log` / screenshot `LC3-auth-preflight-deny.png`.
   Second attempt with `HOME=/Users/roshansilva` + `LANCER_STATE_DIR=/tmp/sweep-C3`
   launched successfully.
2. **Client/UX gap (new, P1):** sync RPC still returns `needsApproval` and the
   app renders it as a terminal error, even when F4's async resume later launches
   and completes the turn. User sees Retry forever; review/receipt chrome never
   binds to the completed run. Suspected locus: `LiveThreadView` errorState on
   `needsApproval` vs missing live transcript subscription for the resumed run.
3. **Harness:** `lancerd pair` while a daemon is already running can leave a
   stale sock / dead process if the daemon was started under a Cursor shell job;
   use `start_new_session` detach (Python) + pair-then-start. Daemon must stay
   alive for auto-pair (`TEST_RUNNER_LANE_C3_PAIR_CODE`).

## Incident note (production pairing)

A bare `/tmp/lancerd-sweep pair` without `LANCER_STATE_DIR` briefly rotated
`~/.lancer/relay-pairing.json` to code `310440` on fly.dev. Restored to that
working fly.dev identity after a dead Cloud Run KEEP backup failed. **Owner
phone may need re-pair** (already owner-gated for daily-use L6). Production
daemon pid `91280` reconnected at 12:30:13.

## Files

- Test: `LancerUITests/SweepLaneC3Tests.swift`
- Screenshots: `screenshots/LC3-*.png`
- Git proof: `LC3-git-proof.txt`
- Auth-preflight evidence: `LC3-audit-auth-preflight-deny.log`
- Raw: `/tmp/sweep-C3/daemon.log`, `/tmp/sweep-C3/test-run5.log`, `/tmp/sweep-C3/C3.xcresult`

## Simurgh feedback

- `lease-1` was released mid first attempt (HOME pollution put lease metadata under
  `/tmp/sweep-C3/home/.simurgh`); re-acquired `lease-194` with correct HOME.
- Manual `renew` loop required when not using `simurgh exec` (derivedDataPath clash).
