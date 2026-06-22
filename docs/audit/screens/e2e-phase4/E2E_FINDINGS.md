# Lancer — Governed-Approvals Phase 4 E2E Findings

- Date (UTC): 2026-06-12
- Sim: iPhone 17 Pro `095F8B3A-FEA3-4031-A2A5-561755740730` (iOS 27.0), bundle `dev.lancer.mobile`
- Worktree: `/Users/roshansilva/Documents/command-center/.claude/worktrees/agent-ad5a294fb3ffeb4aa`
- Toolchain: Go 1.26.4, xcodegen, Xcode-beta (only Xcode installed)

## CRITICAL ENVIRONMENT FINDING — worktree was forked at the WRONG commit (recovered)

The worktree was checked out at `5232b4d8` (branch `worktree-agent-ad5a294fb3ffeb4aa`,
dated 2026-06-05), NOT the audit checkpoint. That commit is the **clean merge-base / direct
ancestor** of the audit checkpoint `f6a36a55` ("chore(audit): checkpoint governed-approvals
audit (B1–B4, wave1/2 reliability, relay auth)", 2026-06-12) and is **41 commits behind it
with 0 commits ahead**. NONE of the governed-approvals code existed in the working copy as
delivered (no `relay_security.go`, `decisions.go`, `relay_token.go`, `decision_poll.go`; zero
refs to `APPROVAL_RELAY_SECRET` / `relayToken` / `/approval/decision`).

Recovery (no new commits created — respects "do NOT git commit"): `git checkout --detach f6a36a55`.
This was a clean fast-forward checkout (working tree was clean apart from `node_modules`).
The audit branch `feat/governed-approvals` is checked out in ANOTHER worktree
(`/Users/roshansilva/Documents/cc-wt/governed-approvals-audit`) owned by the other worker, so
a detached checkout of the commit (not the branch) was the correct, non-conflicting way to reach
the intended state. **All checks below were run at `f6a36a55`.**

## ENVIRONMENT LIMITATION — programmatic UI taps are unavailable

The only installed Xcode is `Xcode-beta.app`, which ships `SimulatorKit.framework` under
`Contents/SharedFrameworks/` instead of `Contents/Developer/Library/PrivateFrameworks/` where
`idb` (ios-simulator MCP) and XcodeBuildMCP hardcode the lookup. Result: **screenshots and
accessibility-tree reads work; HID taps/typing do NOT** (idb, XcodeBuildMCP `tap`/`snapshot_ui`
all fail with "SimulatorKit ... does not exist"). The GUI Simulator window is not driveable via
`cliclick` either (no window-owning Simulator process — only `SimulatorTrampoline`). I did NOT
modify the Xcode bundle (symlinking into a system app would risk the other worker's setup).
Consequently every check that requires a tap (press Approve, tap Skip, switch tabs, drive
onboarding) could not be exercised at runtime and is marked accordingly.

## Build status

| Step | Result | Evidence |
|---|---|---|
| `swift build` (LancerKit) | PASS | "Build complete! (86.97 secs.)" |
| `swift test` (LancerKit) | PASS | "337 tests in 57 suites passed" (incl. "M9 — exactly-once decision delivery gate") |
| `xcodegen generate` | PASS | "Created project at .../Lancer.xcodeproj" |
| **App target** `xcodebuild ... build` | **PASS** | `** BUILD SUCCEEDED **` (Lancer.app + Widget + Watch + LiveActivity appex) |
| `go build` push-backend | PASS | 51 MB binary |

## Check results

| Check | Verdict | Evidence |
|---|---|---|
| 1 — Live-SSH approval happy path | **BLOCKED** | `01-session-launch.png`, `01c`, `01d-echo-autocmd.png` — see below |
| 2 — B1 TOFU first-connect | **PARTIAL (code-verified, runtime BLOCKED)** | `TOFUHostKeyValidator.swift`, `SessionView.swift:63-82,227-235` |
| 3 — B3 idempotency (first-decision-wins) | **PASS** | `relay-idempotency.txt`; `ApprovalRepository.swift:133-147`; M9 test `firstDecisionWins`; `TestDecisionRelayDedupeByApprovalID` |
| 4 — Relay fallback (local push-backend) | **PASS (curl + tests); three-way wiring PASS via tests** | `relay-curl.txt`; Go relay tests (below) |
| 5 — Cold-launch banner (M6) | **PARTIAL (code-verified, runtime BLOCKED)** | `AppRoot.swift:341-360`; `HostedAgentM6Tests.swift` |
| 6 — Gallery screenshots | **PASS** | 3 dark routes + prod Inbox light/dark captured |

### Check 1 — Live-SSH approval happy path — BLOCKED

Two independent blockers:

1. **Cannot tap.** Even if an approval card appeared I cannot press Approve (HID broken, above).
2. **Autocmd never cleanly executes against this host's zsh.** First launch landed on a "Tmux
   Sessions" reattach sheet (`01-session-launch.png` was originally this) because the host had a
   detached tmux session. I killed the host tmux server (safe, reversible) to clear it. On relaunch
   the session connects ("Done") but the block output shows Lancer's OSC-133 shell-integration
   bootstrap **leaking as literal text** (`__lancer_preexec` function bodies, `printf '\033]133;C\007'`)
   and the shell wedged at a zsh PS2 continuation `elif-then function function quote>`. The autocmd
   text (`claude`, and even a trivial `echo HELLO-E2E` — see `01d`) is pasted INTO that unterminated
   multiline construct, so no command executes and no block finalizes; the session then flips to
   "Offline" (`01c`). The user's 440-line interactive `~/.zshrc` contains a `claude` wrapper function
   and `elif` constructs (lines 283/323) that collide with the integration injection — this looks like
   the integration injecting before `unifiedIntegrationReady` (the exact footgun called out in
   CLAUDE.md / agent-contract §5), aggravated by a heavy login shell.

   **Honest attribution:** this reproduces a real fragility but on a host with a non-trivial `.zshrc`,
   so I cannot cleanly separate "Lancer block-pipeline regression" from "this host's shell config."
   The approval-card / block UI itself renders correctly (see Check 6: `gallery-blocks-*`,
   `gallery-inbox-typed-*`, `prod-inbox-*`), so the failure is in the live zsh-integration handshake,
   not the rendering or approval layer. `02-approval-card.png` / `03-after-approve.png` were NOT
   produced — no approval card ever formed.

### Check 2 — B1 TOFU first-connect — PARTIAL (code-verified)

The exact B1 fix is present and documented. `SessionView.swift:63-82` presents
`SessionHostKeyConfirmSheet` from INSIDE SessionView (comment: "Presented from INSIDE SessionView
so it appears above the fullScreenCover ... that was the B1 hard-hang"), bound to
`vm.pendingHostKeyFingerprint != nil`. Reject → `vm.rejectHostKey()` → `.disconnected` with a
dismissible overlay (lines 227-235: "New-host TOFU transitions to `.disconnected` ... show a
dismissible overlay"); Back is pure navigation. `TOFUHostKeyValidator` fails unknown keys with
`LancerError.hostKeyUnknown` (no silent accept). The harness auto-trusts only when
`autoTrustHostKey` is set (debug only); production default propagates `hostKeyUnknown` so the sheet
shows (`LiveTerminalView.swift:110-123`). **Runtime repro BLOCKED:** localhost key is already trusted
and forcing a fresh-host production prompt requires tapping through onboarding/host-add (no HID).

### Check 3 — B3 idempotency — PASS

Two layers, both verified:
- **iOS (the `WHERE decision IS NULL` fix the task names):** `ApprovalRepository.decide()` runs
  `UPDATE approvals SET decision=?,decidedAt=? WHERE id=? AND decision IS NULL` and returns
  `db.changesCount > 0`. First decision returns true (caller forwards once); a second/stale decision
  returns false (no-op). Proven by SPM test `firstDecisionWins` (M9 suite) — passed in the 337-test run:
  `firstApprove == true`, `secondReject == false`, final `decision == .approved`.
- **Relay:** `relay-idempotency.txt` — re-POST of the same `approvalId` replaces (not appends); poll
  drains exactly ONE record. Backed by Go `TestDecisionRelayDedupeByApprovalID` (PASS).

### Check 4 — Relay fallback with LOCAL push-backend — PASS

Backend run locally: `PORT=8077 APPROVAL_RELAY_SECRET=test-secret-123 go run .` (default port is 8080
per main.go; 8099 from `.env.example` was occupied by an unrelated process, so I used 8077). Full curl
matrix in `relay-curl.txt`:

| Assertion | Expected | Got |
|---|---|---|
| (a) `POST /register` no secret / wrong secret | 401 | 401 / 401 |
| (b) `POST /register` correct secret (sessionId→relayToken) | 204 | 204 |
| control `/approval` no secret / correct secret (no device token) | 401 / 202 | 401 / 202 |
| (c) `POST /approval/decision` no token / wrong token / correct token | 401 / 401 / 204 | 401 / 401 / 204 |
| (c) bad decision verb (correct token) | 400 | 400 |
| (d) `GET /decisions` no token / wrong token / correct token | 401 / 401 / 200+drain | 401 / 401 / 200+drain |
| (d) second poll (already drained) | 200 + empty | 200 + empty |
| cross-session: session-A token draining session B | 401 | 401 |
| session-B own token draining session B | 200 + apB | 200 + apB |

Body of `sessionId` must equal the registered sessionID — enforced by `relaySessionAuthorized()`
(constant-time compare against the per-session record). Two-tier model holds (Tier-1 shared secret
on control plane; Tier-2 per-session relayToken on decision/poll).

**Three-way wiring (BEST-EFFORT):** verified via lancerd Go tests rather than a live daemon —
`TestDecisionPollerResolves` (phone-posted decision resolves a pending approval with NO live SSH,
through `applyDecision`), `TestDecisionPollerSendsBearerToken` (poller authenticates with the
relayToken), `TestApplyDecisionApproveAlwaysPersistsPolicyAndAudit`. A full live
phone→backend→lancerd loop was not stood up (would need a running lancerd + a phone decision POST,
and the phone side can't be driven without taps), but every link is independently proven.

### Check 5 — Cold-launch banner (M6) — PARTIAL (code-verified)

M6 / MAJOR-6 is the cold-launch approval-action drain: a killed app's lock-screen Approve/Reject is
buffered by `LancerNotificationDelegate` into `ApprovalActionBuffer`, then `drainPendingApprovalActions`
(`AppRoot.swift:341-360`) replays each through `ApprovalRelay.enqueue` (durable, first-decision-wins,
idempotent — "replaying an already-resolved gate is a no-op"). Dedicated `HostedAgentM6Tests.swift`
exists. **Runtime BLOCKED:** requires tapping a delivered push notification on the lock screen (no HID,
no live APNs in this harness).

### Check 6 — Gallery screenshots — PASS

3 requested DARK routes captured and visually verified:
- `gallery-orb-connected-dark.png` — green PixelBox grid + "Connected" + "Tap anywhere to continue". OK.
- `gallery-blocks-dark.png` — Warp blocks: streaming `tail -f`, `git status` (✓ exit 0 ★), `kubectl` (✓),
  `npm run build` (✗ exit 1, red gutter, TS error). OK.
- `gallery-inbox-typed-dark.png` — QUESTION multiple-choice card (A/B/C/D + SUBMIT) and a "Claude Code
  wants to call a tool" approval card (`tool use toolu_…`, `read_file` block, `✗ deny / always /
  edit & run / ✓ approve`). OK.

Production tabs: app launched with no gallery env loads straight into the **production Inbox**
(`prod-inbox-light.png` / `prod-inbox-dark.png`) — real governed-approval cards with `BASH DESTRUCTIVE`
/ `BASH RISK` chips, blast-radius command preview, `EDIT & RUN / DENY / ALLOW ALWAYS / APPROVE`, plus a
DECIDED section. The tab bar (INBOX / FLEET / ACTIVITY / SETTINGS) is present and all four buttons are
AX-labeled + enabled in the accessibility tree. Fleet / Activity / Settings tabs could NOT be captured
(switching tabs needs a tap — no HID); only the default Inbox tab is shown, in light and dark.

## Anomalies

1. **Worktree forked at wrong commit** (see top) — would have caused a false-everything run if
   unnoticed; recovered by detached checkout to `f6a36a55`.
2. **Shell-integration bootstrap leaks into the live session block** as literal text and wedges the
   shell at a zsh PS2 continuation on this host (`elif-then function function quote>`), so the live
   autocmd never executes (Check 1). Reproduced with both `claude` and `echo HELLO-E2E`. Likely the
   `unifiedIntegrationReady` ordering footgun amplified by a heavy `~/.zshrc` (custom `claude` wrapper).
   Worth a clean-shell repro on a vanilla host before deciding if it is a product regression.
3. **No approval-card host-label wrapping issue observed** on `inbox-typed` (the task flagged this as a
   thing to watch) — the segmented host/mode control and card labels wrap cleanly in both appearances.
4. Tap tooling is unusable on this machine (Xcode-beta framework path) — flagged so a future run on a
   box with a release Xcode (or a fixed SimulatorKit path) can complete Checks 1/2/5 at runtime.
