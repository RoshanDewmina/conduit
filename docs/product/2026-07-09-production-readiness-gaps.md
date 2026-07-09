# Lancer production-readiness gaps (2026-07-09)

Evidence-backed gap scan for dogfood / TestFlight / App Store. **P0** = will burn users immediately if shipped today without mitigation.

---

## 1. Method

**What was verified live (2026-07-09):**

| Source | Action |
|--------|--------|
| `docs/PUBLISH_READINESS_CHECKLIST.md` | Read as checklist baseline; several claims are stale vs `docs/STATUS_LEDGER.md` (see reconciliations below). |
| `docs/STATUS_LEDGER.md` | Treated as fresher for Tier 0 / 5c / Layer 4 bar (last updated 2026-07-08 evening, tip `732071a7`). |
| `ARCHITECTURE.md` §0.1, §19.2 | Read for scope; **§19.2 privacy-manifest claims are stale** vs live `Lancer/PrivacyInfo.xcprivacy`. |
| Live code grep + file reads | `Lancer/LancerApp.swift`, `Lancer/PrivacyInfo.xcprivacy`, `PurchaseManager.swift`, `DeepLinkRoute.swift`, `daemon/push-backend/decisions.go`, `daemon/push-backend/entitlements.go`, `scripts/release-lancerd.sh`, `daemon/lancerd/install.sh`, Cursor shell bridge/error paths, Siri intents, `fastlane/Fastfile`. |
| Competitor clones | `research-repos/{orca,happier,omnara}` present; quick scan for crash/update/billing/privacy patterns only. |

**Stale checklist claims reconciled against live evidence:**

| Checklist claim | Live verdict |
|-----------------|--------------|
| §A “App-closed physical-device approval loop ❌ FAILED 2026-07-08” | **Superseded.** `STATUS_LEDGER` + `docs/test-runs/2026-07-08-tier0-5c-retest-results.md` record **PASS** after `732071a7` content-hash fix. Morning FAIL doc remains historical only. |
| §A “Emergency stop non-atomic” (via B11b) | **Fixed on `master`.** `daemon/lancerd/server.go` `applyEmergencyStop()` + tests (`server_test.go`, `dispatch_test.go`). |
| §B10 “Prove Tier 0 through live Cursor shell” open | **Partially closed.** Simulator relay harness PASS; owner device D0.2/5c PASS 2026-07-08 evening. Question-loop device proof still **OPEN** (`STATUS_LEDGER` Layer 4 bar). |
| `ARCHITECTURE.md` §19.2 “Privacy manifest declares SystemBootTime + CrashData” | **Stale.** Live manifest explicitly omits crash collection because `sentryDSN = ""` (`Lancer/PrivacyInfo.xcprivacy:26–28`, `LancerApp.swift:27`). |
| `ARCHITECTURE.md` §0.1 “Siri Phase 2 not merged” | **Stale.** `STATUS_LEDGER` lists Siri I1–I3 merged (#38, #41, #43) Jul 7–8. |
| `docs/wwdc26-lancer-opportunity-audit/02-current-codebase-state.md` “AppRoot ends Live Activity on background” | **Stale.** `AppRoot.swift:331–338` documents intentional *non*-end on background; push-driven lifecycle retained. |

**Not re-run in this pass:** full `swift test` / `go test` / Xcode archive (prior bar on `732071a7` cited in `STATUS_LEDGER`).

---

## 2. Lancer production gap table

| Area | Live status (file/evidence) | Checklist claim | Gap | Priority |
|------|----------------------------|-----------------|-----|----------|
| **Crash reporting** | Sentry wired behind `#if canImport(Sentry)` but **`sentryDSN = ""`** → SDK never starts (`Lancer/LancerApp.swift:27,50–52`). Opt-out key + no-PII config ready when DSN set. | Implied ready via `ARCHITECTURE.md` §19.2 + `project.yml` Sentry package | **Zero production crash signal.** Enabling DSN also requires re-adding `NSPrivacyCollectedDataTypeCrashData` + `SystemBootTime` to `PrivacyInfo.xcprivacy` (currently omitted on purpose). | **P1** (ops blind, not user-facing crash) |
| **Daemon self-update / install / notarization** | `scripts/release-lancerd.sh` builds linux+darwin flat `lancerd_${os}_${arch}` + `SHA256SUMS` + copies `install.sh` (`scripts/release-lancerd.sh:63–82`). `daemon/lancerd/install.sh` curls GCS `conduit-dist-f1c2466d`. **No codesign/notarization step** for macOS binaries. | B0 ✅ script fixed; owner `gsutil cp` to GCS still owner-gated (`KNOWN_ISSUES.md` §0 TESTER-2) | **Publish step unproven in this session**; Mac hosts get unsigned `lancerd` (Gatekeeper friction). Linux path is the happy path. | **P0** if testers hit `curl\|sh` before GCS publish |
| **App Store privacy manifest** | `Lancer/PrivacyInfo.xcprivacy` declares FileTimestamp, UserDefaults, DeviceID (APNs); **`NSPrivacyTracking: false`**; comment notes no crash SDK active. | D2 privacy nutrition label + manifest | Manifest matches *current* empty-DSN build. **Drift risk:** `ARCHITECTURE.md` §19.2 and `docs/legal/APP_PRIVACY_LABELS.md` still describe crash-data declarations that are **not** in the live file. App Store nutrition label + D2 still open. | **P1** (App Review / label accuracy) |
| **Push-backend durability** | Approval **decisions** are **in-memory** with 5m TTL (`daemon/push-backend/decisions.go:11–13,31–37`) — by design for ~120s lancerd poll window; Cloud Run redeploy drops pending decisions. Relay session registry also in-memory (`main.go` comments). Stripe **entitlements** persist to file or Redis (`entitlements.go:65–74`). | §A push-backend tests ✅; B6 “divergent security design parked in stash” open | V1 relay path works when process stays up; **no durable decision store** → lock-screen approve during backend rollout can silently fail until retry. B6 stash unreconciled. | **P1** |
| **Auth / billing (StoreKit vs Stripe)** | **Two mechanisms:** StoreKit IAP `dev.lancer.mobile.pro` (`PurchaseManager.swift:28,44–51`) vs Stripe cloud entitlement `hasCloudEntitlement` (`PurchaseManager.swift:54–64`, gates `AgentStore`). Settings UI shows Stripe path (`CursorSettingsView.swift:230,437`). **`isPro` computed in `AppRoot.swift:202–214` but never referenced; `showingPaywall` never set true** — IAP paywall dormant. Deep links fixed (`DeepLinkRoute.swift:14–20`, tests in `DeepLinkRouteTests.swift`). | C5 StoreKit TestFlight sandbox ⏸; D2 IAP $14.99; `STATUS_LEDGER` P1 “dormant StoreKit vs Stripe” | **Billing truth split:** UI copy reflects Stripe cloud; IAP exists but gates nothing. External beta risks wrong entitlement story + App Store IAP rules. | **P1** |
| **Remote host E2E** | V1 transport is **E2E relay**, not SSH (`ARCHITECTURE.md` §0.1). SSH TOFU + `HostKeyStore` retained for legacy (`SessionViewModel.swift:340–387`). UITest `LANCER_LIVE_SSH_E2E` **skipped** — “SSH host management moved out of Cursor Settings” (`TapInjectionProofTests.swift:169–173`). No `docs/test-runs/` record for real VPS + relay beyond localhost. | C1 “Live E2E on real remote host” ⏸ owner-gated | **Dogfood on a fresh VPS unproven end-to-end** (install → pair → dispatch → approve) in this repo’s test evidence. | **P0** for VPS-first testers |
| **CloudKit / cross-device (C7)** | `ConversationSyncEngine` + `CKDatabaseSubscription` registered (`ConversationSyncEngine.swift:69–74`, `CloudSync.swift:218–236`). Unit tests pass (`ConversationSyncEngineTests.swift`). `CloudSync` no-ops without entitlement (simulator). | B9 ✅ code; C7 two-device QA ⏸; D2 “promote schema Dev → Production” | **No hardware proof** A→B propagation or silent-push pull. **Production CloudKit schema not promoted** → new App Store users can fail sync (`PUBLISH_READINESS_CHECKLIST.md` D2 note). | **P0** if cross-device ship is on |
| **TestFlight / signing** | `fastlane/Fastfile` has `beta` lane (match + archive + `upload_to_testflight`). `project.yml` ships production push URL + Supabase anon key. `STATUS_LEDGER` Layer 4: app-target `build_sim` PASS iOS 27. | D5 ✅ uploaded; B3 app-target archive open | TestFlight **uploaded** per checklist; **B3 full archive on cleanup branch** still unchecked. Dual iOS 26+27 build blocked on runtime (`STATUS_LEDGER`). | **P2** for internal dogfood; **P1** for external beta refresh |
| **Secrets / TOFU** | Relay pairing uses capability tokens (`server.go` relayToken). SSH TOFU prompt path intact (`SessionViewModel.trustHostKey`). Daemon secrets RPC + encrypted store (`server.go` `agent.secret.*`, `secrets` store). Policy fail-closed defaults (`ARCHITECTURE.md` §0.1). Biometric gate **removed** (permanent). | Governance ✅ in Settings; TOFU on production paths | **V1 path is relay TOFU/pairing, not SSH host-key.** Secrets approval UI not surfaced in Cursor shell views (governance in Settings). No regression found in code; **physical secrets loop not re-tested here.** | **P2** |
| **Rate-limit / error honesty in chat** | Push-backend pairing rate limit 429 (`websocket_relay.go`). Decision cap 429 (`decisions.go:144`). `LancerError.rateLimited` in BYOK `AgentKit` clients only (`LancerError.swift:26,61`). Cursor shell surfaces **`activeThreadError`** + Retry/Refresh (`CursorWorkThreadView.swift:305–323`, `AppRoot.swift:1077–1079`). Some paths genericize empty errors to “Couldn't start the run.” (`AppRoot.swift:751–754`). **No Cursor UI for `ConversationSyncCoordinator` `.conflict` / `.hostOffline`** (coordinator tested; CursorStyle views don't bind sync state). | B8 empty/error sweep open | Users can see bridge errors; **sync conflict/offline states may look like silent “Working…”**; provider 429 not mapped on relay dispatch path. | **P1** |
| **Live Activities on-device** | `LancerLiveActivityManager` push token + push-to-start (`LiveActivityManager.swift:210–213`). `push-backend/liveactivity.go` sender. `AppRoot` re-registers APNs on foreground (`AppRoot.swift:342–348`). **5c lock-screen approve PASS** 2026-07-08 evening. | C2 morning FAIL superseded; ARCHITECTURE claims push-driven LA while closed | **Code + 5c approval path proven.** Push-to-start / Dynamic Island **visual confirmation for relay-dispatch still open** (`wwdc26` device-hub matrix). Watch embed cut Jul 8. | **P2** |
| **Siri intents `openAppWhenRun`** | **`true`:** `StartAgentRunIntent`, `SearchLancerIntent`, `OpenConversationIntent`, `ApprovalActionIntent` (`StartAgentRunIntent.swift:32`, `StatusQueryIntents.swift:108,142`, `ApprovalActionIntent.swift:77`). **`false` (default):** `AgentStatusQueryIntent`, `PendingApprovalsQueryIntent`, `AnswerQuestionIntent`, `DenyApprovalIntent`, `PauseRunIntent`, `StopRunIntent` — read-only / voice-answer / deny-by-design. `StartAgentRunSupport.swift` handles cold-launch reconnect for `openAppWhenRun` intents. | Siri I1–I3 merged per `STATUS_LEDGER` | **Navigation intents open app; query/control intents intentionally background-only.** Risk: cold-start status queries return “not connected” (`StatusQueryIntents.swift:20–24`) — documented, not a bug. | **P2** |

---

## 3. Competitor production scan (short)

| Competitor | Crash / ops | Updates / install | Billing | Privacy |
|------------|-------------|-------------------|---------|---------|
| **Omnara** (`research-repos/omnara`) | **Sentry** on mobile (`apps/mobile/src/lib/logger.ts`), backend, web — DSN-gated init pattern | README advertises mobile auto-updates (TestFlight) | **RevenueCat** + Stripe backend (`subscriptionService.ts`) | In-app privacy policy links (`PrivacyScreen.tsx`) |
| **Happier** (`research-repos/happier`) | **Sentry** release pipeline (`scripts/pipeline/sentry/track-release.mjs`) | **macOS notarization** hard-gated in CI (`build_tauri_workflow.production_signing_gate.test.mjs`) | (not deep-scanned) | EAS/Sentry env contracts in release scripts |
| **Orca** (`research-repos/orca`) | Internal crash repro harnesses (`tools/repro-watcher-crash-7547/`) | Desktop update E2E (`tools/win-update-e2e/`) | Product billing mostly provider/workspace scoped, not mobile IAP | Desktop/Electron surface (no iOS privacy manifest analogue) |

**Takeaway:** Shipped competitors treat **Sentry (or equivalent) + explicit release signing/notarization + single billing spine** as table stakes. Lancer is ahead on **governed relay + daemon policy** but behind on **ops telemetry, billing consolidation, and Mac daemon distribution polish**.

---

## 4. Ranked burn list (top 8 — dogfood / TestFlight risk)

1. **Publish `lancerd` to GCS** — run `scripts/release-lancerd.sh` + owner `gsutil cp` (`KNOWN_ISSUES.md` §0 TESTER-2). Without this, `curl|sh` onboarding 404s for real hosts.
2. **Prove VPS / remote-host relay loop (C1)** — fresh Linux box → `install.sh` → pair → dispatch → approve → audit, recorded in `docs/test-runs/`.
3. **CloudKit Production schema promotion (D2)** — deploy `LancerConversations` zone + `Conversation` / `ConversationTurnChunk` before external builds; then **two-device C7 QA**.
4. **Reconcile billing (StoreKit vs Stripe)** — pick one customer-facing spine; wire or remove dormant IAP (`isPro` / paywall never shown); verify C5 sandbox on TestFlight.
5. **Configure Sentry DSN + sync privacy manifest** — flip `sentryDSN`, add crash-data declarations to `PrivacyInfo.xcprivacy`, verify symbolication once on device.
6. **Owner device question-loop proof** — `STATUS_LEDGER` Layer 4 OPEN; extend `relay-approval-e2e.sh` or runbook Phase for `/question` round-trip.
7. **Chat sync-state honesty** — surface `ConversationSyncCoordinator` `.conflict` / `.hostOffline` in Cursor work-thread/composer (today: coordinator + tests only).
8. **App Store Connect D2 + fresh TestFlight archive (B3)** — metadata, IAP, screenshots, privacy labels; re-archive after A3 (#63–#66) UI pass.

---

## 5. Final answer

Lancer’s **Tier 0 governed-approval loop is materially closer than the stale checklist suggests**: lock-screen 5c passed on device after `732071a7`, emergency stop is daemon-atomic, deep links and Siri navigation intents are merged, and the live Cursor shell bridge surfaces many dispatch errors. The **highest dogfood burn risk is still off-phone**: unpublished or unsigned `lancerd` installs, unproven VPS relay E2E, and CloudKit Production schema + two-device sync left unverified. **Production ops gaps** (empty Sentry DSN, in-memory push-backend decisions, dual billing) won’t crash the app on day one but will blind you in TestFlight and confuse paying users once Stripe or cross-device sync is marketed. Prioritize GCS publish + remote-host proof, then CloudKit promotion/C7, then billing + crash telemetry consolidation, before widening external beta.
