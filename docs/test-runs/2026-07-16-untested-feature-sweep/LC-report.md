# Lane C — Review stack, receipts, repo honesty (candidates 7, 8, 9, 17, 19, 23)

Date: 2026-07-16. Sim: Simurgh lease-182, `iPhone 17 Pro`, udid `C04F25A4-3103-46AE-BF66-AEEF967F2528`
(released at end). Daemon: isolated `/tmp/sweep-C` (`/tmp/lancerd-sweep`, restarted 3x during the
session — see below). App: `/tmp/dd-untested-sweep/Build/Products/Debug-iphonesimulator/Lancer.app`
for manual launches; a locally rebuilt (`build-for-testing`) copy of the **same tip** for the XCUITest
runs (see "Why a rebuild" below — no source was modified, only a new UI test file was added).

## HID taps were dead here too — switched to XCUITest (per HARD LESSON #3)

`mcp__ios-simulator__ui_tap` against "Add Repo" (2 taps, different durations) produced a
byte-identical `ui_describe_all` tree both times — confirmed dead, same as Lane A/D. Also confirmed
`mcp__XcodeBuildMCP__snapshot_ui` cannot be used at all without touching global session defaults
(errored "Simulator ... not found in set" against a stale UDID from another lane — proof HARD LESSON
#2 is real and load-bearing, not hypothetical).

**Fallback used:** wrote `LancerUITests/SweepLaneCTests.swift`, a single XCUITest driving Add Repo →
composer → send → Review/Receipt/FlightRecorder, built via `xcodebuild build-for-testing` with
`-derivedDataPath`/`-destination` pinned to lease-182's udid (never touching XcodeBuildMCP's global
session), and run via `xcodebuild test-without-building -only-testing:LancerUITests/SweepLaneCTests`.
XCUITest event injection worked perfectly — every tap landed and every UI transition was real. This
is the same lesson Lane A already documented; recording it again because it's the correct fallback,
not a workaround to avoid.

**Gotcha for next lane:** a new test file is invisible to `xcodebuild` until `xcodegen generate` is
rerun (`project.yml` uses a folder-glob target, but the checked-in `.xcodeproj` is generated, not
live-synced) — first build+run silently executed 0 tests (`Executed 0 tests`) until I ran
`xcodegen generate` and rebuilt. Second gotcha: `-only-testing:` must be passed to **both**
`build-for-testing` and the later `test-without-building` invocation, or the latter silently runs
every test class in the target (burned one ~13 min pass through the whole `LancerUITests` suite,
relaunching the app dozens of times, before I caught it and killed it).

## Setup

- `git init` target repo at `/tmp/sweep-C/target-repo` (greeting.txt, readme.md, notes.txt — 3 files, 1 commit).
- Isolated daemon at `/tmp/sweep-C` (`LANCER_STATE_DIR` always inline with the daemon invocation, per
  HARD LESSON #1 — verified `grep -c "/Users/roshansilva/.lancer"` = 0 on every daemon log).
- **DEBUG auto-approve seam:** searched (`rg -ni "auto.?approve"`) and found none in
  `AppFeature/` — this app build has no client-side auto-approve toggle at all (only daemon-side
  `AutonomySettings`/policy). Nothing to disable.
- **`SIMCTL_CHILD_` env-var gotcha (worth flagging loudly):** `xcrun simctl launch <udid> <bundle>
  KEY=VALUE` treats `KEY=VALUE` tokens as **launch arguments (argv)**, not environment variables —
  they must be exported as real shell env vars *in front of* the `simctl launch` command
  (`SIMCTL_CHILD_FOO=bar xcrun simctl launch ...`). My first 3 manual-pair attempts silently no-op'd
  on this (auto-pair never fired, onboarding never skipped) before I caught it via `ProcessInfo`
  tracing in `AppRoot.swift` — cost ~8 minutes and 2 wasted pairing codes.

## Candidate verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 19 | Repo display-name vs dispatch cwd | **PASS (partial, real code path traced + live UI)** | `AddRepoView.swift:83` passes `(previewName, normalizedPath)` — name and cwd are already separate params at the call site, threaded through `WorkspacesView.swift:186` → `workspaceData.addRepo(name:cwd:)` unchanged. Added a repo with path `/tmp/sweep-C/target-repo` and a **different, shorter** display name `sc-repo`. Live UI confirms the split is real: Workspaces list row shows `sc-repo` (`screenshots/LC-02-workspaces-repo-added.png`), composer repo chip shows `sc-repo` (`screenshots/LC-03-composer-filled.png`), but the **LiveThreadView header subtitle shows `target-repo`** (the cwd's basename, not the display name) — `screenshots/LC-04-thread-after-run.png`. That subtitle is a separate label choice, not the dispatch cwd; I could not get a real daemon receipt of the actual transmitted `cwd` string because every dispatch in this lane was blocked before completion (see below) — `daemon/lancerd` never got far enough to report a tool-call cwd. **What I can state as fact:** the app-side plumbing does not reuse the display name as the cwd anywhere in the code path I traced; the suspected dogfood bug (row 19) does not reproduce in the current source. What I cannot state as fact: the exact byte-for-byte cwd the daemon received for a completed run (blocked, see below). |
| 7 | Review pill → ReviewSheetView (real diffs) | **BLOCKED** | `LiveThreadView.swift:67` `reviewDataSource` already uses `RelayReviewDataSource(bridge:)`, not `FixtureReviewDataSource` — the G11 "fixture" finding from 2026-07-13 is fixed in this tip's source. But no turn ever reached a completed state (see below), so `session-diff-pill` never appeared to prove it live end-to-end. `screenshots/LC-06-review-sheet.png` shows the app state at the point the test gave up waiting (thread still blocked). |
| 8 | FileViewerView | **BLOCKED** | Same root cause — no real diff ever existed to open a file from. |
| 9 | AddCommentSheet | **BLOCKED** | Same root cause. |
| 17 | Receipt `filesTouched` honesty | **BLOCKED** | Traced the code precisely: `ReceiptCardView.swift:134` `filesLine` computes `receipt.filesTouched?.count ?? 0` → `"0 touched (observed)"` when nil/empty. This is a straight passthrough of whatever the daemon populates in the receipt JSON — **no iOS-side bug in the render**, so if "0 touched" recurs on a *completed* multi-file run, the fix belongs entirely on the daemon side (receipt construction), not iOS. Could not observe a real receipt because no turn completed. |
| 23 | Flight Recorder timeline | **BLOCKED** | Same root cause — `FlightRecorderTurnListView`/`FlightRecorderView` are reachable code (confirmed present, `ThreadDetailView.swift:606-614`), but there was no completed turn's tool-call timeline to open. |

## Why every dispatch blocked — precise root cause (not the HID-tap excuse; this is a real app/relay finding)

This is the most important result of this lane, and it directly answers the orchestrator's specific
ask ("record whether first send succeeds without Retry — your setup pairing doubles as the 30s
pairing-timeout fix's live test").

1. **The 30s pairing-timeout fix itself is present and works.** `ShellLiveBridge.swift:1067`
   `waitForConnectedMachine(timeout: TimeInterval = 30)` — confirmed in source. Pairing itself
   completed cleanly every time I tried it fresh (no prior churn): auto-pair (`LANCER_RELAY_PAIR_CODE`
   seam) took ~20–39s end-to-end from app launch to `e2e: paired with phone` in the daemon log,
   comfortably inside the 30s budget on the **connection** side.
2. **But the first send after pairing still failed, twice, reproducibly**, with the in-app terminal
   error state "Couldn't get a reply / Awaiting your approval — check the Inbox. / Retry"
   (`LiveThreadView.swift:985` `errorState`) — screenshots `LC-04-thread-after-run.png` (first
   attempt, immediately after the earlier full-suite-run churn) and `screen-retry-mid.png` (second
   attempt, from a **freshly restarted daemon + freshly paired app with zero prior churn** — this
   rules out the "stale relay generation from repeated test launches" confound I initially suspected).
3. **This is NOT the pairing/connection race** (candidate #20) and NOT a policy misconfiguration.
   `/tmp/sweep-C/home/.lancer/audit.log` shows both attempts hit the daemon fine and were correctly
   evaluated: `"action":"conversation-append-needs-approval","rule":"ask-medium","effect":"ask"`.
   Traced `daemon/lancerd/dispatch.go:844` — `ask-medium` is an **explicit named rule**
   (`policy/types.go:132`), and `relaxLaunchEscalation` only relaxes the *default*-ask case for a
   hook-wired agent (confirmed `/tmp/sweep-C/home/.claude/settings.json` correctly registers the
   `lancer-hook.sh` PreToolUse hook — hook-wiring is not the problem either). A prompt that mentions
   Bash/git is *correctly* asking for approval by design — that part is fail-closed-by-design, not a bug.
4. **The actual bug: no live decision path was ever presented for that approval.** Compare with
   **Lane B**, whose report (`LB-report.md` §"#20") shows the *identical* `needsApproval`/ask-medium
   escalation for their dispatch, but rendered as a **live in-thread Approve/Deny card**
   (`cursor.approval.approve` visible and tappable, 3 approvals decided, real git commit landed) —
   because their first send happened well after a long idle/debugging gap post-pairing. My sends
   happened **immediately** (within 0–1s of `e2e: paired with phone`) both times, and in both cases
   the daemon's `sendApproval` path (`e2e_router.go:83`) never fired at all — `grep -i "sent approval"`
   across every daemon log from this lane returns **zero matches**, vs. Lane B's daemon log showing
   `sent approval <uuid> over relay` three times. `LANCER_DESTINATION=inbox` (a documented DEBUG
   deep-link value) lands on the plain Workspaces root, not a distinct pending-approvals list —
   so "check the Inbox" in the error copy has **no reachable destination** in this build; the
   fleet-wide pending-approvals banner (candidate #4, Lane A/B territory) is the only other surface
   and it never appeared either.
   **Conclusion: a `conversation-append` that needs approval sent very soon after pairing completes
   races the daemon→relay approval-delivery path; the phone gets the synchronous "needsApproval"
   HTTP-shaped response (which renders as a terminal, non-recoverable error) but never receives the
   separate async `ApprovalEvent` that would render a decidable card. Retry re-sends the same append
   and hits the same race again — this can loop forever with no way out except waiting an unknown
   amount of time before the very first send (which contradicts the whole point of testing "first
   send succeeds without Retry").** Suspected locus: `daemon/lancerd/e2e_router.go` `sendApproval`
   vs. whatever emits the synchronous `needsApproval` conversation-append response — they appear to
   be two independent code paths that aren't ordered/synchronized against relay-session readiness.

## Files

- New test (kept, mirrors existing lane precedent like `TapInjectionProofTests.swift`):
  `LancerUITests/SweepLaneCTests.swift`
- Screenshots: `docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/LC-01-add-repo-filled.png`,
  `LC-02-workspaces-repo-added.png`, `LC-03-composer-filled.png`, `LC-04-thread-after-run.png`,
  `LC-06-review-sheet.png`, `LC-09-comment-in-composer.png`
- Raw evidence: `/tmp/sweep-C/home/.lancer/audit.log` (both `needsApproval` escalations),
  `/tmp/sweep-C/daemon{2,3,4}.log` (three clean daemon restarts, each isolation-verified)
- This report: `docs/test-runs/2026-07-16-untested-feature-sweep/LC-report.md`

## Top surprises

1. XCUITest event injection works perfectly on this sim (idb/`ui_tap` doesn't) — every one of my
   ~15 taps/types landed on the first try once I switched. This should be the default strategy for
   future lanes, not the fallback.
2. The "0 touched (observed)" receipt-honesty bug (candidate #17) is provably an iOS **passthrough**
   of the daemon's `filesTouched` field, not a rendering bug — worth telling whoever owns the daemon
   side directly rather than re-investigating the iOS code again.
3. The genuinely new finding: **first-send-after-pairing has a real, reproduced-2x race between the
   synchronous needsApproval response and the async approval-card delivery**, distinct from and not
   fixed by the 30s connection-timeout change. Lane B's PASS on candidate #20 is real but only
   because their send happened well after pairing settled — a true "pair then send immediately"
   workflow (exactly what a first-time user does) still breaks.
4. `LANCER_DESTINATION=inbox` is a documented value but has no distinct destination behind it —
   dead/no-op deep-link.

## Simurgh feedback (1 item)

- No friction with the CLI itself — `acquire --json`/`renew --ttl`/`release` all worked exactly as
  documented, and the 30-minute TTL was fine as long as I renewed proactively before each long
  XCUITest run (each full test pass took 2.5–5 minutes; renewed 6 times total across the session
  with zero expiry incidents). The one thing that cost real time was unrelated to Simurgh: XcodeGen
  project regeneration + first cold `build-for-testing` (~80s) before the lease's derived-data cache
  warmed up.
