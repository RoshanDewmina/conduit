# Lancer Verification Commands

Choose checks by touched files.

## Pre-flight: disk space

Before any Xcode build, multi-repo clone, or parallel worktree build, check free disk space —
`/tmp` DerivedData and per-worktree build caches have independently caused 0-bytes-free and 67GB
DerivedData incidents at least 4 times:

```bash
df -h / /tmp
```

If free space is under ~15GB, clean stale caches before proceeding rather than mid-build:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Lancer-*
rm -rf /tmp/LancerDerivedData*
./scripts/check-worktree-sprawl.sh
```

## Physical device reinstall

Never reinstall a build onto a physical device with live paired/relay state without asking the
owner first — a fresh install silently wipes the stored pairing code, breaking connectivity until
manual re-pair.

## Swift Package

```bash
cd /Users/roshansilva/Documents/command-center/Packages/LancerKit
swift build
swift test
```

Use for quick LancerKit feedback. It does not replace app-target simulator builds for iOS-only UI.

## Xcode App Target

Use XcodeBuildMCP for iOS app target verification.

Required sequence in a fresh tool session:

1. `session_show_defaults`
2. If project, scheme, or simulator are missing, discover/set:
   - project: `/Users/roshansilva/Documents/command-center/Lancer.xcodeproj`
   - scheme: `Lancer`
   - simulator: an available iPhone simulator, commonly `iPhone 17 Pro`
3. Run `build_sim` or `build_run_sim`.

Reason: `swift build` can skip `#if os(iOS)` app code and miss strict-concurrency or SwiftUI issues.

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
