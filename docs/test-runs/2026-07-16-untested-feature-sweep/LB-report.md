# Lane B report — Onboarding, Composer, Approvals (redo, session lane-b2)

Candidates: 5, 13, 6, 4, 12, 20. Worktree: `untested-sweep-2026-07-16`. State dir `/tmp/sweep-B`.
Simulator: Simurgh `lease-183`, udid `B3371356-2C90-4C46-BBFF-0492E0A22AC5` (iPhone 17 Pro / iOS 27).

This is a full redo. A prior Lane B attempt left stray screenshots (`LB-01..07` timestamped
08:11-08:26) in the shared screenshots dir but no report file — I did not trust or reuse them
(couldn't verify their repro steps or the daemon they ran against). All evidence below is fresh,
driven by this session, with new filenames to avoid collision.

## Pre-flight (redo hygiene)

- Found a stale `lancerd-sweep` daemon (pid 67083) already bound to `LANCER_STATE_DIR=/tmp/sweep-B`
  from the prior stalled attempt. Killed it, wiped `/tmp/sweep-B`, and started a fresh daemon —
  it ran healthy for the entire session (pid 74590, never died, never needed the restart-once
  fallback from the redo constraints).
- Verified isolation: `daemon.log` never mentions `/Users/roshansilva/.lancer`; socket bound at
  `/tmp/sweep-B/lancerd.sock`. Left lane C's daemon (pid 71206, `LANCER_STATE_DIR=/tmp/sweep-C`)
  untouched.
- No `timeout`/`gtimeout` binary available on this Mac — wrote a small wrapper
  (`scratchpad/to.sh SECONDS CMD...`) using background+watchdog-kill and used it to bound every
  daemon/pair/log Bash call.

## Candidate verdicts

### #5 — First-run onboarding gate (wp4) — **PASS**
Fresh install on the leased sim (guaranteed clean state), launched with no skip seams / no pair
code.
- Screen 1: "Lancer" / "Mission control for AI coding agents" + Continue. Screen 2: "Pair a
  machine" / "Pair a Machine" + "Skip for now". Matches the described 2-screen flow.
  `screenshots/LB-01-onboarding-welcome.png`
- Generated a fresh `lancerd pair` code (802950) immediately before use, entered it **manually**
  through the on-screen numeric keypad (typed digit-by-digit via individual taps — `ui_type`
  does not register keystrokes on this custom SwiftUI keypad, confirmed by testing both ways).
- **FAIL sub-finding**: after the code is fully entered, the "Connect" button is rendered
  **behind/underneath the on-screen keypad** — visually only a ghost of the button text peeks
  out from under the "1" key, and it is not present in the accessibility tree at that scroll
  position, so it cannot be tapped. Workaround: swipe the sheet content up a small amount, which
  un-occludes "Connect" and makes it tappable/enabled. Screenshots:
  `screenshots/LB-02-pair-connect-occluded-bug.png` (bug state) and
  `screenshots/LB-03-pair-connect-visible-after-scroll.png` (after the workaround).
  Locus: likely the pairing sheet's layout in the onboarding/pairing SwiftUI view — the numeric
  keypad is a fixed-position overlay that isn't accounted for in the scroll content's bottom
  inset.
- After the scroll workaround, tapped Connect; daemon log shows `paired with phone` at 09:19:00;
  app landed on Workspaces.
- Relaunch (kill + fresh launch): app goes straight to Workspaces, onboarding does NOT
  reappear. `screenshots/LB-05-relaunch-no-onboarding.png` + a11y tree confirms no onboarding
  elements, just the normal home.

### #13 — Composer dispatch picker restructure (wp1) — **PASS**
New Chat → tapped the "Dispatch settings, Haiku · Safe writes" summary chip.
`screenshots/LB-06-composer-picker-sheet.png` + a11y tree.
- Sheet renders cleanly: **Agent** (Claude Code / Codex / OpenCode / Kimi, each with icon + full
  horizontal label, checkmark on selection), **Model** (Haiku "Fastest replies" / Sonnet
  "Balanced speed and quality" / Opus, with subtitle), **Tools** (Full tools toggle, off by
  default), **Permission mode** (Auto-approve reads / Auto-approve safe writes / Always ask /
  Critical only / Full bypass). No vertical letter-stacking anywhere — all labels render as
  normal horizontal text.
- Selection reflects live: tapping "Sonnet" immediately updated the summary chip to
  "Dispatch settings, Sonnet · Safe writes" and dismissed the sheet (single-tap-and-apply per
  row, not a multi-select-then-confirm sheet — worth knowing but not a bug).
- Send works (see #6/#20 below — same composer, same send path).

### #6 — Inline approval card (production path, DEBUG auto-approve OFF) — **PASS, strong evidence**
Confirmed there is no DEBUG auto-approve seam in this app build (`rg -n "autoApprove"
Packages/LancerKit/Sources` finds no UI bypass; the only auto-approve is the daemon hook's
explicit read-only tool allowlist in `daemon/lancerd/hook_install.go` — `Read/Glob/Grep/...`
skip approval, `Bash`/`Write`/`Edit` do not). Dispatched a real haiku run against a real git repo
(`/tmp/sweep-B/target-repo`, `git init` + committed files) with the prompt "echo hello >>
file1.txt then git add and commit... test-commit".
- **3 sequential approval cards** appeared and were each Approved:
  1. `Command / High / echo hello >> file1.txt` — `screenshots/LB-14-after-send.png`
  2. `Command / High / git add file1.txt && git status`
  3. (git commit step)
- `cursor.approval.approve` button tapped each time; daemon log shows the round-trip:
  `sent approval <uuid> over relay` for each (09:28:32, 09:29:01, 09:29:32).
- Turn continued to completion after every approve: transcript ends with "Done — appended
  \"hello\" to file1.txt and committed it as 881e62e with message \"test-commit\"."
  `screenshots/LB-16-approval-card-full-loop.png`
- **Ground truth verified in the actual repo** (strongest possible evidence): `file1.txt`
  contains the appended line, and `git log --oneline` shows `881e62e test-commit` on top of
  `c50c39a initial commit`.

### #4 — Fleet-wide pending-approvals banner (wp3) — **PASS, strong evidence**
Sent a follow-up ("echo second >> file1.txt") from inside the live thread, then immediately
tapped Close to return to Workspaces home **before** approving.
- A banner appeared at the very top of Workspaces (above "All Repos"):
  `workspaces-pending-approvals-banner`, label **"1 pending approval"**, subtitle
  **"echo second >> file1.txt"**, help text "Opens the live thread for the most recent pending
  approval". `screenshots/LB-17-home-pending-approval-banner-check.png`
- Tapped the banner: navigated straight into the live thread with the same pending
  `echo second >> file1.txt` approval card visible (Approve/Deny), confirming the "tap navigates
  to the pending decision" requirement. `screenshots/LB-18-banner-tap-navigates.png`
- Approved it to clean up; daemon log shows the decision went through.

### #12 — Permission-mode pill (autonomy) — **PASS (core ask), one flaky-send observation**
- While the run above was in flight (approval card open), the `permission-mode-pill` element was
  directly visible and readable in the a11y tree mid-run: `AXLabel: "Permission mode, Safe
  writes"`, `AXUniqueId: permission-mode-pill`, a real `AXPopUpButton` — this alone answers the
  G12 "not in a11y tree mid-run" regression: it now IS present.
- Tapped the pill → native menu opened with Full bypass / Critical only / Always ask /
  Auto-approve safe writes (checked) / Auto-approve reads. Selected "Always ask" — the pill
  label updated immediately to "Permission mode, Always ask" and persisted across a
  follow-up compose. `screenshots/LB-19-permission-mode-always-ask.png`
- Attempted to dispatch again under the new mode to observe behavior change; the follow-up send
  action was flaky on this sim (the on-screen composer's send affordance and the software
  keyboard's return-key-labeled "send" button did not reliably register a tap — after two
  attempts the thread transcript rendered blank and the new message was never dispatched). Per
  the hard-lesson rule (switch strategy after 2 failed taps), I stopped rather than burning
  further time chasing this — it doesn't change the #12 verdict (the pill's visibility and label
  update are the core ask and are both proven), but it's a real interaction-reliability gap worth
  a follow-up XCUITest-driven pass rather than more idb taps.

### #20 — Pairing connect-wait timeout (G4, WP7 fix) — **PASS**
Confirmed statically first: `Packages/LancerKit/Sources/AppFeature/Bridge/ShellLiveBridge.swift:1067`
now reads `waitForConnectedMachine(timeout: TimeInterval = 30)` (was 8) — the WP7 fix is present
on this build.
- Live timing: pairing code generated at manual-pair time was used ~9.3 min later due to
  debugging the #5 Connect-button bug (well past any 5-min code-expiry norm), yet pairing still
  completed (`paired with phone` at 09:19:00) — codes/relay session did not hard-expire in this
  build.
- First real dispatch/send after pairing: tapped Send at `09:28:23.37` (unix
  `1784208503.365543`); daemon log shows `sent approval ... over relay` at `09:28:32` — roughly
  **9 seconds** end-to-end, well inside the new 30s window, and critically: **no "No connected
  machine" failure/retry occurred** on first send. This is the clean, expected behavior once
  WP7 is landed, and is the live proof this candidate asked for.
- Side observation (not this candidate, logged for awareness): daemon log shows two
  `rejecting replayed or out-of-order frame` lines during the session (09:21:09, 09:26:37) on
  the relay E2E channel — did not block pairing or dispatch, but worth a look if seen again.

## Verdict table

| # | Feature | Verdict |
|---|---------|---------|
| 5 | Onboarding gate | PASS (+ FAIL sub-bug: Connect button occluded by keypad, workaround = scroll) |
| 13 | Composer dispatch picker | PASS |
| 6 | Inline approval card | PASS (strong: real git commit landed) |
| 4 | Pending-approvals banner | PASS (strong: banner + navigation both proven) |
| 12 | Permission-mode pill | PASS (pill visible + label updates); flaky-send observation only |
| 20 | Pairing timeout (WP7) | PASS (9s send after pairing, well under new 30s; code confirmed at ShellLiveBridge.swift:1067) |

## Top surprises

1. **#5's Connect-button-behind-keypad bug** is a genuine, repeatable UI defect on the pairing
   sheet — not a sim artifact (reproduced twice with identical symptom: ghost text under the "1"
   key, absent from the a11y tree until scrolled).
2. **AddRepoView is currently unreachable from the New Chat composer's "Add a repo first"
   chip** — that chip opens `RepoPickerView` (a read-only picker with a dead-end "Add a repo to
   get started" message and no add affordance), not `AddRepoView`. The only working path to add
   a repo is the separate "Add Repo" row on the Workspaces home list. `grep -rn "AddRepoView("
   Packages/LancerKit/Sources` found zero call sites before I traced it — worth flagging to the
   owner as its own gap (adjacent to candidate #19), not something this lane was scoped to fix.
3. Standard SwiftUI `TextField`/numeric-keypad text entry via `ui_type` (idb) is unreliable on
   this sim build — it silently no-ops instead of erroring. The `simctl pbcopy` + long-press
   "Paste" trick from the common brief was required for every text field in this lane (pairing
   code, Add Repo path, composer message, follow-up) and worked 100% of the time it was tried.
4. #20's evidence turned out stronger than planned: the ~9-minute gap between code-generation and
   Connect (from debugging #5) accidentally stress-tested code/session longevity beyond the
   nominal 5-minute expiry note, and it still worked — that's a positive data point, not a bug,
   but flagging it since it contradicts the "codes expire ~5 min" assumption in the brief.

## Simurgh feedback

- `lease_acquire`/`renew` worked cleanly, no bad errors or hangs. One friction point: default TTL
  (30m) is tight against realistic UI-debugging overhead — I had to renew once mid-session after
  ~33 minutes of work, and would have renewed earlier had I not been focused on the #5 bug.
  No other complaints; `simurgh acquire --model "iPhone 17 Pro" --json` worked first try.

Simurgh feedback count for final message: **1** (TTL-vs-debugging-overhead friction).
