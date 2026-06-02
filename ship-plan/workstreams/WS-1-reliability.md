# WS-1 — Connection reliability  (LEAD — covers 17-pt #12,13,14,15)

> The #1 market complaint and the riskiest least-tested area. Depends on WS-0. This is the lead workstream — be rigorous and add tests.

## ⚠️ VERIFY FIRST — this may already be largely DONE
The source plan's reliability audit is **stale**. Commit `dafa6ba` ("production-readiness batch — reliability…") plus the project record (B4 Reliability, 2026-05-30) state that the reconnect engine was **wired**, keepalive-with-timeout added, history-restore-on-reconnect implemented, and type-based error mapping + password retry shipped — with 203 tests passing. **Before writing any code, audit the current state** of each task below in `SessionViewModel`/`SSHTransport` and report what's already implemented vs genuinely missing. Re-scope this workstream to **closing the remaining gaps and proving the behavior on a real network (WS-10)** — NOT re-implementing what exists. If a task is already done, say so and verify it with a test/repro instead of rebuilding it.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/ConduitKit && swift build`. Tests: `swift test`. Read `CLAUDE.md`, `docs/agent-contract.md` §5, `docs/block-terminal-implementation.md`, and `ARCHITECTURE.md`.

**Source-plan claims to CHECK (do not assume true — they predate `dafa6ba`):** that `AutoReconnectEngine` (exp-backoff 250ms→10s, jitter, max 5) is "declared but never wired" in `SessionViewModel`; that the unified PTY isn't re-opened on byte-stream finish; that `SessionPool` keeps a stale `isConnected`; that keepalive is only a default-off shell `:` ping; that `BlockRepository.recent()` is never called on reconnect. **Verify each against the current code first.**

## Tasks (= A1–A4 in the source plan — treat as a gap-closing checklist, not a fresh build)
1. **#12 Wire `AutoReconnectEngine` + PTY self-heal.** Initialize the unused `reconnectEngine` in `connect()`; wire its callback → `attemptReconnect()` + `reportReconnectOutcome()`. Wrap `shell.bytes` so an *unexpected* finish sets `.reconnecting`, re-opens the shell, **re-injects the integration**, and resumes the bridge. Show a reconnecting banner. Must recover on drop AND on Wi-Fi↔cellular handoff while foregrounded. Files: `SessionFeature/SessionViewModel.swift`, `SSHTransport/{AutoReconnectEngine,ReconnectController,SSHShell,SessionPool}.swift`.
2. **#13 Keepalive + dead-link heartbeat.** Add TCP/SSH keepalive at the Citadel/NIO layer (or a timed global-request); wrap the `:` keepalive in a timeout that flips `isConnected=false` and triggers task 1; add a `SessionPool` heartbeat that clears the stale flag. Files: `SSHTransport/{SSHSession,SessionPool}.swift`, `SessionViewModel.swift`.
3. **#14 Restore block history on reconnect.** After `openUnifiedShell()`, load `BlockRepository.recent(for:)` into `BlockRenderer.blocks` as non-interactive `.done` blocks; de-dupe against the live prompt so there's no duplicate trailing prompt. Files: `SessionViewModel.swift`, `PersistenceKit/BlockRepository.swift`, `TerminalEngine/BlockRenderer.swift`.
4. **#15 Type-based error mapping + credential refresh.** Replace string-matched `SSHSession.map(error:)` with type-based catches; add "retry with new password" after N auth failures without dropping the session; clear `cachedCredential` on `disconnect()`. Files: `SSHSession.swift`, `SessionViewModel.swift`, `AppRoot.swift`.
5. **Tests (B4).** Cover all four with mocks: simulated drop → reconnect, network handoff, history restore (no dup prompt), error-type mapping, wrong-password re-prompt. These must run without a live network.

## Hard invariants — DO NOT REGRESS
- Single unified PTY only — **never spawn a second `SSHShell`** for raw mode (`agent-contract.md` §5).
- Connect-time commands (`runStartupCommandIfAny`, `attemptAgentResume`) must still wait on `unifiedIntegrationReady` via `awaitUnifiedShellReady()` — re-injection on reconnect must respect this.
- `.submitted`-only TUI escalation guard stays intact.

## Acceptance
- Background→reconnect and Wi-Fi↔cellular handoff recover transparently with history intact; 30-min idle session survives; killed link detected ≤10s. (State which you verified in sim vs deferred to WS-10 on real device.)
- Build + suite green; new transport tests added and passing.

## Report Template (fill in, return)
```
## WS-1 Report
### #12 reconnect+PTY self-heal: <what changed; reconnectEngine wired where>
### #13 keepalive+heartbeat: <mechanism; dead-link detection time>
### #14 block-history restore: <how; dedup approach>
### #15 error mapping+cred refresh: <types handled; re-prompt flow>
### Invariants: single-PTY <held?> await-ready re-inject <held?> submitted-escalation <held?>
### Tests added: <list> · Build: <green/red> · Suite: <count, pass/fail>
### Verified in sim: <which scenarios> · Deferred to WS-10 (real device): <which>
### Files changed: <list> · Deviations/risks:
```
