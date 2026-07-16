# Oracle matrix — risk class → verification bar

Pick the **lowest** oracle that still falsifies the claim. Escalate when a lower oracle passes but user-facing risk remains.

When a change spans multiple rows, run the **union** of the applicable gates. A lower-risk row never cancels a higher-risk requirement.

## Stack (weakest → strongest)

```text
lancer-verification-gate (swift/go/MCP build)
  → Simurgh lease + sim live-loop (pair to live lancerd, drive real flow)
    → XCUITest harness (automated UI path)
      → audit.log (daemon governance trail)
        → physical device 5c (Tier 0 / lock-screen / APNs)
```

## Matrix

| Risk class | Touched areas | Minimum oracle | Stronger when |
|------------|---------------|----------------|---------------|
| **LancerKit-only logic** | `Packages/LancerKit`, no `#if os(iOS)` UI | `swift build` + targeted `swift test` | Behavior spans modules → full `swift test` pre-merge |
| **iOS UI / shell** | AppFeature, DesignSystem, Workspaces, composer | XcodeBuildMCP app-target build | User-facing flow → sim live-loop |
| **Composer / send / streaming** | ShellLiveBridge, dispatch callbacks | Sim live-loop: send → stream → follow-up | Add XCUITest if AX ids stable |
| **Approvals / inbox** | InboxFeature, review sheet | Sim live-loop: approval → `decide()` | Lock-screen path → device 5c |
| **Relay / reconnect** | E2ERelay, generation guard | XCUITest reconnect suite (e.g. 10×) | Physical device re-proof after sim PASS |
| **Daemon / dispatch** | `daemon/lancerd`, `dispatch.go` | `go test ./...` from `daemon/lancerd` | + `vendor-cli-adapter-audit`; live dispatch on sim |
| **Policy / audit / security** | policy engine, hooks, hashes | `go test` + adversarial review (2×) + owner/human sign-off | `audit.log` excerpt in evidence |
| **Pairing / TOFU** | relay pairing, trusted machines | Sim pair once; **never** orphan owner phone | Device re-pair owner-gated |
| **Publish / Tier 0** | governed loop end-to-end | Physical device 5c per `LIVE_LOOP_RUNBOOK` + owner sign-off | Historical PASS on old tip ≠ current tip |
| **Publish miss-scan** | roadmap / backlog | Regenerate `docs/product/2026-07-15-publish-oracle-audit.md` from SSOT | — |

## Simurgh rules

- Always `lease_acquire` / `lease_release` — never pick UDID from raw `simctl`.
- Sim pairing orphans the single relay slot; re-pair phone after sim work (`AGENTS.md`).
- Session-bound lease default; no `detach=true` unless deliberate.

## Sim oracle pilot (tool completeness test)

Scorecard template for "fix a real bug on sim" — run only when owner greenlights:

| Step | Tool / skill | Pass? | Notes |
|------|--------------|-------|-------|
| 1 | Simurgh `lease_acquire` | | |
| 2 | Pick reproducible bug | | |
| 3 | Lancer on sim → live `lancerd` → fix | | |
| 4 | `audit.log` + screenshot/UITest | | |
| 5 | Risk-tiered independent review with context | | high-risk pilot requires 2× + owner sign-off |
| 6 | `lease_release` | | |
| 7 | Missing MCP/skills logged | | feeds this matrix |

**Execution gate:** do not run until the owner approves live execution and Simurgh MCP is available in the active session.

## Evidence path

Behavioral/high-risk live, device, security, and publish oracle runs → `docs/test-runs/<date>-<slug>/` with `README.md` listing commands, results, and artifact paths. Routine build/test checks may remain in the task or PR.
