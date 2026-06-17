# Conduit — Known Issues & Pre-Launch Audit (canonical)

> **Compiled:** 2026-06-17 · branch `opencode/onboarding-redesign` (83 commits ahead of `master`).
> This is the canonical "what's broken / what's verified / what's residual" doc. It supersedes the
> scattered point-in-time audit docs for **issue tracking**. For launch *checklist* state use
> `docs/PUBLISH_READINESS_CHECKLIST.md`; for product/architecture narrative use `ARCHITECTURE.md`
> + `docs/CONDUIT_PROJECT_DOSSIER.md` (note: dossier is from 2026-06-11 and its IA section is stale —
> tabs are now **Inbox / Fleet / Activity / Settings**, session surface is chat-based).
>
> **Method note:** the planned multi-agent deep audit (perf / UX / a11y fan-out) was cut short by an
> account session/rate limit on 2026-06-16. The security + build + architecture findings below were
> verified inline against current source. The perf/UX/a11y lanes should be re-run after the limit
> resets and merged here.

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

**Residual operational items (not code bugs):**
- Confirm `APNS_*` + live `STRIPE_*` secrets are set on the running push-backend instance (D1 in checklist).
- Ensure the **deployed daemon is the Go build**, not the stale Swift `conduitd` 0.1.0 (see §3).

---

## 3. Architecture & dead code

**Verified against current code (V1_READINESS_AUDIT.md was partially actioned):**
- ✅ Already removed: `isDemo` dead branches (InboxView), `SessionsHomeView`, `WorktreeBoardView`.
- ✅ Engine boundary intact: `ConduitCore/SecurityKit/SSHTransport/AgentKit/PersistenceKit/NotificationsKit/DiffKit/SyncKit` import **zero** SwiftUI/UIKit.
- ⚠️ **Still orphaned (zero production routes) — candidates for dead-strip before publish:**
  `FilesFeature/*` (FilesView, SFTPFilesView, FilePreviewView), `PreviewFeature/*` (PreviewSurface/Toolbar/ViewModel),
  `QuotaGuardView`, `SettingsFeature/SnippetEditorView`, plus dead DesignSystem components
  (`DSMetricTile`, `DSRiskRow`, `DSStepNode`, `DSHealthRow`, `DSToast`, `DSSkeletonRow`, `DSIconTokenView`, `DSSpendHero`).
  Re-confirm reachability per-symbol before removing.

**Duplicate / confusing abstractions:**
- `daemon/conduitd/` ships **both** the canonical **Go** module (`go.mod`, policy engine) **and** a stale
  **Swift** package (`Package.swift`, `Sources/conduitd`, v0.1.0, no policy). The Swift one is the
  "stale 0.1.0" called out in the checklist (B4). **Action:** remove the Swift package or move it under
  an explicit `legacy/` path so no one ships it by accident.
- `DiffKit` (engine) vs `DiffFeature` (UI) and `PreviewKit` vs `PreviewFeature` — confirm both layers are
  actually used; PreviewFeature appears orphaned (above).

**Repo hygiene — FIXED this session:**
- `daemon/agent-runner/agent-runner` (Mach-O 8.2 MB) was **tracked in git** and churning in diffs while
  the sibling `push-backend`/`conduitd` binaries were already ignored. Untracked (`git rm --cached`) and
  added to `.gitignore`. File kept on disk; change is unstaged-isolated (not committed).

---

## 4. Performance notes (compile-time hints; runtime perf lane not yet deep-audited)

Slow-to-type-check view getters (>300ms) — break up the expression to speed builds (no runtime cost):
- `SessionFeature/Chat/ChatTranscriptView.swift:90` `transcriptBody` — **481ms** (in the in-flight chat work).
- `SettingsFeature/SnippetEditorView.swift:176` `body` — 303ms (note: SnippetEditorView is orphaned, §3).
- `AppFeature/FleetView.swift:89` `body` — 308ms.

**Not yet audited (rate-limited):** SwiftUI invalidation on large transcripts/lists, terminal/block render
cost, block-store/audit-tail growth caps, async task cancellation on view disappear. Re-run the perf lane.

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
- **P1:** (a) Re-run the throttled perf/UX/a11y deep audit and fold results here. (b) Empty/loading/error +
  a11y sweep across surfaces (checklist B8) — not yet verified per-screen. (c) Remove/quarantine the stale
  Swift `conduitd` package so governance can't ship disabled (checklist B4).
- **P2:** Dead-strip orphaned `FilesFeature`/`PreviewFeature`/`QuotaGuardView`/`SnippetEditorView` + dead
  DS components. Break up the 3 slow-type-check getters. Deliberate doc archival pass (§5).
- **Owner-gated (unchanged):** App Store Connect setup, physical-device APNs smoke test, live remote-host
  E2E, vanity domain/DNS — see `docs/PUBLISH_READINESS_CHECKLIST.md` §C/§D.
