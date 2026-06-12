# Fable Findings — Governed Approvals v1 pre-submission audit

> Durable scratchpad for the full pre-App-Store-submission pass (2026-06-12).
> Phases: 1 orient/baseline · 2 feature coverage · 3 exhaustive review · 4 E2E sim run ·
> 5 UX polish · 6 submission readiness · 7 verify & report.

## Status

- [x] Phase 1 — Orient & green baseline
- [x] Phase 2 — Feature inventory & coverage matrix (`FEATURE_COVERAGE.md`)
- [x] Phase 3 — Exhaustive static review & hardening (governed-approvals path first)
- [~] Phase 4 — E2E run: builds/tests/relay/idempotency **verified**; live-approval/TOFU/M6 runtime **BLOCKED** by HID tooling (see Continuation §)
- [x] Phase 5 — UX/UI/perf polish (code-complete, app-target build 0/0; sim-visual pending on HID fix)
- [ ] Phase 6 — Submission readiness (go/no-go)
- [ ] Phase 7 — Final verification & report (`FABLE_REPORT.md`)

## Continuation — Phase 4 E2E + Phase 5 (2026-06-12, second session)

Checkpoint commit `f6a36a55` froze all Phase 1–3 work; Phase 4 verification ran against it (in an
isolated worktree, detached at `f6a36a55`), Phase 5 was implemented on `feat/governed-approvals`.

### Phase 5 — UX polish (DONE, build-verified; sim-visual pending)

Commits on `feat/governed-approvals`:
- `680ee7eb` — 14 token-drift fixes; `TextPreview` NUL-byte binary guard (MAJOR); `SnippetEditor`
  preserves `hostTags`/`tags` on edit (MAJOR); iPad `NavigationStack` in `regularRoot` (MAJOR-2).
- `ab1e8a04` — Face ID opt-in persists `appLockEnabled` only on real success (MAJOR-3); removed dead
  shipped UI (Library +new, mock Workflows card, RECENT run-rows); deleted orphaned
  `WorkflowsView`/`HistoryView` (DEBUG gallery views kept).
- `500c0981` — saved-hosts reconnect list + dedup (MAJOR-4): `AddHostView` upserts by `host:port:user`
  (no duplicate records, preserves trusted host-key); `FleetView` "Saved hosts" section
  (tap-reconnect, swipe-delete).

Verification: ConduitKit `swift build` green every chunk; **app-target `xcodebuild` SUCCEEDED, 0
errors / 0 warnings**. Sim-visual checks (Face ID launch-lock, iPad layout, reconnect/dedup flow,
dead-UI gone) **pending** — blocked by HID tooling (below).

Deferred deliberately: **MAJOR-5** (password-retry sheet present-over-cover) — same B1 presentation
path that was under E2E verification; not destabilized mid-pass.

### Phase 4 — E2E verdicts (evidence in `screens/e2e-phase4/`)

| Check | Verdict | Basis |
|---|---|---|
| 1 Live-SSH approval happy path | **BLOCKED** | shell-integration wedge + no HID taps |
| 2 B1 TOFU first-connect | PARTIAL (code-verified) | sheet inside SessionView above cover; runtime needs taps |
| 3 B3 idempotency (first-decision-wins) | **PASS** | test `firstDecisionWins`; relay dedupe; `WHERE decision IS NULL` |
| 4 Relay fallback (two-tier auth) | **PASS** | full curl matrix + `TestDecisionPollerResolves`/`SendsBearerToken` |
| 5 Cold-launch banner (M6) | PARTIAL (code-verified) | buffer drain + `HostedAgentM6Tests`; runtime needs a push tap |
| 6 Gallery + prod Inbox shots | **PASS** | 3 dark routes + prod Inbox L/D; **no host-label wrap issue** |

Builds: SPM + **337 tests** PASS, app-target `xcodebuild` PASS, Go push-backend + relay tests PASS.

### Two blockers found in Phase 4

1. **HID tap/typing tooling is dead on this machine.** Only `Xcode-beta.app` is installed; it ships
   `SimulatorKit.framework` under `Contents/SharedFrameworks/` while idb / XcodeBuildMCP hardcode
   `Contents/Developer/Library/PrivateFrameworks/`. Screenshots + AX-tree reads work; taps/typing
   fail. Blocks **all** interactive verification — Phase 4 Checks 1/2/5, tab navigation, and the
   Phase 5 sim-visual pass. Not patched (modifying the Xcode bundle would risk the environment).
2. **Shell-integration bootstrap leaks into the live block and wedges zsh** (Check 1). The OSC-133
   bootstrap renders as literal text and the shell wedges at a PS2 continuation
   (`elif-then function function quote>`); the connect-time autocmd (`claude`, and even `echo`) pastes
   into the unterminated construct and never runs → session goes Offline. Reproduced twice.
   **Code finding:** `awaitUnifiedShellReady()` (SessionViewModel.swift:969) has a **3s timeout
   backstop** that drains connect-time waiters *without* `unifiedIntegrationReady` becoming true. On a
   heavy login shell (the user's 440-line `~/.zshrc` with a `claude` wrapper + `elif` blocks) where the
   integration prompt takes >3s or the rc mangles the injection, that timeout releases the autocmd
   prematurely → the wedge. Plausible product fragility amplified by host config; needs a clean-shell
   repro on a vanilla host to attribute definitively. Approval/block **UI renders correctly** (Check 6),
   so the fault is isolated to the live zsh-integration handshake, not rendering or the approval layer.

## Baselines (2026-06-12, start of audit)

- ConduitKit `swift build`: **clean** (only third-party Package.swift deprecation warnings in GRDB/BigInt checkouts — not ours)
- Xcode `Conduit` target `build_sim` (iPhone 17 Pro): **SUCCEEDED, 0 warnings, 0 errors**
- `daemon/push-backend`: `go vet ./...` clean; `go test ./...` **ok** (conduit/push-backend 0.608s)
- ConduitKit `swift test`: **331 tests / 54 suites, all pass** (9.5s; docs variously claimed 203/253/292/327 — 331 is current truth)

## Findings log

| # | Severity | Area | Finding | Reachability | Status |
|---|----------|------|---------|--------------|--------|
| 1 | major | build/targets | `Conduit.xcodeproj` (gitignored, generated) was stale vs `project.yml`: the `ConduitWidget` target (added 2026-06-02) was missing, so the home-screen widget was never being built or embedded | any local build since Jun 2 | fixed — ran `xcodegen`; all 5 targets present; `build_sim` clean (0 warn/0 err) |
| 2 | minor | config | `project.yml` comment says push backend should be a Cloud Run URL (`*.a.run.app`) but the value is `https://35.201.3.231.sslip.io` (third-party wildcard-DNS host pointing at a bare IP) — works (health 200 verified 2026-06-12), but ship-gate says repoint to vanity domain before TestFlight/public | release builds | flagged (owner) |
| 3 | major | submission | `fastlane/metadata/en-US/*` still carries the OLD terminal-first copy (name "Conduit", subtitle "SSH + AI Agent Control", description leads with SSH/terminal) while `docs/app-store-metadata.md` defines the governed-approvals positioning ("Conduit — Agent Approvals", approvals-led description). fastlane is what `deliver` uploads — must sync | submission | open — fix in Phase 6 |
| 4 | major | submission | Store screenshots don't exist at spec: `fastlane/screenshots/en-US/` has 5×1320×2868 PNGs with OLD terminal-first content; the "canonical" `docs/screenshots/governed-approvals/` set is only 368×800 JPG (doc-verification grade, not uploadable). Need fresh 1320×2868 captures of the governed-approvals flow (6.9" simulator) | submission | open — capture in Phase 6 |

## Phase 1 orientation — current believed state (from docs, 2026-06-12)

**Where the project thinks it is:** ship-gate doc (latest, 2026-06-11) says "engineering is complete; everything remaining is an owner action" (App Store Connect record + capabilities + IAP, physical-device APNs validation, DNS/vanity domain, archive/upload). Paid team 39HM2X8GS6 + APNs key L8LVU9X82W exist. Backend live at https://35.201.3.231.sslip.io (health 200 claimed). Pricing: free app + $14.99 lifetime IAP `dev.conduit.mobile.pro`; AI credits via Stripe web (US storefront only, never compare prices in-app).

**Doc conflicts to settle in code** (older docs call these bugs; newer docs claim fixed):
1. `.approvedAlways` collapse (DaemonChannel.swift:52 old → :111 sends `approveAlways` + conduitd persists to policy-always.yaml per dossier) — verify.
2. Structured tool_use wire protocol (hook flattened tool_input to 500-char string → PROD_PLAN claims structured toolName/toolUseID/input end-to-end) — verify.
3. conduitd → push-backend `/approval` POST (missing → done at server.go:532-614 per dossier) — verify.
4. Token routing (identifierForVendor vs agent-session keying mismatch) — verify resolved.
5. WS-11 approval-card host-label wrap bug (DSApprovalCard) — possibly fixed in 858b688; verify gallery `inbox-typed` + `review`, light/dark/AX3.

**Security-review-blind area (top priority):** the backend-relay decision fallback (commit a552e2d3: app POSTs decision to `/approval/decision` when no live SSH channel; conduitd poller resolves). Postdates SECURITY-REVIEW.md and every planning doc. Must verify: auth, exactly-once delivery, replay/spoof resistance, fail-safe behavior.

**Release-hygiene checks promised by docs:** isPro DEBUG bypass, DebugSeeder, REVIEW pill, debug host auto-trust all compiled out of Release; Sentry DSN empty (SDK never starts; PrivacyInfo SystemBootTime 35F9.1 tied to Sentry); iCloud Sync is push-only — its UI row must stay hidden; swift-nio-ssh is a fork (Wellz26) pinned to a version range, not a SHA (SECURITY LOW-7, open).

**Open security-review items (LOW, from 2026-05-31):** LOW-1 no app-switcher snapshot redaction on key screens; LOW-2 BiometricGate silently succeeds on biometryLockout; LOW-3 `autoTrustHostKey` is a runtime-settable public API with no DEBUG guard; LOW-5 Redactor lacks PEM/Bearer/JWT patterns.

**Known UI gaps from WS docs (verify, then fix in Phase 5):** .system fonts in AgentIsland/AgentStatusHeader/FilesView; "· Done" label should read "Connected"; REVIEW pill gating; safe-area confirmation for DSTabBar (fixed 64pt) + composer inset; empty/error/loading states (WS-4 open).

**App Review risk posture (Guideline 2.5.2):** Conduit drives a *remote* shell, no local code download/execution — reviewer notes must say this. DEBUG-seeded inbox exists for review. Other risks: 4.2 minimum functionality, 2.1 completeness, 3.1.1 IAP works in sandbox.

**Note:** `docs/app-store-submission.md` + `docs/app-store-metadata-governed-approvals.md` were deleted on this branch; `docs/app-store-metadata.md` (modified) is the survivor — cross-check it against the app in Phase 6.

## CONSOLIDATED TRIAGE — Phase 3 results (2026-06-12)
_Per-area detail in `findings/review-*.md`. 7/8 reviewers done; core-kits [03b2cb3d] pending._

### BLOCKERS
- **B1 — TOFU first-connect hard-hangs; host-key prompt never appears.** `AppRoot.startSession` raises the `SessionView` `fullScreenCover` *before* `vm.connect()`, so the ancestor `HostKeyConfirmSheet` can't present over the cover and `SessionView`'s connect overlay has no `.disconnected` case → stuck "Connecting…", back button covered, force-quit only. Every new host hits this. (review-app-onboarding) — **breaks the core flow.** Fix: order connect/host-key resolution before/over the cover; add `.disconnected` overlay state + dismissal.
- **B2 — Approval decision relay has NO AUTH (governance bypass).** Backend (`/approval/decision`, `/decisions`, `/register`, `/approval`) trusts caller-supplied `sessionId` as the capability; anyone who learns a sessionId can forge `approveAlways` or drain decisions. Swift side (`ApprovalRelay.swift:112`) sends no auth header and discards the response → when backend is secured it 401-drops silently; when open it's anonymous + no replay binding. Backend worker shipped partial mitigation (`APPROVAL_RELAY_SECRET` + input hardening) and flagged the real fix = **per-session capability token** (coordinated conduitd↔backend↔app). (review-backend, review-approvals)
- **B3 — No first-decision-wins / idempotency.** `ApprovalRepository.decide` does an unconditional UPDATE; nothing checks `isPending`; delivered notifications never cleared. Deny on card → tap Approve on lingering banner re-resolves the SAME gate → a reject is flipped to approve. (review-approvals) Fix: guard on `isPending`; clear delivered notifications + Live Activity on decision.
- **B4 — Missing `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`.** In-session mic (`ChatInputBar`→`DictationEngine`) requests speech+mic; no purpose strings → iOS crashes on first tap + App Review auto-reject. Not debug-gated. (review-targets) Fix: add to `project.yml` info props + regenerate.

### MAJORS (grouped)
- **Approval reliability (review-approvals + review-session-ssh):** approvals not re-armed after SSH reconnect (`DaemonChannel`/`ApprovalIngest` created once; events finish, never restart); silent decision drop on dead-but-attached channel (`DaemonChannel.respond` no-ops on nil writer; relay fallback only when `channel==nil`); cold-launch banner Approve/Reject lost (`ConduitApp.swift:167` posts before `AppRoot` subscribes); `blastRadius`/`question`/`choices` dropped on DB round-trip (governance context never renders); divergent `identifierForVendor ?? UUID()` at 4 sites mis-routes push/relay; offline decision double-delivered (relay POST + SSH drain).
- **Session pipeline (review-session-ssh):** TUI escalation guard permits `.promptEditing` (must be `.submitted` only) → idle prompt escalates; connect-time commands race integration injection (no `unifiedIntegrationReady` gate); auto-reconnect leaves dead terminal (`unifiedShell` never nilled).
- **Watch / Live Activity (review-targets):** `ENABLE_APP_INTENTS_METADATA_EXTRACTION: NO` risks Approve/Reject buttons not resolving in Release (headline surface!); `LiveActivityManager.updatePendingApprovals` drops `pendingApprovalID` (strips buttons); watch decisions never persist to local DB; watch→phone send is best-effort `sendMessage` (lost when phone unreachable, UI optimistically clears).
- **Security (review-approvals; confirm w/ core-kits):** BiometricGate silently succeeds on `.biometryLockout` (app-lock + SSH-key bypass); Redactor lacks PEM/Bearer/JWT.
- **UI features (review-ui-features):** SnippetEditor wipes `tags`/`hostTags` on edit (LWW propagates loss); BillingView "AI usage today" hardcoded `$0.00` stub; TextPreview ISO-Latin-1 fallback makes binary-file guard dead; KeyImportView gates encrypted-key import on English error substring.
- **Nav/onboarding (review-app-onboarding):** iPad `regularRoot` detail has no `NavigationStack` (in-tab links dead); Face ID onboarding never sets `appLockEnabled` (claims a lock it never enables); no saved-host list/reconnect/edit → re-add mints duplicate hosts; password-retry sheet has same present-over-cover conflict as B1.
- **Config (review-targets):** `MARKETING_VERSION 0.1.0` vs hard-coded `CFBundleShortVersionString 1.0`; PrivacyInfo over-declares CrashData (Sentry DSN empty), FileTimestamp reason questionable.

### FEATURE-COVERAGE DRIFT (review FEATURE_COVERAGE.md)
- **Implemented-but-hidden:** saved-hosts list/reconnect, host edit, SFTP browser, web/localhost preview, post-onboarding provisioning wizard.
- **Shown-but-unimplemented:** Library "+new snippet" no-op, RECENT row no-op, snippets "run" TODO, Workflows mock+dead "add step", paywall sheet never triggered.

### FIX PLAN (build-conflict aware: only one Swift build at a time in this worktree)
- **FIX-BACKEND worker (Go+conduitd, parallel-safe):** implement per-session capability-token for B2 (conduitd issues token + registers sessionId→token with backend; backend validates on `/approval/decision`+`/decisions`); close conduitd poll audit/`approveAlways` policy gap. Contract defined by coordinator.
- **FIX-SWIFT worker (owns Swift build, sequential):** B1, B3, Swift side of B2 (send token on relay), approval-reliability majors, session-pipeline majors, watch/LiveActivity, BiometricGate/Redactor, UI-feature majors, nav/onboarding majors, the 5 build warnings. Build + ConduitKit tests + build_sim green before finishing.
- Coordinator: define the token contract, fold in core-kits findings, then verify end-to-end in Phase 4 sim run (both live-SSH + relay paths).

### Fix workers (in flight)
- FIX-BACKEND (Go push-backend + conduitd relay-auth capability token; conduitd audit/policy gap) → `findings/fix-backend-relay-auth.md` — [cd710ec6](cd710ec6-c688-4de4-b806-89fc3b54322e)
- FIX-SWIFT wave 1 (B1 TOFU hang, B3 idempotency, relay-auth Swift side, approval-reliability majors, BiometricGate, session pipeline, watch/LiveActivity, mic/speech usage strings + version, 5 build warnings) → `findings/fix-swift-wave1.md` — [e6717214](e6717214-96fd-457a-a77d-bba2787386ac)
- Mandated wire contract for B2 (both workers): conduitd issues per-session `relayToken`, delivers it to the app over the DaemonChannel attach/handshake as field `relayToken`; app sends `Authorization: Bearer <relayToken>` on `POST /approval/decision`; backend validates per-session (TOFU-on-token, constant-time).

### Deferred to wave 2 / Phase 5 (after wave 1 verifies)
- Feature-drift: wire-or-remove dead Library/Workflows/snippet buttons; surface-or-remove hidden saved-hosts/host-edit/SFTP/preview.
- UI majors: SnippetEditor tag loss, BillingView $0.00 stub, TextPreview binary guard, KeyImportView English-substring gate.
- Nav/onboarding: iPad NavigationStack, Face ID onboarding honesty, saved-host duplicate-on-readd.
- core-kits majors: SSHHostRuntime run-status (cancel no-op / always-succeeded / actor reentrancy), CloudKit deletion resurrection + dead `CONDUIT_ICLOUD_ENABLED` gate/contract mismatch.
- core-kits minors: `nonisolated(unsafe)` usage-counter race, OpenRouter usage under-report, RiskScorer evadable substring rules (can suppress approval push), fire-and-forget device-token registration.
- Token/theme drift cleanup (14 items, Phase 5).

## Decisions made

- **2026-06-12 (Fable resume) — BRANCH CORRECTION:** the session began with the working tree on `master`, which lacks the governed-approvals feature (old `Hosts/Inbox/Library/Settings` IA, no backend-relay decision fallback, missing dossier/readiness/plan docs). The reflog showed the last action was `checkout: moving from feat/governed-approvals to master`. The audit target is unambiguously **`feat/governed-approvals`** (this branch carries the IA, relay, tests, and the audit prompt itself). Created a dedicated worktree at `/Users/roshansilva/Documents/cc-wt/governed-approvals-audit` and am running the audit there to avoid disturbing the master checkout. An initial fan-out of 9 review agents was launched against master before the discovery — those are **superseded**; only branch-agnostic findings (if any) will be harvested.
- Worktree build isolation: derivedData at `/tmp/conduit-ga-dd`; regenerated `Conduit.xcodeproj` via `xcodegen 2.45.4` (it's gitignored, absent from a fresh checkout).

### Re-baseline on feat/governed-approvals (2026-06-12)
- ConduitKit `swift build`: ✅ success (58.5s). **1 ConduitKit warning:** `SSHTransport/DaemonChannel.swift:40` (and likely :36) — "no 'async' operations occur within 'await' expression" (prior notes called build "clean" — this is ours, fix in cleanup pass).
- `go vet ./...`: ✅ clean · `go test ./...`: ✅ ok (1.09s)
- Xcode `build_sim` (Conduit app target, Debug, iPhone 17 Pro): ✅ SUCCEEDED (117.8s). **5 warnings to clean for DoD:**
  1. `SSHTransport/DaemonChannel.swift:36` — await on non-async
  2. `SSHTransport/DaemonChannel.swift:40` — await on non-async
  3. `OnboardingFeature/OnboardingView.swift:334` — await on non-async
  4. `SettingsFeature/ShortcutBarEditor.swift:14` — `body` type-check 323ms (>300ms)
  5. `AppFeature/AppRoot.swift:839` — `weak` capture of `agentStore` differs from implicit strong capture (#ImplicitStrongCapture) — **investigate (possible capture bug)**

### Phase 2/3 review fan-out (feat/governed-approvals worktree) — IN FLIGHT
- Phase 2 coverage → `FEATURE_COVERAGE.md` — [4971b51a](4971b51a-1c8c-43ca-8307-f0016cbd6f50)
- Approvals (Swift, incl. relay fallback) → `findings/review-approvals.md` — [6818f2f6](6818f2f6-e9ab-44ad-acdf-63898330e798)
- Go backend (review+fix) → `findings/review-backend.md` — [5b792eae](5b792eae-14b4-426d-a65e-c23e54ca653d)
- Session/SSH/Terminal → `findings/review-session-ssh.md` — [2663f235](2663f235-c827-4f61-8f42-e48af5c5eda8)
- Core kits → `findings/review-core-kits.md` — [03b2cb3d](03b2cb3d-40d5-4439-9439-9100226bf9cb)
- App/Workspaces/Onboarding + IA → `findings/review-app-onboarding.md` — [5074bcde](5074bcde-5b0c-4160-8695-b6b618c73ee3)
- UI features + DesignSystem → `findings/review-ui-features.md` — [bc822808](bc822808-afae-42da-ac5d-4a0fce89d8e6)
- Targets/widgets/watch + submission → `findings/review-targets-widgets.md` — [25696a38](25696a38-923b-4601-a1aa-26c6d330e418)

## Installed on machine

(nothing installed yet; xcodegen 2.45.4 was already present at /opt/homebrew/bin/xcodegen)

## Fix progress — Phase 3 (2026-06-12, coordinator-verified)

**B2 relay-auth (Go, both modules) — DONE + verified.** [cd710ec6] (+ resume). Two-tier auth: Tier-1 control plane `APPROVAL_RELAY_SECRET` guards `/register`,`/approval`,`/run-complete`; Tier-2 per-session `relayToken` (32-byte base64url, conduitd-minted at attach) guards `POST /approval/decision` + `GET /decisions` (constant-time; missing/wrong → 401, no side effects). conduitd registers `sessionId→relayToken` (control-plane authed), returns it to the app over the `conduit.device.register` RPC reply `result.relayToken` (was `"ok"`), and sends `Authorization: Bearer` on its poll. Poll-gap closed: live-SSH + poll paths now share one `applyDecision` (relayed `approveAlways` audited + written to policy-always.yaml identically; removed a pre-existing double-audit). **Verified by coordinator:** push-backend `go vet` clean / `go test` ok; conduitd `go vet` clean / `go test` ok (conduitd + policy). Report: `findings/fix-backend-relay-auth.md`. Residual: registration is last-writer-wins (no token TOFU); control plane open if secret unset (loud warning).
  - **Wire contract (pinned, all 3 sides matched):** handshake `conduit.device.register` reply `result.relayToken`; decision POST header `Authorization: Bearer <relayToken>` + body `sessionId` == the register `sessionID`.

**FIX-SWIFT PRIORITY 1 — DONE + verified.** [85d02340] (two no-op "success" runs then a resume that completed P1 before `[resource_exhausted]`; durable because report+edits were written incrementally). Done & **coordinator-verified green** (`swift build` clean = only GRDB/BigInt deprecations; `swift test` **331/54 pass**):
  - B1 TOFU first-connect hang (host-key prompt now presents from inside SessionView; added `.disconnected` phase + dismissible overlay/back; production TOFU preserved — connect only on explicit Trust & Connect).
  - B2 Swift side (DaemonChannel.registerDevice parses/stores `result.relayToken` w/ `"ok"` back-compat; ApprovalRelay sends Bearer + checks HTTP status, fail-safe; AppRoot wires token).
  - B3 idempotency (`UPDATE … WHERE id=? AND decision IS NULL` returns Bool; `exists(id:)`; clear delivered banner + Live Activity; cold-launch still forwards).
  - B4 mic+speech usage strings; version reconcile (MARKETING_VERSION 0.1.0→1.0.0 all 5 targets; CFBundleShortVersionString/CFBundleVersion now driven from vars).
  - M16 `ENABLE_APP_INTENTS_METADATA_EXTRACTION: YES`.
  - B13 BiometricGate `.biometryLockout` → device-passcode fallback, fail-closed (no more silent success).
  - 5 build warnings (DaemonChannel:36/40, OnboardingView:334, ShortcutBarEditor body split, AppRoot:839 weak→explicit-strong). Report: `findings/fix-swift-wave1.md`.

**FIX-SWIFT PRIORITY 2 — DONE + verified.** [ac461184] fresh worker (clean context, edit-first/incremental-report/build-once). All 11 reliability majors complete: M6 `ApprovalActionBuffer` (cold-launch banner durable), M7 persist+rehydrate blastRadius/question/choices (Approval.encode/init(row:) JSON), M8 new `ConduitCore/DeviceIdentity` (persist-once id; guarantees registerDevice sessionID == relay decision sessionId — the B2 key), M14 LiveActivity preserve pendingApprovalID, M5 residual (global-inbox onDecision falls back to relay on dead channel). Verified-already-present: M4 (onReconnected/FleetStore.rearm), M9 (single forwardDecisionOnly chokepoint), M10 (.submitted-only guard), M11 (awaitUnifiedShellReady), M12 (closeUnifiedShell on reconnect), M15 (watch decisions persisted). New files: `ConduitCore/DeviceIdentity.swift`, `Tests/.../ApprovalReliabilityWave2Tests.swift`. Report: `findings/fix-swift-wave2.md`.

**Coordinator-caught app-target breaks (SPM-vs-Xcode footgun).** Package `swift build` was clean but `build_sim` (app target, stricter isolation inference) flagged: (1) `AppRoot.swift:989` `ApprovalRelay.shared.setRelayToken(token)` missing `await` — fixed by removing the redundant explicit set (setChannel already refreshes relayToken from channel.currentRelayToken after registerDevice populates it; registerDevice kept for push registration); (2) `SessionViewModel.swift:979` redundant `await self?.drainIntegrationReadyWaiters()` — dropped.

**FINAL VERIFICATION (coordinator, 2026-06-12) — ALL GREEN:**
- ConduitKit `swift build`: ✅ clean (only GRDB/BigInt third-party deprecations)
- ConduitKit `swift test`: ✅ **337 tests / 57 suites pass**
- `xcodegen generate` + Xcode `build_sim` (Conduit scheme = app + widget/live-activity/watch/watch-widget, iPhone 17 Pro, Debug): ✅ **SUCCEEDED, 0 errors / 0 warnings**
- push-backend `go vet`/`go test`/`-race`: ✅ · conduitd `go vet`/`go test`/`-race`: ✅
- DoD warnings target met: the 5 baseline Swift warnings cleared; no new warnings introduced.

**Subagent reliability note:** background workers here repeatedly returned `status: success` with only an intermediate "let me check…" detail and ZERO edits/report; one later failed with `[resource_exhausted]`. Mitigation that worked: resume (preserve understanding) + edit-before-build + write the report incrementally + run heavy `build_sim` from the coordinator. Always verify worker output against `git status` + a real build, never trust the success flag alone.

## TODO / open threads

