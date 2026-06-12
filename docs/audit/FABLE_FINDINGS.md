# Fable Findings — Governed Approvals v1 pre-submission audit

> Durable scratchpad for the full pre-App-Store-submission pass (2026-06-12).
> Phases: 1 orient/baseline · 2 feature coverage · 3 exhaustive review · 4 E2E sim run ·
> 5 UX polish · 6 submission readiness · 7 verify & report.

## Status

- [ ] Phase 1 — Orient & green baseline
- [ ] Phase 2 — Feature inventory & coverage matrix (`FEATURE_COVERAGE.md`)
- [ ] Phase 3 — Exhaustive static review & hardening (governed-approvals path first)
- [ ] Phase 4 — Full E2E simulator run, every screen screenshotted
- [ ] Phase 5 — UX/UI/perf polish
- [ ] Phase 6 — Submission readiness (go/no-go)
- [ ] Phase 7 — Final verification & report (`FABLE_REPORT.md`)

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

## Decisions made

(autonomous choices worth noting)

## Installed on machine

(nothing yet)

## TODO / open threads

