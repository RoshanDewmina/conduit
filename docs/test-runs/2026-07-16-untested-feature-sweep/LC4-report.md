# Lane C4 — Post-Wave-1 live re-test (#7 chain, #2/#3 relay, FX5, #10/#14)

Date: 2026-07-16. Tip: `integration/2026-07-16-untested-sweep` @ `b8bb778c` (Wave-1 merge
`7707e4fa` + docs sync). Simurgh `lease-197`, `iPhone 17 Pro`, udid
`64681957-3C48-4539-A58F-04CCE429D52A`. Isolated daemon `LANCER_STATE_DIR=/tmp/sweep-C4`,
binary `/tmp/lancerd-sweep-C4`. Pair code `483328` via `TEST_RUNNER_LANE_C4_PAIR_CODE`.
`HOME=/Users/roshansilva` (passwd home; Claude auth). Harness:
`scripts/sweep-lane-c4-run.sh` + `LancerUITests/SweepLaneC4Tests.swift`.

## Headline

**Lane C4 ran to completion (~15 min XCUITest) but live pairing never settled** — daemon log
stops at `e2e: connected to relay as daemon` with **zero** `paired with phone` / `sent approval`
lines; target-repo git log unchanged (`5246ad4 init` only). That blocked the entire #7 review
chain and pill rechecks. **Lane P relay mirror partially proven:** audit feed loads over relay;
policy shows the coarse mode picker (`policyRelayPicker=true`) but a stale SSH error string also
remains visible (hard XCTest fail). **FX5 PASS:** Connect button hittable with number pad open.

## Evidence summary (attachment `public.plain-text`)

```
policyRelayPicker=true auditLoaded=true auditSSHError=false
approveTaps=0 awaitingCard=false terminalRetry=true
diffPill=false proof=false bgPill=false bashCount=0 stop=tapped
```

## Candidate verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 5 | Connect above keypad (FX5) | **PASS** | `LC4-01-pairing-keypad.png` — Connect exists + `isHittable` with number pad up |
| 2 | Policy over relay (Lane P) | **PARTIAL** | Mode picker present (`policyRelayPicker=true`, `LC4-03-policy.png`) but SSH error copy also on screen → XCTest fail line 97 |
| 3 | Audit over relay (Lane P) | **PASS** | `auditLoaded=true`, `auditSSHError=false`, `LC4-04-audit.png` |
| 7 | Review pill → sheet | **FAIL** | `terminalRetry=true`, `awaitingCard=false`, `approveTaps=0`; `LC4-08-thread-stale-retry.png` shows "Couldn't get a reply / Retry" |
| 8 | FileViewerView | **BLOCKED** | No completed turn / no diff pill |
| 9 | AddCommentSheet | **BLOCKED** | Same |
| 17 | Receipt filesTouched | **BLOCKED** | `proof=false` |
| 23 | Flight Recorder | **BLOCKED** | No completed turn |
| 10 | Background-tasks pill | **FAIL** (reconfirm) | `bgPill=false` after completed-ish turn window; `LC4-12-pills.png` |
| 14 | Tool-call dedup | **FAIL** (no chips) | `bashCount=0` |
| 1 | Emergency Stop | **PARTIAL** | Button reachable + confirm tapped (`stop=tapped`); clean PASS not isolated from pairing race |
| 11 | Mid-run feedback | **BLOCKED** (harness) | No mid-run window — pairing/turn never advanced |
| 18 | Todo checklist | **BLOCKED** (harness) | Not reached cleanly |

## Root cause (load-bearing)

1. **Relay auto-pair did not complete in this harness run.** Daemon never logged
   `e2e: paired with phone` despite fresh `lancerd pair` → `483328` immediately before test.
   Without pairing, Policy may flash SSH-first error before relay fleet connects; dispatch never
   delivers approval cards (`approveTaps=0`).
2. **FX7 awaiting-approval path not observed live** (`awaitingCard=false`) — thread still hit
   terminal Retry error, same symptom class as LC3 pre-FX7 when pairing is absent or late.
3. **Policy UI nit:** `PolicyEditorView` can show relay mode picker while `errorMessage` from an
   SSH-first load attempt remains rendered — UX should clear SSH error when relay fallback succeeds.

## Simurgh / harness notes

- `simurgh exec lease-197 -- xcodebuild …` worked; caller `-derivedDataPath` merged cleanly.
- Cold `build-for-testing` ~25 min; test ~15 min. Lease `lease-197` released on harness exit.
- **Harness fix for retry:** single app session (don't terminate/relaunch 5×), longer post-launch
  pairing settle, assert daemon `paired with phone` before Settings/dispatch; remove FX5 manual
  `123456` typing (use auto-pair only).

## Files

- Test: `LancerUITests/SweepLaneC4Tests.swift`
- Harness: `scripts/sweep-lane-c4-run.sh`
- Screenshots: `screenshots/LC4-*.png`
- Raw: `/tmp/sweep-C4/daemon.log`, `/tmp/sweep-C4/test-run.log`, `/tmp/sweep-C4/C4.xcresult`

## Remaining checklist (exact)

1. Re-run C4 with **one** long-lived app session + daemon pairing gate (grep daemon log for
   `paired with phone` before proceeding).
2. If pairing green: re-grade #7/#8/#9/#17/#23 (FX7 awaiting card vs Retry).
3. Policy UI: clear stale SSH error when relay mode picker loads.
4. Owner re-pair on production phone (still owed from C3 incident).
