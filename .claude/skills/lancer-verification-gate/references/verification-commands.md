# Lancer Verification Commands

Choose checks by touched files.

## Pre-flight: disk space

Before any Xcode build, multi-repo clone, or parallel worktree build, check free disk space —
`/tmp` DerivedData and per-worktree build caches have independently caused 0-bytes-free and 67GB
DerivedData incidents at least 4 times:

```bash
df -h / /tmp
./scripts/check-disk-budget.sh
```

`check-disk-budget.sh` fails (exit 1) if free space drops below 20GB, `Lancer-*` DerivedData
exceeds 15GB, or a worktree lives outside the approved `/Volumes/LancerDev/worktrees/` root — it
lists branch + merge status per offending worktree and never deletes anything itself.

If free space is under ~15GB, clean stale caches before proceeding rather than mid-build:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Lancer-*
rm -rf /tmp/LancerDerivedData*
./scripts/check-worktree-sprawl.sh
```

### Migration to /Volumes/LancerDev (done 2026-07-18)

`/Volumes/LancerDev` is mounted (APFS, 2TB external SSD, USB). Xcode's global DerivedData location
is now set to `/Volumes/LancerDev/lancer-tmp/DerivedData` via `defaults write com.apple.dt.Xcode
IDECustomDerivedDataLocation` (Settings → Locations → Derived Data → Custom shows the same value).
`-derivedDataPath "$LANCER_DERIVED_DATA"` on a raw `xcodebuild` invocation still overrides it
per-command if needed. All Lancer/Simurgh/Momentum worktrees live under
`/Volumes/LancerDev/worktrees/<project>/` — `check-disk-budget.sh` should PASS with no `WORKTREE_ROOT`
override needed.

**Do not set `TMPDIR` to a path on this volume.** macOS caps Unix-domain-socket paths at ~104 bytes,
and both `lancerd` and Simurgh's lease sockets live under `TMPDIR`/`HOME`-relative paths — a long
external `TMPDIR` risks silently breaking those. Leave `TMPDIR` as the system default; only
DerivedData (file-based, no socket path-length concern) moves to the SSD.

One accepted exception `check-disk-budget.sh` will always flag: three detached-HEAD scratch
worktrees under `simurgh/.claude/worktrees/benchmark-blockers-2026-07-13-37773c/bench/results/`
are command-center worktrees nested inside a Simurgh benchmark-run directory. They're harmless
archived checkouts of an already-merged commit (not unique work), but moving the parent Simurgh
worktree would break their internal gitdir links, so they're left in place intentionally.

## Physical device reinstall

Never reinstall a build onto a physical device with live paired/relay state without asking the
owner first — a fresh install silently wipes the stored pairing code, breaking connectivity until
manual re-pair.

## Swift Package

```bash
cd /Users/roshansilva/Documents/command-center/Packages/LancerKit
swift build
swift test --filter <SuiteOrTestName>
```

Scope `swift test` to the suite(s) covering the touched module during day-to-day iteration —
`--filter` takes a regex (`swift test --help`); `--skip <regex>` excludes known-flaky suites
instead of skipping the whole run. Run the full, unfiltered `swift test` once before merge/PR,
not on every iteration — the full LancerKit suite is 91 test files and most changes only touch one
or two of them. Do not add `--no-parallel` locally: that flag exists only because CI's small-core
runners deadlock under Swift Testing's concurrent scheduling (see `.github/workflows/ci.yml`); a
dev Mac doesn't have that constraint and `--no-parallel` just makes local runs slower.

Use for quick LancerKit feedback. It does not replace app-target simulator builds for iOS-only UI.

## Xcode App Target

**Simulator routing (required):** call Simurgh MCP `pool_status`, then `lease_acquire`
before any simulator/XcodeBuildMCP work. Route every `xcodebuild` through
`simurgh exec <lease-id> -- …` (or work inside `simurgh shell <lease-id>` for
manual steps, still using `exec` for long builds). Never pick a booted simulator
UDID from `simctl list`. Release the lease when done (`lease_release`).

Use XcodeBuildMCP for iOS app target verification (with the per-lease adapter:
`simurgh integration xcodebuildmcp start --session <lease-id>`).

Required sequence in a fresh tool session:

1. `session_show_defaults`
2. If project, scheme, or simulator are missing, discover/set:
   - project: `/Users/roshansilva/Documents/command-center/Lancer.xcodeproj`
   - scheme: `Lancer`
   - simulator: an available iPhone simulator, commonly `iPhone 17 Pro`
3. For a build-only check, run `build_sim` or `build_run_sim`.
4. For a change with UI/behavior logic worth testing, run `test_sim` instead of a build-only
   check, scoped to the touched screen's test class via
   `extraArgs: ["-only-testing:LancerUITests/<TouchedClass>"]` (repeat the flag per class/method).
   `test_sim` has no dedicated "only run these tests" parameter — `-only-testing:`/`-skip-testing:`
   inside `extraArgs` is the mechanism, same syntax as raw `xcodebuild`. Run the full
   `LancerUITests` target only before merge/PR; it is not in CI today and a full run is
   comparatively expensive — scope to what the change touched for iteration.

Reason: `swift build` can skip `#if os(iOS)` app code and miss strict-concurrency or SwiftUI
issues. A build-only check (`build_sim`) also misses runtime/UI regressions that only a real test
run catches — prefer `test_sim` scoped to the touched area whenever the change has testable
behavior, not just a build check.

## Go Daemon

Run from the module directory:

```bash
cd /Users/roshansilva/Documents/command-center/daemon/lancerd
go build -o lancerd .
go test ./...
```

Do not use `go test ./daemon/lancerd/...` from the repo root unless the module layout changes. Historical docs may show that form, but current local verification should run from `daemon/lancerd`.

## Hook And Resident Bridge

Use when hook, approval, lancerd resident socket, audit tail, or Inbox approval flow changed.

```bash
cd /Users/roshansilva/Documents/command-center
chmod +x scripts/validation/validate-hook-flow.sh
LANCERD_BINARY=./daemon/lancerd/lancerd \
HOOK_SCRIPT=./docs/lancer-hook.sh \
./scripts/validation/validate-hook-flow.sh
```

```bash
cd /Users/roshansilva/Documents/command-center/daemon/lancerd
go build -o lancerd .
LANCERD_BINARY=./lancerd ../../scripts/validation/resident-bridge-smoke.sh
```

Local SSH fixture for simulator testing:

```bash
cd /Users/roshansilva/Documents/command-center
chmod +x scripts/validation/local-sshd-fixture.sh
./scripts/validation/local-sshd-fixture.sh
```

Manual approval-loop checks in `docs/validation-playbook.md` require Lancer iOS running and a live host. Do not mark them complete from automated tests alone.

## Vendor Adapter Checks

For adapter changes, also run local help/version checks from `$vendor-cli-adapter-audit`, then daemon tests:

```bash
claude --version
codex --version
opencode --version
kimi --version
cd /Users/roshansilva/Documents/command-center/daemon/lancerd && go test ./...
```

Also run `go build -o lancerd .` if the adapter code changed.

## Design Board

Distinguish:

- feature backlog (canonical IA/scope): `docs/product/FEATURE_BACKLOG.md`
- exported interactive board: `/Users/roshansilva/Downloads/Lancer GitHub repo/Lancer Board.dc.html`

Verification must inspect the rendered result after hydration. Use browser automation, DOM text checks, and screenshots as needed.

## Reporting Template

```text
Verification:
- SwiftPM: <pass/fail/skipped and command>
- Xcode app target: <pass/fail/skipped and tool>
- Go daemon: <pass/fail/skipped and command>
- Hook/resident bridge: <pass/fail/skipped and command>
- Board/browser: <pass/fail/skipped and method>
- Owner-gated release items: <APNs/TestFlight/DNS/etc. status>
- Warnings: <important warnings>
```
