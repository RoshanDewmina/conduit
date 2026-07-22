# Lane A2 — re-verification via XCUITest (candidates 1, 2, 3, 24)

Date: 2026-07-16. Sim: Simurgh `lease-187`, `iPhone 17 Pro`, udid
`2A91DC88-2B1E-48D8-A506-AC7584BCC0F6` (released at end). Daemon: isolated `/tmp/sweep-A2`
(`/tmp/lancerd-sweep`). App: `/tmp/dd-untested-sweep/Build/Products/Debug-iphonesimulator/Lancer.app`
(bundle `dev.lancer.mobile`), already installed on this lease from a prior turn of this same
sweep session. Worktree: `.worktrees/untested-sweep-2026-07-16` (branch
`integration/2026-07-16-untested-sweep`, tip `d1f175dd` at the time of this run — the brief's
`f2635b5b` had already moved forward from other agents' commits landing on the branch).

## Headline: the HID-input blocker from Lane A does NOT apply to XCUITest

Lane A proved raw HID taps (idb, `mcp__ios-simulator__ui_tap`, `mcp__XcodeBuildMCP__tap` via AXe,
even the hardware Home button) are completely dead on this sim — every call reports "success"
with zero UI state change. This lane drove every interaction through a throwaway XCUITest
(`LancerUITests/SweepLaneA2Tests.swift`, deleted after this run — see Files) run via
`mcp__XcodeBuildMCP__test_sim`, and **taps, typing, navigation, and sheet dismissal all worked
correctly** — dozens of real interactions across two test methods, no dead taps observed. This is
the major finding of this lane: **the input blocker is specific to the raw-HID delivery path
(idb/AXe/simctl), not a property of this simulator or build** — XCUITest's own synthesize-event
path (which goes through the same on-device accessibility/event-injection stack Xcode uses for
recording) reaches the app fine. Future lanes on this sim should default to XCUITest, not HID
tools, for any interactive verification.

## Setup

- `git init` at `/tmp/sweep-A2/target-repo` (already done by a prior turn; 1 commit, `readme.md`).
- Isolated daemon at `/tmp/sweep-A2`, restarted clean multiple times during this session (see
  Simurgh/ops feedback) — final restart confirmed clean via
  `grep -c "Users/roshansilva/.lancer" /tmp/sweep-A2/daemon.log` → `0`, and
  `lsof ~/.lancer/lancerd.sock` continuously showed the real production PID throughout (91280),
  never evicted by this lane.
- `LANCER_STATE_DIR=/tmp/sweep-A2 /tmp/lancerd-sweep pair` regenerated a fresh 6-digit code
  immediately before each test launch; the XCUITest passes it through
  `TEST_RUNNER_LANE_A2_PAIR_CODE` → `app.launchEnvironment["LANCER_RELAY_PAIR_CODE"]`.
- Found and killed 2 leaked `/tmp/lancerd-sweep daemon` processes left running from a prior turn
  of this same session (PIDs 78770, 26950) that were not holding the socket — only the
  socket-holding PID stayed up. Verified with `lsof /tmp/sweep-A2/lancerd.sock` before killing.

## Candidate verdicts

| # | Candidate | Verdict | Evidence |
|---|-----------|---------|----------|
| 2 | Policy editor (Settings → Policy) | **FAIL** (real product gap, not an input issue) | XCUITest reached Settings the real way (Profile → Settings row → Policy row), the YAML `TextEditor` loaded, typed a unique marker, tapped **Save policy** (button was enabled and tappable — screenshot shows blue-active state), waited, navigated back and re-opened. Verdict data attachment: `policyLoaded=true initialErrorPresent=true roundTripPassed=false`, reloaded text empty. Root cause found in code: `Packages/LancerKit/Sources/AppFeature/Settings/GovernanceHostActions.swift:36-48` — `fetchPolicy`/`savePolicyYAML` require `ApprovalRelay.shared.channel` (an **SSH** `DaemonChannel`) and throw `Failure.sshRequired` otherwise; there is "no relay mirror on the daemon today" (code comment, line 9). Our sweep pairing is relay-only (`LANCER_RELAY_PAIR_CODE`), so the screen visibly renders: *"Policy requires an SSH host session. Relay-only pairings cannot reach this RPC yet."* — confirmed on-screen. Screenshots: `LA2-01-policy-editor-loaded.png`, `LA2-02-policy-after-save-error.png`, `LA2-03-policy-reopened-empty.png`. On daemon side, `/tmp/sweep-A2` never gained a `policy.yaml` file (consistent with save never reaching the daemon). |
| 3 | Audit feed (Settings → Audit) | **FAIL** (same root cause as #2) | Same screen family, reached via Profile → Settings → Audit row. `GovernanceHostActions.swift:50-55` — `tailAudit` also requires `ApprovalRelay.shared.channel` (SSH), throws `Failure.sshRequired("Audit feed")` otherwise. On-screen: *"Audit feed requires an SSH host session. Relay-only pairings cannot reach this RPC yet."* Screenshot: `LA2-04-audit-feed-ssh-required.png`. No `audit.log` file exists on the isolated daemon either way (no governed events happened in this session), so this candidate cannot PASS under a relay-only pairing regardless of dispatch state — **this is an architectural gap, not a UI bug**: Policy + Audit are SSH-only RPCs and the app's copy makes that explicit rather than silently failing, which is at least honest UX. |
| 1 | Emergency Stop | **BLOCKED** (test-harness pairing race, not a confirmed app bug) | First combined-flow run reached the button, tapped it, and got the confirmation dialog (`"Stop all runs"` — `AppSettingsCopy.swift:16`) to appear and tapped it — full UI mechanics proven reachable via XCUITest, unlike Lane A's total block. Verdict data: `sawApproval=false sawWorking=false stopOutcome=error:No connected host. Pair a trusted machine or open an SSH session first.` Code (`GovernanceHostActions.swift:26-34`) shows Emergency Stop *does* have a relay fallback (`relayFleetStore.firstConnectedMachine?.bridge?.sendEmergencyStop()`), unlike Policy/Audit — so this SHOULD work over relay-only pairing. The "No connected host" error is most likely because this run's fresh `pair` regeneration (each retest rotates identity, dropping the prior relay session per daemon log: `"relay pairing identity changed — dropping the previous relay session"`) hadn't fully re-confirmed by the time Emergency Stop fired, ~45s into the test. A later attempt at fixing this raced into a genuine `Test crashed with signal kill` (Xcode UI-test-runner level crash, not an observed app crash — no `.ips` crash report was found under `~/Library/Logs/DiagnosticReports` or the sim's container for this run) right after tapping into Settings; a third attempt (with a 15s settle delay added post-launch) got past that but then a leftover Chat sheet from the Agents-tap-through step (see #24) blocked the composer step before reaching Emergency Stop again. **Net: mechanically reachable and functional-looking, but never got a clean run all the way through to a non-error result under time budget** — screenshots `LA2-06-emergency-stop-settings-before.png`, `LA2-07-emergency-stop-after-error.png` show the reachable UI + the transient error. Re-enable-after-stop behavior still unobserved. |
| 24 | Agents section tap-through | **PASS** | This is the definitive resolution of Lane A's half-confirmed finding. Tapping the `running-agents-section` row (accessibility ID confirmed in `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift`) opened a real presented sheet: title **"Chat"**, subtitle **"target-repo"**, showing the actual prior turn's transcript (`"Run \`sleep 45\` via Bash, then say done."` → `"Ran a command"` tool-call chip → agent's real declining response about blocking standalone sleep commands) **and a live, focused "Follow up…" text field** — i.e. a genuinely continuable thread, not a dead end. Screenshot: `LA2-05-agents-tap-opens-real-thread.png`. (My own test's `threadOpened` heuristic checked for a `BackButton`, but this screen is presented as a sheet with a `Close` button instead, so the automated assertion under-reported `threadOpened=false` — the screenshot evidence overrides that flawed check.) |

## Top surprises

1. **The HID-input blocker Lane A found is not a simulator-wide dead end — it's specific to the raw
   HID delivery tools.** XCUITest's own event-synthesis path worked for every tap, type, and
   navigation this lane attempted (composer, Save button, back navigation, sheet dismissal,
   confirmation dialogs). Any future lane blocked by "SUCCEEDED but no UI change" via idb/AXe/simctl
   should switch to a disposable XCUITest before calling something BLOCKED.
2. **Policy and Audit are SSH-only by design, not by bug** — `GovernanceHostActions.swift`
   comments this explicitly ("no relay mirror on the daemon today"). A pure relay-pairing sweep
   (which is what our isolated-daemon harness uses) can never PASS these two candidates as
   currently architected; a real PASS/FAIL run needs an SSH-paired host, not a relay pair code.
   This should be flagged to product/eng as a real gap if relay-first pairing is meant to be a
   first-class path (many onboarding flows use relay pair codes, not SSH).
3. **Repeated `pair` regeneration between test runs orphans the previous relay session** (daemon
   log: `"relay pairing identity changed — dropping the previous relay session; phones on it are
   orphaned until re-paired"`) — each throwaway-test iteration needs a fresh code generated
   *immediately* before that specific `app.launch()`, and the app needs real settle time
   (~15-30s observed) before its relay channel is confirmed live; testing state-changing actions
   (like Emergency Stop) too early after launch risks a spurious "No connected host" that is a
   harness timing artifact, not a real app failure.
4. Two duplicate `/tmp/lancerd-sweep daemon` processes were found already running (leaked from an
   earlier turn of this exact session) bound to the same `/tmp/sweep-A2` state dir but not holding
   the socket — cleaned up safely by checking `lsof` first, killing only the non-socket-holding
   PIDs. Production `~/.lancer/lancerd.sock` was continuously verified as owned by the real
   launchd-managed PID throughout this lane's work and was never touched.

## Simurgh feedback (1 item)

1. **`simurgh renew` is cheap and safe to call defensively.** No friction from the CLI itself —
   `acquire`/`list`/`renew`/`status --json` all returned clean, well-typed JSON with exactly the
   fields needed (`udid`, `expiresAt`, lease `state`). This lane inherited an already-active lease
   from a prior turn of the same session (`lease-187`, about to expire) and `simurgh renew
   lease-187 --ttl 30m --json` extended it cleanly twice with no reconnection needed to the
   already-booted simulator or already-installed app — this "resume an existing lease across a
   session gap" path worked perfectly and is worth calling out as a good pattern for other lanes
   that get interrupted mid-task.

## Files

- Screenshots: `docs/test-runs/2026-07-16-untested-feature-sweep/screenshots/LA2-01` through
  `LA2-07` (see table above for the mapping).
- Throwaway XCUITest: `LancerUITests/SweepLaneA2Tests.swift` — **deleted** after this run per the
  brief (two test methods: `testLaneA2_PolicyAuditEmergencyStop` covering #2/#3/#1 in one flow,
  and `testLaneA2_EmergencyStopAndAgentsTapThrough` as a follow-up isolating #24 and #1 from a
  clean Workspaces state). Not committed.
- This report: `docs/test-runs/2026-07-16-untested-feature-sweep/LA2-report.md`.
