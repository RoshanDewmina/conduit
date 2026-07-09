# Lancer — Publish Readiness Checklist (single source of truth)

> Reconciled 2026-07-06 against the current Tier 0 live Cursor shell state.
> Supersedes the status claims in the purged `docs/_archive/remaining-work.md` (2026-05-28, stale: says "free team"),
> and reconciles `ship-gate-owner-steps.md` + purged `docs/_archive/PRODUCTION_READINESS_PLAN.md` + `validation-playbook.md`.
> When those disagree, **this file + `ARCHITECTURE.md` (§0.1 / §4.1) + `docs/STATUS_LEDGER.md` win.**
> (`LANCER_PROJECT_DOSSIER.md` and `docs/_archive/` were **purged 2026-07-06** — superseded by `ARCHITECTURE.md` §0.1.)

Legend: ✅ done/verified · 🔶 partial · ❌ not started · ⏸ owner-gated (one human action away)

---

## A. Verified GREEN (updated 2026-06-27)

| Layer | Result | Evidence |
|---|---|---|
| LancerKit (SPM) build + tests | ✅ **548 Swift Testing tests / 91 suites + 13 HostServiceClient/VerificationPhrase tests pass** (2026-07-03, includes the new cross-device conversation sync suites) | `cd Packages/LancerKit && swift build && swift test` exit 0 |
| lancerd + policy (Go) | ✅ pass, incl. host conversation ledger + `attachObservedSession` import | `go test ./...` exit 0 |
| push-backend (Go) | ✅ pass | `go test ./...` exit 0 |
| agent-runner (Go) | ✅ pass | `go test ./...` exit 0 |
| Chat persistence + FTS search | ✅ v10 migrations, `ChatConversationRepository` with 18 tests | `ChatConversationRepositoryTests.swift` |
| Chat artifact cards + detail views | ✅ 7 card types, detail panels, 14 rendering tests | `ChatArtifactCards.swift`, `ChatArtifactDetailView.swift` |
| **Cursor shell (production UI)** | ✅ `CursorAppShell` under `AppFeature/CursorStyle/` — Home / Workspaces / Settings | `LANCER_CURSOR_SHELL=1` (mock), `LANCER_CURSOR_SHELL_LIVE=1` (live bridge); see `ARCHITECTURE.md` §4.1 |
| **Cursor shell live bridge (2026-07-06)** | ✅ pairing, workspaces, dispatch, approval, continue wired through `CursorShellLiveBridge` | `docs/test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md` |
| **Live relay dispatch (2026-06-19)** | ✅ phone→relay→daemon dispatch proven live (opencode "Hi" → `dispatch-launched`) | PATH fix in launchd plist; `agentRunContinue` chain verified end-to-end |
| **Push backend (canonical, reconciled 2026-06-24)** | ✅ Cloud Run **`conduit-push`** (`conduit-push-y4wpy6zeva-ts.a.run.app`, the URL `project.yml:26` ships) — `/health` 200; APNs keys wired, `APPROVAL_RELAY_SECRET` enforced (401 on unauth), lancerd sends Bearer token on `/register`. (Name preserved per rebrand infra-migration; the earlier `lancer-push`/australia-southeast1 reference was doc drift.) | `roshan-agent-f1c2466d` project |
| Fleet thread routing | ✅ `FleetThreadMapper` with 4 tests | maps host/agent/cwd to conversation |
| Relay regression script | ✅ `scripts/relay-regression.sh` created | repeatable localhost approval loop |
| **Full live governed-approvals loop** | ✅ **proven on simulator** after fixing 2 bugs | `docs/test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md`; `ARCHITECTURE.md` §0.1 |
| **App-closed physical-device approval loop** | ⏸ **Historical PASS 2026-07-08 evening; current tip re-proof PENDING** | Evening force-quit + lock Approve/Reject reached host audit after #52 + `732071a7` — [`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (`79137ae4…` / `461bc3e0…`). Morning FAIL (same day) is historical: [`docs/test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md). Tip has moved (`b18f519d`+); Layer 0 CLOSED only after fresh proof in [`docs/test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md). |
| **Governance in Settings** | ✅ merged | Policy/audit/secrets/drift/doctor/usage under Settings → Policy & Governance (Cursor shell); no separate Control root |
| **TestFlight** | ✅ uploaded | Build uploaded; release remains gated on beta validation/App Review/owner store operations |
| Visual consistency, light+dark | ✅ | polish batch 1 |

**Two live-relay bugs found & fixed (June 17):** TOFU first-connect never armed the daemon channel;
UUID case mismatch dropped every phone decision. Both fixed, regression-tested.

---

## B. Engineering — finish/verify before publish (things we can do)

- [x] **B1 — Reconcile the current working tree before release.** ✅ 2026-06-20: Codex's account-identity + V1-surface WIP verified (414 SPM tests, app-target UI 7/7 iPhone+iPad, all 3 Go modules, resident smoke 4/4) and committed to `codex/ios27-shell-workspace`; device-management screen added. No secrets staged (Supabase config is `$(...)` placeholders).
- [x] **B0 — Restore the tester loop (P0).** ✅ RECONCILED 2026-06-24 (see `KNOWN_ISSUES.md` §0): (a) the canonical relay `https://conduit-push-y4wpy6zeva-ts.a.run.app` (the URL `project.yml:26` actually ships) returns `/health` 200 — the `sslip.io` / `lancer-push` references were stale doc drift; (b) `scripts/release-lancerd.sh` now emits the flat `lancerd_${os}_${arch}` binaries + `SHA256SUMS` + `install.sh` that the installer consumes, and the `curl|sh` loop was proven end-to-end offline. **Owner step:** run the release script + the printed `gsutil cp … gs://conduit-dist-f1c2466d/` to publish the binaries.
- [x] **B2 — Make the live app↔daemon relay repeatable.** ✅ `scripts/relay-regression.sh` created. Run it to verify the loop.
- [ ] **B3 — Green *app-target* build/archive on this cleanup branch.** Requires Xcode (watchOS runtime gate). SPM passes, but full Xcode scheme catches strict-concurrency breaks SPM misses.
- [ ] **B4 — Rebuild/repackage lancerd from Go source.** `scripts/release-lancerd.sh` must emit the Go build.
- [ ] **B5 — Finish the 16 remaining pixel-polish items.** Track in `docs/KNOWN_ISSUES.md` (previously `docs/superpowers/specs/2026-06-12-lancer-pixel-perfect-polish-plan.md`, purged 2026-07-06).
- [ ] **B6 — Reconcile the push-backend WIP.** Divergent security design parked in stash.
- [ ] **B7 — Feature-wiring audit.** Confirm policy editor, audit feed, usage dashboard, composer reachable from real navigation.
- [ ] **B8 — Empty/error/loading + a11y sweep.** Every surface: empty/loading/error states, Dynamic Type, VoiceOver, light+dark.
- [x] **B9 — Cross-device conversation sync: add `CKDatabaseSubscription` for background pull.** ✅ DONE 2026-07-03. `CloudSync.ensureDatabaseSubscriptionExists` registers a `CKDatabaseSubscription` (idempotent, `shouldSendContentAvailable`); `ConversationSyncEngine.start()` registers it after the first sync (best-effort — entitlement issues fall back to the pre-existing foreground-only behavior); `AppDelegate.didReceiveRemoteNotification` now distinguishes a CloudKit push from an APNs approval push and routes to `ConversationSyncEngine.handleRemoteNotification(subscriptionID:)`. Registration + routing are code-complete and unit-tested; actual silent-push delivery is still unverified on hardware — see C7.
- [ ] **B10 — Prove Tier 0 through the live Cursor shell.** `LANCER_CURSOR_SHELL_LIVE=1` must complete pair → dispatch → approve/deny → follow-up against the real daemon/relay path. The shell is merged and partially wired; seeded `LANCER_CURSOR_SHELL=1` coverage is not sufficient for external beta.
- [x] **B11a — `BiometricGate` no-passcode fail-open.** ✅ Moot as of 2026-07-07 — Face ID/biometric
  gating was removed from the app entirely (permanent product decision), so there is no gate left to
  fail open. See `docs/legal/SECURITY_ARCHITECTURE.md` §5.1.
- [ ] **B11b — Close remaining P0 beta blockers.** External beta is blocked until Emergency Stop is
  implemented as a daemon-side atomic primitive, or the owner explicitly signs off on a
  release-blocking exception.

---

## C. Tests that REMAIN (not yet covered)

- [ ] **C1 — Live E2E on a real *remote* host.** Only localhost-sim subset done. Needs a real SSH host. ⏸ owner-gated.
- [ ] **C2 — Physical-device APNs, app *closed* (checkpoint 5c).** **Historical PASS** 2026-07-08 evening on tip `732071a7` — [`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (Approve `79137ae4…`, Reject `461bc3e0…`) after #52 delivery + content-hash/race fixes. Morning FAIL same day is historical (`docs/test-runs/2026-07-08-tier0-device-proof-results.md`). **Current tip re-proof: PENDING** — tip moved (`b18f519d`+); do not treat evening PASS as current-tip green. Fresh owner+agent run → [`docs/test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md).
- [ ] **C3 — Expand the app-target UI suite.** Add: onboarding completeness, StoreKit IAP purchase, approve-from-lockscreen tests.
- [ ] **C4 — Reconnect / session-loss hardening as tests.** Background, network switch, daemon restart. Partial: daemon-restart durability for the conversation ledger specifically was live-verified 2026-07-03 (9 real conversations across 3 vendors, full turn/event/vendor-session data, survived a complete `lancerd` process restart byte-for-byte; dispatch resumed working immediately after) — see `ARCHITECTURE.md` §0.1 / §11.2. iOS-side background/network-switch/reconnect behavior remains untested.
- [ ] **C5 — StoreKit IAP purchase verified in TestFlight** (sandbox account). ⏸ owner-gated.
- [ ] **C6 — Security review closure + semgrep triage.** Work `docs/SECURITY-REVIEW.md`.
- [ ] **C7 — Cross-device conversation sync: two-device CloudKit QA.** Host-ledger behavior (append, conflict, offline, observed-session import) is covered by `go test ./...` + LancerKit tests, but the CloudKit private-mirror propagation itself (start on A → appears on B; kill/reinstall A → restores from CloudKit) is unverified on physical hardware — `CloudSync`/`ConversationSyncEngine` are simulator no-ops by design. Run `docs/LIVE_LOOP_RUNBOOK.md` Phase 7 on two devices signed into the same iCloud account. ⏸ owner-gated (needs a second physical Apple device).

---

## D. Owner-gated — App Store / external (one human action away)

- [x] **D1 — Confirm APNs secrets on the *running* backend.** ✅ Set on Cloud Run `lancer-push` (australia-southeast1) + hermes-box `relay.env`. `APPROVAL_RELAY_SECRET` enforced.
- [ ] **D2 — App Store Connect setup.** App record, Push + CloudKit + App Groups entitlements, IAP `dev.lancer.mobile.pro` Non-Consumable $14.99, privacy nutrition label, screenshots, reviewer notes. **CloudKit schema note (added 2026-07-03):** the cross-device conversation sync feature adds a custom private-DB zone (`LancerConversations`) with two new record types (`Conversation`, `ConversationTurnChunk` — see `ARCHITECTURE.md` §11.2 and `SyncKit/ConversationCloudRecords.swift`). These are auto-created in the **Development** CloudKit environment the first time the app runs against it; before the App Store build ships, promote the schema from Development to **Production** in the CloudKit Dashboard (Container → Schema → Deploy Schema Changes) or new-device users will fail to sync conversations against a container that only knows the old (Hosts/Snippets) record types.
- [ ] **D3 — Physical-device validation** (= C2). Evening 2026-07-08 historical PASS on `732071a7` (see C2 / `2026-07-08-tier0-5c-retest-results.md`). **Current tip re-proof PENDING** — blocked on fresh 5c in `2026-07-09-tier0-device-proof-results.md`.
- [ ] **D4 — Vanity domain + DNS.** Repoint `LANCER_PUSH_BACKEND_URL` off `sslip.io` to `push.conduit.dev`.
- [x] **D5 — Archive → TestFlight upload.** ✅ TestFlight build uploaded; release/App Review remains owner-gated after beta validation.

---

## E. Doc hygiene

- [ ] **E1 — Continue doc consolidation.** Keep useful evidence, route active state through this checklist, `ARCHITECTURE.md` §0.1, `docs/KNOWN_ISSUES.md`, and the Tier 0 gap matrix. July 4/5 Away/Proof/Siri/design artifacts remain context until the Tier 0 live shell and validation gates are proven.

---

## Honest limits

App Store submission, TestFlight upload with distribution signing, production APNs cert verification, real remote-host E2E, DNS changes, and paid-account actions all require the owner. Engineering target = everything **green, committed, archivable, and documented to one human action.**
