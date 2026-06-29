# 06 — Testing & Reliability

## Baseline (measured)
- `swift test` (LancerKit): **462 tests / 77 suites, 0 failures**, ~31s wall.
- `go test ./...` (lancerd + policy): pass.
- App-target build: SUCCEEDED, 1 warning, 0 errors.
- XCUITest: **only 2 files** (`HomeButtonTapTests`, `TapInjectionProofTests`) for a TestFlight app.

## Coverage by critical workflow (not by %)

| Workflow | Unit happy-path | Error/edge paths | Verdict |
|---|---|---|---|
| Governed approval loop | partial (`ApprovalRelayBackendTests` = JSON body) | **gap** — no cold-launch empty-token / 401 / queue-then-drain | **TEST-01 (Medium)** |
| Device pairing / TOFU | good (`HostKeyStoreTests`) | minor — no TOCTOU / Keychain-error injection | adequate |
| Session resume / follow-up | argv only (`AgentResumeBuilderTests`) | **gap** — no `runId` round-trip / malformed-runId | **TEST-02 (Medium)** |
| Offline approval queue | minimal (`OpenApprovalBufferTests`) | gap — memory-only queue, no crash-persistence (TEST-04) | adequate w/ backstop |
| SSH lifecycle | good (`ReconnectTests`, `ErrorMappingTests`, `HostServiceClientTests`) | no integration / network-handoff | adequate (unit) |
| Secret redaction | strong (`RedactorTests`, 19 cases) | no perf/DoS case | adequate |

## Test-quality red flags
- **TEST-03 (Low):** fixed `Task.sleep`/`usleep` waits instead of poll-until — `ReconnectTests.swift:
  111-114`, `TapInjectionProofTests.swift:47,71,136,142,218`. Flaky risk under CI load.
- A couple of tests seed with real `Date()` (e.g. watch transfer) — low risk, no injected clock.

## Recommended new tests (Phase B, paired with the fixes)
1. **TEST-01** — cold-launch forward populates the Bearer header before POST (asserts SEC-2 fix;
   in-memory `Keychain` seeded, mock URLSession verifies header). Highest value.
2. **CONC-2 regression** — cancel a session mid-`sendRPC`; assert no double-resume fatal.
3. **TEST-02** — `continueRun` parses a valid `runId`; rejects empty/malformed with a typed error.
4. Convert TEST-03 fixed sleeps to bounded polling.

## XCUITest gap (informational)
Core journeys with zero UI automation: session resume, offline queue drain, terminal interaction,
lock-screen approval tap, watch sync, error states. Adding these is valuable but is a larger,
separate effort — **not** bundled into the fix batches above. Recommend one cold-launch-approval
XCUITest as the first addition when UI work resumes.

Do not chase a coverage percentage — the gaps that matter are the approval loop and resume paths
above.
