# Lancer — Known Issues & Pre-Launch Audit (canonical)

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

> **Compiled:** 2026-06-19 · branch `master` (updated).
> This is the canonical "what's broken / what's verified / what's residual" doc. It supersedes the
> scattered point-in-time audit docs for **issue tracking**. For launch *checklist* state use
> `docs/PUBLISH_READINESS_CHECKLIST.md`; for product/architecture narrative use `ARCHITECTURE.md`
> (§0.1 current-state snapshot + §4.1 IA). The current IA is the **sidebar / New Chat shell** —
> not a tab bar (the old `LANCER_PROJECT_DOSSIER.md` is archived under `docs/_archive/`).
>
> **Method note:** the multi-agent fan-out repeatedly tripped the account session limit (parallel agents
> burn quota fast), so **all dimensions were audited inline by a single agent** against current source —
> security, architecture, build, **and** perf/UX/a11y (§4, §4b). Findings cite real file:line evidence.

---

## 0. P0 tester-readiness blockers — VERIFIED DOWN (2026-06-20)

> Found while assessing "can self-hosted testers use this yet?". Both block the V1 relay loop;
> neither is an app-code bug. Tracked here; owned by the daemon/infra lane.

- **`TESTER-1` — The V1 relay is unreachable.** `curl https://35.201.3.231.sslip.io/health`
  (the URL baked into `project.yml:26` `LANCER_PUSH_BACKEND_URL`) returns nothing. V1's transport is
  the E2E relay (phone ↔ `push-backend` ↔ daemon), so the entire control loop is dead until it is
  redeployed. **Note the drift:** §A of `PUBLISH_READINESS_CHECKLIST.md` claims a 2026-06-19 Cloud Run
  rebuild (`lancer-push`, australia-southeast1), but the app ships the `sslip.io` URL — reconcile which
  instance is canonical and point `project.yml` at the live one.
- **`TESTER-2` — The `lancerd` install one-liner 404s.** The only published GitHub release is stale
  `v0.1.0` (2026-05-24, pre-policy/pre-relay-fix). Its asset names use hyphens
  (`lancerd-darwin-arm64`) but `daemon/lancerd/install.sh` fetches underscores
  (`lancerd_darwin_arm64`); there is also no `SHA256SUMS`, no `install.sh` asset, and no darwin-amd64
  binary. `curl … | sh` cannot succeed. Fix: cut a fresh release from current source for
  darwin/linux × amd64/arm64 with `SHA256SUMS`, reconcile the naming, and add a release CI job
  (only `ci.yml` exists today).

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

**Open test debt — `UI-IA-1` (tracked 2026-06-19):** four `LancerUITests/TapInjectionProofTests` are
**quarantined with `XCTSkip`** — `testTapInjectionViaTabSwitch`, `testApproveDecisionApplies`,
`testFaceIDToggleOptIn`, `testSavedHostReconnectPresentsPrompt`. They assert the **superseded tab-bar
navigation** (`app.buttons["Settings"]`/`["Inbox"]`, `LANCER_TAB=settings/fleet`, "inbox" default header).
The app home is now the **sidebar / New Chat shell**, so these surfaces aren't reachable via the old nav.
They are *not* a regression from the 2026-06-19 V1 work (Live Activity push / watch / opencode gating) —
`git diff` shows that work never touched `LancerUITests/`. **Re-enable** them with sidebar-shell navigation
(open-drawer → destination) once the sidebar IA is committed/settled. The XCUITest injection-proof value
(approve-applies, Face-ID opt-in, saved-host reconnect, TOFU) is worth preserving — rewrite, don't delete.

---

## 2. Security posture — GO holds; most prior OPEN items now CLOSED in code

The 2026-06-13 triage (`docs/audit/2026-06-13-security-triage.md`) reached **GO** on the four core
properties. Re-verified 2026-06-17, the code has since **closed almost every OPEN item** — that triage
doc is now stale on its "OPEN" column:

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

**Documented security follow-up (P2, device validation needed):**
- **BiometricGate no-passcode fallback still degrades open.** `SecurityKit/BiometricGate.swift:16-24`
  now falls back to `.deviceOwnerAuthentication` when biometry is not enrolled, and the `.biometryLockout`
  branch requires passcode. If `canEvaluatePolicy` fails for other reasons, the gate still returns success
  for simulator/no-passcode compatibility. **Recommended fix:** add a device-tested policy that fails closed
  on real devices without passcode, while preserving explicit simulator/test bypass behavior. Defense-in-depth
  bonus: bind SSH-key Keychain items with `SecAccessControl` where feasible.

**Residual operational items (not code bugs):**
- Confirm `APNS_*` + live `STRIPE_*` secrets are set on the running push-backend instance (D1 in checklist).
- Ensure the **deployed daemon is the Go build**, not the stale Swift `lancerd` 0.1.0 (now quarantined in §3).

---

## 3. Architecture & dead code

**Verified against current code (V1_READINESS_AUDIT.md was partially actioned):**
- ✅ Already removed: `isDemo` dead branches (InboxView), `SessionsHomeView`, `WorktreeBoardView`.
- ✅ Engine boundary intact: `LancerCore/SecurityKit/SSHTransport/AgentKit/PersistenceKit/NotificationsKit/DiffKit/SyncKit` import **zero** SwiftUI/UIKit.
- ✅ **Removed this session:** stale Swift `lancerd` → `daemon/lancerd/legacy-swift/`; 8 zero-ref DS
  components (`DSMetricTile/DSRiskRow/DSStepNode/DSHealthRow/DSToast/DSIconTokenView` + dead `DSSkeletonRow`
  siblings); `SnippetEditorView`; **`PreviewFeature/*` whole module** (verified orphan — only a dead
  `import PreviewFeature` in `AppRoot.swift:18`, zero type usage; removed dir + Package.swift target/product/dep).
- ✅ `PreviewFeature` **REMOVED** (commit 59e7ae3d): module dir + Package.swift target/product/AppFeature dep all deleted.
- ✅ **CORRECTION:** `FilesFeature` is **NOT orphaned** — `FilePreviewView` has a real production route via
  `AgentFilesView` → `AgentDetailView.swift:405` ("Files" tool row) + `AgentRunDetailView.swift:215`. **Keep.**
  (An earlier draft of this doc wrongly listed it as orphaned.)
- ✅ `QuotaGuardView` is **reachable** (`AppRoot.swift:489`) — keep (also wrongly listed orphaned earlier).
- 🟡 **Follow-up:** after PreviewFeature removal, `PreviewKit` is consumed only by the test target — evaluate
  it for removal separately.

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

~90 markdown docs, many overlapping or point-in-time. **Drift confirmed:**
- `agent-contract.md` §8 named `docs/current-state-audit.md` (2026-06-02) as the source of truth for
  "what works" — that doc is the **oldest** state doc. Pointer corrected this session.
- `docs/remaining-work.md` is self-flagged SUPERSEDED yet still states a **wrong** "free Apple team"
  blocker — keep the banner, do not act on its blockers.

**Canonical set (keep + maintain):**
`ARCHITECTURE.md` (product/architecture + §0.1 current-state snapshot), `docs/agent-contract.md`,
`docs/PUBLISH_READINESS_CHECKLIST.md` (launch state), `docs/SECURITY.md` +
`docs/legal/SECURITY_ARCHITECTURE.md`, `docs/ROADMAP.md`, **this file** (`KNOWN_ISSUES.md`),
`docs/block-terminal-implementation.md`. (`LANCER_PROJECT_DOSSIER.md` is **archived** —
ARCHITECTURE.md §0.1 is its successor.)

**Recommended archival** (move to `docs/_archive/` with a pointer — preserve, don't delete; do deliberately
in a dedicated cleanup pass, checking inbound references first): `docs/current-state-audit.md`,
`docs/remaining-work.md`, `docs/APP_AUDIT.md`, `docs/cloud-execution-engine-plan.md`,
`docs/demos/M0–M11*.md`, the dated `docs/lancer-test-run-2026-05-*.md`, and the redundant audit reports
that have been folded into newer ones (`V1_SIMPLIFY_REPORT`, `FRONTEND_SIMPLIFICATION_REPORT` vs `_REVIEW`,
`FABLE_FINDINGS` vs `FABLE_REPORT`, `FEATURE_COVERAGE` vs `FEATURE_VERIFICATION_AUDIT`).

---

## 6. Remaining P0/P1/P2 after this audit

- **P0:** none found in code (builds green, security GO, no confirmed exploitable issue).
- **P1:** `e2eRouter.sendApproval` (`daemon/lancerd/e2e_router.go`) silently no-ops with zero logging when
  `!r.client.isPaired()` — found 2026-06-18 during `docs/LIVE_LOOP_RUNBOOK.md` Phase 3 live testing on a
  real phone. A real escalation was dropped this way (audit showed `escalate`→`deny` exactly 120s apart,
  i.e. the fail-closed timeout, not a human decision) while `lancerd.stderr.log` showed irregular relay
  re-pairing right around that timestamp — the daemon and phone's websocket pairing flaps, and any
  approval that fires inside a flap window vanishes with no trace beyond the eventual timeout-deny. A
  retry once the relay had been stable for 30+ min succeeded normally (`escalate`→`approve` in 49s). The
  loop's fail-closed behavior means this is safe, not silent-unsafe — but it's silent-*undiagnosable*: add
  a log line on the early-return so a dropped send is distinguishable from "phone never got it" in
  `lancerd.stderr.log` instead of only inferable from audit-log timing + re-pair-log correlation after
  the fact.
  (Perf/UX/a11y deep audit is now done — §4/§4b. The stale Swift `lancerd` was quarantined this session;
  `SnippetEditorView` + dead DS components were removed.)
- **P2:** (b) Per-screen VoiceOver-label + Dynamic-Type sweep across all surfaces (checklist B8).
  *(a) Reduce-Motion ✓ fixed 53bac151. (c) PreviewFeature ✓ removed 59e7ae3d.*
- **P3:** `BridgeAuditFeedView` plain-VStack laziness defeat (§4); 2 slow-type-check getters (§4); deliberate
  doc archival pass already done this session (§5 archived 23 docs). GitHub-repo-connector chip in the
  new-chat composer (seen in Claude mobile's composer, studied during the 2026-06-18 sidebar/Sessions IA
  redesign) is intentionally deferred — revisit when repo-scoped dispatch context is needed.
- **Owner-gated (unchanged):** App Store Connect setup, physical-device APNs smoke test, live remote-host
  E2E, vanity domain/DNS — see `docs/PUBLISH_READINESS_CHECKLIST.md` §C/§D.
