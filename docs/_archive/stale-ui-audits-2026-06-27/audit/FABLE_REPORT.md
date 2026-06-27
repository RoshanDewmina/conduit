# FABLE Report - Governed Approvals v1 Pre-Submission Audit

**Date:** 2026-06-13
**Branch:** `codex/uiux-audit`
**Device Hub target:** iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`)
**Verdict:** **NO-GO** for App Store submission until the owner-only production gates are cleared.

## Executive Summary

The governed-approvals core loop is materially stronger after this pass. The app now teaches the approval model first, delays notification permission until after onboarding, preserves the production TOFU host-key prompt, fixes a live first-connect race, and fails closed when the relay backend is deployed without its shared secret. Local live SSH, local relay fallback, Swift package tests, Go tests, Xcode build, and archive all passed.

The release is still a strict no-go because several production-only checks cannot be completed by the agent: distribution signing/export, App Store Connect/TestFlight, physical-device APNs delivery, production CloudKit, production backend secret deployment, IAP sandbox, and final store submission. The archive is build-valid but development-signed.

## What Changed

### UX and onboarding

- Reframed onboarding around the mental model: agents ask permission, the user approves, work resumes.
- Removed misleading "detected network" first-run copy and replaced it with trust/security language.
- Made Face ID copy honest: biometric unlock protects app launch and secrets on the device.
- Clarified Inbox empty state, Fleet empty state, Add Host helper text, approval-card copy, allow-always scope, autonomy labels, and connected state.
- Improved touch target consistency for design-system buttons and fixed a saved-host reconnect icon layout issue.
- Avoided a first-launch notification prompt; notification categories now register only after onboarding is seen.

### Correctness and security

- Fixed the live SSH TOFU trust race in `SessionView`: tapping "Trust & Connect" no longer causes the sheet dismissal binding to reject the same host key.
- Kept the production TOFU prompt intact; only the debug/e2e seeded flow prefills the local password for test automation.
- Made Cloud Sync visibility follow the app's `LANCER_ICLOUD_ENABLED` Info.plist flag instead of a hard-coded false path.
- Added production fail-fast detection in the Go relay backend when `APPROVAL_RELAY_SECRET` is missing.
- Added `APPROVAL_RELAY_SECRET` to backend examples and deployment docs.

### Build, project, and metadata

- Updated `project.yml` rather than hand-editing the generated project; regenerated `Lancer.xcodeproj`.
- Added App Intents framework wiring where needed and fixed iPad orientation metadata that caused archive warnings.
- Synced fastlane metadata and App Store docs to avoid overclaiming closed-app/lock-screen approvals before physical APNs is verified.
- Updated support URL metadata to `https://conduit.dev/support`.

### Tests and audit artifacts

- Expanded `LancerUITests/TapInjectionProofTests.swift` with deterministic reseeding, tap-injection proof, approve-decision proof, Face ID opt-in coverage, saved-host reconnect coverage, and a live localhost SSH TOFU test path.
- Added June 13 Device Hub screenshots under `docs/audit/screens/`.
- Rewrote `FABLE_REPORT.md` (this file), `FABLE_FINDINGS.md` (archived → `docs/_archive/audit/FABLE_FINDINGS.md`), `FEATURE_COVERAGE.md` (archived → `docs/_archive/audit/FEATURE_COVERAGE.md`), and the screenshot manifest for this strict pass.

## Diff Summary

In-scope work touched the iOS app, XcodeGen config, UI tests, push backend, metadata, and audit docs. The current in-scope code/docs diff is approximately 26 tracked files before the report rewrite, plus new audit screenshots. The unrelated dirty files under `docs/lancer-ui-prototype/**` are explicitly out of scope and were left untouched.

Representative changed areas:

- `Packages/LancerKit/Sources/AppFeature/**`
- `Packages/LancerKit/Sources/OnboardingFeature/**`
- `Packages/LancerKit/Sources/InboxFeature/**`
- `Packages/LancerKit/Sources/SessionFeature/**`
- `Packages/LancerKit/Sources/SettingsFeature/**`
- `LancerUITests/TapInjectionProofTests.swift`
- `daemon/push-backend/**`
- `project.yml`
- `docs/**`, `ship-plan/**`, `fastlane/metadata/**`

## Verification Evidence

| Check | Result | Evidence |
|---|---:|---|
| Hook hygiene | Pass | No Lancer approval hook found in `~/.codex/` or global Claude settings; md5s recorded during the run. |
| Tap injection proof | Pass | `testTapInjectionViaTabSwitch` returned `** TEST SUCCEEDED **` in `/tmp/lancer-fable-uitest-testTapInjectionViaTabSwitch-final.log`. |
| Approval decision UI | Pass | `testApproveDecisionApplies` returned `** TEST SUCCEEDED **` in `/tmp/lancer-fable-uitest-testApproveDecisionApplies-final.log`. |
| Active UI suite | Pass with beta cleanup caveat | 4 selected tests passed with 0 failures in `/tmp/lancer-fable-uitests-active-final.log`; Xcode 27 beta hung after suite completion during Device Hub shutdown and was killed. |
| Live localhost SSH TOFU | Pass | `/tmp/lancer-fable-live-ssh-simenv3.log`; real SSH to `127.0.0.1:22`, Keychain-backed password, TOFU prompt, trust, and `Connected`. |
| Local relay fallback | Pass | Local `daemon/push-backend` handled register, decision, authorized poll, one-time drain, and 401s for missing/wrong tokens. |
| `swift build` | Pass | `/tmp/lancer-fable-swift-build-final2.log`. |
| `swift test` | Pass | `/tmp/lancer-fable-swift-test-final2.log`. |
| XcodeBuildMCP `build_sim` | Pass, 0 warnings | Log under `~/Library/Developer/XcodeBuildMCP/workspaces/command-center-c3ef378ca557/logs/`. |
| XcodeBuildMCP `test_sim` | Not cleanly returned | Wrapper timed out on the beta environment; raw XCUITest evidence above passed assertions. |
| Archive | Pass, warning-free | `/tmp/lancer-fable-archive-final3.log`, archive `/tmp/lancer-fable-final3.xcarchive`. Development signing only. |
| `go vet ./...` push backend | Pass | `/tmp/lancer-fable-pushbackend-govet-final2.log`. |
| `go test ./...` push backend | Pass | `/tmp/lancer-fable-pushbackend-gotest-final2.log`. |
| `go vet ./...` lancerd | Pass, read-only | `/tmp/lancer-fable-lancerd-govet-final2.log`. |
| `go test ./...` lancerd | Pass, read-only | `/tmp/lancer-fable-lancerd-gotest-final2.log`. |

No long-running `xcodebuild`, backend, Go, or UI-test runner processes were left running.

## Findings

### Blockers - fixed

- **TOFU trust dismissal race:** Fixed. Live first-connect now reaches the TOFU prompt and then a connected session.
- **Relay backend could start in production without `APPROVAL_RELAY_SECRET`:** Fixed. Cloud Run, Fly, and production env markers now fail fast.
- **Archive orientation warning:** Fixed through `project.yml`; archive is warning-free.
- **Metadata overclaiming lock-screen/closed-app approvals:** Fixed. Copy now matches locally verified behavior and flags APNs delivery as owner-only.

### Blockers - flagged

- **Distribution signing/export is not verified:** Owner-only. Current archive uses development signing (`get-task-allow = 1`, `aps-environment = development`).
- **Physical-device APNs delivery is not verified:** Owner-only. Device Hub cannot prove lock-screen push delivery or notification actions with the production `.p8`.
- **App Store Connect/TestFlight/upload/submission are not done:** Owner-only and intentionally not attempted.
- **Production CloudKit is not verified:** Owner-only capability/container/environment gate.
- **Production backend deployment with real secrets is not verified:** Owner-only; no test traffic was sent to the deployed backend by instruction.
- **IAP sandbox and privacy nutrition labels are not verified in App Store Connect:** Owner-only.

### Majors - fixed

- Onboarding now explains governed approvals before plumbing.
- First-run notifications no longer interrupt onboarding.
- Cloud Sync UI follows the configured flag instead of being permanently suppressed.
- The active UI tests include direct tap proof and approval decision proof.
- Settings body and port-forward view were split to avoid SwiftUI type-checking pressure.

### Majors - flagged

- Several implemented capabilities are still hidden or weakly surfaced: fuller session shell/preview surfaces, SFTP browser, fuller SSH key management, snippet creation/editing paths, OpenRouter provider selection, dispatch composer, and post-onboarding provisioning.
- Several visible surfaces still contain placeholder or partial behavior: Library run/new snippet paths, workflow add-step, key host counts, watch pending-count freshness, invite email delivery, allow-always revoke scope, and production APNs/Live Activity delivery.
- Xcode 27 beta Device Hub cleanup is unstable after UI test completion. Assertions pass, but the wrapper can hang while tearing down the runner.

## Feature Coverage

The coverage matrix is in `docs/_archive/audit/FEATURE_COVERAGE.md`. Summary:

- Core approvals path: shown and locally verified through Inbox, UI tests, live SSH TOFU, and relay fallback.
- Local host connection path: shown and locally verified against localhost SSH.
- Relay fallback: backend route behavior verified locally and by Go tests; deployed delivery remains owner-only.
- Widgets, Watch, Live Activity, APNs: compiled and code-reviewed, but physical delivery/action verification remains owner-only.
- Hosted agents, billing, Cloud, CloudKit, IAP: code surfaces exist, but production entitlement/store checks remain owner-only.

## UX/UI

### Screenshot index

See `docs/audit/screens/MANIFEST.md` for the final image list.

Captured June 13:

- Onboarding, light and dark.
- Inbox, light and dark.
- Fleet, light and dark.
- Activity, light and dark.
- Settings, light and dark.
- Tab contact sheet / reference screenshot.

### Simplifications made

- The first screen now leads with the approval loop instead of host connection mechanics.
- The core cards use plain permission language: "is asking permission" and "remember this exact action".
- The app no longer asks for notifications before the user understands what approvals are.
- Status vocabulary now says "Connected" rather than "Done".
- Empty states now tell the user what is true and what to do next, without adding extra feature promises.

### Recommended but not changed unilaterally

- Consider renaming or restructuring Library if snippet/workflow/key management stays partial at submission.
- Decide whether OpenRouter, Dispatch, SFTP, and Preview are shipping concepts or deferred debug/internal capabilities.
- Review Watch and Live Activity scope after physical APNs testing; do not market lock-screen actions until proven on device.

## Submission Readiness

**Strict verdict: NO-GO.**

Engineering-local checks are in good shape, but submission is blocked until the owner clears:

- Paid-team distribution signing and App Store export.
- App Store Connect app record, metadata, screenshots, privacy labels, and TestFlight upload.
- Physical-device APNs delivery and notification action verification.
- Production backend deployment with `APPROVAL_RELAY_SECRET` and APNs `.p8`.
- Production CloudKit container/capability verification.
- IAP sandbox verification for the pro product.
- Final App Review notes and submission decision.

## Installed Items and Assumptions

- Installed nothing.
- Assumed macOS 27 / Xcode 27 beta Device Hub cleanup instability is environmental because individual tests and selected-suite assertions passed before teardown hangs.
- Assumed localhost SSH on `127.0.0.1:22` and the Keychain item `lancer-localhost-ssh` are the intended live E2E path. The secret value was not printed.

## What I Would Commit

One commit would be appropriate:

`Governed approvals pre-submission hardening`

It would include the onboarding/UX simplifications, TOFU race fix, relay secret hardening, metadata corrections, XcodeGen config updates, UI-test expansion, screenshots, and audit docs. The working tree is intentionally left uncommitted.
