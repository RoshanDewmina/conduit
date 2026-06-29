# 00 — Executive Summary

**App:** Lancer — iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi)
running on the developer's own machines. TestFlight-shipped; the governed approval loop is proven
on a physical device.
**Audit date:** 2026-06-28 · **Scope:** Full engineering audit (architecture, Swift/concurrency,
security/privacy, testing/reliability, build/release). **UI/UX/design axis skipped per owner.**
**Mode:** report-first — no source changed yet; Phase B implementation is gated on owner approval.

## Overall assessment

**The codebase is healthy and close to its quality bar.** This is not a remediation job; it's a
short list of genuine, mostly-low-severity findings plus two Medium reliability/crash items worth
fixing before the next external RC.

- **Build:** app-target build (iPhone 17 Pro / iOS 27 sim, Xcode 27) **SUCCEEDED** with **one**
  warning (a slow-to-type-check view body). `swift test`: **462 tests / 77 suites, 0 failures**.
  `go test ./...` (lancerd): pass. No pre-existing failures were found or hidden.
- **Security:** strong and fail-closed — device-only Keychain, TOFU + BiometricGate, two-tier relay
  auth with constant-time compare and production fail-closed, compliant privacy manifest, no
  hardcoded secrets, thorough secret redaction. All debug/mock seams are `#if DEBUG`-gated.
- **Concurrency:** strict concurrency `complete`; every `@unchecked Sendable` justification holds up
  on inspection. One real runtime crash hazard (CONC-2) the compiler can't see.

## Highest-risk findings (all verified by reading the code)

1. **SEC-2 (Medium)** — Cold-launch relay-token hydration is fire-and-forget, so the backend-relay
   fast path reads an empty token and queues the decision instead of relaying it. The decision is
   not lost (DB+audit+SSH-drain+120s-timeout backstops), but the cold-launch optimisation it was
   built for is defeated on first attempt. A code comment even *asserts* this is safe — it isn't.
2. **CONC-2 (Medium)** — `DaemonChannel.sendRPC`'s write-failure `catch` resumes a checked
   continuation unconditionally; a simultaneous disconnect (`failPendingRPCs`) can resume it first →
   double-resume → **fatal crash**. The two triggers (write failure, session death) are correlated.
3. **TEST-01 / TEST-02 (Medium)** — No test covers the cold-launch approval forwarding path (the #1
   product gate) or the session-resume `runId` round-trip. These are the highest-value coverage gaps.

## Most important recommended actions (Phase B order)

1. Fix CONC-2 (one-line guard) + add the mid-RPC-cancel test — it's a crash.
2. Fix SEC-2 (make hydration `async`+awaited) + add TEST-01.
3. Add TEST-02 (resume `runId` validation), then the lower-severity items (ARCH-1 view-body
   extraction, CONC-1 task cancellation, SEC-1 deep-link tightening, BUILD-1 CI/Xcode alignment,
   style cleanups CQ-1..4).

## What was tested / what was not

- **Tested:** full repo read; app-target + SwiftPM + Go builds and test suites; 5 parallel
  read-only review passes (arch, concurrency, security, testing, build) each independently
  verified; targeted code-reads of the two headline findings; dependency provenance; Claude-config
  secret exposure.
- **Not tested (out of scope or needs hardware/backend):** UI/UX/design/screenshots/accessibility
  (skipped per owner); real-device energy/thermal/GPU performance; live end-to-end relay loop on
  device; App Review metadata. No runtime performance hotspot surfaced, so no Instruments profiling
  was warranted (see 05).

## Release-readiness judgment

**Ship-capable today; recommend landing CONC-2 and SEC-2 (+ their tests) before the next external
RC.** No Critical or High findings. The two Medium items are a latent crash on a network-edge race
and a cold-launch reliability regression — both low-effort, high-confidence fixes.

See `08-findings-register.md` for the full table and `09-change-log.md` (Phase B) for implementation
tracking. **Three originally-suspected bugs were disproved on inspection** (two "crash" force-ops
are guarded; the "stale URL" is intentional live infra) — recorded as VERIFIED-SAFE.
