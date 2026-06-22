# Governed Approvals v1 — Pre-submission Audit: SSH + Terminal + Session pipeline

**Scope:** `SSHTransport/*`, `SessionFeature/*`, `TerminalEngine/*`, `LancerCore/{Block,PortForward,Identifiers,LancerDProtocol}`.
**Branch:** `feat/governed-approvals` (worktree `governed-approvals-audit`).
**Method:** read-only correctness/security/concurrency review. No source modified, no build run.
**Focus:** correctness, edge cases, races/actor-isolation, retain cycles, security, silent failures.

Paths are repo-relative to the worktree root. Each candidate was put through an adversarial "is it actually reachable / already guarded?" pass before inclusion.

---

## SECURITY VERIFICATION (KEY VERIFY #1) — TOFU host-key path is SOUND

Verified end-to-end; no bypass found in any production path:

- `TOFUHostKeyValidator.validateHostKey` (`SSHTransport/TOFUHostKeyValidator.swift:22-40`) only ever `succeed()`s on `HostKeyStore.Verdict.match`; `.unknown` and `.mismatch` both `fail()` the NIO promise. There is **no default-allow branch**. The async `store.verify` runs in a `Task` that always completes the promise exactly once.
- `HostKeyStore.verify` (`SecurityKit/HostKeyStore.swift:34-41`) returns `.unknown` for an unrecorded host (it does **not** auto-record) and `.mismatch` for any fingerprint that differs from the stored one. `.match` requires an exact recorded fingerprint.
- Production connect (`SessionFeature/SessionViewModel.swift:298-312`): `hostKeyUnknown` → sets `pendingHostKeyFingerprint` and surfaces the confirmation sheet (`AppRoot.swift:463` wires `onTrust → trustHostKey()`); `hostKeyMismatch` → `.failed("Host key changed")`. Trust is only recorded when the user explicitly calls `trustHostKey()` (`SessionViewModel.swift:333-338`). **Prompts on first/unknown, rejects on mismatch.** ✓
- `SSHSession.connect` uses `.custom(hostKeyValidator)` with `reconnect: .never` (`SSHTransport/SSHSession.swift:90-97`), so Citadel cannot silently re-establish a connection bypassing the validator. ✓

**PRIOR FLAG LOW-3 (`autoTrustHostKey`) — resolved, not a leak in Release.** See NIT-13: the flag exists as a public, runtime-settable parameter with no `#if DEBUG` guard on the API, but its default is `false`, the only caller that passes `true` is `DebugTerminalHarness` (`#if DEBUG && os(iOS)`), and `LiveTerminalModel`/`LiveTerminalView` are only instantiated by debug harnesses + the gallery. No Release code path reaches the auto-trust branch. Recommend a defense-in-depth guard anyway.

**`.approveAlways` distinctness (KEY VERIFY #5) — correct.** `DaemonChannel.decisionWireValue` (`SSHTransport/DaemonChannel.swift:108-114`) maps `.approvedAlways → "approveAlways"` and `.approved → "approve"`; the same mapping is used by the backend relay body (`SessionFeature/ApprovalRelay.swift:95-108`). Not collapsed. ✓ Approval-event ordering/exactly-once is preserved: events arrive over an unbounded FIFO `AsyncStream` and `ApprovalIngest` (`AppFeature/ApprovalIngest.swift:20-46`) persists via `repository.upsert` keyed on approval ID, so duplicate re-deliveries are idempotent. ✓

---

## BLOCKER

None. The TOFU/security path is sound (above). The reconnect/approval-pipeline defects below fail **closed** (lancerd's 120 s timeout auto-denies), so they are correctness/release-quality issues rather than security escalations — but MAJOR-2 and MAJOR-4 break the core approval feature after a routine mobile network blip and should be fixed before submission.

---

## MAJOR

### [MAJOR][correctness] Belt-and-suspenders TUI escalation fires for idle `.promptEditing` prompts (KEY VERIFY #3 — guard is WRONG)
`Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift:708-715`
```swift
if let block = self.blocks.blocks.first(where: { $0.id == blockID }),
   block.state == .promptEditing || block.state == .submitted {   // ← .promptEditing must NOT be here
    if interactiveHint || self.blocks.pendingTUIEscalation {
        self.blocks.setState(.executing, for: blockID)
        self.isExecutingUnified = true
        self.blocks.pendingTUIEscalation = false
    }
}
```
The documented invariant (CLAUDE.md / KEY VERIFY #3) is that this escalation must fire **only for `.submitted` blocks, never an idle `.promptEditing` prompt**. Here the guard explicitly allows `.promptEditing`. `interactiveHint` is `TUIDetector.shouldEscalate(to:)` (`TerminalEngine/AnsiSGRParser.swift:368-379`), which returns `true` for `\e[H`, `\e[2J`, `\e[?1h`, `\e[?25l`, `\e[?47h`, `\e[?1049h` — i.e. exactly the cursor-home / clear-screen / app-cursor-key / hide-cursor sequences that zsh's ZLE and the shell-integration screen-clear emit around an idle prompt.

**Reachability:** confirmed. After every `onPromptStart` (133;A) a block is created in `.promptEditing` (`SessionViewModel.swift:760-766`). zsh ZLE redrawing the idle prompt (`\e[?1h`, cursor moves) or the integration's own `printf '\033[2J\033[H'` (`SessionViewModel.swift:867,874`) flows through `onBlockBytes` while the block is still `.promptEditing` → `interactiveHint == true` → the idle prompt is escalated to `.executing`. Consequence: the bare prompt (`~ %`) is captured as block output, `isExecutingUnified` flips true, and `submit()` (`:945-947`) then routes the user's next line as raw keystrokes instead of starting a new command block. For a governance product where blocks are the audit/approval context, this mis-states the transcript.

**Proposed fix:** change the guard to `block.state == .submitted` only (drop the `.promptEditing` disjunct), matching the invariant.

---

### [MAJOR][correctness] Connect-time commands race the shell-integration injection — no `unifiedIntegrationReady` gate exists (KEY VERIFY #4 — FAILS)
`Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift:269-276` (call order), `:557-562` (`runStartupCommandIfAny`), `:569-585` (`attemptAgentResume`), `:846-879` (`openUnifiedShell` injection)
```swift
await openUnifiedShell()          // returns immediately; injection runs in a detached Task with sleeps
await runStartupCommandIfAny()    // sends the startup command NOW
await attemptAgentResume()        // sends the agent-resume command NOW
```
`openUnifiedShell()` sets `unifiedShell` (`:846`) and then spawns the integration-injection work in `Task { try? await Task.sleep(300ms); … bootstrap …; printf '\033[2J\033[H' }` (`:853-879`) — it does **not** await it. `runStartupCommandIfAny`/`attemptAgentResume` only check `unifiedShell != nil` and immediately `shell.send(...)`. There is **no `awaitUnifiedShellReady()` / `unifiedIntegrationReady`** mechanism anywhere in the file (searched the whole tree — the symbols named in the project invariant do not exist on this branch).

**Reachability:** confirmed on every connect with a `host.startupCommand` or `host.autoResume` snapshot. The startup/agent-resume bytes are sent at ~0 ms while the integration probe fires at +300 ms and the bootstrap script + screen-clear at ~+800–1100 ms. Result is exactly the documented footgun: the integration bootstrap text and `\033[2J\033[H` get pasted into the stdin of the just-launched agent (e.g. `claude`/`codex`), corrupting the launch.

**Proposed fix:** reintroduce a readiness gate — have `openUnifiedShell` expose an awaitable that resolves on the first OSC 133 A (or after the bootstrap+clear has been sent and acknowledged), and `await` it inside `runStartupCommandIfAny`/`attemptAgentResume` before sending.

---

### [MAJOR][correctness] Auto-reconnect leaves a dead terminal — `attemptReconnect` never resets `unifiedShell`, so `openUnifiedShell` no-ops
`Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift:155-169` and the guard at `:652`
```swift
private func attemptReconnect() async {
    await transitionStatus(.reconnecting(attempt: 1))
    do {
        try await sshSession.attemptReconnect()
        ...
        await transitionStatus(.connected)
        await openUnifiedShell()      // guard: `unifiedShell == nil` is FALSE → early return
        await refreshCWD()
    } ...
}
// openUnifiedShell(): guard status == .connected, unifiedShell == nil else { return }
```
Unlike the manual `disconnect()` path (which calls `closeUnifiedShell()` and nils `unifiedShell`, `:371`/`:901-910`), `attemptReconnect()` never closes or nils the stale shell. After `SSHSession.attemptReconnect` swaps the underlying Citadel client, the old PTY channel's byte stream finishes and `PTYBridge.start()`'s pump loop ends — the old `unifiedShell` is dead — but `openUnifiedShell()`'s `unifiedShell == nil` guard sees it as non-nil and returns immediately, so no new PTY is opened.

**Reachability:** confirmed. `attemptReconnect()` is invoked from `handleSceneActive()` (`:142`, foreground-while-disconnected) and from the `AutoReconnectEngine.onReconnect` closure (`:414-417`, network restored). Both are common mobile scenarios. The session shows `.connected` but the terminal is non-functional until the user fully tears down and re-opens.

**Proposed fix:** call `closeUnifiedShell()` (or set `unifiedShell = nil` and reset `unifiedBlockID`/`unifiedBridge`/`isExecutingUnified`) at the start of `attemptReconnect`'s success path, before `openUnifiedShell()`.

---

### [MAJOR][correctness] Approval pipeline is not re-armed after reconnect — `DaemonChannel`/`ApprovalIngest` are created once and never restarted (KEY VERIFY #6)
`Packages/LancerKit/Sources/AppFeature/AppRoot.swift:854-958` (one-time setup); `SessionViewModel.swift:155-169` (`attemptReconnect`), `:360-363` (`reconnect`)

`DaemonChannel(session:)`, `ApprovalIngest`, `channel.start()`, `registerDevice`, and `ApprovalRelay.setChannel` are all wired exactly once inside `startSession(...)` (the host-selection flow). Neither `SessionViewModel.attemptReconnect()` (auto) nor `reconnect()`→`disconnect()`+`connect()` (manual, `:360-363`) restarts the channel. When the SSH client is replaced on reconnect, the channel's exec stream finishes → `DaemonChannel.start`'s `readTask` ends → `eventContinuation.finish()` (`DaemonChannel.swift:39`). `ApprovalIngest.start`'s `for await event in channel.events` loop (`ApprovalIngest.swift:22`) therefore terminates and is never restarted.

**Reachability:** confirmed for both auto and manual reconnect (channel.start() is only ever called at `AppRoot.swift:948` and `AgentKit/.../SSHHostRuntime.swift:59`; nothing re-runs it on a status transition). After a network blip the device keeps showing `.connected` but: (a) new `agent.approval.pending` events are no longer ingested into the repository, so the in-app Inbox never shows them; and (b) `respond()` writes go to a dead writer. New agent approval requests sit pending until lancerd's 120 s timeout auto-denies them — the user **cannot approve anything** after a reconnect. Fails closed, but the core feature is dead.

**Proposed fix:** tie the `DaemonChannel`/`ApprovalIngest` lifecycle to the session connection: on (re)connect, `stop()` the old channel and create+`start()` a fresh `DaemonChannel`/`ApprovalIngest` and re-`setChannel` on the relay. Drive this from the same place that detects reconnect (e.g. a status observer in `AppRoot` or a hook in `SessionViewModel.attemptReconnect`).

---

### [MAJOR][silent-failure] Approval decisions are silently dropped when the attached channel is dead — `respond()` no-ops on nil writer and the relay's backend fallback is bypassed
`Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:116-136` (`respond`), `:93-106` (`registerDevice`); `SessionFeature/ApprovalRelay.swift:66-75` (`enqueue`)
```swift
// DaemonChannel.respond / registerDevice
guard let writer = stdinWriter else { return }   // silent no-op, no throw
...
// ApprovalRelay.enqueue
if let ch = channel {
    try? await ch.respond(approvalId: approvalID, decision: decision)  // error swallowed
} else {
    await postDecisionToBackend(...)   // backend fallback ONLY when channel == nil
    queue.append(...)
}
```
`ApprovalRelay.channel` is a `weak` ref to the `DaemonChannel`, which stays alive (held by `FleetStore.Slot`/`AppRoot`) even after its stream dies on reconnect. So `enqueue` sees `channel != nil` and calls `respond`, which either (a) silently returns (writer nil'd by `stop()`) or (b) `try await writer.write` throws on the dead writer and the `try?` swallows it. Either way the decision is **neither forwarded, queued, nor posted to the backend relay** — it lands only in the local DB.

**Reachability:** confirmed in combination with MAJOR-4 (dead-but-attached channel after reconnect). A lock-screen / Dynamic Island approval tap after a reconnect is lost to lancerd; it resolves only via the 120 s auto-deny (fail-closed, but silent and surprising — a user "Approve" becomes an auto-deny).

**Proposed fix:** `respond()`/`registerDevice()` should `throw DaemonChannelError.notRunning` when `stdinWriter == nil` (don't silently return). `ApprovalRelay.enqueue` should treat a thrown `respond` as "not delivered" and fall back to `postDecisionToBackend(...)` + `queue.append(...)` (and `drainQueue` should not `removeAll()` until each item is confirmed sent).

---

## MINOR

### [MINOR][robustness] `DaemonFraming.unframe` has no maximum frame size — a desynced/garbage length prefix grows the read buffer unboundedly
`Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift:16-26`; consumer `SSHTransport/DaemonChannel.swift:30-41`
A 4-byte big-endian length is read with no upper bound (`needed = 4 + Int(len)`, up to ~4 GiB). If framing ever desyncs or lancerd emits a malformed prefix, `unframe` returns `nil` (waiting for bytes that never come) while `DaemonChannel.start`'s `buffer` keeps `append`-ing every subsequent byte → unbounded memory / OOM. Authenticated SSH channel to the user's own daemon lowers the threat, but a buggy daemon is enough. **Fix:** cap `len` to a sane max (e.g. a few MB); on overflow, drop the frame and/or tear down the channel.

### [MINOR][reliability] `DaemonChannel.sendRPC` has no timeout — an alive-but-unresponsive daemon hangs the caller forever
`Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:66-91`
The continuation in `pendingRPC[id]` is resolved only by a matching response (`handleFrame`), a write failure, or `failPendingRPCs` (stream end / `stop()`). If the daemon is connected but never replies, `tailAudit`/`fetchPolicy`/`dispatchAgent`/etc. await indefinitely. **Fix:** add a per-RPC deadline that removes the pending entry and resumes with a timeout error.

### [MINOR][correctness] `AutoReconnectEngine` backoff + give-up logic is dead because `reportReconnectOutcome` is never called; `triggerWithRetry` would tight-loop if wired
`Packages/LancerKit/Sources/SSHTransport/AutoReconnectEngine.swift:76-89,126-141`; `SessionViewModel.startReconnectEngine` closure `:414-417`
`SessionViewModel.attemptReconnect` (the `onReconnect` body) never calls `reportReconnectOutcome(succeeded:)`, so `failureCount` stays 0 and `lastAttemptSucceeded` stays `false`. Effects: (1) exponential backoff (`triggerReconnect` only sleeps when `failureCount > 0`) never engages; (2) the `maxAttempts == 5` give-up / `onFailed` path never fires; (3) `triggerWithRetry()` (`while !stopped { triggerReconnect(); if lastAttemptSucceeded break }`) would become a **backoff-free infinite loop** — currently safe only because nothing calls it. The network-edge `runLoop` path is bounded by reachability transitions, so this is latent rather than active. **Fix:** call `reportReconnectOutcome` from the reconnect closure (or have the engine itself track success/failure), and never expose `triggerWithRetry` without that wiring.

### [MINOR][robustness] `PTYBridge` OSC/CSI accumulators are unbounded across chunks
`Packages/LancerKit/Sources/TerminalEngine/PTYBridge.swift:165-167,327-350,295-325`
`oscBody`/`csiBody` persist across chunks and only reset on a terminator/final byte. An unterminated OSC (no BEL/ST) or a long run of valid CSI param bytes (0x20–0x3f) with no final grows memory unbounded for the life of the connection. Bounded by what the remote sends. **Fix:** cap accumulator length and bail back to `.normal`, re-emitting buffered bytes, on overflow.

### [MINOR][edge-case] Alt-screen / bracketed-paste detection only matches within a single chunk
`Packages/LancerKit/Sources/TerminalEngine/PTYBridge.swift:222-252`
`scanAltScreen` uses `contains(chunk, subsequence:)` on each chunk in isolation. If `\e[?1049h`/`\e[?1049l`/`\e[?2004h` is split across TCP segments (8-byte sequence straddling a chunk boundary), the transition is missed → `onAltScreenEnter` never fires → `clearChunks` not called → the TUI renders onto a stale block snapshot. The OSC/CSI stripper handles cross-chunk state, but this scanner does not. **Fix:** scan against a small rolling tail (last ~8 bytes of the previous chunk prepended).

---

## NIT

### [NIT] `DaemonChannel` redundant `await` on synchronous same-actor calls (the `:36`/`:40` warning)
`Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:36,40` — `readTask` inherits the actor's isolation (`Task {}` is `@_inheritActorContext`), so `handleFrame`/`failPendingRPCs` are same-actor synchronous calls; the `await` is a no-op and triggers the "no async operations occur within 'await'" warning. Harmless; drop the `await` (or make the intent explicit). Confirms the prior-audit note — not a real cross-actor hop bug.

### [NIT] `DaemonChannel.sendRPC` write-failure path can double-resume in a pathological ordering
`Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:85-88` — the `catch` calls `cont.resume(throwing:)` unconditionally after `pendingRPC.removeValue`; if a response had already resumed+removed the same continuation (extremely unlikely since a failed write means no request was sent), this is a double-resume crash. **Fix:** only resume if `removeValue(forKey: id) != nil`.

### [NIT] `autoTrustHostKey` is a public, runtime-settable API with no `#if DEBUG` guard (PRIOR FLAG LOW-3 — not reachable in Release)
`Packages/LancerKit/Sources/SessionFeature/LiveTerminalView.swift:37,61,119-122,160,168` — default `false`; only `true` caller is `DebugTerminalHarness` (`#if DEBUG && os(iOS)`); `LiveTerminalModel`/`LiveTerminalView` are only instantiated by debug harnesses + gallery. No Release path sets it true, so the auto-trust branch is unreachable in Release. **Recommend** wrapping the parameter/branch in `#if DEBUG` (or `assert(!autoTrustHostKey)` in Release) for defense-in-depth so a future caller can't accidentally enable it.

### [NIT] `AnsiSGRParser.parse` finds the CSI final via `isLetter`, over-consuming CSI sequences with non-letter finals
`Packages/LancerKit/Sources/TerminalEngine/AnsiSGRParser.swift:50` — CSI final bytes span 0x40–0x7E (includes `@ [ \ ] ^ _ \` { | } ~`). Using `firstIndex(where: { $0.isLetter })` skips past non-letter finals and swallows following text as params until the next letter. Block-text cosmetic path only (the primary `PTYBridge` stripper handles finals correctly). **Fix:** terminate on the first byte in 0x40–0x7E.

### [NIT] `SSHSession.attemptReconnect` drops the old client without closing it
`Packages/LancerKit/Sources/SSHTransport/SSHSession.swift:135-147` — sets `client = nil` without `try? await client.close()`; the old Citadel client (and its socket) is retained by any in-flight PTY/exec task until that task ends, then released. Transient leak. **Fix:** close the old client before reconnecting.

### [NIT] `LocalPortForwardTunnel.isActive` is a non-atomic `Bool` mutated off the Network queue
`Packages/LancerKit/Sources/SSHTransport/PortForwardTunnel.swift:34,57,66,133` — written from the `NWListener` state handler (NW global queue) and from `start()`/`stop()` without synchronization while the type is `@unchecked Sendable`. Benign diagnostic flag; technically a data race. **Fix:** guard with the existing `Protected`/a lock, or make it an atomic.

---

## Items checked and found OK (adversarial pass, no defect)

- **Unified PTY is the single byte source.** Only `openUnifiedShell` opens an `SSHShell` for the live session; `activeShell` is just an alias of `unifiedShell` set during alt-screen/fallback (`SessionViewModel.swift:895`). No second `SSHShell` is spawned for raw mode. ✓ (CLAUDE.md §5 invariant holds.)
- **Block store concurrency.** `BlockRenderer` is `@MainActor @Observable`; every mutation (`append`, `setState`, `finalize`, `clearChunks`, live-handle map) happens on the main actor, and `SessionViewModel`'s PTY callbacks all hop to `Task { @MainActor … }` before touching it. No data race on the block store or live-grid maps. ✓
- **Retain cycles.** PTYBridge callbacks, `onResize`, `explain`'s `AsyncThrowingStream`, keepalive, reconnect-engine, and `ScenePhaseObserver` closures all use `[weak self]` (or are local streams with `onTermination { task.cancel() }`). No long-lived strong self capture found. ✓
- **Continuations.** `SSHSession.preResolveHost`, `requestShellChannel`/`requestExecChannel` (writer via `AsyncStream.first`), and `PortForwardTunnel` pumps each resume exactly once per path; no never-resume/double-resume except the pathological NIT-12. ✓
- **Command injection.** `TmuxClient` validates session names against `[A-Za-z0-9._-]` before interpolation (`TmuxClient.swift:30-72`); `SSHSession.loginShellWrap` POSIX-single-quote-escapes (`SSHSession.swift:197-202`). ✓
- **ANSI SGR bounds.** `SGRState.apply` guards all `codes[i+n]` indexing; `ansi16` clamps; `ansi256` has a default. No OOB. ✓
- **Block memory bounds.** `BlockRenderer.truncateOldestLinesIfNeeded` caps linear output at `maxLinearLines` and `enforceScrollbackLimit`/`trimToLatest` bound block count. ✓
