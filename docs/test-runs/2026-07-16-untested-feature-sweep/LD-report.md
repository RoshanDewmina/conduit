# Lane D report — Chat pills, transcript cards, thread list (2026-07-16)

Candidates: #10, #11, #14, #18, #15, #16, #22. Simurgh lease-184 (`iPhone 17 Pro`,
udid `C7E83AA9-5959-47E9-A929-1DAC20F41B24`). Daemon `LANCER_STATE_DIR=/tmp/sweep-D`
(isolated; `daemon.log` never mentions `/Users/roshansilva/.lancer` — confirmed clean).
Target repo `/tmp/sweep-D/target-repo` (git init + committed `greeting.txt`, `README.md`,
`src/main.py`).

## Root-cause blockers hit (apply to every candidate below)

1. **Total HID tap failure, confirmed with exact a11y-tree coordinates** (not a coordinate
   estimation error — re-verified with `mcp__ios-simulator__ui_describe_all` frames in device
   points, e.g. "Add Repo" button `{0,304}-{402,354}` tapped dead-center at `(201,329)`, "Retry"
   button `{20,296.7}-{55.7,313.7}` tapped at `(38,305)`). `ui_tap` reports `"Tapped
   successfully"` every time; the app never changes state. 6 independent tap attempts across
   3 different screens (onboarding Continue, avatar/Profile, Add Repo, Retry), 2 coordinate
   systems (pixels and points), 2 durations (default, 0.3s/0.5s long-press) — zero effect. This
   matches Lane A's HARD LESSON verbatim. `snapshot_ui`/`tap` (XcodeBuildMCP) were not usable as
   an alternate injection path because that tool has no `simulatorId` param — it targets
   whatever the global session default is, which errored with a UDID belonging to a different
   concurrent lane (`BF6E4883-...` not found in my device set), confirming HARD LESSON 2 as well.
2. **Relay auto-pair never completed**, 4 independent attempts (2 daemon restarts, 3 fresh
   pairing codes generated immediately before launch). `daemon.log` never printed a "paired with
   phone" line; `relay-pairing.json` only ever holds the daemon's own generated code fields
   (`relayURL`/`code`/`privateKey`/`publicKey`), never a paired-peer indicator. The composer
   consistently shows **"Couldn't get a reply — No connected machine. Pair one in Settings →
   Trusted Machines."** This blocks every candidate that needs a live dispatched turn (#10, #11,
   #14, #18) and leaves #15/#16 with an empty thread list (no data to filter/sort).
3. **Self-inflicted but worth flagging as a tooling gotcha**: my first 3 launches used
   `xcrun simctl launch <device> <bundle> SIMCTL_CHILD_X=value` — placing the env assignment
   *after* the command instead of before it. `simctl launch --help` confirms env vars must be
   set in the **calling shell environment** (i.e. before the command), not passed as trailing
   argv. This silently no-ops (the string becomes an inert extra argv token to the app) and cost
   ~15 minutes before being caught by comparing `strings` output of `Lancer.debug.dylib`
   (proved the DEBUG env-check code is compiled in) against actual behavior. Once fixed
   (`SIMCTL_CHILD_LANCER_DESTINATION=... xcrun simctl launch ...`), `LANCER_DESTINATION` deep
   links worked immediately and reliably (onboarding skip, `prDetail`, `threadList` all
   confirmed navigating correctly). Documenting this because the COMMON brief's own example
   command has the same ordering used correctly, but it's easy to break by appending env after
   copy/pasting — flagging for the next lane.

## Verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 10 | Background-tasks pill + sheet | **BLOCKED** | Dispatch requires a paired machine (root-cause #2); prompt never left "Couldn't get a reply" state. `LD-12/13/14-*.png`. |
| 11 | Mid-run feedback queue | **BLOCKED** | Same — no active turn ever started. Composer/follow-up field enabled and present in a11y tree (`LD` a11y dump: `AXTextField` "Follow up…" `enabled:true`) but never exercised mid-run. |
| 18 | Turn activity summary + Todo checklist | **BLOCKED** | Same root cause; no TodoWrite/tool_call turn ever ran. |
| 14 | Tool-call label dedup (wp2) | **BLOCKED** | No thread transcript with tool chips reachable (no pairing); no observed desktop session reachable in this isolated env either — both sub-checks honestly BLOCKED, not silently skipped. |
| 15 | Thread-list filters + customize | **BLOCKED** | `LANCER_DESTINATION=threadList` deep-link **does** navigate correctly (`LD-17-threadlist.png`: "All Repos" header, search + customize-hamburger icons both render) but the list is empty (no paired machine → no threads), so filter/customize sheets have nothing to re-filter even if tap worked. Compounded by root-cause #1 (can't tap the hamburger icon to open the sheet at all). |
| 16 | Thread-list metadata rows | **BLOCKED** | Same — zero rows exist to inspect for relative-time/diff-stat/unread metadata. |
| 22 | PRDetailView | **PASS (honest-empty)** | `LANCER_DESTINATION=prDetail` deep-link navigates cleanly to a real `PRDetailView`: header "Pull request", back chevron, body **"Not available yet — PR status and diffs will show here when ship actions are wired to a real pull request."** This matches `CANDIDATES.md`'s own note ("PR actions disabled without daemon RPC") — the view is reachable and honestly renders its unwired state rather than faking data or crashing. `LD-16-prdetail.png`. |

## Surprises worth flagging up

- **Root-cause #1 (dead HID) is reproducible independent of coordinate-estimation error** — this
  session eliminated that variable by reading exact button frames from `ui_describe_all` (device
  points, e.g. iPhone 17 Pro logical size confirmed `402×874`) and tapping dead-center. Still zero
  effect. This looks like a real idb/HID-injection break on this specific sim runtime (iOS 27
  clone), not an agent methodology problem — worth an infra ticket independent of any Lancer app
  bug.
- **Relay auto-pair failure is new** (not previously called out in the COMMON brief's proven
  workarounds) and blocked 6 of 7 candidates outright. Worth a dedicated repro session with more
  daemon-side logging (the log format here only ever prints "connected to relay as daemon", never
  a peer-pair event either way — so it's not even clear from the log whether the phone's pairing
  request reached the relay at all).
- `LANCER_DESTINATION` deep-links themselves work great once env-var ordering is correct, and are
  a good complementary verification path to taps for view-reachability questions (as used for #22
  and the thread-list nav confirmation on #15/#16) even when interaction is impossible.

## Simurgh feedback

- **1 friction point**: `simurgh acquire`/`renew`/`release` all behaved exactly as documented,
  fast, clean JSON, no errors. No complaints — acquire→renew→release round-tripped without issue.
  (Counting this as 0 real friction items; the CLI itself was flawless in this session.)

Lease lease-184 released cleanly (`state=released`) at end of session.
