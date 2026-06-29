# 09 — Change Log (Phase B implementation)

**Status: NOT STARTED — gated on owner approval.** No source has been modified by this audit.
Phase B lands on a dedicated branch `audit/ios-2026-06-28` (preserving the pre-existing uncommitted
`daemon/lancerd/install.sh` and `docs/KNOWN_ISSUES.md` changes).

Each batch is build- + test-verified before the next. Verification gate per batch:
- XcodeBuildMCP `build_sim` of the **Lancer app target** (catches `#if os(iOS)` code),
- `swift test` in `Packages/LancerKit`, `go test ./...` in `daemon/lancerd`,
- review the full `git diff`; no new warnings.

## Planned batches (proposed order)

| Batch | Findings | Files | Risk |
|---|---|---|---|
| B1 — crash fix | CONC-2 | `SSHTransport/DaemonChannel.swift` (+ test) | Low (one-line guard) |
| B2 — cold-launch reliability | SEC-2 / TEST-01 | `SessionFeature/ApprovalRelay.swift` (+ test) | Low–Med (make hydration async/awaited) |
| B3 — resume coverage | TEST-02 | `SessionFeature/RunControlStore` (+ test) | Low (test + typed error) |
| B4 — concurrency hygiene | CONC-1 | `SessionFeature/SessionViewModel.swift` | Low (store+cancel task) |
| B5 — build/CI + style | BUILD-1, CQ-1, CQ-2, CQ-3, CQ-4 | `.github/workflows/ci.yml`, `SettingsView.swift`, `DSButton.swift`, `AppRoot.swift` | Low |
| B6 — deep-link hardening | SEC-1 | `Lancer/LancerApp.swift` | Low |

Deferred (note only, not in scope): ARCH notification/DI refactors, `AppEnvironment` split, XCUITest
journey build-out, device-based performance pass, BUILD-2 self-host decision.

> Entries below are filled in as each batch lands (files changed · reason · tests · verification
> output · remaining risk). Empty until Phase B begins.
