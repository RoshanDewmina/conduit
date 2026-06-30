# Lancer Cleanup Report — 2026-06-27

Branch: `cleanup/lean-sweep` from cached `origin/master` / `7816286a`.

`git fetch origin` failed before and after the sweep with:

```text
fatal: could not read Username for 'https://github.com': Device not configured
```

So the branch could not be refreshed from GitHub, pushed, opened as a PR, or merged from this machine.

## What Was Removed

### Swift / iOS

- Removed the dead `WorktreesFeature` SPM target/product and all source files:
  - `WorktreesBoardView.swift`
  - `NewWorktreeView.swift`
  - `WorktreeConflictsView.swift`
- Removed zero-reachability AppFeature files not covered by guardrails:
  - `RunnerSetupView.swift`
  - `EditScheduleSheet.swift`
  - `LoopDetailView.swift`
  - `GitStore.swift`
- Removed unused Swift code surfaced by Periphery/reachability:
  - `LancerApp.pushBackendURL`
  - `FleetView.ciEventLoader(for:)`
  - `FleetView.gitStore(for:)`
- Removed pre-rebrand local fallback shims:
  - `HostServiceClient` no longer falls back to `~/.conduit/conduitd.sock` or `~/.conduit/ipc-token`.
  - StoreKit config and purchase token keys now use Lancer naming / `dev.lancer.mobile.pro`.
- Updated `scripts/relay-regression.sh` away from the deleted gallery path to the current
  `LANCER_DAEMON_E2E=1` + `LANCER_DESTINATION=sessions` seam.
- Deleted the one-time `scripts/rebrand-lancer.py` migration script.

### Go

- `daemon/lancerd`: removed unreachable agent-status helpers, stale secret helpers, quota wrapper,
  policy path helper, and audit helper flagged by `deadcode`.
- `daemon/push-backend`: removed unreachable GCS upload helper, customer/app-token entitlement wrapper,
  Live Activity end sender, and unused `jsonFileStore` wrapper.

### Docs / Local Clutter

- Archived tab/gallery-era or superseded docs into `docs/_archive/`:
  - `docs/design-handoff/PAGES.md`
  - `docs/design-handoff/BACKEND_COVERAGE.md`
  - `docs/PRODUCTION_READINESS_PLAN.md`
  - root `ship-plan/`
  - stale UI audit boards, screenshot bundles, dated implementation handoffs, and dead plans under
    `docs/_archive/stale-ui-audits-2026-06-27/`
- Updated active docs and agent rules to the current sidebar / Command Home / seeded real-app seams.
- Removed empty directories in the main worktree. Current empty-dir scan is clean excluding build/worktree caches.

## Counts

- Non-archive code/doc diff: `45 files changed, 118 insertions(+), 2294 deletions(-)`.
- Tracked archive moves: `388` renames into `docs/_archive/`.
- Direct compiled Swift removals: 8 Swift files plus 1 SPM target/product.
- Direct compiled Go removals: 3 files plus unreachable helpers in 6 Go files.

## Retained By Guardrail

- V2 hosted-cloud UI retained: `ProviderDetailView`, `HostedProvisioningView`,
  `HostedRunnerStatusView`, `SelfHostVsHostedView`.
- Hosted execution / `agent-runner` multi-cloud depth retained.
- SSH / legacy transport retained: `lancerd serve`, `DaemonChannel`, `RawTerminalView`,
  `LiveTerminalView`, and the dormant `isRaw` escalation path.
- DEBUG and test seams retained: `LANCER_DESTINATION`, `LANCER_SEED_DEMO`,
  `LANCER_FAKE_RELAY_HOST`, `LANCER_DAEMON_E2E`, `LANCER_TEST_*`.
- `MockAIClient` retained as an exported AgentKit mock/test utility even though it has no app-target
  references.

## Uncertain / Owner Decision

- Dirty external worktrees were not deleted because they contain other agents' or owner work:
  - `.claude/worktrees/agent-a37edf612c97bb881`
  - `.claude/worktrees/agent-a3ec76299d167e51d`
  - `.claude/worktrees/agent-a5ae960112e1bee2a`
  - `.claude/worktrees/agent-a5f8044b9495e8828`
  - `.claude/worktrees/agent-ab6add8e9e4f0ecdc`
  - `.worktrees/audit-pre-launch-cleanup`
- Governance "Verify chain" remains client-side ordering/count verification only. I did not wire
  daemon-side verification in this cleanup pass because that is correctness work with a larger contract
  surface, not a low-risk deletion.
- SwiftPM-specific Periphery scanning remained blocked by package/index-store target mismatch, so the
  authoritative Swift detector used here was the app-target Periphery scan plus reachability grep and
  build-gated removals.

## Tooling Results

- Periphery app-target scan:

```text
periphery scan --project Lancer.xcodeproj --schemes Lancer --targets Lancer --format xcode --disable-update-check
* No unused code detected.
```

- Go deadcode:

```text
cd daemon/{lancerd,push-backend,lancer-mcp,agent-runner}
go build ./... && go vet ./... && go test ./... && ~/go/bin/deadcode -test ./...

lancerd: ok
push-backend: ok
lancer-mcp: ok (no test files)
agent-runner: ok
deadcode: no remaining output
```

- Rebrand code sweep:

```text
rg "Conduit|conduit|CONDUIT_" Packages Lancer daemon scripts project.yml
```

Remaining hits are deliberate live infrastructure URLs/buckets, deployment docs, or the stale-hook
test fixture that verifies old hook commands are not treated as wired.

## Final Gate

- `cd Packages/LancerKit && swift build && swift test`
  - Build succeeded.
  - `449` Swift Testing tests in `75` suites passed.
  - `13` HostControlKit tests in `2` suites passed.
  - `8` XCTest tests passed.
- XcodeBuildMCP app-target build:
  - `build_sim` for `Lancer.xcodeproj`, scheme `Lancer`, `iPhone 17 Pro`, Debug, `/tmp/lancer-dd`
  - `SUCCEEDED`
  - One known warning remains: `AppRoot.mainBody` took `400ms` to type-check.
- Go full gate:
  - `daemon/lancerd`: `go build`, `go vet`, `go test`, `deadcode` passed.
  - `daemon/push-backend`: `go build`, `go vet`, `go test`, `deadcode` passed.
  - `daemon/lancer-mcp`: `go build`, `go vet`, `go test`, `deadcode` passed.
  - `daemon/agent-runner`: `go build`, `go vet`, `go test`, `deadcode` passed.
- Empty directory scan:
  - clean for the main tree, excluding build outputs and external worktrees.

## Not Completed

- Could not push, open a PR, merge, prune GitHub-backed worktrees, or re-fetch final `master` because
  GitHub HTTPS auth is unavailable in this environment.
