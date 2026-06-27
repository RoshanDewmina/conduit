# FABLE Findings - Governed Approvals v1

**Date:** 2026-06-13
**Verdict:** **NO-GO** until owner-only production blockers are cleared.

This file is the findings ledger for the June 13 strict pre-submission pass. The full narrative report is `docs/audit/FABLE_REPORT.md`; the capability matrix is `docs/audit/FEATURE_COVERAGE.md`.

## Phase Status

- [x] Orient, scope, and hook hygiene.
- [x] Source and feature coverage review.
- [x] UX/UI simplification pass focused on "understand governed approvals fastest."
- [x] Live Device Hub tap-injection proof.
- [x] Live localhost SSH TOFU verification.
- [x] Local relay-fallback verification.
- [x] Swift package build/test.
- [x] Xcode build and archive check.
- [x] Go backend vet/test.
- [x] Store metadata/readiness reconciliation.
- [x] Final audit docs and screenshots.

## Blockers

| ID | Finding | Status | Evidence / Recommendation |
|---|---|---|---|
| B-001 | TOFU trust flow could reject the host key while the user was tapping "Trust & Connect" because the sheet dismissal binding ran the reject path during explicit trust. | Fixed | `SessionView` now tracks trust-in-progress. Live localhost SSH E2E passed in `/tmp/lancer-fable-live-ssh-simenv3.log`. |
| B-002 | `daemon/push-backend` could be started in production-like environments without `APPROVAL_RELAY_SECRET`. | Fixed | Production env detection now fails fast for Cloud Run, Fly, and `LANCER_ENV` / `APP_ENV` production markers. Go tests pass. |
| B-003 | App Store metadata overclaimed closed-app / lock-screen approval delivery before physical APNs validation. | Fixed | `docs/app-store-metadata.md` and fastlane description/promotional text now avoid that claim and mark APNs delivery as owner-gated. |
| B-004 | Archive emitted iPad orientation warning from incomplete metadata. | Fixed | `project.yml` now sets iPhone and iPad supported orientations; archive warning-free. |
| B-005 | Distribution signing and App Store export are not verified. | Flagged | Owner-only. Archive is development-signed, with development APNs entitlement. |
| B-006 | Physical-device APNs delivery and notification action routing are not verified. | Flagged | Owner-only. Device Hub cannot prove production push delivery. |
| B-007 | App Store Connect, TestFlight upload, privacy labels, and final submission are not done. | Flagged | Owner-only and intentionally not attempted. |
| B-008 | Production CloudKit and production backend deployment are not verified. | Flagged | Owner-only. No deployed backend test traffic was sent by instruction. |
| B-009 | IAP sandbox purchase and subscription/entitlement reconciliation are not verified in App Store Connect. | Flagged | Owner-only. |

## Major Findings

| ID | Finding | Status | Recommendation |
|---|---|---|---|
| M-001 | Onboarding led too much with connection setup instead of the governed-approvals mental model. | Fixed | New copy teaches "agents ask permission, you approve, work resumes" before host setup. |
| M-002 | First launch could request notification authorization before the user understood why approvals matter. | Fixed | Categories register after onboarding is seen; no first-screen notification interruption. |
| M-003 | Cloud Sync visibility ignored the configured Info.plist gate. | Fixed | Settings now reads `LANCER_ICLOUD_ENABLED`. Production CloudKit remains owner-only. |
| M-004 | Empty states and approval cards used less direct language than the core flow deserves. | Fixed | Inbox, Fleet, Add Host, approval cards, allow-always, autonomy labels, and connected state were clarified. |
| M-005 | Device Hub tap injection needed proof on macOS/Xcode beta before trusting simulator interaction. | Fixed | `testTapInjectionViaTabSwitch` passed cleanly. |
| M-006 | Governed approval decision needed real UI interaction proof. | Fixed | `testApproveDecisionApplies` passed cleanly. |
| M-007 | Live localhost first-connect path needed real SSH, Keychain-backed password, and TOFU prompt verification. | Fixed | Live SSH E2E passed against `127.0.0.1:22`; secret value was not printed. |
| M-008 | Local relay fallback needed real backend route verification without touching deployed infra. | Fixed | Local backend verified register, decision, one-time poll drain, and auth failures. |
| M-009 | Implemented capabilities remain hidden or mostly unreachable. | Flagged | Decide whether to ship, surface, or defer: SFTP browser, Preview/SessionShellView, fuller KeysView, snippet editor, OpenRouter, Dispatch, post-onboarding provisioning. |
| M-010 | Visible surfaces still contain partial behavior. | Flagged | Library run/new snippet, workflow add-step, mock key counts, watch pending-count freshness, invite email, and allow-always revoke semantics need product decisions. |
| M-011 | Xcode 27 beta can hang after UI tests pass while shutting down the Device Hub runner. | Flagged | Treat as environment/tooling caveat; use individual test logs and selected-suite pass lines as evidence until Xcode stabilizes. |

## Minor Findings

| ID | Finding | Status | Recommendation |
|---|---|---|---|
| m-001 | Saved-host reconnect icon could shift size. | Fixed | Icon frame is now stable. |
| m-002 | Back chevron accessibility did not say the session remains running. | Fixed | Accessibility label now says "Leave session running." |
| m-003 | Port-forward UI showed remote forwarding affordance even when unsupported. | Fixed | Remote chip is hidden/annotated when unavailable. |
| m-004 | Settings and port-forward SwiftUI bodies were large enough to stress type checking. | Fixed | Split into smaller sections. |
| m-005 | Metadata support URL differed from the docs. | Fixed | Fastlane support URL now points to `/support`. |

## Feature Coverage Gaps

### Implemented but hidden or weakly surfaced

| Capability | Status | Recommendation |
|---|---|---|
| `SessionShellView` / preview / localhost web surfaces | Flagged | Either surface as a clear session tool or keep out of submission claims. |
| SFTP file browser and file preview | Flagged | Do not market until there is a normal route and E2E coverage. |
| Fuller SSH key management | Flagged | Replace mock host-counts and verify import flows before treating as complete. |
| Snippet editor creation/edit paths | Flagged | Wire a clear Library entry or remove the incomplete affordance. |
| OpenRouter provider support | Flagged | Surface in Settings only if provider testing and usage reporting are ready. |
| Dispatch composer | Flagged | Keep debug-gallery-only unless Cloud/agent dispatch is part of the submission story. |
| Post-onboarding provisioning wizard | Flagged | Add a normal entry point only if provisioning is ready for App Review. |

### Shown but partial or unimplemented

| Surface | Status | Recommendation |
|---|---|---|
| Library new snippet / run actions | Flagged | Wire or remove before submission screenshots. |
| Workflows add-step | Flagged | Replace mock builder with real behavior or hide. |
| Key host counts | Flagged | Stop showing mock counts if not backed by data. |
| Watch pending count / decision freshness | Flagged | Verify on paired hardware and avoid store claims until proven. |
| Live Activity and lock-screen actions | Flagged | Owner-only physical APNs proof required. |
| Invite email | Flagged | Do not claim team invite delivery until backend email is enabled. |
| Allow-always revoke | Flagged | Clarify local-only vs bridge policy behavior before marketing. |

## Verification Notes

- `swift build` and `swift test` passed in `Packages/LancerKit`.
- XcodeBuildMCP `build_sim` passed warning-free.
- Archive passed warning-free at `/tmp/lancer-fable-final3.xcarchive`.
- Push backend `go vet ./...` and `go test ./...` passed.
- Read-only `daemon/lancerd` `go vet ./...` and `go test ./...` passed.
- XcodeBuildMCP `test_sim` wrapper timed out in the beta environment; raw XCUITest logs show passing assertions before Device Hub teardown hangs.
- Local backend relay verification was performed only against a local process, not the deployed backend.
- No secrets were printed.

## Owner-Only Remainder

- Distribution signing and App Store export.
- App Store Connect record, metadata finalization, privacy labels, screenshots, TestFlight upload, and submission.
- Physical-device APNs delivery and lock-screen action verification.
- Production backend deployment with secrets.
- Production CloudKit verification.
- IAP sandbox verification.
- Any destructive cloud/backend operation or secret rotation.
