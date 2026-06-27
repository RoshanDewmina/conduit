# Lancer — Status Report & Change Log

**Date:** 2026-06-23 · **Branch:** `rebrand/lancer` · **State:** uncommitted working tree, builds green.
This report covers where Lancer stands and every change made in this session (audit → cleanup → screenshots → handoff).

---

## 1. Where Lancer is (current state)

**Product:** iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the developer's own machines. The phone **steers and approves**; it is not a phone IDE. Three layers: iOS app (`Packages/LancerKit/`), `lancerd` Go daemon, and `push-backend`/`agent-runner` cloud control plane.

**Maturity:** V1 core loop (pair → dispatch → approve → continue) is real and was **device-proven** — physical-device APNs approval with the app closed PASSED 2026-06-23 (C2). First TestFlight build uploaded 2026-06-23 (`dev.lancer.mobile`). The app is build-green and materially leaner after this session's cleanup.

**Verified this session (actually run, not inferred):**
- LancerKit `swift build` ✅ · iOS app-target `build_sim` ✅ (0 errors/warnings) — re-run after every cleanup batch.
- macOS `swift test` 13/13 ✅ · Go `go test ./...` ✅ for all 3 daemon modules (lancerd 22.8 s, push-backend, agent-runner).
- iOS sim test suite: **463/464 pass — 1 real failure** (see Risks).

**Top risks / open items:**
- 🟥 **1 failing iOS test** — `LiveActivityContentStateTests.lastUpdateEncodesAsUnixNumber` — Swift's default `JSONEncoder` encodes `Date` as 2001-epoch, not Unix; an ActivityKit push-contract mismatch on the **app-closed approval path**. Not fixed (audit/cleanup only). The docs' "385 tests green" figure is stale (actual 464/1-fail).
- ⚠️ **TESTER-1/TESTER-2** (launch blockers, unchanged this session): relay host still named `conduit-push` (no vanity domain); published `lancerd` installer release is stale. The shipping app config already points at the live Cloud Run URL.
- ⚠️ **Demo-seed data persists** into normal runs ("2 conversations blocked" with no machines was leftover `LANCER_SEED_DEMO` state, not hardcoded — a clean install shows "All clear tonight").
- ⚠️ Onboarding gates value behind an account fork; IA still has 6 roots (target: 4).

---

## 2. Changes made this session

### A. Full product/UX/design audit (new docs under `docs/audits/`)
Ten evidence-based reports produced — nothing in the app's behavior changed to create them:
- `product-audit-status.md` (tracker), `source-of-truth-report.md`, `backend-frontend-feature-matrix.md` (45 RPCs + ~40 routes traced to UI), `screen-inventory.md`, `information-architecture-report.md`, `onboarding-audit.md`, `visual-consistency-report.md`, `test-and-quality-report.md`, `ux-simplification-report.md`, plus `screenshots/` (foldered).

### B. Codebase cleanup — dead/old/prototype code removed (build-verified)
**49 files deleted, 4 modified, ≈ −11,900 LOC.** Every deletion verified against `swift build` + the iOS app-target build; one false-positive (`LancerGlassChrome`, used via a `.lancerGlassChrome()` extension) was caught by the build and restored.

Deleted:
- **Debug gallery harness** — `DebugGalleryView`, `StatesGallery`, `DebugSessionHarness`, `DebugTerminalHarness`; the `LANCER_GALLERY` branch in `AppRoot.swift` and `LANCER_TERMINAL_TEST` branch in `LancerApp.swift`; the onboarding gallery wrapper struct.
- **Legacy onboarding** — `OnboardingView` + 5 phase screens (Welcome/InstallBridge/Pair/Scan/Paired/Caution/FirstRun). Production uses `OnboardingRedesignView`.
- **Duplicate / dead views** — entire `KeysFeature` module (`KeysView` + `KeyImportView`, removed from `Package.swift`), legacy `FilesView` (SFTP), `AgentsView`, `AgentDetailView`, `AgentRunDetailView`, `AgentExecView`, `AgentOrgView`, `AgentWorkspaceView`, `AgentBillingSheet`, `CreateAgentSheet`, `PremiumComparisonView`.
- **Orphaned prototype components** — `DSDecisionSheet`, `HostHealthBadge`, `InboxEmptyState`, `DSOfflineState`, `DSSkeletonRow`, `DSSlowOverlay`, `AgentStatusBar`, `ExplainSheet`, `RelayChatViewModel`; and the 5 gallery prototypes (Agent Features / HUD / Proof Card / Sessions-glyph / Typed-Inbox).
- **Archived dirs** — repo `archive/` (conduit + lancer dead-views) and `Packages/LancerKit/archive/`.
- **2 gallery-dependent UI tests** — `OnboardingRedesignNavTests`, `SendFollowUpFlowTests` (drove the removed `LANCER_GALLERY`).

**Kept (owner decisions):** deferred-V2 code — hosted-cloud (Provisioning/RunnerStatus/RunnerSetup/SelfHostVsHosted/ProviderDetail), Loops, Worktrees. Test scaffolding still backing tests — `MockAIClient`, `DebugSeeder`. Live views the scan flagged as false-positives (Typography, DSCard, Keychain, etc.).

Modified files: `Lancer/LancerApp.swift`, `Packages/LancerKit/Package.swift`, `AppFeature/AppRoot.swift`, `OnboardingFeature/OnboardingRedesignGalleryView.swift`. (`Lancer.xcodeproj` regenerated via XcodeGen — it's gitignored.)

### C. Real-app screenshots (replacing the deleted gallery)
Captured via a throwaway XCUITest driving the **real running app** (the in-app gallery harness was removed). **10 real screenshots** in `docs/design-handoff/app-screenshots/`:
`real-01-home`, `real-02-sidebar`, `real-03-inbox` (live approval cards), `real-04-machines` (Dev VPS + saved hosts), `real-05-settings`, `real-06-newchat`, `real-07-settings-providerkeys`, plus 3 Home states (empty/first-run, permission-prompt, populated). The 5 old-design prototype screenshots were removed from the audit set.

### D. Claude Design handoff brief (`docs/design-handoff/application-redesign-brief.md`)
Self-contained redesign brief: product overview, **every page described** (10 captured + the rest described from Swift source), feature constraints, redesign objectives, required Design outputs, and a **capture checklist** for the ~15 screens still needing a real shot (with exact nav paths + the `LANCER_UITEST_RESEED=1 LANCER_FAKE_RELAY_HOST=1` seam to populate them).

---

## 3. Verification summary

| Gate | Result |
|---|---|
| LancerKit `swift build` | ✅ |
| iOS app-target `build_sim` | ✅ 0 errors/warnings |
| macOS `swift test` | ✅ 13/13 (platform-agnostic) |
| iOS sim test suite | 🟥 463/464 (1 ActivityKit timestamp-contract failure) |
| Go `go test ./...` ×3 modules | ✅ |
| Screenshot capture UITest | ✅ TEST SUCCEEDED |

---

## 4. Recommended next steps
1. **Triage the failing Live Activity timestamp test** (touches the app-closed approval path).
2. **Commit** this cleanup + audit + screenshots (nothing committed yet — all git-revertable).
3. Capture the remaining ~15 screens (checklist in the handoff brief).
4. Begin IA simplification (fold Inbox into Home → 4 roots; reduce onboarding to value-first; collapse settings depth).
5. Engineering track: resolve TESTER-1/2, finish `conduit→lancer` naming, gate demo-seed data out of normal runs.

---

## 5. Deliverable locations
- Reports: `docs/audits/*.md` (+ `screenshots/`)
- Real app screenshots: `docs/design-handoff/app-screenshots/`
- Design brief: `docs/design-handoff/application-redesign-brief.md`
- This report: `docs/audits/STATUS-REPORT-2026-06-23.md`
- Downloads copy: `~/Downloads/lancer-audit-2026-06-23/`
