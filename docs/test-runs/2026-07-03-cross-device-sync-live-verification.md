# Cross-device conversation sync — live verification + CI hardening

Date: 2026-07-03
Runner: Claude Sonnet 5
Branch: `feat/cross-device-conversation-sync` (PR #14)
Scope: independently re-verify the cross-device conversation sync feature (built across a prior
Claude Code session and a prior Cursor session — see
`docs/design-questions/2026-07-03-cross-device-conversation-sync-build-handoff.md`), fix whatever
was actually broken, and live-test the real behavior against the real running daemon rather than
trusting the self-reported "everything green."

## Summary

The feature works. Five real, pre-existing bugs were blocking CI from ever actually proving that —
none were introduced by this feature; all were latent issues CI's swift-tools-version mismatch had
been masking for days by failing before any of them could be exercised. All five are fixed on this
branch. Independently, the feature itself was live-tested against the real `lancerd` daemon (built
from this branch) for cross-device continuation, all three supported vendors, and durability across
a full daemon restart — all passed.

## Part 1 — CI was red, and not because of this feature

PR #14's self-report ("`go test ./...` green, 548 LancerKit tests green, app-target builds") was
true *locally*, but GitHub's actual CI was red on all three checks. Root-caused and fixed, in order
of discovery:

1. **`swift-tools-version: 6.4` orphaned.** No GitHub-hosted runner has Xcode 27 (Swift 6.4) yet —
   confirmed by fetching the actual `macos-26` runner image's installed Xcode list (tops out at
   26.6). A prior, never-merged fix branch (`fix/ci-toolchain-and-flaky-test`, 2026-06-30) had
   already root-caused this exact thing; cherry-picked its two commits rather than re-deriving them.
   Lowered to `swift-tools-version: 6.2` — no 6.4-exclusive manifest APIs were in use.
2. **`TestE2ERouterDispatchStarted` shelling out to a real `opencode` binary.** Not a race —
   `newServer` wires the real launcher, which execs `opencode` via a PATH that includes
   `/opt/homebrew/bin`. Passes on a dev machine with opencode installed, fails on any bare CI
   runner. Cherry-picked from the same prior fix branch: stub the launcher, matching the pattern
   `TestE2ERouterContinue` already used.
3. **`DarkTerminalBlockCard`'s nested `enum State` shadows SwiftUI's `@State`.** Only surfaces under
   Xcode 26/Swift 6.2 — Xcode 27/Swift 6.4 resolves the ambiguity silently. Pre-existing since
   2026-06-21, never actually compiled under 6.2 in CI until fix #1 let `swift package resolve`
   succeed for the first time. Renamed to `CardState`.
4. **`LancerLiveActivityWidget.swift` uses an iOS-27-only WidgetKit `EnvironmentValues` key**
   (`isDynamicIslandLimitedInWidth`) that doesn't exist in the iOS 26 SDK at all — `if #available`
   alone can't gate it, since Swift still type-checks the branch under any SDK. Added
   `#if swift(>=6.4)` around the struct and its call site; a build under 6.2 gets the pre-existing
   iOS<27 fallback (always show the trailing badge), a real Xcode 27 build is unchanged.
5. **A genuine CI deadlock**, not just slowness. Once fixes #1-4 let the LancerKit CI job actually
   reach "Run tests" for the first time, it hung for 48+ minutes with zero completed tests — the
   job log showed ~90 tests across every suite reporting "started" within the same few
   milliseconds, then a 45-minute gap with no output until cancellation. Root cause:
   `OpenSSHKeyParserTests` has 6 of its 24 tests each running a real, deliberately-slow bcrypt-pbkdf
   KDF synchronously (~20s each on this dev machine, by OpenSSH's own design). Swift Testing's
   default concurrent scheduling hands all 24 of a suite's tests to the shared cooperative thread
   pool at once; on a small-core CI runner (unlike this many-core dev machine) that pool doesn't
   have enough threads to make progress on that much simultaneous CPU-bound synchronous work
   without yielding, so the whole `swift test` run stalls indefinitely — not just this suite. Fixed
   with `@Suite("OpenSSHKeyParser", .serialized)` (24 tests now run one-at-a-time, 39.9s total
   locally vs. the previous ~20s parallel — still fast, no longer deadlock-prone). Also added
   `timeout-minutes` to all three CI jobs as a safety net so a future hang fails within a normal
   ceiling instead of silently burning CI minutes toward GitHub's 6-hour default cap.

**CI status on PR #14 as of this report:** Daemon ✅, app-target ✅, LancerKit — see the PR for final
status; was healthy and progressing normally (not hung) as of this report, first real completed run
after fix #5 landed.

## Part 2 — Independent re-verification of the build-handoff doc's Task 1-10 checklist

Three parallel subagents independently re-read
`docs/design-questions/2026-07-03-cross-device-conversation-sync-build-handoff.md`'s task-by-task
checklist and verified each claimed interface/behavior against actual code at HEAD — not against
the doc's own self-reported checkmarks.

- **Daemon side (Tasks 1-4, 9 daemon half): all CONFIRMED**, with real (not superficial) test
  coverage for the hard cases — idempotency, conflict detection, best-effort ledger-write
  persistence, exact-resume selection.
- **iOS side (Tasks 5-8, 9 iOS half): CONFIRMED with one real discrepancy** — Task 8's CloudKit
  data model spec called for 4 record types including artifact sync; the implementation shipped 2
  record types (turn+events merged into one chunk record) with **artifact metadata never synced to
  CloudKit at all**. Not disclosed in the original Task 8 self-report (only the
  `CKDatabaseSubscription` and device-verification gaps were disclosed). Noted here for the record;
  not fixed in this pass — artifacts remain host-ledger-only, readable while the host is reachable,
  just not part of the CloudKit read-continuity mirror.
- **Docs (Task 10): CONFIRMED** — `ARCHITECTURE.md` §11.2/11.3, `LIVE_LOOP_RUNBOOK.md` PHASE 7, and
  `PUBLISH_READINESS_CHECKLIST.md`'s B9/C7/D2 rows all match their described content, and 11 cited
  file paths (exceeding the doc's own 8-path spot-check) all resolve.

## Part 3 — Closed B9 (`CKDatabaseSubscription`)

Implemented the background-pull subscription the build-handoff doc's Task 8 explicitly left open:

- `CloudSync.ensureDatabaseSubscriptionExists(subscriptionID:)` — idempotent `CKDatabaseSubscription`
  registration with `shouldSendContentAvailable`, database-wide (not zone-scoped — it's currently the
  app's only CloudKit push subscription; `SyncEngine`'s Hosts/Snippets sync still polls on
  foreground/account-change only, an unrelated pre-existing scope).
- `ConversationSyncEngine.start()` registers it after the first sync cycle, best-effort (an
  entitlement/profile issue falls back to the pre-existing foreground-only behavior rather than
  blocking startup).
- `AppDelegate.didReceiveRemoteNotification` (`Lancer/LancerApp.swift`) now distinguishes a
  CloudKit database-change push from an APNs approval/run-complete push by trying
  `CKNotification(fromRemoteNotificationDictionary:)` first, and routes to a new
  `.lancerCloudKitRemoteNotification` NotificationCenter name.
- `ConversationSyncEngine.handleRemoteNotification(subscriptionID:)` takes an already-parsed
  `String?`, not the raw `userInfo` dictionary — `Notification.userInfo` (`[AnyHashable: Any]?`)
  isn't `Sendable`, so the `CKNotification` has to be parsed outside actor isolation (in the
  `NotificationCenter.notifications(named:)` `Task`, before crossing into the actor) to satisfy
  Swift 6 strict concurrency.
- Added unit tests for the subscriptionID-matching logic. Full LancerKit suite: 551 tests / 91
  suites green locally (was 548 before this addition + the 3 new tests).

Still open, unchanged by this: **actual silent-push delivery and two-device CloudKit propagation
are unverified on physical hardware** (C7, still `⏸ owner-gated` — needs a second physical Apple
device, which this session didn't have).

## Part 4 — Live verification against the real running daemon

The user asked for actual live testing, not compile/unit tests. Two constraints shaped the
approach:

- **CloudKit is a simulator no-op by design** (`CloudSync`/`ConversationSyncEngine`), so two
  simulators can't demonstrate CloudKit propagation regardless of tooling — only physical hardware
  can (C7, unchanged).
- **This specific Xcode-beta/iOS 27 simulator build does not respond to any synthetic tap.**
  Confirmed three independent ways: `mcp__ios-simulator__ui_tap` at exact accessibility-reported
  coordinates, `XcodeBuildMCP`'s `tap`/`key_press` (including a hardware Return keypress on a
  system alert's default button), and repeated relaunches to rule out stale elementRefs — all
  reported "succeeded" with zero visible effect on-screen, on both a system permission alert *and*
  plain in-app SwiftUI buttons. This matches (and extends) a tooling limitation already flagged in
  `docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md`. A `LANCER_SKIP_NOTIFICATION_PROMPT`
  debug launch seam was added (`AppRoot.swift`, `#if DEBUG`-gated, same pattern as
  `LANCER_SEED_DEMO`/`LANCER_DESTINATION`) so at least the permission-prompt dead-end doesn't block
  every future simulator pass, but interactive multi-step UI flows (typing a prompt, tapping Send,
  navigating) could not be automated this session.

Given that, host-ledger continuation itself — the actual mechanism both SSH and relay transports
use, verified in Part 2 to share identical dispatch code (`ConversationSyncCoordinator`'s own doc
comment, and the daemon's `agent.conversations.*` RPCs being called identically from
`e2e_router.go`'s relay handlers and `DaemonChannel`'s SSH methods) — was tested directly at the
daemon's real IPC protocol layer: a from-scratch Go client speaking the exact wire protocol
(`~/.lancer/lancerd.sock`, 4-byte-length-prefixed JSON-RPC frames, token-authenticated `hello`
handshake) that `HostServiceClient`/`DaemonChannel` use, built against `lancerd` rebuilt fresh from
this branch and running for real (not the pre-existing `0.1.0-dev` binary from before this
feature — that was safely stopped, swapped, and restarted via `launchctl`).

### Two-device continuation

1. "Device A" dials the daemon and starts a new `opencode` conversation (`agent.conversations.append`,
   no `conversationId`). Real dispatch — the actual `opencode` CLI ran.
2. "Device B" (separate connection) fetches the same `conversationId` and sees Device A's turn,
   full event stream, and exit status.
3. Device B sends a follow-up on the same conversation. The daemon correctly resolves
   `resumeMode: "exact"` using the vendor session ID it bound from Device A's turn.
4. Device A re-fetches and sees both turns.

**Result: PASS.**

### Multi-vendor exact-resume (opencode, claudeCode, codex)

Same append → wait-for-terminal-status → follow-up → check-resume-mode sequence, run against all
three vendors this repo dispatches (Kimi also installed but not in scope of this ask):

| Vendor | Dispatch | Vendor session ID bound | Follow-up resumeMode |
|---|---|---|---|
| opencode | ✅ started | `ses_...` (opencode session ID) | `exact` |
| claudeCode | ✅ started | UUID (Claude `session_id`) | `exact` |
| codex | ✅ started | UUID (`thread_id`) | `exact` |

Two real, non-bugs surfaced and are recorded for completeness:

- **codex's dispatch initially returned `needsApproval`.** Correct, working policy-gate behavior —
  this machine's `policy.yaml` has no explicit rule for codex, so it defaults to `ask` (fail-closed,
  same as any un-configured agent). Verified by temporarily adding a scoped allow rule
  (`match: "*codex*"`), reloading via `agent.policy.reload`, testing, then restoring the original
  `policy.yaml` byte-for-byte and reloading again. Confirms the policy gate applies identically to
  the new `agent.conversations.append` path as it does to the legacy dispatch path (both build the
  same `"[<prefix>] <argv>"` command string the policy engine matches against — the prefix itself
  differs, `"[dispatch]"` vs. `"[conversation-append]"`, which is what made the first attempt at a
  scoped test rule not match; broadened the glob rather than assuming the wrong prefix again).
- **codex's dispatch failed outright the first time even once policy-allowed**, with exit code 1
  and no relayed error text. Root cause: codex CLI refuses to run in a directory that isn't a
  trusted git repo (`"Not inside a trusted directory and --skip-git-repo-check was not
  specified."`) unless `--skip-git-repo-check` is passed — which `dispatch.go`'s `agentArgv` for
  codex does not currently pass. This is a real, if narrow, product gap: dispatching codex against
  a non-git cwd fails silently (the daemon's event stream shows only `exitCode:1, status:"failed"`,
  never codex's actual stderr explanation) with no diagnostic surfaced to the ledger or UI. Not
  fixed in this pass — most real usage dispatches into an actual project (git) directory, but a
  user hitting a bare/non-git folder would see an unexplained failure. Worth a follow-up: either
  relay stderr into a ledger event on non-zero exit, or default-append `--skip-git-repo-check` for
  headless dispatch the same way the sandbox-bypass flag is already conditionally added.

**Result: PASS for all three vendors once dispatched against a trusted git directory.**

### Durability across daemon restart

9 real conversations (spanning all three vendors, created during the tests above) were present
before a full `launchctl bootout` + `bootstrap` restart of `lancerd` (not a binary swap — the exact
same binary, a genuine process stop/start). After restart:

- `agent.conversations.list` returned all 9 conversations with identical `lastSeq` values.
- A full `agent.conversations.fetch` on one conversation showed both turns, both events, and the
  **same bound `vendorSessionId` on both turns** (proving the exact-resume relationship itself
  survived, not just raw row counts).
- A fresh dispatch immediately after restart succeeded normally — the daemon didn't just retain old
  data, it resumed normal operation.

**Result: PASS** — `~/.lancer/conversations.sqlite` is a real, durable, host-owned ledger.

Test conversations were archived (`agent.conversations.archive`) after verification so they don't
clutter the owner's real conversation list.

## What's still open

- **C7 (two-device CloudKit QA on physical hardware)** — unchanged, still owner-gated. Nothing in
  this session could close it; it needs a second physical Apple device signed into the same iCloud
  account, per `docs/LIVE_LOOP_RUNBOOK.md` PHASE 7.
- **Device Hub simulator UI screenshot pass over the new surfaces** (Home IA, sync badges,
  `ConversationSyncBanner`, resumed-thread markdown, Import-to-Lancer) — not completed. Blocked by
  the tap-injection limitation above; static (non-interactive) screenshots of Home/Machines were
  captured but multi-step interactive flows could not be driven.
- **Codex non-git-cwd silent failure** (Part 4) — real, narrow gap, not fixed this session.
- **Task 8's CloudKit artifact-sync scope narrowing** (Part 2) — real, undisclosed-until-now scope
  reduction from the original spec, not fixed this session.
