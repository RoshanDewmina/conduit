# Live-Loop E2E — Pass 1 Report (real Claude Code + conduitd on this Mac)

**Date:** 2026-06-12/13 · **Machine:** owner's Mac (macOS 27, iPhone 17 Pro sim) · **Verdict:** 🟢🟢 **FULL LIVE LOOP PROVEN END-TO-END** — real agent → daemon → policy → phone card → approve → agent unblocked. Two real bugs found AND fixed.

This is the result of standing up the real governed-approvals loop end-to-end. Design: `docs/superpowers/specs/2026-06-12-conduit-live-loop-e2e-test-design.md`.

## TL;DR (updated after the fix)
Running **real Claude Code** (`/opt/homebrew/bin/claude` 2.1.176) with the **real conduit hook** and the **resident `conduitd daemon`** (built from current Go source) on this Mac **works end-to-end**: the policy engine **auto-allows**, **auto-denies**, and **escalates (ask)** real agent tool calls; an escalated ask **reaches the iOS app as an Inbox card**, and tapping **Approve** **routes the decision back and unblocks the real agent** (audit `approve` at +20 s, not the 120 s timeout). Getting there surfaced **two real bugs in the previously-untested live-relay path, both now fixed** (see "The fix").

## The fix (two bugs in the live three-way relay)
1. **TOFU first-connect never armed the daemon channel.** `startSession` ran `channel.start()` (launch `conduitd serve`) right after the first `vm.connect()`, which for a new host throws `hostKeyUnknown` *before* SSH is established — so serve failed to launch and was never retried after the user trusted the key. `trustHostKey()` fired no re-arm. **Fix:** `SessionViewModel.trustHostKey()` now calls `onReconnected?()` after a successful post-trust connect (mirrors `reconnect()`), arming the daemon channel + approval pipeline. (`SessionViewModel.swift`)
2. **UUID case mismatch dropped every phone decision.** The app sends the approval ID via Swift's `UUID.uuidString` (**UPPERCASE**); conduitd stores the hook event ID **lowercase** and did a case-sensitive map lookup → every approve missed → the agent hung to the 120 s timeout → auto-deny. **Fix:** `approvalStore` (`add`/`resolve`/`remove`) normalizes IDs case-insensitively (UUIDs are case-insensitive per RFC 4122). Regression test: `approval_case_test.go`.

**Proof:** live cards `src/auth/session.swift` → `api/handler.go` → `FINAL-verify.txt` appeared in the Inbox with real cwd/file/rule/blast-radius; approving `FINAL-verify.txt` produced audit `approve` 20 s later (well under the 120 s timeout) and unblocked the waiting hook. Screenshot: `/tmp/e2e-loop-COMPLETE.png` (status "Connected", DECIDED · FINAL-verify.txt approved).

## (original) TL;DR before the fix
The earlier finding: the **app's `conduitd serve` daemon channel did not stay attached** — the live session flipped **"Offline"** and queued "ask" approvals never reached the phone. Root-caused to the two bugs above.

## What is PROVEN (evidence-backed)

| # | Claim | Evidence |
|---|-------|----------|
| 1 | conduitd built from current source runs on macOS | `go build` OK; `conduitd daemon` listening on `~/.conduit/conduitd.sock`. The shipped prebuilt `conduitd-darwin-arm64` is **stale** (Swift 0.1.0, no policy/daemon) — see Findings. |
| 2 | Hook → daemon → policy → audit (synthetic) | `echo` → exit 0 `auto-allow`/`allow-echo`; `rm -rf` → exit 2 "Blocked by Conduit" `auto-deny`/`deny-rm-rf`. |
| 3 | **Real Claude Code agent — allow** | real `claude` ran `echo`/`ls`; audit `auto-allow` (`allow-echo`, `allow-ls`). |
| 4 | **Real Claude Code agent — deny** | real `claude` attempted `curl …`; hook returned *"PreToolUse:Bash hook error: conduitd agent-hook: denied by user"*; curl never executed; audit `auto-deny`/`deny-curl`. claude itself reported the block. |
| 5 | **Ask escalation + fail-closed** | `fileWrite` → audit `escalate`/`ask` (queued in `queue.json`); 120 s later, no phone answered → audit `deny` (fail-closed). |
| 6 | App connect UX (production path) | seeded localhost host → tapped → **real password prompt** → **real TOFU host-key prompt** (`SHA256:iiV+95…` Trust & Connect) → SSH session established (shell cwd `/Users/roshansilva`). |
| 7 | Harness isolation held | global `~/.claude/settings.json` byte-identical pre/post (md5 `e5cfb28f…`, 0 hook refs). The test agent's hook was project-scoped to `/tmp/conduit-e2e-workspace`; this running Claude Code session was never gated. |

Audit log (verbatim) in `~/.conduit/audit.log`; connect-flow recording at `/tmp/conduit-e2e-loop.mp4`.

## The BUG (what does NOT work yet)
**The iOS app's `DaemonChannel` (`conduitd serve` over SSH) does not stay attached, so queued "ask" approvals never reach the app Inbox.**

- After Trust & Connect, the session header shows **"Offline"** and the terminal is empty (only the cwd prompt) — the classic shell-session wedge.
- The SSH TCP stays established (`Conduit ↔ sshd roshansilva@notty`), but **no `conduitd serve` process persists** (`pgrep "conduitd serve"` → none).
- A fired "ask" was correctly **queued by the resident daemon** (`queue.json` had the pending `fileWrite`, `matchedRule: default:ask`) but had **no attached serve to relay it** to the phone.
- `conduitd serve` itself is fine: a manual probe (`sleep 4 | conduitd serve`) **attaches to the resident daemon and stays alive** while stdin is open. So the daemon side works; the app side isn't keeping the channel up.

**Likely root cause:** the production `openSession` → `vm.connect()` unified-shell path flips the session **Offline** on this heavy interactive zsh (~440-line `~/.zshrc`) — the same family as the previously-fixed shell-integration wedge, but on the production daemon path rather than `DebugSessionHarness`. When the session goes Offline, the daemon exec channel is torn down and `serve` exits. Needs debugging in `SessionViewModel.connect()` / `DaemonChannel.start()` lifecycle (`AppRoot.swift:1021-1041`).

## Environment / install (real paths used)
- Binary: `~/.conduit/bin/conduitd` (current Go build) · Hook: `~/.claude/hooks/conduit-hook.sh` (700) · Policy: `~/.conduit/policy.yaml` (allow `echo`/`ls`, deny `rm -rf`/`curl`, default ask).
- Test workspace: `/tmp/conduit-e2e-workspace` with **project-scoped** `.claude/settings.json` wiring the hook (the one intentional deviation from a global install — protects the harness session + reuses owner's claude auth).
- DEBUG hooks added to drive the real connect: `CONDUIT_DAEMON_E2E=1` seeds a localhost host (`DebugSeeder.seedDaemonE2EHostIfRequested`) and prefills the password in `PasswordPromptView` (both `#if DEBUG`).

## Findings worth acting on
1. **Stale shipped daemon binary.** `daemon/conduitd/conduitd-darwin-arm64` is Swift 0.1.0 (only `serve`/`agent-hook`/`version`, **no policy engine, no resident `daemon`**). The current canonical conduitd is the Go source (policy + `daemon` + `install` + attach-model `serve`). Release packaging (`scripts/release-conduitd.sh`) must rebuild from Go, or deploys ship a daemon with no governance.
2. **The live app↔daemon relay is the real remaining work** (bug above) — it's the heart of the product and was never end-to-end tested before this run.
3. **Two protection layers observed:** real claude self-refused `rm -rf` on its own judgment *before* the conduit hook (we switched to `curl` to isolate the conduit deny). Worth noting in product messaging — defense in depth.

## Out of scope (Pass 2)
Physical-device APNs (app-closed notifications), the backend decision-relay (`pushBackendURL`), and the resident-daemon survive-disconnect queue drain to a live phone.
