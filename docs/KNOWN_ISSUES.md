# Lancer — Known Issues & Pre-Launch Audit (canonical)

> **2026-06-27 lean sweep.** Periphery app-target scan, reachability grep, Swift/Go gates, and
> Go `deadcode` were used to remove dead Swift/Go/rebrand cruft. Remaining zero-ref hosted-cloud
> UI and SSH/legacy transport are intentionally retained per `AGENTS.md`.
>
> **2026-06-20 editorial redesign — deferred perf items.** The pixel-faithful redesign +
> IA refactor shipped (see git log on `codex/ios27-shell-workspace`). Cheap perf wins done:
> all `.repeatForever()` animations confirmed Reduce-Motion-gated; 711 lines of dead code
> removed (SessionsListView, GovernanceView, WorkspaceRoute enum). **Deferred (real, but
> high-risk — warrant a dedicated session with live-harness regression testing, NOT bundled
> into a UI pass):** (1) `SessionViewModel` is ~1218 lines / 30+ `@Observable` props — a single
> property change invalidates the whole session view; split into focused sub-stores
> (connection / block-render / keyboard) without regressing the sacred terminal pipeline.
> (2) `AppRoot.mainBody` getter type-checks at ~328ms (>300ms limit) — compile-time only, on a
> load-bearing `.task`/`.onChange` lifecycle chain; decompose only with care. (3) Optional:
> further decompose `NewChatTabView`/`SessionView` bodies. The redesigned screens themselves
> profile fine; these are pre-existing hotspots.

> **Compiled:** 2026-06-19 · **Last updated: 2026-07-15** · branch `master` (updated).
> This is the canonical "what's broken / what's verified / what's residual" doc. It supersedes the
> scattered point-in-time audit docs for **issue tracking**. For launch *checklist* state use
> `docs/PUBLISH_READINESS_CHECKLIST.md`; for product/architecture narrative use `ARCHITECTURE.md`
> (§0.1 current-state snapshot + §4.1 IA). **Correction (2026-07-15):** `AppFeature/CursorStyle/`
> was removed by commit `6b97da65` (2026-07-11 "revert(ios): restore Codex Workspaces shell as
> the frontend") — confirmed zero matches in the current tree. The current production root is
> `AppFeature/Workspaces/WorkspacesView.swift`, DEBUG-gated by `LANCER_DESTINATION` (not the old
> `LANCER_CURSOR_SHELL*` flags). The "not a tab bar" / not-the-legacy-sidebar framing still holds
> — see `ARCHITECTURE.md` §0.1/§4.1 and `docs/STATUS_LEDGER.md`'s 2026-07-11
> "frontend reversal" note. The old `LANCER_PROJECT_DOSSIER.md` and `docs/_archive/`
> were **purged 2026-07-06** — use `ARCHITECTURE.md` §0.1 + `docs/STATUS_LEDGER.md`.
>
> **Method note:** the multi-agent fan-out repeatedly tripped the account session limit (parallel agents
> burn quota fast), so **all dimensions were audited inline by a single agent** against current source —
> security, architecture, build, **and** perf/UX/a11y (§4, §4b). Findings cite real file:line evidence.

---

## 0. P0 tester-readiness blockers — RECONCILED (2026-06-24)

> Found while assessing "can self-hosted testers use this yet?". Re-verified 2026-06-24; status below
> supersedes the 2026-06-20 "VERIFIED DOWN" snapshot. Neither was ever an app-code bug.

- **`TESTER-1` — Relay reachability: RESOLVED (Fly relay is live).** The canonical instance is
  `https://conduit-push.fly.dev`; `GET /health` returns **200**, unauthenticated protected routes
  return **401**, and `/ws/relay` is live. The retired Cloud Run endpoint returns 404. Existing
  confirmed pairings migrate only the exact retired hostname while preserving codes and keys.
- **`TESTER-2` — installer 404s: FIXED in source (publish is owner-gated).** Root cause was
  rebrand drift in the GCS dist path, not the old GitHub-release naming: `install.sh` fetches flat
  `lancerd_${os}_${arch}` + `SHA256SUMS`, but `scripts/release-lancerd.sh` only emitted versioned
  hyphenated tarballs and never wrote `SHA256SUMS`, and the bucket still held stale `conduitd_*` sums
  with **no binaries** (all 404). `release-lancerd.sh` now also emits the flat `lancerd_${os}_${arch}`
  binaries (incl. darwin-amd64) + a matching `SHA256SUMS` + `install.sh`, and prints the `gsutil`
  upload command. The full `curl|sh` loop was proven end-to-end offline (download → checksum → install
  → pair) on 2026-06-24. **Owner step remaining:** run `scripts/release-lancerd.sh <ver>` then the
  printed `gsutil cp … gs://conduit-dist-f1c2466d/` to publish; a release CI job is still nice-to-have.

## 0.1 Account / device management — COMPLETED (2026-06-20)

- Codex's account-identity stack (Supabase email/password, self-hosted offline mode, QR device
  bind/redeem, HS256 JWT verification, billing rebound to JWT subject) verified green: 414 SPM tests,
  app-target UI tests 7/7 on iPhone + iPad, all 3 Go modules, resident smoke 4/4.
- **Device-management screen added** (`SettingsFeature/DeviceManagementView.swift`): Settings →
  Connection → Devices (standard-account only) lists bound daemons and revokes them against
  `GET /v1/devices` + `POST /v1/devices/{id}/revoke`. Covered by `AccountSessionTests`.
- **Residual release gates** (owner-configured, not code bugs): production Supabase project + SMTP +
  `SUPABASE_JWT_SECRET`; **HS256-only** verifier (add JWKS if the project signs RS256); physical-device
  APNs/biometric/StoreKit/Watch pass per `OWNER_DEVICE_CHECKLIST.md`.

---

## 1. Build & test baseline — VERIFIED GREEN (2026-06-18)

| Target | Command | Result |
|---|---|---|
| LancerKit (SPM) | `cd Packages/LancerKit && swift build` | ✅ clean |
| LancerKit tests | `cd Packages/LancerKit && swift test` | ✅ **385 tests / 61 suites pass** |
| Xcode app-target (iOS sim) | `XcodeBuildMCP build_sim` | ✅ **SUCCEEDED** 0 errors 0 warnings (2026-06-19) |
| lancerd + policy (Go) | `go vet ./... && go build ./... && go test ./...` | ✅ 124 tests pass |
| push-backend (Go) | `go vet/build/test ./...` | ✅ pass |
| agent-runner (Go) | `go vet/build/test ./...` | ✅ pass |
| lancer-mcp (Go) | `go build ./...` | ✅ pass (no test target) |

Only compiler **warnings** in our code (8 total) are "getter took >300ms to type-check" hints — compile-time
only, no runtime effect. See §4.

**Open test debt — `UI-IA-1` (tracked 2026-06-19, updated 2026-07-15):** legacy tab-bar/sidebar
`TapInjectionProofTests` XCTSkip cases were removed. UITests now deep-link via
`LANCER_DESTINATION` into the Workspaces production root (retired `LANCER_CURSOR_SHELL_LIVE=1`
/ CursorStyle suite names are historical). Remaining skips: opt-in relay E2E (owner-gated)
and one permanently-skipped SSH path. See Workspaces UITests + `docs/LIVE_LOOP_RUNBOOK.md`.
(Former `docs/test-runs/user-ready-tier0-2026-07-06/` path is absent from the tree.)

---

## 2. Security posture — GO holds; most prior OPEN items now CLOSED in code

The 2026-06-13 security triage (formerly `docs/audit/2026-06-13-security-triage.md`, **purged
2026-07-06**) reached **GO** on the four core properties. Re-verified 2026-06-17, the code has since
**closed almost every OPEN item** — see `docs/legal/SECURITY_ARCHITECTURE.md` for the current threat
model:

| Prior finding (Jun 13) | Status now | Evidence (2026-06-17) |
|---|---|---|
| FINDING-1 Dockerfiles run as root | ✅ **CLOSED** | `daemon/agent-runner/Dockerfile:26-27` (`useradd lancer; USER lancer`); `daemon/push-backend/Dockerfile:10-14` (`adduser lancer; USER lancer`) |
| FINDING-2 `APPROVAL_RELAY_SECRET` unenforced | ✅ **CLOSED** | `relay_security.go:143-166` `relaySecretStartupCheck` → `log.Fatal` in prod; wired at `main.go:120` `warnIfRelayUnauthenticated()` |
| LOW-5 Redactor missing PEM/Bearer/JWT | ✅ **CLOSED** | `AgentKit/Redactor.swift:29,33,37` (PEM private key, Bearer token, JWT patterns present) |
| LOW-1 no `.privacySensitive()` on key views | 🟢 **Residual-LOW (effectively moot)** | Secret *values* use `SecureField` (already snapshot-masked): `ProviderKeysView.swift:69`, `SecretsView.swift:296`, `KeyImportView.swift:176`. Only *public* keys/fingerprints render as plain `Text` (`KeysView.swift:142,247`). `.privacySensitive()` would be redundant. |
| LOW-3 `autoTrustHostKey` runtime-settable | 🟢 Residual-LOW | Parameter defaults `false`; only `DebugTerminalHarness`/`DebugSessionHarness` pass `true`, both `#if DEBUG && os(iOS)`. Zero release exposure. Compile-time guard still a nice-to-have. |
| LOW-7 Wellz26 swift-nio-ssh fork | 🟡 OPEN (watch) | Still on community fork (`Package.swift`). Low risk; track upstream for CVEs. |

**Independently re-verified safe (this audit):**
- **Fail-closed policy** — daemon-down holds all mutating kinds; policy default = `ask`; timeout → deny.
- **TOFU in production** — `TOFUHostKeyValidator` always prompts; auto-trust strictly `#if DEBUG`.
- **No secret logging** — Swift + Go daemon (run/agent IDs only; `redactSecrets()` on every audit command field).
- **Keychain** — `whenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable:false`.
- **Notification action hardening** — approval Reject now uses
  `UNNotificationActionOptions.authenticationRequired` as well as `.destructive`, matching Approve's
  unlocked-device requirement. Evidence: `NotificationsKit/Notifications.swift` `registerCategories()`.
- **Cross-tenant / IDOR** — `push-backend/agents.go` scopes **every** handler via
  `resolveEntitlementFromBearer` + `resourceVisibleToEntitlement(ent, CustomerID, OrgID)`.
- **Artifact download path traversal** — GCS-backed, entitlement-scoped, plus defense-in-depth
  `strings.HasPrefix(objName, "runs/"+runID+"/")` (`artifacts.go handleArtifactDownload`).
- **exec.Command** — explicit argv, no shell (triage FINDING-3, re-confirmed).

**Official-docs verification (part 9) — 7/8 compliant (2026-06-17):** Keychain accessibility
(`WhenUnlockedThisDeviceOnly` + non-synchronizable), ATS (enforced; only local networking exempt), APNs
`aps-environment: production`, `PrivacyInfo.xcprivacy` required-reason codes (CA92.1↔UserDefaults,
C617.1↔FileTimestamp) + honest DeviceID declaration, push-driven background model, and TOFU fail-closed are all
**compliant** with current Apple/OWASP-MASVS guidance.

**BiometricGate no-passcode policy — moot, removed 2026-07-07:** `BiometricGate` (and the
per-decision/per-key-load gate that used it) was deleted from the app entirely, a permanent product
decision — there is no fail-open/fail-closed policy left to validate. See
`docs/legal/SECURITY_ARCHITECTURE.md` §5.1. `BiometricGateTests` was deleted with it.

**Approval-trust-boundary hardening pass — 2026-07-04 (branch `fable/approval-security-hardening`), against the 2026-07-02 Codex read-only audit's 6 findings:**

- ✅ **Replay resistance (audit finding) — verified correct in both directions.** The Go daemon stamps
  `sendSeq` on every send and checks `recv.accept(seq)` on every receive (`e2e_client.go`); the Swift
  client mirrors both (`SSHTransport/E2ERelayClient.swift` `SeqFrame`/`ReplaySequencer`); counters
  reset on `peer_joined`. 🟡 **Accepted P2 limitation:** the session key derivation has no epoch
  nonce, so a malicious relay forging `peer_joined` re-derives the SAME key and resets the sequencer,
  permitting replay of prior-generation frames. Impact bounded: approval IDs are single-use
  (`approvalStore.resolve` deletes on resolve) and decisions must also pass the content-hash check.
  Full fix = epoch nonces in HKDF inputs (protocol change on both sides) — tracked, not done.
- ✅ **Content-hash binding (audit finding) — verified; cross-language vector pinned on BOTH sides.**
  Go `computeContentHash` and Swift `Approval.computeContentHash` produce byte-identical digests;
  the shared vector `c5fca73e…` is asserted in `content_hash_test.go` (Go) and
  `ApprovalContentHashTests.matchesGoVector` (Swift), and was independently recomputed with `shasum`.
- ✅ **`noClientGrace` 8s auto-allow (audit P0) — reclassified: confirmed intentional,
  risk-tier-scoped, NOT a fail-open bug.** The comment block at `server.go:1274-1297` documents the
  owner directive (2026-07-02): only low/medium risk gets the grace; high/critical waits indefinitely
  for an explicit human decision. **However, the tier gating was NOT airtight — real gap found and
  fixed:** `policy.Evaluate` trusted a wire-supplied `risk >= 0` verbatim, and hook adapters send
  coarse tiers (opencode: any non-bash tool → low; Claude wrapper: unknown tools → low; a JSON event
  omitting `risk` unmarshals to 0 = low), so a lied/omitted band made a dangerous escalation
  grace-eligible. Fixed: the evaluated risk is now **floored at the daemon's own `ScoreRiskInt`** —
  clients may raise a tier, never lower it. Regressions: `TestEvaluateWireRiskCannotDowngrade`
  (policy) + `TestHookLiedLowRiskNoClientDoesNotAutoApprove` (server-level, proves the event stays
  pending past the grace and honors the eventual explicit decision).
- ⏹️ **BiometricGate wired into approval decisions — superseded, removed 2026-07-07.** This audit
  finding described `ApprovalDecisionAuth`'s risk-tiered gate, which existed from 2026-07-04 to
  2026-07-07. It was removed entirely (permanent product decision, not a regression) — approve/
  reject decisions now commit directly at every entry point regardless of risk tier, with no local
  auth check. `ApprovalDecisionAuth`, `InboxDecisionGateTests`'s gate-specific cases, and
  `BiometricGateTests` were deleted with it. See `docs/legal/SECURITY_ARCHITECTURE.md` §5.1.
- ✅ **App Attest on device binding (audit finding — was: QR secret + auth alone binds).**
  `push-backend` now verifies an Apple App Attest attestation at **bind** time (bind is the iOS-side
  step; redeem is performed by the Go daemon, which cannot attest — the audit's "at redeem" intent,
  *leaked QR secret must not suffice to bind*, is enforced at bind, and redeem already requires a
  completed bind). Full verification per Apple's steps (chain to pinned Apple App Attest root CA,
  nonce, keyId, App ID, counter, aaguid) in `app_attest.go`; single-use per-user server nonces via
  `POST /v1/devices/attest-challenge`; iOS `AccountSessionController.bindDaemonDevice` attests via
  `DCAppAttestService` (iOS 26 target — no DeviceCheck fallback needed). **Fail-closed startup
  check** mirrors `relaySecretStartupCheck`: production deployment without
  `APP_ATTEST_TEAM_ID`/`APP_ATTEST_BUNDLE_ID` → `log.Fatal`. Regressions:
  `TestBindRejectsWithoutValidAttestation` (correct QR secret + missing/garbage attestation → 401;
  attest nonce single-use), `TestAttestChallengeIsPerUserAndExpires`, `TestAppAttestStartupCheck`.
  Simulator/dev backends without the env vars keep working (warn, not fatal, off Cloud Run/Fly).

**Residual operational items (not code bugs):**
- Confirm `APNS_*` + live `STRIPE_*` secrets are set on the running push-backend instance (D1 in checklist).
- **NEW (2026-07-04): the next push-backend deploy will refuse to start** unless
  `APP_ATTEST_TEAM_ID=39HM2X8GS6` and `APP_ATTEST_BUNDLE_ID=dev.lancer.mobile` are set on the service
  (plus `APP_ATTEST_ENV=development` for dev-signed builds). Deliberate fail-closed choice — set the
  env vars as part of the deploy.
- Ensure the **deployed daemon is the Go build**, not the stale Swift `lancerd` 0.1.0 (now quarantined in §3).

---

## 3. Architecture & dead code

**Verified against current code (V1_READINESS_AUDIT.md was partially actioned):**
- ✅ Already removed: `isDemo` dead branches (InboxView), `SessionsHomeView`.
- ✅ Removed in the 2026-06-27 lean sweep: `WorktreesFeature` whole target, `RunnerSetupView`, `EditScheduleSheet`, `LoopDetailView`, `GitStore`, stale `scripts/rebrand-lancer.py`, Conduit StoreKit metadata, HostControlKit `.conduit` socket/token fallback, and unused Go helpers flagged by `deadcode`.
- ✅ Engine boundary intact: `LancerCore/SecurityKit/SSHTransport/AgentKit/PersistenceKit/NotificationsKit/DiffKit/SyncKit` import **zero** SwiftUI/UIKit.
- ✅ **Removed this session:** stale Swift `lancerd` → `daemon/lancerd/legacy-swift/`; 8 zero-ref DS
  components (`DSMetricTile/DSRiskRow/DSStepNode/DSHealthRow/DSToast/DSIconTokenView` + dead `DSSkeletonRow`
  siblings); `SnippetEditorView`; **`PreviewFeature/*` whole module** (verified orphan — only a dead
  `import PreviewFeature` in `AppRoot.swift:18`, zero type usage; removed dir + Package.swift target/product/dep).
- ✅ `PreviewFeature` **REMOVED** (commit 59e7ae3d): module dir + Package.swift target/product/AppFeature dep all deleted.
- ✅ **CORRECTION:** `FilesFeature` is **NOT orphaned** — `FilePreviewView` has a real production route via
  `SessionWorkspaceContainer.swift:604` (relay-backed file preview) and `RelayFileBrowserView.swift`. **Keep.**
  (An earlier draft of this doc wrongly listed it as orphaned; a later draft's citation —
  `AgentDetailView.swift:405`/`AgentFilesView` — was itself stale, since both were superseded by
  `RelayFileBrowserView`/`SessionWorkspaceContainer` and no longer exist in the tree. Corrected 2026-07-06.)
- ✅ `QuotaGuardView` is **reachable** (`AppRoot.swift:489`) — keep (also wrongly listed orphaned earlier).
- 🟡 **Follow-up:** after PreviewFeature removal, `PreviewKit` is consumed only by the test target — evaluate
  it for removal separately.

**Per-run git worktree isolation (2026-07-04 foundation):**
- Daemon RPCs: `agent.worktree.create`, `agent.worktree.remove`, extended `agent.worktree.list` (`managed` flag + `managedOnly` filter).
- Opt-in via `useWorktree` on `agent.dispatch` and new-conversation `agent.conversations.append`.
- Managed paths live under `~/.lancer/worktrees/<repo>/<id>` — distinct from vendor scratch dirs (`.claude/worktrees/`).
- **Retention policy:** successful runs (`exited`, exit code 0) auto-remove the managed worktree; **failed runs keep the worktree** on disk for host-side inspection. Manual cleanup: `agent.worktree.remove` or `git worktree remove` on the host. No automatic TTL yet — stale failed worktrees are an operational follow-up.
- iOS surfaces `worktreePath` / `isolated` on dispatch responses; no dedicated worktree manager UI (the old `WorktreesFeature` target stays removed per §3 above).

**Repo hygiene — FIXED:**
- `daemon/agent-runner/agent-runner` (Mach-O 8.2 MB) was tracked in git while sibling binaries were ignored.
  Untracked (`git rm --cached`) + added to `.gitignore`. Committed `810d8704`.

---

## 4. Performance — audited inline 2026-06-17 (verdict: HEALTHY)

The runtime perf lane (originally throttled) was completed inline against current source. **Conclusion: no P1
perf issues.** The hot paths are correctly engineered:
- ✅ **List virtualization** — `ChatTranscriptView` (`LazyVStack` + stable `ForEach(..., id: \.element.id)`,
  line 74/78), `InboxView` (`LazyVStack`, line 106), `FleetView` (`LazyVStack`, line 108), `ActivityView`
  (`LazyVStack`, line 38) all virtualize.
- ✅ **Terminal output is capped** — `TerminalEngine/BlockRenderer.swift:214-239` trims per-block to
  `maxLinearLines`; `trimToLatest(_:)` (line 318) caps total block count. Not unbounded.
- ✅ **Audit feed is capped** — `ActivityView.swift:113` `tailAudit(100)` bounds entries to 100.

**Residual (low):**
- **P3** `InboxFeature/BridgeAuditFeedView.swift:24-25` renders its rows in a plain `VStack` (not Lazy)
  nested as the single child of `ActivityView`'s `LazyVStack` — so all ≤100 audit rows build eagerly,
  defeating the parent's laziness. Harmless at the 100-row cap; would matter if the cap grows. Fix: render
  the `ForEach` directly in the parent `LazyVStack`, or make this a `List`.
- **P3 (build-time only, no runtime cost)** slow-to-type-check getters >300ms — split the expressions:
  `ChatTranscriptView.swift:90` `transcriptBody` (481ms), `FleetView.swift:89` `body` (308ms).
  (`SnippetEditorView` was deleted in §3, so its 303ms getter is gone.)

---

## 4b. UX + Accessibility — audited inline 2026-06-17

**UX (verdict: solid):**
- ✅ Empty states exist on core surfaces — `InboxView.swift:102-103` (`InboxEmptyState`), `FleetView.swift:140-141`
  (`emptyState`), `ActivityView.swift:66` (loading `ProgressView` + empty branch).
- ✅ Design-system glass primitive (`lancerGlassChrome`) is the single chrome path (agent-contract §4).
- No prototype-quality/placeholder screens found in the production navigation.

**Accessibility — VoiceOver labels FIXED this session:**
- ✅ Added `.accessibilityLabel` to the icon-only controls flagged by the per-screen sweep: ChatInputBar
  (mic/snippet/stop, send Menu, attach Menu), ToolCardView (Explain/collapse), ChatHeaderView (session-options
  menu), AgentStatusBar (expand chevron), SecretsView (delete/add), and the shared `DSIconButton` (new
  `accessibilityLabel:` param + all 5 call sites labeled). Verified app-target build green.
- 🟡 **Residual P3 (documented, not fixed — need per-caller judgment):** (a) hardcoded `.font(.system(size: N))`
  literals that won't scale with Dynamic Type on user-facing text — `DSApprovalBanner.swift:26` (safety-critical),
  `InboxApprovalCard.swift:121`, `DSOfflineState.swift:26/52`, `ChatInputBar.swift:115` hint. Fix: swap to a
  relative text style (`.font(.subheadline)` etc.) or the DS relative token. (b) `DSStatusDot` (Primitives.swift)
  conveys status by color only (WCAG 1.4.1) — needs a tone→text `accessibilityLabel`, but it usually sits beside
  descriptive text so blind labeling risks VoiceOver double-speak; label per-caller instead.

**Reduce Motion — ✅ FIXED (commit 53bac151):**
- P2 resolved. All 7 design-system animations now gate `repeatForever` on
  `@Environment(\.accessibilityReduceMotion)` with static/opacity fallbacks: BlinkModifier,
  BlinkingCaretModifier, AgentIsland nudge, DSStatusDot pulse, DSConnectionGlyph spinner,
  DSOfflineState pulse, DSSkeletonRow shimmer, and AgentBadge streaming dots.
- **Residual (info):** `.accessibilityLabel` appears in only 8 files — icon-only buttons elsewhere may lack
  VoiceOver labels. Not individually verified (would need per-button audit); flagged for the per-screen a11y
  sweep (checklist B8).

---

## 5. Documentation state — heavy sprawl; canonical set proposed

~90 markdown docs, many overlapping or point-in-time. **Drift found earlier, now resolved:**
- `agent-contract.md` §8 once named `docs/current-state-audit.md` (2026-06-02) as the source of truth
  for "what works"; the pointer was corrected and that doc was **purged 2026-07-06**.
- `docs/remaining-work.md` (self-flagged SUPERSEDED, with a wrong "free Apple team" blocker) was
  **purged 2026-07-06**; `ARCHITECTURE.md` §0.1 + `docs/STATUS_LEDGER.md` are the live state docs.

**Canonical set (keep + maintain):**
`ARCHITECTURE.md` (product/architecture + §0.1 current-state snapshot), `docs/agent-contract.md`,
`docs/PUBLISH_READINESS_CHECKLIST.md` (launch state), `docs/SECURITY.md` +
`docs/legal/SECURITY_ARCHITECTURE.md`, `docs/ROADMAP.md`, **this file** (`KNOWN_ISSUES.md`),
`docs/block-terminal-implementation.md`, **`docs/STATUS_LEDGER.md`**. (`LANCER_PROJECT_DOSSIER.md` and
`docs/_archive/` were **purged 2026-07-06** — `ARCHITECTURE.md` §0.1 is its successor.)
Tab/gallery-era handoff/planning docs (`docs/design-handoff/PAGES.md`,
`docs/design-handoff/BACKEND_COVERAGE.md`, `docs/PRODUCTION_READINESS_PLAN.md`, root `ship-plan/`)
were **purged 2026-07-06** with the rest of `docs/_archive/`.

**Purged in the 2026-07-06 doc sweep** (formerly under `docs/_archive/`, inbound references checked):
`docs/current-state-audit.md`, `docs/remaining-work.md`, `docs/APP_AUDIT.md`,
`docs/cloud-execution-engine-plan.md`, plus the tab/gallery-era handoff/planning docs above.
**Still candidates** (lower priority): `docs/demos/M0–M11*.md`, the dated
`docs/lancer-test-run-2026-05-*.md`, and redundant audit reports folded into newer ones
(`V1_SIMPLIFY_REPORT`, `FRONTEND_SIMPLIFICATION_REPORT` vs `_REVIEW`, `FABLE_FINDINGS` vs
`FABLE_REPORT`, `FEATURE_COVERAGE` vs `FEATURE_VERIFICATION_AUDIT`).

---

## 6. Remaining P0/P1/P2 after this audit

- ~~P0 (fixed 2026-07-06): `BiometricGate` fail-closed on no-passcode / biometry-unavailable~~ —
  **moot as of 2026-07-07:** `BiometricGate` was removed from the app entirely (commit `9e18d679`,
  permanent product decision), so there is no fail-closed policy left to validate. See
  `docs/legal/SECURITY_ARCHITECTURE.md` §5.1.
- **P0 (fixed 2026-07-06, owner device validation pending):** daemon-side atomic Emergency Stop
  latch in `dispatch.go` (`agent.emergencyStop` RPC). Verified: `go test ./...` from
  `daemon/lancerd`. External beta still needs owner sign-off on real-device policy behavior.
- **P1 (RESOLVED):** `e2eRouter.sendApproval` (`daemon/lancerd/e2e_router.go`) silently no-ops with zero
  logging when `!r.client.isPaired()` — found 2026-06-18 during `docs/LIVE_LOOP_RUNBOOK.md` Phase 3 live
  testing on a real phone. **Fixed:** early-return now logs
  `e2e: dropped approval <id> — relay client not paired` so a dropped send is distinguishable from
  "phone never got it" in `lancerd.stderr.log` (branch `cursor/sendapproval-log-9257`).
- **P2:** (b) Per-screen VoiceOver-label + Dynamic-Type sweep across all surfaces (checklist B8).
  *(a) Reduce-Motion ✓ fixed 53bac151. (c) PreviewFeature ✓ removed 59e7ae3d.*
- **P3:** `BridgeAuditFeedView` plain-VStack laziness defeat (§4); 2 slow-type-check getters (§4); deliberate
  doc archival pass already done this session (§5 archived 23 docs). GitHub-repo-connector chip in the
  new-chat composer (seen in Claude mobile's composer, studied during the 2026-06-18 sidebar/Sessions IA
  redesign) is intentionally deferred — revisit when repo-scoped dispatch context is needed.
- **Owner-gated (unchanged):** App Store Connect setup, physical-device APNs smoke test, live remote-host
  E2E, vanity domain/DNS — see `docs/PUBLISH_READINESS_CHECKLIST.md` §C/§D.
- **P1 (found + fixed 2026-07-02):** relay machine pairing silently traps users at the 3-machine cap
  with no way to tell why. Root cause: `RelayMachineMigration`'s machines-index lives in the iOS
  **Keychain** (`RelayMachineMigration.swift`), which — unlike `UserDefaults`/app-container files —
  **survives a full app uninstall + reinstall**. Repeated pairing attempts during physical-device
  testing (stale/expired codes, reconnect races) each persisted a `RelayMachineRecord`, and even
  uninstalling the app didn't clear them. Two compounding symptoms discovered live on-device:
  1. `E2ERelayPairingView`'s cap check (`existingMachineCount >= relayFleetMaxMachines`) correctly
     saw 3 stale/dead machines and refused new pairing ("You've paired 3 machines — the maximum"),
     but gave no indication *those machines were themselves unreachable* — a user has no way to
     know removing them is safe/expected.
  2. Simultaneously, `FleetView`'s "Machines" tab rendered as if **zero** machines were paired
     (`activeRelayMachines.isEmpty` — active-only filter) — directly contradicting the pairing
     screen's "3 machines, at the max" message from the very same `relayFleetStore.machines` data.
     A user hitting the cap had nowhere obvious to look, since the one screen that *would* show
     stale entries with per-row offline indicators (Settings → Paired Machines,
     `RelayMachinesListView`) isn't surfaced from the error message's dead end.
  **Fix (commit pending):** `FleetView.emptyState` now takes `hasOfflinePairedMachines` and renders
  "No machines reachable" (pointing at Settings → Paired Machines) instead of the misleading "No
  machines paired" when `relayMachines` is non-empty but nothing is active
  (`Packages/LancerKit/Sources/AppFeature/FleetView.swift`). The cap-reached message in
  `E2ERelayPairingView.swift` now explicitly states offline/unreachable machines still count toward
  the limit. Verified: `swift build` green. **Not yet fixed:** no in-app warning that pairing state
  survives uninstall (Keychain is arguably correct behavior for real users re-installing, but was
  never surfaced anywhere — worth a "Paired machines carry over after reinstall" note in onboarding
  or the Paired Machines screen if this causes future confusion). No bulk "remove all offline
  machines" action — user had to understand the cap error and navigate to Settings manually.
- **P1 (found + partially fixed, NOT confirmed resolved, 2026-07-03):** the Home screen's per-machine
  connection dot (and by extension `FleetRelayMachine`/`RelayMachineRow` everywhere else
  `relayFleetStore.machines` feeds a UI) can show a paired relay machine as disconnected/orange long
  after it has actually reconnected. Root cause: `RelayFleetStore` (`@Observable`) held each
  machine's `E2ERelayBridge` (`ObservableObject`, `@Published private(set) var isActive`) as a plain
  stored reference — `@Observable`'s macro only tracks direct mutations on the object itself, so a
  `@Published` flip inside the referenced bridge never told SwiftUI to re-render. A view could
  capture `isActive == false` once early in the connection lifecycle and never be re-invoked again
  except by an unrelated state change. Distinct from a similar-sounding, already-fixed issue in
  `SidebarShellState.relayConnected` (the sidebar footer), which has its own working live-update
  loop in `AppRoot.addRelayMachine` — this bug is specifically in `RelayFleetStore`, reached only via
  the Home/Fleet/Settings machine-list code paths.
  **Fix applied** (`Packages/LancerKit/Sources/AppFeature/RelayFleetStore.swift`, commit `61d02b8a`
  on `feat/cross-device-conversation-sync`): `add()` now subscribes to the new machine's
  `bridge.$isActive` and re-assigns `machines[i] = machines[i]` through the `@Observable`-synthesized
  setter on each emission — bridging the Combine publisher into `Observation` tracking, the standard
  pattern for this. `remove()` tears the subscription down. Builds clean, full 551-test suite green.
  **RESOLVED 2026-07-03 (second bug found + fixed, root cause proven on-device):** the Observable
  fix above was real but orthogonal. Device console (`devicectl launch --console` + added
  diagnostics) showed the indexed machine's Keychain **private key is genuinely absent**
  (`SecItemCopyMatching` → OSStatus **-25300** `errSecItemNotFound`; four *orphaned* privKeys for
  other machineIDs still present) while its UserDefaults code + relay URL survive. The old code
  compounded that corrupt state: `restoreNamespacedStoredPairing()` silently no-op'd on its
  all-three guard (never applying the stored code), but `hydrateRelayFleetStore` gated `connect()`
  on `hasStoredPairing` — which checks **only the UserDefaults code** — so the client dialed the
  relay with an **empty pairing code and a freshly generated keypair**. Cloud Run logs confirmed
  the loop: `GET /ws/relay?role=phone&code=&publicKey=<fresh-each-launch>` → HTTP 400, every few
  seconds, forever. `pairingState` never left `.unpaired` → `bridge.isActive` correctly false →
  permanent orange dot, regardless of the daemon's own (healthy) hourly reconnects.
  **Fix (on `feat/cross-device-conversation-sync`):** `restoreNamespacedStoredPairing()` now
  returns `Bool` and logs exactly which piece is missing; hydration gates `connect()` on the full
  restore succeeding (un-restorable machines stay listed but offline instead of hammering the
  relay); `connect()` refuses an empty pairing code outright; `persistPairing()` is now
  all-or-nothing (Keychain key written first, code/URL only on success) so this split state can't
  be re-created. 3 regression tests added (`E2ERelayClientRestoreTests`); full suite 554/554 green;
  verified live on-device: fixed build logs the INCOMPLETE state and makes **zero** relay dials
  (Cloud Run shows no new phone 400s post-fix).
  **Re-pair completed 2026-07-03 (evening session):** owner removed machine `14FBE4E8` and
  re-paired on the physical iPhone against a fresh build with this fix. Confirmed via
  `lancerd.stderr.log` (`e2e: paired with phone (code: 873026)`) and the device UI directly
  ("online · healthy", ONLINE badge, green dot on Home) — the orange-dot bug is closed on the
  owner's real device. Composer send through the real UI over this relay connection was also
  proven live (real dispatch + streamed reply, not a local echo) — see `ARCHITECTURE.md` §0.1 / §11.2
  (detailed test-run logs purged 2026-07-06).
  **Still open, follow-ups (not release-blocking):** (a) 4 orphaned
  `lancer.relay.machine.*.privKey` Keychain items linger on that device (harmless, but a cleanup
  sweep on hydrate would be tidy — not implemented, judged not worth the risk this session);
  (b) no UI yet distinguishes "paired but needs re-pair" from "paired, host offline" — the log
  does, the dot doesn't; (c) the historical writer of the corrupt state (key deleted vs.
  `SecItemAdd` failed during pairing) was not identified — `persistPairing` atomicity + the new
  OSStatus logging make any recurrence self-diagnosing.
  Full investigation record: summarized in this entry (detailed test-run logs purged 2026-07-06).
- **P1 (filed 2026-07-04, ROOT CAUSE FOUND + resolved same day):** after stopping/restarting the
  production `dev.lancer.lancerd`, the daemon logged `connected to relay as daemon (code: 194990)`
  with no `paired with phone` ever following, while Cloud Run showed the phone reconnecting with a
  *different* code (`role=phone&code=893127`). **This was not a restart bug.** Root cause: the
  daemon has exactly ONE pairing slot (`~/.lancer/relay-pairing.json`), and every daemon-side
  pairing entry point (`lancerd pair`, `agent.pair.begin`, `lancerd relay-attach`, the install
  helper) mints a fresh code and overwrites that file immediately; the resident's watcher then
  hot-swaps the live relay client onto the new code within ~5s — silently orphaning every phone
  paired to the old code. On 2026-07-03 20:57 a test session re-paired the daemon (code 194990)
  and the "phone" that completed that pairing was the iPhone 17 Pro **Simulator** (verified: the
  sim container holds `lancer.relay.machine.….code => 194990`); the owner's real iPhone (893127)
  had been orphaned since that moment. The 2026-07-04 10:24 restart merely revealed it. The
  restart-reconnect path itself (persisted pairing intact on both sides) was verified working
  live — see `ARCHITECTURE.md` §0.1 (connection-state test-run logs purged 2026-07-06). Restart-with-intact-
  pairing requires NO re-pair; a daemon-side re-pair orphans all phones BY DESIGN of the single
  pairing slot, and is now loud: `writeRelayPairing` + the watcher log
  `REPLACING existing relay pairing (code X -> Y) — phones paired to the old code are orphaned`.
  A related silent-orphan defect on the phone was fixed in the same pass: `addRelayMachine`
  started + registered a bridge even when `RelayFleetStore.add()` silently dropped the machine at
  the 3-machine cap, producing a pairing that worked in-memory until the next relaunch and then
  vanished (never in the hydration index). `add()` now returns `Bool`; the caller tears down and
  logs `.fault` on a cap drop; hydration logs a launch summary of exactly which machines the index
  restores. **Owner action:** the physical iPhone's 893127 pairing is unrecoverable by code — it
  must be re-paired once against the daemon's current code. Follow-up (unfiled, low): from the
  phone, an orphaned pairing is protocol-indistinguishable from "host offline" — the new
  `ConnectionStateStore.hostOffline` state's UI copy should eventually hint "if the Mac shows a
  new pairing code, re-pair". Second observation from the same logs: an additional daemon dials
  the relay hourly on code `504109` (pk `n_dtq…`) from somewhere other than this Mac's launchd
  daemon — likely a stale test/remote instance; harmless but worth identifying.

---

## 7. Live device dogfood session — 2026-07-18 (rolling log)

> Started when the owner asked to rebuild master on their physical iPhone and walk the remaining
> App Store publish-readiness checks (see `docs/PUBLISH_READINESS_CHECKLIST.md` §B/§C/§D). Findings
> below surfaced from actually watching the app live on-device, not from code review. Appended to
> as the session continues — newest at the bottom of the section, same as `docs/CHANGELOG.md`.

- **P1 (found + fixed same session):** a message the owner typed mid-turn into an *observed*
  desktop session (watching an already-running Claude Code CLI session mirrored onto the phone)
  never appeared in the thread — the assistant's reply rendered, the owner's own question bubble
  did not. Root cause: Claude Code's "queue a message while I'm working" feature persists the
  message as a `type:"attachment"` JSONL record (`{"attachment":{"type":"queued_command","prompt":
  …,"origin":{"kind":"human"}}}`), not a normal `type:"user"` line. `parseClaudeLine`
  (`daemon/lancerd/claude_transcript_adapter.go`) had never seen that shape and bucketed it with
  pure harness bookkeeping (`queue-operation`, `summary`, `mode`, …) — silently dropped before it
  ever reached the ledger, not just hidden by a display filter. **Fix:** `attachment` records with
  `attachment.type=="queued_command"` and `attachment.origin.kind=="human"` now render as a real
  user-role `SessionMessage`; the sibling `queue-operation` enqueue/remove bookkeeping lines (same
  text, different record) stay ignored so the message isn't duplicated. Two regression tests added
  using the exact JSONL shape captured from the live session
  (`TestParseClaudeTranscriptQueuedMidTurnMessageRenders`,
  `TestParseClaudeTranscriptQueuedAttachmentIgnoresNonHumanOrigin`); full `go test ./...` from
  `daemon/lancerd` green. Verified live: rebuilt + reinstalled on the owner's iPhone via
  `XcodeBuildMCP build_run_device`.
- **P2 (found + fixed same session):** no visual indicator that the agent was still working while
  watching a live observed session — the thread looked frozen between completed tool-call chips
  even though the underlying CLI process was actively producing output. Root cause:
  `LiveThreadView`'s working indicator is driven entirely by `ShellLiveBridge.sendState`, which
  only models Lancer-*dispatched* sends; the observed-session follow loop
  (`observedFollowLoop`/`startObservedFollow`) updates `transcriptTurns` on a timer but never
  touches `sendState`, so it stayed `.idle` for the whole watch. **Fix:** added
  `ShellLiveBridge.isObservedSessionWorking` — set true when a follow poll returns new messages,
  cleared after `LivePollPolicy.observedFollowIdleGracePolls` (4) consecutive empty polls so it
  goes honest-idle once activity actually stops rather than claiming "Working…" over stale data
  (same rule already applied to the `.degraded` send state). `LiveThreadView`'s `.idle` reply-state
  case now shows the existing `workingIndicator` when this flag is set. Verified: `swift build` +
  targeted `swift test` (note: both touched files are `#if os(iOS)`-gated, so validation that
  actually matters is the `XcodeBuildMCP` app-target device build, which succeeded and is what's
  running on-device now — plain SPM `swift build` silently skips this code, see `CLAUDE.md`
  "Tooling gotchas").
- **P0 (found live, fix in progress):** app-closed lock-screen APNs push — the last open item on
  `docs/PUBLISH_READINESS_CHECKLIST.md` §C2/D3 — reproduced FAIL live. Fired a real approval
  escalation (`lancerd agent-hook`) with the owner's phone locked; waited 4+ minutes, no push
  banner ever arrived; the pending approval only surfaced once the owner manually unlocked and
  opened the app (fetched over the live relay connection on reconnect, not push). Root cause
  traced fully: `Lancer/LancerApp.swift`'s `AppDelegate` correctly captures the APNs device token
  and posts `.lancerAPNSTokenReceived` — **nothing in the app observes that notification.**
  `SessionFeature/E2ERelayBridge.swift`'s `registerDevice(apnsToken:sessionID:pushBackendURL:)`
  exists specifically to forward the token to the paired daemon over the relay (its own doc
  comment says so) but **is never called from anywhere.** Same dead-end for Live Activity push
  updates: `registerActivityToken(...)` and the `.lancerLiveActivityTokenReady` notification are
  equally unwired. Net effect: the daemon never learns the phone's real push token, so every
  approval delivery has silently depended on the live relay WebSocket staying connected — which
  iOS kills once the app backgrounds/locks long enough, with no APNs fallback ever configured.
  **Fix implemented:** new `DevicePushRegistrationCoordinator` (`AppFeature/Bridge/`, 202 lines)
  observes both triggers — a `RelayFleetStore` connection transition to `.connected` (covers
  pairing-before-token AND reconnect after background/relay-drop/daemon-restart, since the daemon
  itself never persists the raw APNs token — see `server.go` `savePersistedDevice` — only
  session+relayToken, so a phone-side resend on every reconnect is load-bearing, not optional) and
  the `.lancerAPNSTokenReceived`/`.lancerLiveActivityTokenReady` notifications (covers
  token-after-pairing) — and forwards to `E2ERelayBridge.registerDevice`/`.registerActivityToken`
  on **every** currently-connected machine (push delivery is per-daemon; each paired Mac needs its
  own copy of the token to push for runs on that specific host). Wired into `AppRoot` alongside its
  sibling ingest coordinators. Daemon-side `e2e_router.go`'s `deviceRegister` handler (line 627)
  was independently confirmed already-correct — it forwards the APNs token via
  `postDeviceTokenRegistration`, no daemon change was needed. 8 new unit tests covering both
  orderings, reconnect re-registration, and the no-op cases (untestable via plain `swift test` —
  `#if os(iOS)`-gated like the rest of `AppFeature`); the real-iOS-target app build (XcodeBuildMCP,
  simulator) compiles clean with the coordinator included. Rebuilt and installed on the owner's
  physical iPhone 2026-07-18 21:45 ET — **live lock-screen re-proof still owed**, only the owner
  watching their own locked phone can confirm the banner actually arrives.
- **P1 (found + fixed same session):** two independent, compounding bugs behind the widget-count
  bug above — both go deeper than the widget. **Bug A, the more consequential one:**
  `AppDatabase.openShared()` (`PersistenceKit/AppDatabase.swift`) resolved the local GRDB database
  inside `.applicationSupportDirectory` — a path scoped to the *calling process's own sandbox
  container*. `ApprovalActionIntent` (the Lock Screen / Dynamic Island Approve/Reject button) is a
  `LiveActivityIntent`, which iOS runs inside the `LancerWidgets` extension's own process, not the
  main app's — so every lock-screen decision wrote its resolved-row update into a database the main
  app could never see. The decision still correctly reached the daemon over the network
  (`ApprovalRelay.enqueue` is unaffected — this is why the daemon's own approval queue was always
  right), but the main app's local row stayed permanently "pending," producing an ever-growing ghost
  count with a summary frozen on whatever was newest when the ghost accumulation started. **Fix:**
  `openShared()` now resolves the database inside the App Group container
  (`group.dev.lancer.mobile`, confirmed matching both `Lancer.entitlements` and
  `LancerWidgets.entitlements`) so every process — main app, widget extension, Watch companion —
  shares one physical file; `busyMode = .timeout(5)` added since multiple processes now write
  concurrently. A one-time, non-destructive copy migration (DB + WAL/SHM sidecars) moves existing
  installs' history from the old private-container location so upgrading users don't lose data.
  This changes where the *entire* app's local data lives (chat history, hosts, snippets — not just
  approvals), not just approvals — reviewed carefully given the blast radius before merging.
  **Bug B:** the doc comment on `ApprovalRepository+WidgetSnapshot.swift`'s writer claimed it fires
  on both "new approval arrives" and "decision resolves," but the "arrives" call site only existed
  on a dead `ApprovalIngest`/`FleetStore` code path never constructed in production (`AppRoot`/
  `WorkspacesView` exclusively use `RelayFleetStore`) — the real production entry point,
  `RelayApprovalIngest.handle(_:)`, never called the writer at all, so the widget only ever
  refreshed as a side effect of a later in-app decision, never on arrival. Fixed:
  `RelayApprovalIngest.handle(_:)` now calls `writeApprovalWidgetSnapshot()` after persisting.
  Third finding, flagged but explicitly not fixed (dormant in production, not a live contributor):
  `SessionViewModel.writeWidgetSnapshot` writes the same `WidgetSnapshot.pendingApprovalsKey` with a
  narrower single-session count — a real key collision between two widgets' data, currently inert
  only because `SessionViewModel` is itself only reachable through the same dead `FleetStore` path.
  Verified: new `WidgetSnapshotWriterTests.swift` (two suites, arrive→arrive→resolve→resolve
  sequencing + the real `RelayApprovalIngest.handle()` call site) — both pass on the real iOS target
  via `XcodeBuildMCP test_sim` (this file is `#if os(iOS)`-gated end-to-end, so plain `swift test`
  silently compiles it out entirely — confirmed by checking the compiled binary contained zero
  matching symbols; this is a real gotcha worth remembering, not just a caching hiccup). Nine
  pre-existing approval/relay regression tests re-run alongside, all still passing. Rebuilt and
  installed on the owner's physical iPhone 2026-07-18 21:45 ET.
- **P1 (found + fixed same session):** `agent.observedSession.continue` (`dispatch.go`'s
  `resumeObservedSession`) launched a brand-new `claude --resume <sessionId>` process with **zero
  check** for whether that exact vendor+session was already being resumed — two overlapping calls
  (a slow first reply plus an impatient second follow-up, or a client-side race) could spawn two OS
  processes concurrently appending the same on-disk session transcript file, a real corruption risk.
  Root cause of the client-side half: `ShellLiveBridge.isSendInFlight` only reflected
  Lancer-*dispatched* sends (`sendState`), never the observed-follow signal, so `sendFollowUp` would
  skip its own local queue and fire the resume RPC immediately even while the transcript showed the
  session actively still writing. **Fix:** daemon-side reservation guard
  (`dispatcher.activeObservedResumes`, a vendor+sessionID→runID map checked-and-set atomically,
  released on terminal status) rejects a second concurrent resume of the same session with
  `Status: "busy"`; client-side, `isSendInFlight` now folds in `isObservedSessionWorking` (a new
  narrower `isDispatchSendInFlight` keeps the observed-follow loop's own internal "don't
  double-render" check from self-locking against its own busy signal) so a follow-up typed while an
  observed session looks busy queues locally and flushes once activity actually stops — real
  Claude-Code-style queue-while-working parity for the observed-session path, not just the
  Lancer-dispatched one. Verified: 2 new Go tests (`TestResumeObservedSessionSameSessionBusy
  RejectsSecondLaunch`, `...ReservationReleasedOnTerminal`), full `go test ./... -race` green from
  `daemon/lancerd`; Swift side confirmed via a real iOS-target sim build (`XcodeBuildMCP build_sim`)
  after merge — plain `swift build`/`swift test` skip the touched `#if os(iOS)` files entirely.
  Rebuilt and installed on the owner's physical iPhone 2026-07-18 21:45 ET.
