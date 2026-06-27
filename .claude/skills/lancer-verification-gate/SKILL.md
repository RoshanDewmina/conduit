---
name: lancer-verification-gate
description: Use before calling Lancer work done, after Lancer code edits, when reviewing worker output, when diagnosing build/test failures, or when the user asks to verify Swift, Go daemon, iOS app-target, relay, or design-board behavior.
---

# Lancer Verification Gate

## Overview

Use this skill to choose and run the verification that matches the actual blast radius. `swift build` is useful but is not enough for iOS UI or app-target changes.

## Verification Matrix

Load `references/verification-commands.md` for exact commands.

- LancerKit-only Swift changes: run `swift build` and, when behavior/tests changed, `swift test` from `Packages/LancerKit`.
- iOS UI, app shell, app lifecycle, entitlements, or strict-concurrency risk: use XcodeBuildMCP app-target simulator build after checking session defaults.
- Daemon changes: run `go build` and `go test ./...` from `daemon/lancerd`.
- Hook or approval-flow changes: run the validation playbook checks that apply and mark live iOS approval loops as manual unless actually performed.
- Vendor adapter changes: also use `$vendor-cli-adapter-audit`.
- Design board changes: verify the rendered board in a browser or DOM after hydration, not just static HTML.
- Launch/readiness changes: update canonical launch docs only after the checks actually ran.
- APNs physical-device, TestFlight, DNS, App Store Connect, and production deployment steps are owner-gated unless the agent actually has the credentials/device/session and runs them.

## Reporting

Report:

- exact commands or MCP tools used
- pass/fail result
- warnings worth tracking
- checks skipped and why
- current dirty files if relevant

Do not hide failed verification behind a summary. If a command is known to be wrong from repo layout, use the correct scoped command and mention the distinction only if useful.
