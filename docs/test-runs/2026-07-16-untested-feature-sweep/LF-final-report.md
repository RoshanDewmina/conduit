# Lane F-final — Terminal open + remaining chat pills (#10/#11/#14/#18)

Date: 2026-07-16. Tip: `1f08c3c6`. Simurgh `lease-194` (same sim as C3),
udid `652AFCA1-2B70-4B66-83D2-49E4B5F30B27`. Isolated daemon
`LANCER_STATE_DIR=/tmp/sweep-F`, binary `/tmp/lancerd-sweep-C3`,
`HOME=/Users/roshansilva` (Claude auth). Pair code via
`TEST_RUNNER_LANE_F_PAIR_CODE`.

## Headline

**Terminal open is PASS under light load** — overturns Lane E's contention FAIL
for the product path (consistent with F3's env-artifact verdict). Live terminal
showed `shell · connected`, ran startup commands (`ls`, `pwd`, `echo hi | wc -c`
→ `3`), cwd was the worktree. Screenshot: `screenshots/LF-terminal-open-usage.png`.

**#10 Background-tasks pill FAIL reconfirmed** on a completed Bash turn
(`pill=false`, `turnDone=true`, `approves=1`). **#14** still has zero Bash tool
chips (`bashCount=0`). **#11/#18** still did not exercise cleanly
(`followup=false`, `todo=false edited=false approves=0`).

## Verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| Terminal open | LiveTerminalView presents | **PASS** | `LF-02-terminal-check presented=true`; `LF-terminal-open-usage.png` shows connected PTY + command output |
| Terminal usage | ls/pwd/echo\|wc | **PASS** | Same screenshot; `wc -c` printed `3` |
| Terminal lifecycle | dismiss/reopen/kill | **PARTIAL** | Dismiss via Close returned to Workspaces (`LF-04`); reopen/kill PTY not separately stressed |
| Desktop history on open | — | **UNPROVEN** | Not isolated; terminal opened via `LANCER_DESTINATION=terminal` |
| 10 | Background-tasks pill | **FAIL** (reconfirm) | `LF-07-pill-check pill=false followup=false approves=1` after completed sleep turn |
| 11 | Mid-run feedback queue | **BLOCKED** (harness) | `followup=false` — no enabled send while Working… |
| 14 | Tool-call label dedup | **BLOCKED** (no chips) | `bashCount=0` — same transcript hydration gap as #10 |
| 18 | Todo checklist / activity | **BLOCKED** (harness) | `todo=false edited=false approves=0` — TodoWrite turn never hit an approval gate / never rendered checklist |

## Run notes

- XCUITest soft-passed (evidence via attachments; no hard asserts on known FAILs).
- Daemon: paired twice (`12:57:08`, `12:58:56` after addRepo relaunch).
- `F.xcresult` left incomplete after wrapper hang on post-test screenshot; attachment
  names + wall-clock evidence recovered from `/tmp/sweep-F/test-run.log`.
- Lease released at end of session.

## Files

- Test: `LancerUITests/SweepLaneFFinalTests.swift`
- Screenshots: `screenshots/LF-terminal-open-usage.png`, `LF-after-chat-pills.png`
- Raw: `/tmp/sweep-F/daemon.log`, `/tmp/sweep-F/test-run.log`
