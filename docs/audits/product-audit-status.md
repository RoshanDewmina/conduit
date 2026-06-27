# Product Audit — Running Status Tracker

> Living tracker for the Complete Product / Frontend-Coverage / UX / Design-Handoff audit.
> Updated after every phase. Plan: `~/.claude/plans/complete-product-frontend-coverage-virtual-ritchie.md`.
> Started 2026-06-23. Branch `rebrand/lancer`. **Read-only audit — no behavior changes, no deletions.**

## Confirmed scope

Exhaustive evidence-based audit of the Lancer iOS app + its backend, producing 10 reports + a
screenshot set, culminating in a self-contained Claude Design redesign brief. North star:
**aggressively simplify to V1 scope** (sidebar shell + relay + governed approvals + dispatch/continue);
flag orphaned/deferred sprawl as remove-or-defer.

### Owner decisions
1. Screenshots: gallery harness (49 routes) primary + live sim where reachable.
2. Redesign: aggressively simplify to V1; flag hosted-cloud/worktrees/loops/agent-* detail/legacy-onboarding/SFTP as remove-or-defer.
3. Execution: lean parallel Claude Explore agents; no opencode/deepseek.
4. Backend: live — **but owner says skip live relay E2E tests (done with those).** Relay/approval states captured via gallery + code evidence.

## Current phase

**COMPLETE.** All 10 phases done; deliverables written. Awaiting owner review (no redesign/impl yet).

## Completed work
- **Recon:** `claude --version` 2.1.186 (current). Tooling inventoried. Prior session `be82d0a1` read. 4 Explore passes (frontend / backend / docs / RPC↔view / design-system) complete.
- **Phases 0–10:** all reports written (see Deliverables table at bottom of this section).
- **Builds/tests run this audit:** LancerKit `swift build` ✅; app-target build ✅ (0 warn/err); `swift test` macOS 13/13 ✅; **iOS sim suite 464 tests → 1 FAIL** (LiveActivity timestamp contract); Go ×3 modules ✅; 54 screenshots captured.

## Headline findings
- **1 real failing test:** `LiveActivityContentStateTests` ActivityKit push-contract (Date encoded as 2001-epoch, not Unix) — touches app-closed approval path. Docs' "385 green" is stale (actual 464/1-fail).
- **Backend ≫ frontend:** 45 RPCs, ~27 user-reachable; schedules/loops/CI/hosted-cloud backend-only.
- **Onboarding gates value behind a 5-concept account fork + auth form.**
- **Sprawl:** 8 agent-detail views, ~20 settings sub-screens, duplicate Keys/Audit/Premium, orphaned V2 UI.
- **Empty-state bug:** Home shows "2 conversations blocked" with zero machines (demo data leak).

## Discovered features (headline counts)
- **lancerd RPCs:** 45 (server.go `handleMessage`).
- **push-backend routes:** ~40 (approval relay, billing/Stripe, agents/runs, quotas/usage, artifacts, schedules, orgs, webhooks).
- **agent-runner:** cloud task executor (log stream + cancel poll).
- **Vendor adapters:** claude, codex, kimi, opencode (dispatch.go) — opencode hook still TODO.

## Discovered screens (headline)
~50 SwiftUI screens. Sidebar shell, 6 destinations (`SidebarDestination`). 2 onboarding flows (legacy 7-step `OnboardingView` + production 4-step `OnboardingRedesignView`). 49 gallery routes (`LANCER_GALLERY`). Large orphaned surface: hosted-cloud (~900 LOC, 0 refs), worktrees, loops, agent-* detail views, SFTP FilesView.

## Open questions
None blocking. (All four pre-audit questions answered by owner.)

## Blockers
None for the audit itself. Product-level blockers (TESTER-1/2) are out of audit scope — see Backlog.

## Documentation conflicts (live; detailed in source-of-truth-report.md)
1. **Relay URL drift (TESTER-1):** docs say app ships `sslip.io`; **actual `project.yml:26` ships Cloud Run `conduit-push-y4wpy6zeva-ts.a.run.app`.** Doc claim is stale — code is correct. (Naming still says `conduit-push`, not `lancer-push`.)
2. **lancerd installer (TESTER-2):** published GitHub release stale `v0.1.0`; asset-name + checksum mismatch. (Out of audit scope; backlog.)
3. **Runbook ordering:** LIVE_LOOP_RUNBOOK leads with Phase 3 SSH though preamble says relay (5b) is the V1 path.
4. Several already-resolved: IA tab→sidebar (resolved 2026-06-20), APNs C2 (PASSED 2026-06-23), hosted-cloud deferral (consistent).

## Decisions made
See Owner decisions above. Relay E2E live test dropped at owner request.

## Evidence still required
- Phase 4 screenshots (49 gallery + live nav).
- Phase 8: swift build+test result, app-target build, go test ×3 modules, UI tests.

## Deferred items
Live relay/APNs E2E (owner done with those); physical-device runs (owner-driven).

## Backlog (out of scope — do NOT act without explicit request)
- Fix TESTER-1 naming (conduit-push → lancer-push vanity domain) / TESTER-2 installer release.
- Wire or delete orphaned hosted-cloud UI (~900 LOC).
- Remove vestigial `enum Tab` plumbing in AppRoot.swift.
- Doc archival cleanup (~160 md files; ~23 already archived).
- conduit→lancer copy/naming drift sweep.

## Final acceptance checklist
- [x] P0 tracker (this file)
- [x] P1 source-of-truth-report.md
- [x] P2 backend-frontend-feature-matrix.md
- [x] P3 screen-inventory.md
- [x] P4 screenshots/** (54 shots) + _coverage-note.md
- [x] P5 information-architecture-report.md
- [x] P6 onboarding-audit.md
- [x] P7 visual-consistency-report.md
- [x] P8 test-and-quality-report.md
- [x] P9 ux-simplification-report.md
- [x] P10 design-handoff/application-redesign-brief.md
- [x] Final 11-point summary + prompt acceptance checklist delivered (in chat)
