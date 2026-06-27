# WS-7 — Observability & release readiness  (covers 17-pt #11, #16, #17)

> Depends on WS-1/2/3/4/5 having merged (it finalizes the build for upload). Several steps are owner-only (Apple Dev portal, Sentry project) — you do all the plumbing + prep; the owner pastes secrets and clicks buttons.

## Context
Repo `/Users/roshansilva/Documents/command-center`. Build: `cd Packages/LancerKit && swift build`. Read `docs/app-store-metadata.md`, `docs/ship-gate-owner-steps.md`, `ARCHITECTURE.md`, `project.yml`.

**Confirmed state:**
- **Sentry is already wired** in `LancerApp.swift` (`#if canImport(Sentry)` guard + `configureSentry()` in AppDelegate + SPM dep) — it just needs a DSN at `LancerApp.swift:20` (currently `""`).
- `project.yml` L57–63 has an explicit comment to swap from `Lancer-DeviceTesting.entitlements` to `Lancer.entitlements` (which already has `aps-environment: production`, iCloud container IDs, keychain groups) once the paid Apple account is enrolled.
- Debug affordances that must NOT ship in Release: `isPro` DEBUG bypass (see WS-4), `DebugSeeder`, the debug **REVIEW** pill (see WS-9), debug host auto-trust.
- The SSH lib is a fork (`Wellz26/swift-nio-ssh`) — undocumented supply-chain/maintenance risk.

## Tasks
1. **#11 Sentry** — wire the DSN read (keep the DSN itself owner-supplied; do NOT commit a real DSN — read from build config or leave a clearly-marked placeholder + instructions). Confirm symbolicated traces + uncaught-exception capture path. Update the privacy manifest to declare crash-data collection.
2. **#17 Entitlements swap** — change `project.yml` L57–63 to use `Lancer/Lancer.entitlements` (drop the `properties:` keychain override block). Run `xcodegen generate` and confirm the project regenerates cleanly + `swift build` still green. Confirm `CODE_SIGN_IDENTITY` is `Apple Distribution` for Release.
3. **#16 App Store metadata** — finalize `docs/app-store-metadata.md`: name, subtitle, description (lead with the Warp-style blocks story), keywords, support/marketing/privacy URLs (privacy URL = WS-6 `/privacy`). Draft the **App Privacy nutrition label** answers and the **export-compliance** answer (SSH ⇒ uses crypto ⇒ set `ITSAppUsesNonExemptEncryption` + rationale). Verify `PrivacyInfo.xcprivacy` exists and matches actual data/required-reason API usage. Draft **reviewer notes** addressing remote-shell scrutiny (Guideline 2.5.2: Lancer drives a *remote* shell; it does not download/execute code locally — articulate this).
4. **Release hygiene** — gate `isPro` bypass, `DebugSeeder`, and the REVIEW pill out of Release (`#if DEBUG`); confirm debug host auto-trust is `#if DEBUG`/env-guarded only; add a `.env.example` + startup guard for the push backend.
5. **Document the forked NIO-SSH** in `ARCHITECTURE.md` — why the fork, upstream-tracking plan, switch-back trigger.
6. **TestFlight prep** — write/verify `ExportOptions.plist` (`method: app-store-connect`) and document the archive→upload steps (the owner runs them). Confirm bundle id `dev.lancer.mobile`, version/build, capabilities match entitlements.

## Owner-only (list in report, don't fake): create the Sentry project (paste DSN); Apple Dev portal — enable Push + iCloud on the App ID, create the APNs Auth Key (`.p8` → WS-5 + Secret Manager), note Key ID/Team ID (`39HM2X8GS6`); App Store Connect — create IAP `dev.lancer.mobile.pro`, TestFlight internal group; archive → upload.

## Acceptance
- Sentry DSN plumbing ready (no committed secret). · Entitlements swapped; `xcodegen generate` clean; build green. · Metadata + privacy label + export-compliance + reviewer notes drafted; `PrivacyInfo.xcprivacy` verified. · Debug affordances gated out of Release. · NIO-SSH fork documented. · `ExportOptions.plist` + upload steps ready. · Owner-action checklist produced.

## Report Template (fill in, return)
```
## WS-7 Report
### #11 Sentry: <DSN plumbing; privacy manifest updated; no secret committed?>
### #17 Entitlements: <swapped? xcodegen clean? build green? CODE_SIGN_IDENTITY?>
### #16 Metadata: <name/subtitle/desc/keywords drafted where; privacy URL>
### Privacy label + export compliance: <ITSAppUsesNonExemptEncryption=?, rationale>
### PrivacyInfo.xcprivacy: <exists/accurate; required-reason APIs?>
### Reviewer notes (2.5.2 remote-shell): <draft>
### Release hygiene: isPro <gated> DebugSeeder <gated> REVIEW pill <gated> auto-trust <#if DEBUG?>
### NIO-SSH fork doc: <added to ARCHITECTURE.md?>
### TestFlight: <ExportOptions.plist + steps ready?>
### Owner-action checklist: <list>
### Build: <green/red> · Files changed: <list> · Deviations/risks:
```
