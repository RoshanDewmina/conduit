# Lane D2 report — background tasks, follow-ups, todo checklist, thread list (2026-07-16)

Candidates: #10, #11, #14, #15, #16, #18. Isolated daemon `LANCER_STATE_DIR=/tmp/sweep-D2`
(rebuilt `/tmp/lancerd-sweep` from worktree tip `4e45dbaa`+; `daemon.log` never mentions
`/Users/roshansilva/.lancer` — confirmed clean throughout). Target repo
`/tmp/sweep-D2/target-repo` (git init + committed `greeting.txt`, `README.md`, `src/main.py`).
Simurgh lease-192 then lease-193 (`iPhone 17 Pro`; lease-192 expired mid-session, see below).

## Pairing — confirms F3's conclusion, cleanly, twice

Contrary to Lane D's 4-attempt pairing failure, pairing **worked on the first clean attempt** in
this session (no other lanes/build contention), and again after a full re-acquire:

- First pair: `daemon.log` → `2026/07/16 11:20:14 e2e: paired with phone` (~46s after cold launch
  with `LANCER_RELAY_PAIR_CODE` + `LANCER_SKIP_CURSOR_ONBOARDING=1`).
- Second pair (after lease expiry forced a fresh sim + fresh app install): `2026/07/16 11:56:43
  e2e: paired with phone` — **18s** after cold launch, code generated immediately before.
- Bonus confirmation of the merged approval-race fix (`e2e_router.go`, `4e45dbaa`): after the
  second re-pair, the daemon log shows `e2e: re-sending 1 pending approval(s) after (re)pair` /
  `sent approval 48b656ad-... over relay` — the bounded-retry path fired for real, delivering an
  approval that had been queued while unpaired.

**This strongly supports F3's finding**: Lane D's failure was resource contention from concurrent
sweep lanes, not a product bug. Two clean pairs, 18–46s, zero retries needed in isolation.

## Key finding: root cause of the missing HID gotcha was NOT what it looked like

`LANCER_RELAY_PAIR_CODE` alone does **not** auto-pair — `DebugSeeder.autoPairRelayIfRequested`
(`Packages/LancerKit/Sources/AppFeature/DebugSeeder.swift:85`) is only invoked from `AppRoot`'s
`readyRoot` `.task` (`Packages/LancerKit/Sources/AppFeature/AppRoot.swift:354`), which never
renders while onboarding is showing (`shouldShowOnboarding`, `AppRoot.swift:300`). The brief's
launch recipe needs **both** `LANCER_RELAY_PAIR_CODE` and `LANCER_SKIP_CURSOR_ONBOARDING=1` (or
`LANCER_DESTINATION`) set at cold launch, or auto-pair silently never fires. Worth folding into
the next sweep brief's launch recipe.

## Root-cause blockers hit

1. **Sandbox approval gate, not previously flagged in this sweep's briefs**: dispatching a Bash
   command puts up a **Command / risk-tier High** approval sheet (`Approve`/`Deny`) that blocks
   turn execution until tapped — confirmed via `approval-security-hardening` (2026-07-04, risk-tier
   floor). My first XCUITest run didn't tap `Approve`; the turn sat at "Still working…" for the
   full 90s test deadline with zero progress (screenshot evidence: `LD2-08-turn1-result` v1 run,
   still shows the pending `Approve`/`Deny` sheet at "Still working... 1m 52s"). This is a
   **test-script gap, not an app bug** — fixed by auto-tapping `Approve` as it appears; re-verified
   working after the fix (turn completed, "Worked 19s ... Proof · completed · 20.0s").
2. **Simurgh lease expired mid-session** (30 min TTL): the first XCUITest run failed
   ("should land on Workspaces home") after the *first* fix attempt, then a `test-without-building`
   diagnostic-collection step hung for the full 600s Xcode timeout
   (`IDETestOperationsObserverDebug: Failure collecting diagnostics from simulator: Timed out after
   600.0 seconds`) — burning enough wall-clock that lease-192 (acquired 11:12:43, TTL 30m) expired
   before the next command ran. `simurgh status --json` showed `active: 0` at that point. Recovered
   by re-acquiring (lease-193), reinstalling the app, and re-pairing from scratch (18s, see above).
   **Simurgh feedback**: a single failed/hung UI-test run can burn >30 min of wall clock
   (build-for-testing + test-without-building + a 600s diagnostic hang), so the default 30-minute
   lease TTL is tight for UI-test-driven verification specifically; a `renew` before any
   multi-minute `xcodebuild test-without-building` call is cheap insurance worth calling out in the
   brief.
3. **XCUITest same-thread follow-up vs. new dispatch ambiguity**: the `cursor-composer-tap`
   accessibility identifier is reachable both from the Workspaces home ("Plan, ask, build…") and,
   apparently, resolves to the same in-thread follow-up affordance once a thread exists — my
   second dispatch (intended as a fresh #18 TodoWrite+edit prompt) landed in the **existing
   thread's "Follow up…" field** instead of starting a clean turn, and no `composer.send` button
   was ever found/enabled for that field (screenshot `LD2-09`, 12:02, shows the typed text sitting
   unsent in "Follow up…" with the keyboard still up). This blocked #18 and cross-contaminates the
   #11 read — it is a **test-harness targeting gap** (need a distinct accessibility id for
   "send follow-up" vs. "send new turn"), not evidence the app itself can't do it.

## Verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 10 | Background-tasks pill + sheet | **FAIL** | Dispatched `Run \`sleep 40 && echo done\` via Bash, then summarize.` in `target-repo`; approved the risk-tier-High command gate; turn ran to completion (agent's own reply: *"Command is running in the background… You'll be notified when it completes."*, then `Worked 19s · Proof · completed · 20.0s`). At no point in the full session did `background-tasks-pill` (`Packages/LancerKit/Sources/AppFeature/Chat/BackgroundTasksPill.swift:205`) become reachable in the a11y tree (`LD2-04-pill-check`, 20s poll, zero hits). `BackgroundTasksPresentation.rows` (`BackgroundTasksPill.swift:39`) is a pure function over `ToolChipItem` `.running` entries from the live transcript — the transcript for this turn never rendered a distinct Bash tool chip either (see #14), so the pill's empty input is consistent with the chip-population path not firing for this response shape, not with the pill logic itself being wrong. |
| 11 | Mid-run feedback queue | **BLOCKED** | Test-harness gap (root-cause #3): the follow-up field was reachable and accepted typed text (`LD2-06/07` screenshots show "Follow up…" `TextView` present pre- and post-type), but no enabled `composer.send`-equivalent button was found to actually dispatch it, and the turn had already completed (~20s) by the time follow-up typing happened — so this never exercised a genuine "mid-run" state. Needs a re-run with a faster-completing gate check (poll for the `Approve` sheet immediately, type follow-up in the 1–2s window right after Approve before the 20s completion) and the correct send-affordance id. |
| 18 | Turn activity summary + Todo checklist | **BLOCKED** | Same root-cause #3 — the TodoWrite+edit prompt was typed into the existing thread's unsent "Follow up…" field and never dispatched (`LD2-09`, 12:02, text visibly sitting there with keyboard open, no chip/checklist rendered). No `TodoChecklistCard` or "Edited N files" summary row was ever exercised. Not evidence against the feature — the dispatch itself never happened. |
| 14 | Tool-call label dedup | **BLOCKED (no reachable material)** | `app.staticTexts` matching `label BEGINSWITH 'Bash'` returned zero matches (`LD2-12-toolchips bashLabels=[]`) — but the transcript for this turn rendered as plain prose (no visible discrete tool-call chip UI at all, matching the #10 finding), so there was no chip to check for dedup either way. Would need a turn whose adapter response does render `ToolCallChipView` chips (`Packages/LancerKit/Sources/AppFeature/Chat/ToolCallChipView.swift`) to actually test this candidate. |
| 15 | Thread-list filters + customize | **PASS** | From `All Repos` thread list: `thread-list-customize-button` opens `thread-list-customize` sheet (`LD2-15`, groupBy + status/source rows all present with correct a11y ids from `ThreadListCustomizeSheet.swift`); tapping `thread-list-customize.status` opens `thread-list-status-filter` (`LD2-16`) showing a real, distinctly-toggleable `Status` sheet: `Show All` / `Working` / `Completed` / `Failed` / `Archived` / `Unread`, all green (`On`). Sheets open and render correctly. |
| 16 | Thread-list metadata rows | **PASS** | Same list screenshot (`LD2-16`/`17`, 12:03): the dispatched thread row shows `✓ Completed · 4 mins ago · target-repo` (status + relative time + repo), and a live desktop session row shows `Connected · 4 mins ago · target-repo` — both relative-time and status/connection metadata render correctly per row. |

## Surprises worth flagging up

- **The most valuable finding this session wasn't a candidate feature at all**: the exact
  `LANCER_RELAY_PAIR_CODE` + onboarding-gating interaction (root-cause section above) — worth
  correcting in the next sweep brief's launch recipe so future lanes don't have to re-derive it
  from `AppRoot.swift`/`DebugSeeder.swift`.
- #10 and #14's failures look like **the same underlying gap**, not two independent bugs: neither
  the pill nor a discrete tool-call chip ever appeared for this turn, and both draw from the same
  `ToolChipItem` transcript-derived source. Worth a follow-up session that confirms whether *any*
  Bash/tool turn against this daemon build renders a chip at all (possible the daemon's
  event stream for this adapter/version doesn't emit the `tool_call` shape the assembler expects).
- The approval-security-hardening risk-tier gate (`Command`/`High`) is easy to miss when scripting
  dispatch flows — it silently wedges a turn at "Still working…" indefinitely with no error, no
  Retry button, which looks identical to a hung/broken turn from the outside. Any future automated
  dispatch test must budget for tapping `Approve`.
- Confirmed the merged approval-race fix (`4e45dbaa`) is live and doing real work: watched the
  daemon actually re-deliver a pending approval after a re-pair (`re-sending 1 pending approval(s)
  after (re)pair`).

## Simurgh feedback

- **1 real friction point**: default 30-minute lease TTL is tight when a UI-test run includes a
  failure path — `xcodebuild test-without-building` hit Apple's own 600s diagnostic-collection
  timeout after a test assertion failure, which alone consumed 1/3 of the lease TTL. Recommend
  either a longer default TTL for UI-test workflows specifically, or documenting "call `simurgh
  renew` before any `xcodebuild test-without-building` invocation" in the standard brief.
- Acquire/install/pair/release all otherwise behaved exactly as documented — fast, clean JSON, no
  errors on either lease.

Lease lease-193 released cleanly at end of session (see cleanup below). Isolated daemon
(`/tmp/lancerd-sweep`, `LANCER_STATE_DIR=/tmp/sweep-D2`) killed at end of session.
