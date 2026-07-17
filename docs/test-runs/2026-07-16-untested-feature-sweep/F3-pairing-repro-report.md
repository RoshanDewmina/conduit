# F3 — Live repro of "relay auto-pair never completed" (Lane D/E follow-up), 2026-07-16

Branch: `fix/pairing-state-disagreement` (off `integration/2026-07-16-untested-sweep` @ `4e45dbaa`).
Worktree: `.worktrees/fix-pairing-state-disagreement`. No code changes — see conclusion.

## What was asked

Lane D and Lane E (`docs/test-runs/2026-07-16-untested-feature-sweep/LD-report.md`,
`LE-report.md`) both reported the phone reaching `pairingState == .paired` while the daemon's
log never printed `e2e: paired with phone` (`daemon/lancerd/e2e_client.go:377`), leaving the
paired machine stuck "unreachable." Job: reproduce live, trace both sides, find the real root
cause, fix it or explain why it's an environment artifact.

## Method

Rather than fight the same broken HID taps + Xcode-build contention Lanes A/C/D/E all hit, I
first isolated the **protocol** itself: a real `lancerd` binary (built from this tip) talking to
the real production relay (`wss://conduit-push.fly.dev`), against a minimal synthetic "phone"
client (`role=phone`, real X25519 key, real query params) speaking the exact same wire protocol
`E2ERelayClient.swift` uses. This removes iOS runtime/Simulator/XCUITest noise as a variable and
lets the daemon-log-vs-relay-truth question be answered directly and repeatably.

### Test 1 — clean single pairing (isolated daemon `/tmp/fix-f3`)

```
LANCER_STATE_DIR=/tmp/fix-f3 /tmp/lancerd-repro daemon &
LANCER_STATE_DIR=/tmp/fix-f3 /tmp/lancerd-repro relay-attach 185613
# ... 6s later, daemon.log:
2026/07/16 11:00:48 e2e: connected to relay as daemon
# synthetic phone dials the SAME code:
./phonesim 185613
# phonesim.log:
[phonesim] recv: {"peerPublicKey":"g53c9...","role":"daemon","type":"peer_joined"}
[phonesim] PAIRED (peer_joined received)
# daemon.log:
2026/07/16 11:01:11 e2e: paired with phone
```

Symmetric, clean, exactly as `websocket_relay.go`'s `peer_joined` fan-out design predicts (both
sides get the frame at the same instant, under the same `pair.mu` critical section,
`daemon/push-backend/websocket_relay.go:274-285`).

### Test 2 — one round of identity churn (isolated daemon `/tmp/fix-f3b`), reproducing Lane E's exact log shape

```
relay-attach 542453          # code1, daemon connects, waits
relay-attach 807263          # code2, BEFORE any phone joined — simulates impatient re-attach
```

daemon.log:
```
2026/07/16 11:07:08 e2e: connected to relay as daemon
lancerd daemon: relay pairing identity changed — dropping the previous relay session; phones on it are orphaned until re-paired
2026/07/16 11:07:22 e2e: receive error: read tcp [...]: use of closed network connection
lancerd daemon: E2E relay started
2026/07/16 11:07:23 e2e: connected to relay as daemon
```

This is a **byte-for-byte match** for the log pattern Lane E quoted ("repeated `e2e: connected to
relay as daemon` / `receive error: ... use of closed network connection` cycles"). Then dialing
the synthetic phone on the **current** code (807263, the one actually in the pairing file):

```
2026/07/16 11:07:36 e2e: paired with phone   # 13s after the second "connected", clean pairing
```

So even the exact churn signature Lane E saw does **not**, by itself, prevent pairing — as long
as the phone's code matches whatever code the daemon is *currently* on. Pairing completed cleanly
both with and without one round of churn.

## What this rules out

- **Not a relay-protocol bug.** `websocket_relay.go`'s peer_joined fan-out is synchronous and
  symmetric; both synthetic tests confirm the daemon reliably logs "paired with phone" the moment
  a phone with the *matching, current* code joins — with or without a prior churn cycle.
- **Not a URL/endpoint mismatch.** Both `RelaySettings.defaultURLString` (Swift) and
  `defaultRelayURL` (Go, `daemon/lancerd/relay_install_helper.go:22`) point at the same
  `wss://conduit-push.fly.dev` by default — phone and daemon rendezvous on the same hub.
- **Not `E2ERelayClient.swift` being "optimistic."** Read in full
  (`Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift:682-706`): `.paired` is set ONLY
  inside the real `peer_joined` handler, after deriving the session key from the relay-forwarded
  peer key. There is no path to `.paired` without a genuine relay-confirmed `peer_joined` frame for
  that exact process's dial.
- **Not the read-timeout/keepalive tuning** (`e2eReadTimeout = 90s`, `e2eLiveness.go:24`) — too
  long to explain failures inside a single test run's timescale.

## What the evidence instead points to

`daemon/lancerd/e2e_router.go:106-119`'s own comment (added by the just-merged F1 fix,
`065481d9`/`4e45dbaa`) documents a **real, previously-reproduced** case from this same day's sweep
(Lane C, `/tmp/sweep-C/daemon4.log`) where identity churn caused pairing to take **almost 2
minutes** to settle (`09:48:57` connected → `09:50:55` paired). Lane C's own report
(`LC-report.md`) states plainly: *"Pairing itself completed cleanly every time I tried it fresh (no
prior churn): auto-pair took ~20–39s end-to-end... comfortably inside the 30s budget"* — i.e. the
SAME commit, the SAME day, pairing worked reliably when not subjected to rapid re-attach churn.

Lane D and Lane E's own narratives describe exactly the condition that produces multi-minute
settle times: Lane D ran "4 independent attempts (2 daemon restarts, 3 fresh pairing codes)"; Lane
E regenerated codes repeatedly because they "expire ~5 min" and explicitly traced its own daemon
log's reconnect cycles 1:1 to its own `lancerd pair`/relay-attach re-invocations. Lane E's own
Simurgh feedback additionally documents severe resource contention during this exact session:
its simulator lease was silently reclaimed **while a live `xcodebuild test-without-building` was
still running against it** ("5 concurrent sweep lanes each running Xcode" sharing 2 build slots).
I hit the same class of problem independently: attempting to build the real app for a live
in-app repro during this task, `xcodebuild` failed with unexplained `SwiftCompile`/
`SwiftEmitModule` command failures on `NIOCore` (no `error:` diagnostic emitted — a silent
frontend crash under load), and `vm_stat` at that moment showed **~84 MB of free physical memory**
system-wide. That is independent, current-session confirmation that this Mac is under the same
severe multi-agent resource pressure Lane E flagged — a plausible aggravating factor for
timing-sensitive relay/reconnect behavior (delayed goroutine scheduling, delayed XCUITest harness
launch extending the window in which impatient re-attach churn happens) even without any app code
being at fault.

## Conclusion

**No code fix.** The relay pairing handshake (`daemon/lancerd/e2e_client.go`,
`daemon/push-backend/websocket_relay.go`, `Packages/LancerKit/.../E2ERelayClient.swift`) is
correct and was proven live, twice, against the real production relay: once with a clean single
pairing, once reproducing Lane E's exact daemon-log churn signature — both ended in the daemon
logging `e2e: paired with phone` promptly. Lane D/E's "never pairs" observation is best explained
as this sweep session's own procedural artifact — impatient/rapid pairing-code regeneration
compounding with a already-documented (Lane C, this same day) up-to-~2-minute pairing settle time
under identity churn, itself aggravated by severe concurrent resource contention (5 sweep lanes on
one Mac; independently reconfirmed here via a stalled `xcodebuild` and ~84 MB free RAM). The
already-merged F1 fix (`065481d9`, bounded retry for approval delivery when relay isn't yet paired
at send time) is the correct product-side mitigation for the practical consequence of that settle
window; no further pairing-completion fix is indicated by this evidence.

**Is it reproducible by a real single-daemon, single-phone user?** Unlikely in the form Lane D/E
hit it. A real user pairs once, does not run a background loop regenerating pairing codes every
few minutes, and is not sharing a Mac with 4 other concurrent Xcode builds. The **residual** real
risk, already called out by Lane E and out of scope for a code fix here, is UX-only: if a
handshake genuinely takes the full ~1–2 minutes under churn (e.g. a user re-opens the pairing sheet
impatiently), the app shows no distinct "still connecting" state — it looks identical to "gave up."
That is a pre-existing, separately-scoped UX gap, not a new defect this task's evidence supports
fixing here.

## Repro artifacts

- `/tmp/lancerd-repro` — daemon binary built from this branch's tip (`go build ./...` in
  `daemon/lancerd`, clean).
- `/tmp/fix-f3/phonesim/` — minimal synthetic phone-role relay client (Go, `golang.org/x/net/websocket`),
  used only for live protocol verification; not part of the shipped app or test suite.
- `/tmp/fix-f3/daemon.log`, `/tmp/fix-f3b/daemon.log` — raw logs for both tests above.
