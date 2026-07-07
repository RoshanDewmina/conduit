# Tier 0 device proof — follow-up (2026-07-06, evening)

Branch: `cursor/user-ready-tier0-9aec` (has `codex/tier-0-live-cursor-shell` merged — verified
`git merge-base --is-ancestor codex/tier-0-live-cursor-shell HEAD` → yes, so the P0 BiometricGate
fix `531685b6` and atomic emergency stop are already in this branch, not pending merge).

Device: Roshan's iPhone (`557A7877-F729-5031-9606-0E04F2B67822`, iPhone18,3, "available (paired)"
per `xcrun devicectl list devices`).
Simulator (regression check): iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`).

This follows up the morning run in
[`2026-07-06-tier-0-live-cursor-shell-proof.md`](2026-07-06-tier-0-live-cursor-shell-proof.md),
which left one concrete, non-owner-gated gap open: the device UITest asserted a hardcoded fixture
label that a physical device's real paired data would never match. That gap is closed below.

## What was fixed (engineering, not owner-gated)

**Root cause, not a fixture problem.** `AppRoot.swift:1032` seeds the live Cursor-shell workspace
list from real conversation data: `(conv.cwd as NSString).lastPathComponent`, falling back to the
literal string `"command-center"` only when there are **zero** conversations. On the simulator
(harness runs from this checkout, cwd `.../command-center`) that fallback/derived value happens to
read `"command-center"`. On the physical device, real paired conversations exist, so the fallback
never triggers and the derived name is whatever that conversation's `cwd` last path component is —
provably not `"command-center"`. The prior device UITest (`testLiveShell_UsesAppRootBridgeForWorkspaceAndSettings`)
hardcoded `app.staticTexts["command-center"]`, coupling the assertion to which machine's daemon
happened to be attached — never a real bug in the shell itself.

**Fix (2 files):**

1. `Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorWorkspacesView.swift` — added
   `.accessibilityIdentifier("workspace-row")` to each live per-repo row's `Button` (the `"All
   Repos"` and `"Add Repo"` rows are unchanged/unidentified so they aren't ambiguous with a real row).
2. `LancerUITests/CursorAppShellExhaustiveTests.swift` — replaced the hardcoded-label assertion
   with `app.buttons.matching(identifier: "workspace-row").firstMatch.waitForExistence(...)`, i.e.
   "at least one real workspace row rendered," which is true regardless of which repo the attached
   daemon reports.

## Verification (evidence)

| Gate | Command | Result |
|------|---------|--------|
| LancerKit unit build | `cd Packages/LancerKit && swift build` | PASS (no iOS-gated code exercised by this build — see next row) |
| App-target build (sim) | `xcodebuild build -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,id=095F8B3A…'` | **BUILD SUCCEEDED** (17.7s) — authoritative build for the `#if os(iOS)` `CursorWorkspacesView.swift` change |
| Fixed test (sim) | `xcodebuild test … -only-testing:LancerUITests/CursorAppShellExhaustiveTests/testLiveShell_UsesAppRootBridgeForWorkspaceAndSettings` | **PASS** (24.4s) |
| Full regression suite (sim) | `xcodebuild test … -only-testing:LancerUITests/CursorAppShellExhaustiveTests` | 18/22 passed in one run; 4 failed with `Simulator device failed to launch` — reran those 4 in isolation → **4/4 PASS** (contention artifact from a concurrent 484s device build, not a regression) |
| App-target build (physical device) | `xcodebuild build -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS,id=557A7877-F729-5031-9606-0E04F2B67822'` | **BUILD SUCCEEDED** (484.7s), signed `Apple Development: dewminaimalsha2003@gmail.com (2X93YVJ4G4)`, profile "iOS Team Provisioning Profile: dev.lancer.mobile" |
| **Fixed test (physical device)** | `xcodebuild test -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS,id=557A7877…' -only-testing:LancerUITests/CursorAppShellExhaustiveTests/testLiveShell_UsesAppRootBridgeForWorkspaceAndSettings` | **PASS** (22.3s) — the exact test that failed in the morning run now passes against the real device's real paired state |

Screenshots (pulled from the device xcresult via `xcrun xcresulttool export attachments`):
`docs/test-runs/2026-07-06-tier0-device-proof/03-live-shell-workspaces.png`,
`docs/test-runs/2026-07-06-tier0-device-proof/03-live-shell-real-settings.png`.

The workspaces screenshot shows a real workspace row labeled `roshansilva` (4 threads) — this is
the `lastPathComponent` of a real conversation's `cwd` from an earlier relay-E2E dispatch (cwd was
the home directory in that test dispatch, not a repo path), **not a bug**: it confirms the row is
driven by real data, which is exactly what the fixed assertion now tolerates. The Settings
screenshot shows `Trusted machines, 1` — a real persisted pairing, also not simulator fixture data.

## Incidental finding: resident daemon state

While investigating, found the owner's Mac already has a **launchd-resident** `lancerd` running
(`dev.lancer.lancerd`, pid 89605, `RunAtLoad`+`KeepAlive`, `APPROVAL_RELAY_SECRET` set correctly)
connected to the production relay (`conduit-push-y4wpy6zeva-ts.a.run.app`) under E2E test code
`194990`. Its log shows an hourly `receive error: EOF` → immediate reconnect cycle (looks like a
server-side idle timeout, benign) and, notably:

```
2026/07/06 19:50:25 e2e: paired with phone (code: 194990)
```

— a live pairing event that landed **during** the physical-device test run above (test ran
19:48:59–19:50:39). The `"Can't reach your machine"` banner visible in the workspaces screenshot
was captured a few seconds *before* that reconnect completed (screenshot timestamp 19:49:xx vs.
pairing-complete log at 19:50:25) — an accurate live-reachability reading, not a bug, but it means
the daemon-to-relay link is not rock-solid-stable long-term (hourly reconnects). Not investigated
further here — out of scope for this pass, flagging for whoever next touches relay keepalive.

## What remains owner-gated (unchanged from the morning run)

The full **pair → dispatch → approval → continue** loop with a human in it is still not something
this session can complete standalone, for two structural reasons, both already correctly called out
as owner-gated in the task brief:

1. **BiometricGate's Face ID prompt cannot be satisfied by automation on a physical device.** The
   simulator can fake biometric enrollment (`XCUIDevice` face-match simulation); real hardware
   cannot be driven that way from a script. Approving a gated action on the real device requires
   the owner's actual face/passcode.
2. **APNs lock-screen approval requires the app backgrounded/killed while a push arrives** — this
   is inherently an interactive, owner-present scenario (background the app, trigger an approval
   from elsewhere, glance at the lock screen, tap Approve on the banner).

**What is proven, mechanically:** `relay-approval-e2e.sh` (see the morning proof doc) already
exercises pair → dispatch → approval → continue end-to-end through the exact same live Cursor-shell
code path, via a synthetic XCUITest tap standing in for the human tap — 2/2 PASS. Combined with
today's fix, the only structurally-untestable-by-automation pieces are the two owner-only items
above, not the underlying plumbing.

**Ready-to-run owner checklist** (lancerd is already running and the phone is already paired, so
this should take under 5 minutes once the owner is at the keyboard/phone):

1. Confirm `dev.lancer.lancerd` is still running: `launchctl print gui/$(id -u)/dev.lancer.lancerd | grep state`.
2. On the phone: open Lancer, confirm the connection banner reads "connected" (not the
   "Can't reach your machine" state seen transiently above — if it persists, `launchctl kickstart -k
   gui/$(id -u)/dev.lancer.lancerd`).
3. Send a real prompt from the composer that will trigger a gated action.
4. When the approval card/banner appears, **approve using Face ID** — this is the step no script
   can perform. Confirm the action completes and a follow-up/continue in the same thread resumes
   the same session (not a new one).
5. Background or force-quit the app, trigger a second gated action from the Mac side, confirm the
   push arrives and Approve-from-notification works while locked. Screen-record this step per
   `docs/LIVE_LOOP_RUNBOOK.md` Phase 5c.
6. Record pass/fail + screen recording path back into this file or a sibling `docs/test-runs/` entry.

## sessionId parity (push / APNs)

The task brief asked to check "KNOWN_ISSUES MAJOR-8" for sessionId parity — that ID does not exist
in the current `docs/KNOWN_ISSUES.md` (restructured in the 2026-07-06 doc purge; see
`docs/STATUS_LEDGER.md`'s "Doc purge" note). The live reference for this exact concern is
`docs/LIVE_LOOP_RUNBOOK.md`'s triage table, row **E**: *"No push on device — APNs env not set /
token not registered / sessionId mismatch — backend token map keyed by the same sessionId."* Not
independently re-verified this pass (APNs step above is still owner-gated); flagging so whoever
runs step 5 above checks that row if push fails to arrive.

## Do-not-do items honored

- Did not touch or attempt to merge `.claude/worktrees/amazing-mayer-246fef` (STATUS_LEDGER already
  flags it deletion-heavy, cherry-pick only).
- Did not mark APNs green — explicitly left owner-gated above.
- BiometricGate / TOFU: not bypassed; the physical-device test only exercised the workspace/settings
  navigation path, not an approval decision, so the biometric gate was never in the code path this
  pass touched.
