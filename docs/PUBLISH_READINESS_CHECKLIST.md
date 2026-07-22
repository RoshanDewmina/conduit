# Lancer — Publish Readiness Checklist (single source of truth)

> Reconciled 2026-07-17 against the Workspaces production root + Tier 0 live-loop state
> (previous reconciliation 2026-07-15 had drifted — every claim below re-verified against
> `git log`/`gh pr view`/live source in this pass; see per-line evidence).
> When older archives disagree, **this file + `ARCHITECTURE.md` (§0.1 / §4.1) + `docs/STATUS_LEDGER.md` win.**
> (`LANCER_PROJECT_DOSSIER.md` and `docs/_archive/` were **purged 2026-07-06** — superseded by `ARCHITECTURE.md` §0.1.)

Legend: ✅ done/verified · 🔶 partial · ❌ not started · ⏸ owner-gated (one human action away)

---

## Path to App Store submission — 2026-07-17

Everything engineering-side that a human/agent can still finish is tracked in sections B/C below;
this is just the ordered remaining path once those close out. `origin/master` tip as of this
reconciliation: `265b62e1` (PR #164 merged 2026-07-17T17:28:31Z; see §A).

1. **Fresh archive → TestFlight upload** at current master tip (`265b62e1` or later). D5 below
   records a prior upload; re-cut once B3/B8/C3 close so the shipped build reflects Emergency
   Stop + governance wiring + perf fixes, not the earlier tip.
2. **Owner on-device validations** (⏸ owner-gated, cannot be done by an agent):
   - Lock-screen push / app-closed APNs approve-reject (C2/D3) — daemon-side fix is deployed;
     only remaining step is the owner watching the lock screen on the physical device.
   - Full dogfood smoke pass on the fresh TestFlight build (pair → dispatch → approve/deny →
     follow-up) per `docs/test-runs/2026-07-17-dual-product-dogfood/INSTALL_AND_SMOKE.md`.
   - StoreKit IAP sandbox purchase verification (C5).
3. **App Store Connect assets** (D2): app record, Push + CloudKit + App Groups entitlements,
   IAP `dev.lancer.mobile.pro` Non-Consumable **Founder's Edition $89.99** (see [`SHIP_PLAN.md`](SHIP_PLAN.md)
   decision 6), privacy nutrition label, screenshots, reviewer notes — **including promoting the CloudKit schema from Development to Production**
   in the CloudKit Dashboard (new record types `Conversation`/`ConversationTurnChunk` in the
   `LancerConversations` zone; see D2 detail).
4. **App Review submission** — after 1–3 are green/owner-signed-off.

---

## A. Verified GREEN (updated 2026-07-17)

**Master tip `265b62e1`** (PRs #154→#164 merged 2026-07-17; see `docs/CHANGELOG.md` 2026-07-17
section and `git log --oneline` for the full chain). Notable landings this batch, each verified
against `gh pr view` / `git show` in this reconciliation pass:

- **Emergency Stop — implemented + live-verified.** `d68de81e` (2026-07-15) wired the daemon's
  existing `agent.emergencyStop` RPC into Settings (confirmed destructive action, policy editor,
  read-only audit feed) — this closed the "DEAD = Emergency Stop UI" gap B7 previously tracked.
  **PR #160** (merged 2026-07-17T15:26:28Z, `docs/gap-reproof-2026-07-17`) then re-proved it live
  on an isolated Simurgh sim + isolated daemon and found it **FAIL**: the UI/audit reported
  "Stopped 2 runs" but the `PreToolUse` hook process holding a pending escalation survived 6+
  minutes. **PR #161** (merged 2026-07-17T15:30:53Z, `fix/emergency-stop-denies-pending`,
  commit `b8923a46`) closed the FAIL: `applyEmergencyStop` now denies every pending approval
  through the same `approvals.resolve` chokepoint a phone Reject uses (`deny-emergency-stop`
  audit action, `approvalRetired` sync) before stopping runs; TDD RED→GREEN, `go build`/`vet`/
  `test` green, orchestrator full-diff review on the sensitive approval path. **Net: Emergency
  Stop is DONE — implemented, found FAIL live, fixed, and the fix itself is TDD + reviewed.**
- **Hook-binary isolation fix** — PR #162 (`fix/hook-binary-isolation`, commit `3928b2d2`):
  dispatched agent env now pins `LANCERD=` to the dispatching daemon's own executable, closing
  a version-skew bug WP5 found live where isolated `LANCER_STATE_DIR` daemons were gating
  through the production `~/.lancer/bin/lancerd` binary.
- **Perf fixes (WP1)** — PR #163 (`perf/thread-feel`, commit `a2e2ca53`): fixed top thread-open/
  live-follow/thread-list perf offenders (diff-before-publish in `ShellLiveBridge`, memoized
  turn-transcript assembly, batched N+1 fix in `WorkspaceRepoCatalog.loadLocalRows`, 10.3x on
  150 conversations). Evidence: `docs/test-runs/2026-07-17-perf/README.md`.
- **Worktree triage + addrepo fix** — PR #164 (merged 2026-07-17T17:28:31Z, commit `026b0111`):
  salvaged a real un-landed fix (`fix/composer-addrepo-deadend`, master's `RepoPickerView` had
  no `AddRepoView` wiring) plus Lane C4 sweep evidence; **also the source of the B3 app-target
  BUILD SUCCEEDED evidence below** (Simurgh lease-207, 356s).

| Layer | Result | Evidence |
|---|---|---|
| LancerKit (SPM) build + tests | ✅ **548 Swift Testing tests / 91 suites + 13 HostServiceClient/VerificationPhrase tests pass** (2026-07-03, includes the new cross-device conversation sync suites) | `cd Packages/LancerKit && swift build && swift test` exit 0 |
| lancerd + policy (Go) | ✅ pass, incl. host conversation ledger + `attachObservedSession` import | `go test ./...` exit 0 |
| push-backend (Go) | ✅ pass | `go test ./...` exit 0 |
| agent-runner (Go) | ✅ pass | `go test ./...` exit 0 |
| Chat persistence + FTS search | ✅ v10 migrations, `ChatConversationRepository` with 18 tests | `ChatConversationRepositoryTests.swift` |
| Chat artifact cards + detail views | ✅ 7 card types, detail panels, 14 rendering tests | `ChatArtifactCards.swift`, `ChatArtifactDetailView.swift` |
| **Workspaces (production UI)** | ✅ `AppFeature/Workspaces/WorkspacesView.swift` is `AppRoot.readyRoot`; DEBUG via `LANCER_DESTINATION`. Retired CursorStyle / `LANCER_CURSOR_SHELL*` removed `6b97da65`. | `ARCHITECTURE.md` §0.1/§4.1, `docs/STATUS_LEDGER.md` 2026-07-11 frontend reversal |
| **Live relay dispatch (2026-06-19)** | ✅ phone→relay→daemon dispatch proven live (opencode "Hi" → `dispatch-launched`) | PATH fix in launchd plist; `agentRunContinue` chain verified end-to-end |
| **Push backend (canonical, cut over 2026-07-13)** | ✅ Fly **`conduit-push`** (`conduit-push.fly.dev`, always-on `iad`) — `/health` 200; relay route live; APNs secret names wired; `APPROVAL_RELAY_SECRET` enforced (401 on unauth). The retired Cloud Run endpoint returns 404. | Fly app `conduit-push` |
| Fleet thread routing | ✅ `FleetThreadMapper` with 4 tests | maps host/agent/cwd to conversation |
| Relay regression script | ✅ `scripts/relay-regression.sh` created | repeatable localhost approval loop (`LANCER_DAEMON_E2E=1` + `LANCER_DESTINATION=review`) |
| **Full live governed-approvals loop** | 🔶 **simulator path proven historically**; tip re-proof + device still open (see B10 / C2) | `scripts/relay-regression.sh`; `ARCHITECTURE.md` §0.1 |
| **App-closed physical-device approval loop** | ⏸ **Historical PASS 2026-07-08 evening; current tip re-proof PENDING** | Evening force-quit + lock Approve/Reject reached host audit after #52 + `732071a7` — [`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (`79137ae4…` / `461bc3e0…`). Morning FAIL (same day) is historical: [`docs/test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md). Tip has moved (`b18f519d`+); Layer 0 CLOSED only after fresh proof in [`docs/test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md). |
| **Governance in Settings** | ✅ merged | Policy/audit/secrets/drift/doctor/usage under Settings → Policy & Governance; no separate Control root |
| **TestFlight** | ✅ uploaded | Build uploaded; release remains gated on beta validation/App Review/owner store operations |
| Visual consistency, light+dark | ✅ | polish batch 1 |

**Two live-relay bugs found & fixed (June 17):** TOFU first-connect never armed the daemon channel;
UUID case mismatch dropped every phone decision. Both fixed, regression-tested.

---

## B. Engineering — finish/verify before publish (things we can do)

- [x] **B1 — Reconcile the current working tree before release.** ✅ 2026-06-20: Codex's account-identity + V1-surface WIP verified (414 SPM tests, app-target UI 7/7 iPhone+iPad, all 3 Go modules, resident smoke 4/4) and committed to `codex/ios27-shell-workspace`; device-management screen added. No secrets staged (Supabase config is `$(...)` placeholders).
- [x] **B0 — Restore the tester loop (P0).** ✅ Canonical relay is `https://conduit-push.fly.dev`; source defaults and exact-host persisted-pairing migration are in the 2026-07-13 cutover branch. `scripts/release-lancerd.sh` emits the flat installer artifacts required by the published installer.
- [x] **B2 — Make the live app↔daemon relay repeatable.** ✅ `scripts/relay-regression.sh` created. Run it to verify the loop.
- [x] **B3 — Green *app-target* build/archive on this cleanup branch.** ✅ GREEN as of 2026-07-17: `xcodebuild build -project Lancer.xcodeproj -scheme Lancer` via Simurgh lease-207 → **BUILD SUCCEEDED** (356s). Landed as part of **PR #164** (`salvage/worktree-triage-2026-07-17`, merged 2026-07-17T17:28:31Z, commit `026b0111`); also recorded in `docs/CHANGELOG.md` 2026-07-17. Archive/upload still needs a fresh cut per the "Path to App Store submission" section above.
- [x] **B4 — Rebuild/repackage lancerd from Go source.** ✅ VERIFIED 2026-07-15: `scripts/release-lancerd.sh audit-b4-local` ran locally (exit 0), building all four GOOS/GOARCH targets from Go source + flat binaries + SHA256SUMS + install.sh under `daemon/lancerd/dist/`; `gsutil` publish is an echoed owner step only, never executed by the script.
- [ ] **B5 — Finish remaining pixel polish.** Polish list being re-derived by the 2026-07-15 states/a11y audit; tracked in `docs/CHANGELOG.md` PRs. (The old "16 pixel-polish items in KNOWN_ISSUES.md" claim was a phantom — that enumerated list does not exist.)
- [ ] **B6 — Reconcile the push-backend WIP.** Divergent security design parked in stash.
- [x] ~~**B7 — Feature-wiring audit.** AUDITED 2026-07-15: WIRED = composer, Trusted Machines/pairing, Proof Reel, Flight Recorder, chat artifact cards. DEAD = Emergency Stop UI (P0, see B11b — daemon RPC exists/tested, no UI), policy editor (AppSettingsView deferred text), audit feed (tailAudit unwired), drift surface, usage dashboard (placeholder). Wiring of the first three in flight on `feat/w2-governance-wiring`; close B7 when that lands + drift/usage get a keep-or-delete decision.~~ **SUPERSEDED 2026-07-17:** the three DEAD items (Emergency Stop UI, policy editor, audit feed) landed in commit `d68de81e` ("feat(ios): wire Emergency Stop, policy editor, audit feed into Settings", 2026-07-15 21:41:47 -0400) — confirmed destructive Emergency Stop over `agent.emergencyStop` (SSH + relay `agentEmergencyStop` mirror), thin `PolicyEditorView` over policyGet/policySave, read-only `AuditFeedView` over tailAudit. Emergency Stop was then live-re-proven (see A / B11b, PR #160 FAIL → PR #161 fix). **Remaining open from the original audit: drift surface and usage dashboard are still placeholder/undecided** — carry those forward as a new B7b if the owner wants them tracked, otherwise treat as intentionally deferred post-launch.
- [ ] **B8 — Empty/error/loading + a11y sweep.** Every surface: empty/loading/error states, Dynamic Type, VoiceOver, light+dark.
- [x] **B9 — Cross-device conversation sync: add `CKDatabaseSubscription` for background pull.** ✅ DONE 2026-07-03. `CloudSync.ensureDatabaseSubscriptionExists` registers a `CKDatabaseSubscription` (idempotent, `shouldSendContentAvailable`); `ConversationSyncEngine.start()` registers it after the first sync (best-effort — entitlement issues fall back to the pre-existing foreground-only behavior); `AppDelegate.didReceiveRemoteNotification` now distinguishes a CloudKit push from an APNs approval push and routes to `ConversationSyncEngine.handleRemoteNotification(subscriptionID:)`. Registration + routing are code-complete and unit-tested; actual silent-push delivery is still unverified on hardware — see C7.
- [ ] **B10 — Prove Tier 0 through the live Workspaces shell.** Launch with `LANCER_DAEMON_E2E=1` + `LANCER_DESTINATION=review` (see `scripts/relay-regression.sh:70–78`) and complete pair → dispatch → approve/deny → follow-up against the real daemon/relay path. Do **not** use retired `LANCER_CURSOR_SHELL*` flags.
- [x] **B11a — `BiometricGate` no-passcode fail-open.** ✅ Moot as of 2026-07-07 — Face ID/biometric
  gating was removed from the app entirely (permanent product decision), so there is no gate left to
  fail open. See `docs/legal/SECURITY_ARCHITECTURE.md` §5.1.
- [x] ~~**B11b — Close remaining P0 beta blockers.** External beta is blocked until Emergency Stop is
  implemented as a daemon-side atomic primitive, or the owner explicitly signs off on a
  release-blocking exception.~~ **CLOSED 2026-07-17.** Emergency Stop is implemented as a
  daemon-side atomic primitive AND live-verified: **PR #160** (`docs/gap-reproof-2026-07-17`,
  merged 2026-07-17T15:26:28Z) live-re-proved it on an isolated Simurgh sim + isolated daemon
  and found it **FAIL** (UI/audit claimed "Stopped 2 runs" but the `PreToolUse` hook process
  holding a pending sleep-120 escalation survived 6+ minutes — production daemon/audit log
  confirmed untouched by the test). **PR #161** (`fix/emergency-stop-denies-pending`, merged
  2026-07-17T15:30:53Z, commit `b8923a46`) closed the FAIL: `applyEmergencyStop` now denies
  every pending approval through the same `approvals.resolve` chokepoint the phone Reject path
  uses (`deny-emergency-stop` audit action per approval, `approvalRetired` sync), then stops
  runs; result payload adds `deniedApprovals`. TDD (RED proven first), `go build`/`vet`/`test`
  green, orchestrator full-diff review on the sensitive approval path: approved. No P0 beta
  blocker remains on this item.

---

## C. Tests that REMAIN (not yet covered)

- [ ] **C1 — Live E2E on a real *remote* host.** Only localhost-sim subset done. Needs a real SSH host. ⏸ owner-gated.
- [ ] ~~**C2 — Physical-device APNs, app *closed* (checkpoint 5c).** **Historical PASS** 2026-07-08 evening on tip `732071a7` — [`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (Approve `79137ae4…`, Reject `461bc3e0…`) after #52 delivery + content-hash/race fixes. Morning FAIL same day is historical (`docs/test-runs/2026-07-08-tier0-device-proof-results.md`). **Current tip re-proof: still PENDING as of master `65bed890` (2026-07-15)** — a **10/10 Simulator** reconnect proof was claimed 2026-07-15 but its evidence bundle was never committed (integrity gap); re-prove or restore before citing. **No physical-device re-proof yet**, and is additionally blocked right now because a 2026-07-15 test-harness mistake orphaned the owner's real phone pairing (see `docs/STATUS_LEDGER.md` "2026-07-15 in one line") — the owner must re-pair before this can be re-run on device.~~ **UPDATED 2026-07-17** per `docs/STATUS_LEDGER.md` top-of-file state (master `265b62e1`/`c85f4a7e` era): the phone-orphan from 2026-07-15 is resolved — pairing is **confirmed live** ("pair confirmed live (no remint) after reinstall"), and the daemon-side APNs app-closed-push fix has been **deployed** (phone relaunched at the new tip). The **only remaining gap is the owner watching the physical device's lock screen** to confirm the push actually surfaces and Approve/Reject round-trips — this is now a single owner-gated action, not an engineering gap. ⏸ owner-gated.
- [ ] **C3 — Expand the app-target UI suite.** Add: onboarding completeness, StoreKit IAP purchase, approve-from-lockscreen tests.
- [ ] **C4 — Reconnect / session-loss hardening as tests.** Background, network switch, daemon restart. Partial: daemon-restart durability for the conversation ledger specifically was live-verified 2026-07-03 (9 real conversations across 3 vendors, full turn/event/vendor-session data, survived a complete `lancerd` process restart byte-for-byte; dispatch resumed working immediately after) — see `ARCHITECTURE.md` §0.1 / §11.2. iOS-side background/network-switch/reconnect behavior remains untested.
- [ ] **C5 — StoreKit IAP purchase verified in TestFlight** (sandbox account). ⏸ owner-gated.
- [ ] **C6 — Security review closure + semgrep triage.** Work `docs/SECURITY-REVIEW.md`.
- [ ] **C7 — Cross-device conversation sync: two-device CloudKit QA.** Host-ledger behavior (append, conflict, offline, observed-session import) is covered by `go test ./...` + LancerKit tests, but the CloudKit private-mirror propagation itself (start on A → appears on B; kill/reinstall A → restores from CloudKit) is unverified on physical hardware — `CloudSync`/`ConversationSyncEngine` are simulator no-ops by design. Run `docs/LIVE_LOOP_RUNBOOK.md` Phase 7 on two devices signed into the same iCloud account. ⏸ owner-gated (needs a second physical Apple device).

---

## D. Owner-gated — App Store / external (one human action away)

- [x] **D1 — Confirm APNs secret names on the *running* backend.** ✅ Deployed on Fly `conduit-push`; relay secret enforcement returns 401 unauthenticated. Physical-device APNs delivery remains checkpoint C2.
- [ ] **D2 — App Store Connect setup.** App record, Push + CloudKit + App Groups entitlements, IAP `dev.lancer.mobile.pro` Non-Consumable **Founder's Edition $89.99** (see [`SHIP_PLAN.md`](SHIP_PLAN.md) decision 6), privacy nutrition label, screenshots, reviewer notes. **CloudKit schema note (added 2026-07-03):** the cross-device conversation sync feature adds a custom private-DB zone (`LancerConversations`) with two new record types (`Conversation`, `ConversationTurnChunk` — see `ARCHITECTURE.md` §11.2 and `SyncKit/ConversationCloudRecords.swift`). These are auto-created in the **Development** CloudKit environment the first time the app runs against it; before the App Store build ships, promote the schema from Development to **Production** in the CloudKit Dashboard (Container → Schema → Deploy Schema Changes) or new-device users will fail to sync conversations against a container that only knows the old (Hosts/Snippets) record types.
- [ ] ~~**D3 — Physical-device validation** (= C2). Evening 2026-07-08 historical PASS on `732071a7` (see C2 / `2026-07-08-tier0-5c-retest-results.md`). **Current tip re-proof PENDING** — blocked on fresh 5c in `2026-07-09-tier0-device-proof-results.md`.~~ **UPDATED 2026-07-17** — same state as C2 above: pairing confirmed live after reinstall, daemon-side APNs fix deployed; only remaining step is the owner watching the lock screen on the physical device. ⏸ owner-gated (single action).
- [x] ~~**D4 — Vanity domain + DNS.** Repoint `LANCER_PUSH_BACKEND_URL` off `sslip.io` to `push.conduit.dev`.~~ **STALE/CLOSED 2026-07-17:** this line described infra retired before the 2026-07-13 Fly cutover (§A "Push backend (canonical, cut over 2026-07-13)"). Verified in source this pass — `sslip.io` does not appear as a live default anywhere: `RelaySettings.swift:21` (`Packages/LancerKit/Sources/SSHTransport/RelaySettings.swift`) sets `defaultURLString = "wss://conduit-push.fly.dev"`, and `retiredHostedURLString` (line 13) is the old `conduit-push-y4wpy6zeva-ts.a.run.app` Cloud Run host, not sslip.io. `project.yml:25` sets `LANCER_PUSH_BACKEND_URL: "https://conduit-push.fly.dev"` for builds. `conduit-push.fly.dev` **is** the vanity-ish canonical URL already in place; no `push.conduit.dev` DNS repoint has happened or is referenced anywhere in source. Closing this item as **moot** — the original sslip.io premise no longer exists. If the owner still wants a `push.conduit.dev`-style custom domain over the current `conduit-push.fly.dev`, that's a new, separate DNS/infra task, not a completion of this one.
- [x] **D5 — Archive → TestFlight upload.** ✅ TestFlight build uploaded; release/App Review remains owner-gated after beta validation.

---

## E. Doc hygiene

- [ ] **E1 — Continue doc consolidation.** Keep useful evidence, route active state through this checklist, `ARCHITECTURE.md` §0.1, `docs/KNOWN_ISSUES.md`, and the Tier 0 gap matrix. July 4/5 Away/Proof/Siri/design artifacts remain context until the Tier 0 live shell and validation gates are proven.

---

## Honest limits

App Store submission, TestFlight upload with distribution signing, production APNs cert verification, real remote-host E2E, DNS changes, and paid-account actions all require the owner. Engineering target = everything **green, committed, archivable, and documented to one human action.**
