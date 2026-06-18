# V1 Launch Hardening and TestFlight Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`. This plan is verification and launch hardening only; do not use it to redesign product flows.

**Goal:** Move Conduit from working prototype/product implementation to a release-candidate state: repeatable tests, app-target build/archive confidence, APNs/approval-loop validation, and launch docs that match current reality.

## Source Of Truth

- `docs/PUBLISH_READINESS_CHECKLIST.md`
- `docs/KNOWN_ISSUES.md`
- `docs/agent-contract.md`
- `ARCHITECTURE.md`

If this plan finds drift, update the checklist or known issues in the same branch as the verified change.

## Current Known Launch Gates

From the publish checklist:

- Reconcile current working tree before release.
- Make live app-to-daemon relay repeatable.
- Green app-target Release build and clean archive.
- Rebuild/repackage `conduitd` from Go source.
- Finish remaining pixel polish and a11y sweep.
- Reconcile push-backend WIP.
- Verify feature wiring from real navigation.
- Run real remote-host E2E.
- Run physical-device APNs approval loop.
- Verify StoreKit/TestFlight purchase path.
- Close security review residuals.

## Implementation Tasks

- [ ] **Task 1: Establish clean verification baseline**
  - Run and capture:
    - `swift test --package-path Packages/ConduitKit`
    - `go test ./daemon/conduitd/...`
    - push-backend Go tests if that tree is touched
    - agent-runner Go tests if that tree is touched
  - Do not update checklist as green unless commands actually pass in this branch.

- [ ] **Task 2: App-target build and archive lane**
  - Use XcodeBuildMCP for simulator build.
  - Then run the closest local archive/build command available for the app target.
  - Document any watchOS platform/runtime blocker with exact command and error.
  - Do not delete watch targets to make the build pass.

- [ ] **Task 3: Repeatable relay regression**
  - Build an automated or semi-automated test for the previously proven path:
    - app connects;
    - daemon channel arms after TOFU/reconnect;
    - approval pending reaches phone;
    - approve/reject returns to daemon;
    - agent unblocks.
  - Prefer a local fixture before requiring a real remote host.
  - Save evidence under `docs/test-runs/`.

- [ ] **Task 4: Real navigation feature wiring audit**
  - Verify from production navigation, not `CONDUIT_GALLERY`:
    - policy editor;
    - while-you-were-away/audit feed or its replacement;
    - usage/spend dashboard;
    - dispatch composer;
    - schedule composer if still in V1;
    - chat history/search/continue after those plans land;
    - sidebar Fleet and Settings after shell plan lands.
  - Capture screenshots for missing or broken paths.

- [ ] **Task 5: A11y and empty/error/loading sweep**
  - Cover Inbox, Chat, Sidebar, Fleet, Settings, approval detail, artifact detail.
  - Check:
    - VoiceOver labels for icon-only controls;
    - Dynamic Type for user-facing text;
    - Reduce Motion;
    - light/dark contrast;
    - empty states;
    - loading states;
    - error states.
  - File focused fixes or record residuals in `docs/KNOWN_ISSUES.md`.

- [ ] **Task 6: Repackage Go `conduitd`**
  - Verify `scripts/release-conduitd.sh` builds the Go daemon, not stale Swift output.
  - Run `go vet`, `go build`, and `go test` for daemon.
  - Replace packaged binary only through the release script.
  - Record binary version/hash in release notes or test-run evidence.

- [ ] **Task 7: Push backend and APNs readiness**
  - Confirm environment requirements are documented:
    - `APNS_KEY_ID`
    - `APNS_TEAM_ID`
    - `APNS_BUNDLE_ID`
    - `APNS_KEY_PATH`
    - Stripe variables if purchase validation is in scope
  - If live backend access is available, perform a dry-run/health check and one real push smoke test.
  - If not available, mark owner-gated with exact next action.

- [ ] **Task 8: Physical-device closed-app approval loop**
  - Requires owner/device.
  - Test:
    - app closed;
    - host triggers approval;
    - push arrives within acceptable time;
    - lock-screen Approve works;
    - daemon receives decision;
    - agent continues;
    - audit log records decision.
  - Save evidence in `docs/test-runs/`.

- [ ] **Task 9: StoreKit/TestFlight purchase path**
  - Requires App Store Connect/TestFlight access.
  - Verify:
    - app record;
    - bundle ID;
    - IAP product `dev.conduit.mobile.pro`;
    - sandbox purchase;
    - restore purchases;
    - locked state when purchase state is unknown.
  - Save evidence.

- [ ] **Task 10: Final doc reconciliation**
  - Update `docs/PUBLISH_READINESS_CHECKLIST.md` with actual pass/fail state.
  - Update `docs/KNOWN_ISSUES.md` with new verified residuals.
  - Do not claim App Store readiness if owner-gated APNs/TestFlight steps are not complete.

## Required Evidence

For every green claim, capture:

- command;
- date;
- branch/commit if available;
- result;
- short output excerpt;
- screenshot if UI-related;
- owner-gated blocker if not runnable.

Preferred location:

- `docs/test-runs/YYYY-MM-DD-<short-name>.md`

## Acceptance Criteria

- Release branch has a known clean/dirty state.
- App-target simulator build passes.
- Swift package tests pass.
- Daemon tests pass if daemon is in scope.
- Live relay regression is repeatable or explicitly owner-gated.
- APNs physical-device test is passed or explicitly owner-gated.
- StoreKit/TestFlight path is passed or explicitly owner-gated.
- Canonical docs match verified state.

## Non-Goals

- Do not redesign the app.
- Do not change pricing.
- Do not create App Store Connect records unless the owner explicitly asks and credentials are available.
- Do not bypass security gates to make demos pass.
