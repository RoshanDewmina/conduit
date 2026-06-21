# Conduit Verification Commands

Choose checks by touched files.

## Swift Package

```bash
cd /Users/roshansilva/Documents/command-center/Packages/ConduitKit
swift build
swift test
```

Use for quick ConduitKit feedback. It does not replace app-target simulator builds for iOS-only UI.

## Xcode App Target

Use XcodeBuildMCP for iOS app target verification.

Required sequence in a fresh tool session:

1. `session_show_defaults`
2. If project, scheme, or simulator are missing, discover/set:
   - project: `/Users/roshansilva/Documents/command-center/Conduit.xcodeproj`
   - scheme: `Conduit`
   - simulator: an available iPhone simulator, commonly `iPhone 17 Pro`
3. Run `build_sim` or `build_run_sim`.

Reason: `swift build` can skip `#if os(iOS)` app code and miss strict-concurrency or SwiftUI issues.

## Go Daemon

Run from the module directory:

```bash
cd /Users/roshansilva/Documents/command-center/daemon/conduitd
go build -o conduitd .
go test ./...
```

Do not use `go test ./daemon/conduitd/...` from the repo root unless the module layout changes. Historical docs may show that form, but current local verification should run from `daemon/conduitd`.

## Hook And Resident Bridge

Use when hook, approval, conduitd resident socket, audit tail, or Inbox approval flow changed.

```bash
cd /Users/roshansilva/Documents/command-center
chmod +x scripts/validation/validate-hook-flow.sh
CONDUITD_BINARY=./daemon/conduitd/conduitd \
HOOK_SCRIPT=./docs/conduit-hook.sh \
./scripts/validation/validate-hook-flow.sh
```

```bash
cd /Users/roshansilva/Documents/command-center/daemon/conduitd
go build -o conduitd .
CONDUITD_BINARY=./conduitd ../../scripts/validation/resident-bridge-smoke.sh
```

Local SSH fixture for simulator testing:

```bash
cd /Users/roshansilva/Documents/command-center
chmod +x scripts/validation/local-sshd-fixture.sh
./scripts/validation/local-sshd-fixture.sh
```

Manual approval-loop checks in `docs/validation-playbook.md` require Conduit iOS running and a live host. Do not mark them complete from automated tests alone.

## Vendor Adapter Checks

For adapter changes, also run local help/version checks from `$vendor-cli-adapter-audit`, then daemon tests:

```bash
claude --version
codex --version
opencode --version
kimi --version
cd /Users/roshansilva/Documents/command-center/daemon/conduitd && go test ./...
```

Also run `go build -o conduitd .` if the adapter code changed.

## Design Board

Distinguish:

- repo migration board: `/Users/roshansilva/Documents/command-center/docs/audit/migration-board/index.html`
- exported interactive board: `/Users/roshansilva/Downloads/Conduit GitHub repo/Conduit Board.dc.html`

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
