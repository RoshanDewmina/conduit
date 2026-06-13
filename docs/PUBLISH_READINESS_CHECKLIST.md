# Conduit — Publish Readiness Checklist (single source of truth)

> Reconciled 2026-06-13 against **today's verified state** (not older docs).
> Supersedes the status claims in `remaining-work.md` (2026-05-28, stale: says "free team"),
> and reconciles `ship-gate-owner-steps.md` + `PRODUCTION_READINESS_PLAN.md` + `validation-playbook.md`.
> When those disagree, **this file + `CONDUIT_PROJECT_DOSSIER.md` win.**

Legend: ✅ done/verified · 🔶 partial · ❌ not started · ⏸ owner-gated (one human action away)

---

## A. Verified GREEN today (2026-06-13 evidence)

| Layer | Result | Evidence |
|---|---|---|
| ConduitKit (SPM) build + tests | ✅ **337 tests / 57 suites pass** | `swift build && swift test` exit 0 |
| conduitd (Go) + policy | ✅ pass | `go test ./...` exit 0 |
| push-backend (Go) | ✅ pass | `go test ./...` exit 0 |
| agent-runner (Go) | ✅ pass | `go test ./...` exit 0 |
| **Full live governed-approvals loop** (real `claude` → hook → daemon → policy → **phone card** → approve → agent unblocked) | ✅ **proven on simulator** after fixing 2 bugs | `docs/test-runs/2026-06-12-live-loop-pass1.md`; audit `approve` at +20s |
| 4 main tabs visual consistency (Inbox/Fleet/Activity/Settings), light+dark | ✅ | polish batch 1, screenshotted |

**Two live-relay bugs found & fixed this session** (regression-tested): TOFU first-connect never armed the daemon channel (`SessionViewModel.trustHostKey` → `onReconnected`); UUID case mismatch dropped every phone decision (`approvalStore` normID + `approval_case_test.go`). **These fixes are currently UNCOMMITTED.**

---

## B. Engineering — finish/verify before publish (things we can do)

- [ ] **B1 — Commit the uncommitted session work.** 2 bug fixes + polish + dead-view archive + `DSCard`/`LibrarySupportViews` + `approval_case_test.go` + the 3 docs are all uncommitted. Land on a branch (`feat/live-loop-fix-and-polish`), grouped commits. *Blocks everything downstream from being reviewable.*
- [ ] **B2 — Make the live app↔daemon relay repeatable.** It's been proven **once** on the sim. Add a scripted/automated regression (beyond the Go unit test) so a reconnect/TOFU path can't silently regress the channel-arming again.
- [ ] **B3 — Green *app-target* Release build + clean archive.** SPM tests pass, but the full Xcode scheme (iOS + watch + widgets) catches strict-concurrency breaks SPM misses, and is required to archive. **Not run this session.** Resolve the watchOS runtime gate (`xcodebuild -downloadPlatform watchOS`, or a CI config that builds iOS-only without deleting the watch target).
- [ ] **B4 — Rebuild/repackage conduitd from Go source.** The shipped `daemon/conduitd/conduitd-darwin-arm64` is **stale Swift 0.1.0 with no policy engine**. `scripts/release-conduitd.sh` must emit the Go build, and any deployed daemon must be the Go one — else governance silently ships disabled.
- [ ] **B5 — Finish the 16 remaining pixel-polish items.** Documented with file:line in `docs/superpowers/specs/2026-06-12-conduit-pixel-perfect-polish-plan.md` (Billing/Paywall/Onboarding DS headers, 44pt touch targets, card chrome/dividers, P2 nits).
- [ ] **B6 — Reconcile the push-backend WIP.** Divergent security design parked in `stash@{0}` + `/tmp/pushbackend-wip-backup-…`. Decide, land or drop, document.
- [ ] **B7 — Feature-wiring audit.** Confirm policy editor, "while you were away" audit feed, cross-vendor usage dashboard, and dispatch/schedule composer are all reachable from **real navigation** (not only `CONDUIT_GALLERY`). Some done; verify each with UI automation + screenshot.
- [ ] **B8 — Empty/error/loading + a11y sweep.** Every surface: empty/loading/error states, Dynamic Type, VoiceOver labels, light+dark. (Reliability is the wedge.)

---

## C. Tests that REMAIN (not yet covered)

- [ ] **C1 — Live E2E on a real *remote* host** (`validation-playbook.md` TC-1..TC-7). Only the localhost-sim subset is done. fish shell untested. Needs a real SSH host running claude/codex/opencode. ⏸ owner-gated (host).
- [ ] **C2 — Physical-device APNs, app *closed* (Pass 2).** The whole point of the product: background/close the app → trigger an approval on the host → push within ~2s → tap **Approve** on lock screen → decision relay unblocks the agent. **Untested.** Needs a physical iPhone + the APNs `.p8` (exists). ⏸ owner-gated (device).
- [ ] **C3 — Expand the app-target UI suite.** Only `TapInjectionProofTests` (5 tests: tap-injection, approve-applies, approve-evidence, Face ID opt-in, saved-host reconnect). Add: onboarding completeness (Guideline 2.1), StoreKit IAP purchase, approve-from-lockscreen.
- [ ] **C4 — Reconnect / session-loss hardening as tests.** Background, network switch, daemon restart → queue drains, transcript restores ("never lose a session"). Use the local-sshd fixture.
- [ ] **C5 — StoreKit IAP purchase verified in TestFlight** (sandbox account). ⏸ owner-gated (App Store Connect + TestFlight).
- [ ] **C6 — Security review closure + semgrep triage.** Work `docs/SECURITY-REVIEW.md`; confirm secrets never logged, audit redaction holds, TOFU prompt intact in **prod** paths, fail-closed autonomy verified.

---

## D. Owner-gated — App Store / external (one human action away)

- [ ] **D1 — Confirm APNs secrets on the *running* backend.** Health is 200, but push reads env lazily. Confirm `APNS_KEY_ID=L8LVU9X82W`, `APNS_TEAM_ID=39HM2X8GS6`, `APNS_BUNDLE_ID=dev.conduit.mobile`, `APNS_KEY_PATH` per `push-backend-deploy-env.md`. *(Also confirm the backend instance is running the current Go push-backend, per B4.)*
- [ ] **D2 — App Store Connect setup.** App record (`dev.conduit.mobile`, "Conduit"); enable Push + CloudKit (`iCloud.dev.conduit.mobile`) + App Groups (`group.dev.conduit.mobile`); IAP `dev.conduit.mobile.pro` Non-Consumable $14.99; privacy nutrition label (no tracking; declare APNs token + subscription data; "source never leaves device"); age 4+; screenshots from `docs/screenshots/governed-approvals/`; reviewer notes (remote shell, not local execution → pre-empt 2.5.2).
- [ ] **D3 — Physical-device validation** (= C2). APNs is a no-op in the simulator.
- [ ] **D4 — Vanity domain + DNS.** Repoint `CONDUIT_PUSH_BACKEND_URL` off the raw IP `35.201.3.231.sslip.io` onto e.g. `push.conduit.dev`; DNS for conduit.dev (Route53: A `conduit.dev→76.76.21.21`, CNAME `www→cname.vercel-dns.com`) so `/privacy` + `/subscribe` are live for review.
- [ ] **D5 — Archive → TestFlight → release.** Xcode Organizer or `fastlane beta`/`release` if creds present.

---

## E. Doc hygiene

- [ ] **E1 — Kill the doc drift.** `remaining-work.md` (2026-05-28) still says "free personal team" / "v0.1.0 on GCP" — both stale. Mark it superseded by this file + the dossier. Pre-empts an agent acting on wrong account/deploy state.

---

## Honest limits (cannot fake; get to "one action away")

App Store *submission*, TestFlight upload with distribution signing, production APNs cert verification on a live send, real remote-host E2E, DNS changes, and paid-account actions all require the owner. Engineering target = everything **green, committed, archivable, and documented to one human action.**
