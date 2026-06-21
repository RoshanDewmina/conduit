# Conduit — Publish Readiness Checklist (single source of truth)

> Reconciled 2026-06-18 against **today's verified state** (branch `v1-chat-persistence-sidebar`).
> Supersedes the status claims in `docs/_archive/remaining-work.md` (2026-05-28, stale: says "free team"),
> and reconciles `ship-gate-owner-steps.md` + `PRODUCTION_READINESS_PLAN.md` + `validation-playbook.md`.
> When those disagree, **this file + `ARCHITECTURE.md` (§0.1 / §4.1) win.**
> (`CONDUIT_PROJECT_DOSSIER.md` is archived under `docs/_archive/` — superseded by `ARCHITECTURE.md` §0.1.)

Legend: ✅ done/verified · 🔶 partial · ❌ not started · ⏸ owner-gated (one human action away)

---

## A. Verified GREEN (2026-06-18)

| Layer | Result | Evidence |
|---|---|---|
| ConduitKit (SPM) build + tests | ✅ **385 tests / 61 suites pass** | `swift build && swift test` exit 0 |
| conduitd + policy (Go) | ✅ pass | `go test ./...` exit 0 |
| push-backend (Go) | ✅ pass | `go test ./...` exit 0 |
| agent-runner (Go) | ✅ pass | `go test ./...` exit 0 |
| Chat persistence + FTS search | ✅ v10 migrations, `ChatConversationRepository` with 18 tests | `ChatConversationRepositoryTests.swift` |
| Chat artifact cards + detail views | ✅ 7 card types, detail panels, 14 rendering tests | `ChatArtifactCards.swift`, `ChatArtifactDetailView.swift` |
| Sidebar shell (iPhone + iPad) | ✅ `ConduitSidebarView` + `SidebarShellState`, wired into `AppRoot.swift` | compact: drawer overlay; regular: `NavigationSplitView` |
| **Sidebar redesign (2026-06-19)** | ✅ full-height drawer, unified Sessions home (All/Needs input/Ready for review tabs), relay hostname grouping in agent picker | Xcode app-target build SUCCEEDED, 385/385 tests pass |
| **Live relay dispatch (2026-06-19)** | ✅ phone→relay→daemon dispatch proven live (opencode "Hi" → `dispatch-launched`) | PATH fix in launchd plist; `agentRunContinue` chain verified end-to-end |
| **Push backend (2026-06-19)** | ✅ Cloud Run `conduit-push` (australia-southeast1) rebuilt from source, APNs keys wired, `APPROVAL_RELAY_SECRET` enforced (401 on unauth), conduitd sends Bearer token on `/register` | `roshan-agent-f1c2466d` project |
| Fleet thread routing | ✅ `FleetThreadMapper` with 4 tests | maps host/agent/cwd to conversation |
| Relay regression script | ✅ `scripts/relay-regression.sh` created | repeatable localhost approval loop |
| **Full live governed-approvals loop** | ✅ **proven on simulator** after fixing 2 bugs | `docs/test-runs/2026-06-12-live-loop-pass1.md` |
| Visual consistency, light+dark | ✅ | polish batch 1 |

**Two live-relay bugs found & fixed (June 17):** TOFU first-connect never armed the daemon channel;
UUID case mismatch dropped every phone decision. Both fixed, regression-tested.

---

## B. Engineering — finish/verify before publish (things we can do)

- [x] **B1 — Reconcile the current working tree before release.** ✅ 2026-06-20: Codex's account-identity + V1-surface WIP verified (414 SPM tests, app-target UI 7/7 iPhone+iPad, all 3 Go modules, resident smoke 4/4) and committed to `codex/ios27-shell-workspace`; device-management screen added. No secrets staged (Supabase config is `$(...)` placeholders).
- [ ] **B0 — Restore the tester loop (P0, blocks any external testing).** Two blockers verified down 2026-06-20 (see `KNOWN_ISSUES.md` §0): (a) the V1 relay at the baked-in `https://35.201.3.231.sslip.io` is unreachable — redeploy `push-backend` and point `project.yml:26` at the live instance (reconcile the §A Cloud Run vs. sslip.io drift); (b) the `conduitd` `curl|sh` installer 404s — cut a fresh release from current source with matching asset names + `SHA256SUMS`. Until both are green, no self-hosted tester can connect.
- [x] **B2 — Make the live app↔daemon relay repeatable.** ✅ `scripts/relay-regression.sh` created. Run it to verify the loop.
- [ ] **B3 — Green *app-target* Release build + clean archive.** Requires Xcode (watchOS runtime gate). SPM passes, but full Xcode scheme catches strict-concurrency breaks SPM misses.
- [ ] **B4 — Rebuild/repackage conduitd from Go source.** `scripts/release-conduitd.sh` must emit the Go build.
- [ ] **B5 — Finish the 16 remaining pixel-polish items.** Documented in `docs/superpowers/specs/2026-06-12-conduit-pixel-perfect-polish-plan.md`.
- [ ] **B6 — Reconcile the push-backend WIP.** Divergent security design parked in stash.
- [ ] **B7 — Feature-wiring audit.** Confirm policy editor, audit feed, usage dashboard, composer reachable from real navigation.
- [ ] **B8 — Empty/error/loading + a11y sweep.** Every surface: empty/loading/error states, Dynamic Type, VoiceOver, light+dark.

---

## C. Tests that REMAIN (not yet covered)

- [ ] **C1 — Live E2E on a real *remote* host.** Only localhost-sim subset done. Needs a real SSH host. ⏸ owner-gated.
- [ ] **C2 — Physical-device APNs, app *closed*.** The whole point: background app → trigger approval → push → lock-screen Approve → agent unblocks. **Untested.** Needs physical iPhone + APNs `.p8` key. ⏸ owner-gated.
- [ ] **C3 — Expand the app-target UI suite.** Add: onboarding completeness, StoreKit IAP purchase, approve-from-lockscreen tests.
- [ ] **C4 — Reconnect / session-loss hardening as tests.** Background, network switch, daemon restart.
- [ ] **C5 — StoreKit IAP purchase verified in TestFlight** (sandbox account). ⏸ owner-gated.
- [ ] **C6 — Security review closure + semgrep triage.** Work `docs/SECURITY-REVIEW.md`.

---

## D. Owner-gated — App Store / external (one human action away)

- [x] **D1 — Confirm APNs secrets on the *running* backend.** ✅ Set on Cloud Run `conduit-push` (australia-southeast1) + hermes-box `relay.env`. `APPROVAL_RELAY_SECRET` enforced.
- [ ] **D2 — App Store Connect setup.** App record, Push + CloudKit + App Groups entitlements, IAP `dev.conduit.mobile.pro` Non-Consumable $14.99, privacy nutrition label, screenshots, reviewer notes.
- [ ] **D3 — Physical-device validation** (= C2).
- [ ] **D4 — Vanity domain + DNS.** Repoint `CONDUIT_PUSH_BACKEND_URL` off `sslip.io` to `push.conduit.dev`.
- [ ] **D5 — Archive → TestFlight → release.** Xcode Organizer or `fastlane`.

---

## E. Doc hygiene

- [ ] **E1 — Continue doc consolidation.** Keep useful evidence, route active state through this checklist and `docs/KNOWN_ISSUES.md`.

---

## Honest limits

App Store submission, TestFlight upload with distribution signing, production APNs cert verification, real remote-host E2E, DNS changes, and paid-account actions all require the owner. Engineering target = everything **green, committed, archivable, and documented to one human action.**
