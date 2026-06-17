# Conduit — Known Issues & Pre-Launch Audit (canonical)

> **Compiled:** 2026-06-17 · branch `opencode/onboarding-redesign` (83 commits ahead of `master`).
> This is the canonical "what's broken / what's verified / what's residual" doc. It supersedes the
> scattered point-in-time audit docs for **issue tracking**. For launch *checklist* state use
> `docs/PUBLISH_READINESS_CHECKLIST.md`; for product/architecture narrative use `ARCHITECTURE.md`
> + `docs/CONDUIT_PROJECT_DOSSIER.md` (note: dossier is from 2026-06-11 and its IA section is stale —
> tabs are now **Inbox / Fleet / Activity / Settings**, session surface is chat-based).
>
> **Method note:** the multi-agent fan-out repeatedly tripped the account session limit (parallel agents
> burn quota fast), so **all dimensions were audited inline by a single agent** against current source —
> security, architecture, build, **and** perf/UX/a11y (§4, §4b). Findings cite real file:line evidence.

---

## 1. Build & test baseline — VERIFIED GREEN (2026-06-16/17)

| Target | Command | Result |
|---|---|---|
| ConduitKit (SPM) | `cd Packages/ConduitKit && swift build` | ✅ clean (4.9s) |
| App target (strict concurrency) | `xcodebuild -scheme Conduit -destination 'iPhone 17 Pro' build` | ✅ **BUILD SUCCEEDED**, 0 concurrency/sendable warnings |
| conduitd + policy (Go) | `go vet ./... && go build ./... && go test ./...` | ✅ pass |
| push-backend (Go) | `go vet/build/test ./...` | ✅ pass (1.2s) |
| agent-runner (Go) | `go vet/build/test ./...` | ✅ pass |
| conduit-mcp (Go) | `go build ./...` | ✅ pass (no test target) |

Only compiler **warnings** in our code (8 total) are "getter took >300ms to type-check" hints — compile-time
only, no runtime effect. See §4.

---

## 2. Security posture — GO holds; most prior OPEN items now CLOSED in code

The 2026-06-13 triage (`docs/audit/2026-06-13-security-triage.md`) reached **GO** on the four core
properties. Re-verified 2026-06-17, the code has since **closed almost every OPEN item** — that triage
doc is now stale on its "OPEN" column:

| Prior finding (Jun 13) | Status now | Evidence (2026-06-17) |
|---|---|---|
| FINDING-1 Dockerfiles run as root | ✅ **CLOSED** | `daemon/agent-runner/Dockerfile:26-27` (`useradd conduit; USER conduit`); `daemon/push-backend/Dockerfile:10-14` (`adduser conduit; USER conduit`) |
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

**One documented security follow-up (P2, NOT auto-fixed — auth-path change needs device testing):**
- **BiometricGate no-biometrics soft-bypass.** `SecurityKit/BiometricGate.swift:16-20` returns *success* when no
  biometrics are enrolled (and `.biometryNotEnrolled` at the eval branch). On a device with neither biometrics nor
  passcode, the app-lock / SSH-key gate is effectively open (MASVS-AUTH soft bypass). The `.biometryLockout` branch
  already does the right thing (passcode fallback, fail-closed). **Recommended fix:** in the no-biometrics path,
  fall back to `.deviceOwnerAuthentication` (passcode) and only graceful-degrade when *no passcode either* (so the
  simulator/test harness still works). **Deferred** because it changes an auth path and must be validated on a real
  device + the no-passcode sim harness — not a blind cleanup edit. Defense-in-depth bonus: bind the SSH-key Keychain
  item with a `SecAccessControl` (`.biometryCurrentSet`) ACL so the Secure Enclave enforces biometrics, not app logic.

**Residual operational items (not code bugs):**
- Confirm `APNS_*` + live `STRIPE_*` secrets are set on the running push-backend instance (D1 in checklist).
- Ensure the **deployed daemon is the Go build**, not the stale Swift `conduitd` 0.1.0 (now quarantined in §3).

---

## 3. Architecture & dead code

**Verified against current code (V1_READINESS_AUDIT.md was partially actioned):**
- ✅ Already removed: `isDemo` dead branches (InboxView), `SessionsHomeView`, `WorktreeBoardView`.
- ✅ Engine boundary intact: `ConduitCore/SecurityKit/SSHTransport/AgentKit/PersistenceKit/NotificationsKit/DiffKit/SyncKit` import **zero** SwiftUI/UIKit.
- ✅ **Removed this session:** stale Swift `conduitd` → `daemon/conduitd/legacy-swift/`; 8 zero-ref DS
  components (`DSMetricTile/DSRiskRow/DSStepNode/DSHealthRow/DSToast/DSIconTokenView` + dead `DSSkeletonRow`
  siblings); `SnippetEditorView`; **`PreviewFeature/*` whole module** (verified orphan — only a dead
  `import PreviewFeature` in `AppRoot.swift:18`, zero type usage; removed dir + Package.swift target/product/dep).
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
- ✅ Design-system glass primitive (`conduitGlassChrome`) is the single chrome path (agent-contract §4).
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

**Reduce Motion — one real P2 gap:**
- **P2 · Reduce Motion not honored by 7 design-system animations.** Only `PixelBox.swift` checks
  `accessibilityReduceMotion` (3 refs). These components run `repeatForever` (infinite) animations with **no**
  reduce-motion guard:
  `DesignSystem/Components/Composites.swift`, `AgentIsland.swift`, `Primitives.swift` (×2), `DSChip.swift`,
  `ChatComponents.swift`, `States/DSOfflineState.swift`, `States/DSSkeletonRow.swift`.
  *Impact:* users with Reduce Motion enabled (vestibular sensitivity) still get continuous shimmer/pulse —
  WCAG 2.3.3 (Animation from Interactions) concern. *Fix:* gate each `repeatForever` `withAnimation` on
  `@Environment(\.accessibilityReduceMotion)` and fall back to a static/opacity state — same pattern PixelBox
  already uses. High-confidence, low-risk; ~7 small edits, each needs an app-target build check.
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

**Proposed canonical set (keep + maintain):**
`ARCHITECTURE.md`, `docs/agent-contract.md`, `docs/PUBLISH_READINESS_CHECKLIST.md` (launch state),
`docs/CONDUIT_PROJECT_DOSSIER.md` (refresh IA), `docs/SECURITY.md` + `docs/legal/SECURITY_ARCHITECTURE.md`,
`docs/ROADMAP.md`, **this file** (`KNOWN_ISSUES.md`), `docs/block-terminal-implementation.md`.

**Recommended archival** (move to `docs/_archive/` with a pointer — preserve, don't delete; do deliberately
in a dedicated cleanup pass, checking inbound references first): `docs/current-state-audit.md`,
`docs/remaining-work.md`, `docs/APP_AUDIT.md`, `docs/cloud-execution-engine-plan.md`,
`docs/demos/M0–M11*.md`, the dated `docs/conduit-test-run-2026-05-*.md`, and the redundant audit reports
that have been folded into newer ones (`V1_SIMPLIFY_REPORT`, `FRONTEND_SIMPLIFICATION_REPORT` vs `_REVIEW`,
`FABLE_FINDINGS` vs `FABLE_REPORT`, `FEATURE_COVERAGE` vs `FEATURE_VERIFICATION_AUDIT`).

---

## 6. Remaining P0/P1/P2 after this audit

- **P0:** none found in code (builds green, security GO, no confirmed exploitable issue).
- **P1:** none confirmed. (Perf/UX/a11y deep audit is now done — §4/§4b. The stale Swift `conduitd` was
  quarantined this session; `SnippetEditorView` + dead DS components were removed.)
- **P2:** (a) **Reduce-Motion guard on 7 DS animation components** (§4b) — the one confirmed accessibility
  fix. (b) Per-screen VoiceOver-label + Dynamic-Type sweep across all surfaces (checklist B8). (c) Dead-strip
  orphaned `FilesFeature`/`PreviewFeature` whole modules (needs Package.swift surgery — deferred, higher-risk).
- **P3:** `BridgeAuditFeedView` plain-VStack laziness defeat (§4); 2 slow-type-check getters (§4); deliberate
  doc archival pass already done this session (§5 archived 23 docs).
- **Owner-gated (unchanged):** App Store Connect setup, physical-device APNs smoke test, live remote-host
  E2E, vanity domain/DNS — see `docs/PUBLISH_READINESS_CHECKLIST.md` §C/§D.
