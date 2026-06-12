# FABLE Report — Governed Approvals v1 Pre-Submission Audit

**Date:** 2026-06-12
**Branch:** `feat/governed-approvals` (worktree `governed-approvals-audit`)
**Version:** 1.0.0 (`MARKETING_VERSION`, all 5 targets)
**Verdict:** 🟡 **CONDITIONAL GO** — engineering is submission-ready and build-green; release is gated on owner infrastructure actions and the remaining tap-interaction verification (needs a full Xcode the owner is installing).

---

## Executive go/no-go

The governed-approvals approval path is **engineering-complete**. All four launch blockers (B1–B4) plus the
late-surfacing **live shell-integration blocker** are fixed and the fixes are verified by build, unit
tests, an auth curl-matrix, and — for the shell blocker — a live on-device run. Phase 5 UX polish is done
with a clean app-target build (0 errors / 0 warnings). What stands between here and the App Store is **not
engineering**: it is owner-only infrastructure (backend deploy with the relay secret, physical-device APNs,
App Store Connect record + IAP sandbox, store screenshots) and a final **tap-interaction pass** that this
machine cannot run (no Simulator.app in the installed Xcode-beta → HID injection unavailable).

**Recommendation:** proceed to TestFlight once the owner items below are done; the tap-interaction checks
can be completed in parallel on a full-Xcode box or a physical device (Phase 6 needs a device anyway).

---

## What was verified (evidence-backed)

| Area | Status | Evidence |
|------|--------|----------|
| ConduitKit `swift build` | ✅ green | every Phase-5 chunk |
| ConduitKit `swift test` | ✅ **337 tests / 57 suites pass** | incl. `firstDecisionWins` (M9 exactly-once) |
| App-target `xcodebuild` (5 targets) | ✅ **BUILD SUCCEEDED, 0 err / 0 warn** | `/tmp/ga-*-build.log` |
| push-backend / conduitd Go | ✅ `go vet` + `go test` + `-race` | relay tests below |
| **B1** TOFU first-connect | ✅ fixed; code-verified | sheet inside `SessionView` above the cover; `.disconnected` overlay |
| **B2** relay two-tier auth | ✅ **PASS** | full curl matrix (`relay-curl.txt`): 401-without/200-with secret; per-session token on decision/poll; cross-session token rejected |
| **B3** idempotency (first-decision-wins) | ✅ **PASS** | `WHERE decision IS NULL`; test `firstDecisionWins`; `TestDecisionRelayDedupeByApprovalID` |
| **B4** mic/speech usage strings | ✅ fixed | `project.yml` |
| Relay fallback (no live SSH) | ✅ **PASS** | `TestDecisionPollerResolves` / `TestDecisionPollerSendsBearerToken` |
| **Live shell-integration blocker** | ✅ **fixed + verified LIVE** | single-line eval injection; `live-session-AFTER-oneline-fix.png` (`✓ exit 0`), `live-session-claude-inblock.png` |
| Phase 5 rendering | ✅ verified (read path) | `phase5-inbox-typed-accentfg.png`, `phase5-diff-monofont.png` |
| Gallery dark routes + prod Inbox | ✅ **PASS** | `gallery-*-dark.png`, `prod-inbox-*.png`; **no host-label wrap issue** |

### Phase 5 fixes shipped (commits on `feat/governed-approvals`)
- `680ee7eb` — 14 token-drift fixes; TextPreview NUL-byte binary guard; SnippetEditor tag-loss; iPad `NavigationStack`.
- `ab1e8a04` — honest Face ID opt-in (`appLockEnabled` persists only on real success); dead shipped-UI removed.
- `500c0981` — saved-hosts reconnect list + dedup (upsert by host:port:user; preserves trusted host-key).
- `3698dd55` — **shell-integration single-line eval fix** (the live-approval blocker).
- `23fffec9` — fastlane metadata synced to governed-approvals; PrivacyInfo CrashData/SystemBootTime removed.

---

## Tap-interaction — now UNBLOCKED via XCUITest

The "taps don't inject" wall is **resolved**. The installed Xcode-beta is a stripped 3.5 GB build missing
`Simulator.app` (so no GUI window for cliclick) and `idb` 1.1.8 is incompatible with macOS 27 (objc class
collision) — but **XCUITest** runs headlessly via `xcodebuild test`, needs neither, and its frameworks are
present. A `ConduitUITests` target was added and the suite is now **fully green on this machine**
(`** TEST SUCCEEDED **`, 5/5, 0 failures):
- `testTapInjectionViaTabSwitch` — event injection works (Inbox⇄Settings tab taps toggle the screen).
- `testApproveDecisionApplies` — **APPROVE → pending count drops**: the Phase-4 Check-1 approval
  interaction (previously BLOCKED) is verified, exercising B3 first-decision-wins live in the UI.
- `testApproveDecisionVisualEvidence` — captures a before/after screenshot pair of a live decision.
- `testFaceIDToggleOptIn` — Settings → Security → "Require Face ID on launch" flips OFF→ON (the Phase-5
  honest app-lock opt-in). Surfaced a real XCUITest gotcha: the toggle sits below the scroll fold but
  `isHittable` reports true (frame within window bounds, behind the tab bar), so a naive tap lands
  off-screen — the test scrolls it into the safe viewport first.
- `testSavedHostReconnectPresentsPrompt` — Fleet → "Saved hosts" → tapping a seeded host fires
  `onReconnect → openSession`, which presents the connect prompt (proves the reconnect+dedup wiring
  without needing a live SSH endpoint).

**Determinism:** every test launch sets `CONDUIT_UITEST_RESEED=1`, which (DEBUG-only,
`DebugSeeder.resetForUITestIfRequested`) wipes the approvals table and re-seeds the fixed sample set
(2 pending + 1 decided), seeds the Fleet saved-hosts if the table is empty, and clears the app-lock
opt-in. Without it the seed is consumed by the first APPROVE and persists decided, so re-runs would find
no pending cards. This makes every interaction proof re-runnable. Tests launch straight onto a tab via
`CONDUIT_TAB` (inbox/fleet/activity/settings).

**Visual evidence captured** (`screens/e2e-phase4/`): `verify-inbox-pending-light.png` /
`verify-inbox-pending-dark.png` (PENDING · 2 cards with EDIT&RUN / DENY / ALLOW ALWAYS / APPROVE);
`verify-approve-01-before.png` (PENDING · 2 / DECIDED · 1) → `verify-approve-02-after.png` (PENDING · 1 /
DECIDED · 2 — the HIGH-risk `rm -rf` card moves PENDING → approved after the live tap). The before/after
pair is the governed-approvals decision flow demonstrated end-to-end in the simulator.

**Now covered by XCUITest:** the Face ID app-lock opt-in and the saved-host reconnect (above). **Still
infra-gated, assessed honestly — not faked:**
- **B1 TOFU host-key prompt** — reachable, but needs the live-SSH harness (a reachable host with its key
  cleared from the trust store so TOFU re-fires); not a pure mock. The fix itself is code-verified (sheet
  presented inside `SessionView` above the cover) and now exercised by the same presentation mechanism as
  the MAJOR-5 retry sheet.
- **M6 cold-launch replay** — `ApprovalActionBuffer` is an in-memory buffer (not persisted), so it can't
  be pre-seeded via launch env; an automated test needs a small DEBUG seed hook. The drain → relay →
  first-decision-wins path it feeds is already covered by the Go poller + idempotency tests.

**MAJOR-5 (password re-entry over the live-session cover) — FIXED.** The retry sheet was only wired at the
app root, where it can't present over the session `fullScreenCover` (the B1 family). Added
`SessionPasswordRetrySheet`, presented from inside `SessionView` above the cover, mirroring the TOFU sheet.

**Full three-way live relay loop** (phone POST → running conduitd poll) still needs a running conduitd
stood up alongside; every link is independently proven (curl matrix + Go poller tests).

---

## Owner actions before submission (not agent-doable)

| Item | Why it's owner-only |
|------|---------------------|
| Deploy conduitd + push-backend with `APPROVAL_RELAY_SECRET` set | prod infra + secret; without it Tier-1 is open and Tier-2 tokens don't exist server-side |
| Physical-device APNs validation | real push delivery + notification actions; needs a paid-team device |
| App Store Connect record + IAP sandbox (`dev.conduit.mobile.pro`, $14.99) | account-level; sandbox test |
| Store screenshots (1320×2868, governed-approvals flow) | needs the tap-driven flow captured; current fastlane shots are stale terminal-first |
| Vanity domain for push backend | replace `35.201.3.231.sslip.io` bare-IP host before public |
| `fastlane deliver` upload | uploads the now-synced metadata — owner's call to publish |
| Full-Xcode/device for the tap-interaction pass | this machine's Xcode-beta cannot inject taps |

---

## Risk register (App Review)

- **2.5.2 remote-shell:** Conduit drives a *remote* shell over SSH; it does **not** download/execute code
  locally. App Review notes must state this (drafted in `docs/app-store-metadata.md` §App Review notes).
- **Copy claim "even when the app was closed":** true **only** with the backend decision-relay enabled.
  Keep the relay live, or change the promo/description per the caveat in `app-store-metadata.md`.
- **Privacy label:** PrivacyInfo now declares only DeviceID (APNs) + FileTimestamp (SFTP) + UserDefaults;
  CrashData removed (Sentry DSN empty). The App Store Connect privacy nutrition label must match.
- **support_url:** left as `https://conduit.dev` (doc suggests `/support`) — change only if that path resolves.

---

## Open lower-severity items (deferred, non-blocking)

- **MAJOR-5** password-retry sheet present-over-cover — **FIXED** (`SessionPasswordRetrySheet` presented inside `SessionView` above the cover, mirroring B1's TOFU sheet).
- Security LOW-1/2/3/5 (app-switcher snapshot redaction; biometryLockout; `autoTrustHostKey` DEBUG guard; Redactor PEM/Bearer/JWT) — from the 2026-05-31 security review, pre-existing.
- Core-kits (CloudKit deletion resurrection, SSHHostRuntime cancel/status) — fix only if E2E surfaces them; iCloud UI stays hidden.
- Cosmetic: the `\e[2J\e[H` clear echoes into claude's input box (pre-existing §3.3 dynamic; low severity).

---

*Full detail: `FABLE_FINDINGS.md` (scratchpad), `findings/review-*.md` (8 static reviews), `screens/e2e-phase4/` (E2E + Phase-5 evidence).*
