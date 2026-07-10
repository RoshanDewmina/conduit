# Frontend rebuild — Sim dogfood Status

**Updated:** 2026-07-10T16:01:00-04:00
**Plan:** `docs/plans/2026-07-10-frontend-rebuild-sim-dogfood-Plan.md`
**Results:** `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md`
**Branch / worktree:** `feat/frontend-rebuild-m1` @ `60b4feb0` (tip re-checked at S0 start; still that commit — see "Uncommitted changes" below) in `.worktrees/frontend-scorched-wipe`

## Done

- M1–M4 code complete on branch (visual shell + pairing + live send/poll + in-thread approval)
- **S0–S6 of the sim-dogfood Plan all executed and PASSED — D0 through D8 all PASS on Simulator alone.**
  Pair → send → reply → in-thread Approve/Deny → Remove all proven end-to-end against the real
  resident `lancerd` + relay, with screenshot + audit-log evidence. No owner phone time was needed.
- Full writeup: `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md`

## Uncommitted changes (this worktree, not yet committed)

Two real fixes were required mid-run (Simulator HID taps are fully dead in this session — confirmed
via a control test, not just "unreliable" — and a genuine `ShellLiveBridge` reconnect race that
would affect real users too, not just this test). Six files touched, all `#if DEBUG`-gated except
the race fix itself:

- `AppFeature/Bridge/ShellLiveBridge.swift` — **real bug fix**, not DEBUG-gated: bounded wait for
  hydration + reconnect before declaring "no connected machine"
- `AppFeature/AppRoot.swift` — hydration-complete signal + DEBUG auto-pair wiring
- `AppFeature/DebugSeeder.swift` — new `autoPairRelayIfRequested` (`LANCER_RELAY_PAIR_CODE`)
- `AppFeature/Chat/LiveThreadView.swift` — new debug approve/deny hook (`LANCER_DEBUG_APPROVAL_DECISION`)
- `AppFeature/Workspaces/WorkspacesView.swift` — `LANCER_LIVETHREAD_PROMPT` override
- `AppFeature/Settings/TrustedMachinesView.swift` — new debug remove hook (`LANCER_DEBUG_REMOVE_CONNECTED_MACHINE`)

Full rationale + verification per file in the results doc. **Not committed or pushed** — owner should
review before merging, especially the `ShellLiveBridge` fix (real behavior change) vs. the five
DEBUG-only test seams (no effect on Release builds).

## Remaining

- Owner review + commit decision on the 6 modified files above
- Owner physical-device checklist (below) — only items Simulator genuinely could not prove
- Optional cosmetic cleanup: 2 stale "Relay host" dead pairings in Trusted Machines (pre-existing,
  not caused by this session)

## Owner physical-device checklist (≤5 items, from the results doc)

1. APNs while the app is closed/backgrounded (Simulator cannot receive production push at all)
2. One real finger-tap pass through Pair → Approve/Deny (logic proven via debug hooks; UI wiring itself not tap-tested this session, since Simulator HID was dead)
3. Dynamic Island / Live Activity for the relay-dispatch approval card (out of scope for M2–M4, needs real device)
4. Clear the 2 pre-existing stale dead pairings (cosmetic, not urgent)
5. Code review the 6 modified files before merging

## Commands run

See `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md` → "Commands run" for the full list (XcodeBuildMCP calls, `lancerd pair`/`doctor`, `go build && go test`, audit-log checks).

## Blockers

- None. S0–S6 all completed without needing to stop for owner input.

## Next agent instruction

Dogfood track is done. If picking this back up: read the results doc first, then decide whether to
commit the 6 modified files (review `ShellLiveBridge.swift`'s change carefully — it's a real bug fix,
not a test seam) before any merge. Do not merge without owner sign-off.
