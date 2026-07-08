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

### Migration to /Volumes/LancerDev

The repo is migrating build/tmp caches off the internal disk onto `/Volumes/LancerDev` — set these
once that volume is mounted, so Xcode/tooling stop writing gigabytes of DerivedData back onto the
internal SSD:

```bash
export LANCER_DERIVED_DATA=/Volumes/LancerDev/lancer-tmp/DerivedData
export TMPDIR=/Volumes/LancerDev/lancer-tmp/
```

`LANCER_DERIVED_DATA` is a convention for this repo's tooling/scripts, not an Xcode-recognized env
var by itself — point Xcode's actual DerivedData location there via **Settings → Locations →
Derived Data → Custom**, or `-derivedDataPath "$LANCER_DERIVED_DATA"` on any `xcodebuild`
invocation, so the two stay in sync. Until `/Volumes/LancerDev` exists, `check-disk-budget.sh`
falls back to its defaults (internal disk, `~/Library/Developer/Xcode/DerivedData`) and will flag
every current worktree as outside the approved root — that is expected pre-migration, not a script
bug.

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

Use XcodeBuildMCP for iOS app target verification.

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
