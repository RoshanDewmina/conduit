# Beta simulator pass — 2026-07-14

**Final integrated SHA:** `a566425f40a56d0e9671810cd532542923414dd9`
**Original simulator capture SHA:** `c90bed67a16a71bc5af5a521e32c2068a796b134`
**Simulator:** iPhone 17 Pro (`095F8B3A-FEA3-4031-A2A5-561755740730`), iOS **27.0** (`com.apple.CoreSimulator.SimRuntime.iOS-27-0`).
**App build:** `LANCER 1.0.0 (2)` (from Profile footer screenshot).
**Safety:** Did **not** run bare `lancerd pair`, did **not** pair simulator to production Fly relay (`conduit-push.fly.dev`), did **not** reinstall to owner physical phone.
**DerivedData:** `/tmp/lancer-beta-20260714/DerivedData` (outside repo).
**Disk preflight:** `df` 36 GiB free on `/System/Volumes/Data` (≥20 GiB); `scripts/check-disk-budget.sh` exit 1 (worktree sprawl warning only — not a disk blocker).

---

## Executive summary

| Final gate | Result |
|------------|--------|
| LancerKit package build | ✅ PASS |
| Full LancerUITests | ✅ 22 executed, 2 owner-gated skips, 0 failures |
| RelayFleetStoreTests | ✅ 7 tests, 0 failures |
| App-target simulator build | ✅ PASS |
| `git diff --check` / Package.resolved | ✅ clean / unchanged |
| Physical relay + APNs acceptance | ⏸ owner iPhone required |
| Atomic Emergency Stop | ⚠️ open P0 product blocker |
| Functional Policy & Governance Apply | ⚠️ open product gap |

The original simulator pass found stale shell tests and duplicate invalid pairing rows. Those were fixed in `4a6677b7` and `a566425f`; the final automated evidence above supersedes the pre-fix failure counts retained below for diagnosis history.

**Highest honest readiness claim:** simulator and automated engineering gates are green. External beta still requires the minimized owner-iPhone pass below, especially live diff/review, reconnect, dispatch, attachment upload, and app-closed APNs. Atomic Emergency Stop remains a documented P0 unless the owner explicitly grants a release exception.

---

## Phone test session 4 (`docs/plans/phone-test-session4.md`)

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Open Lancer — connected banner, no stuck unreachable | ⏸ PHONE-ONLY | Sim: `Agents` → "Machine unreachable — no successful update yet" (`screenshots/01-workspaces-seeded.png`). No production relay pairing (safety). |
| 2 | Workspaces → search **"fix triple"** → long command-center thread | ⏸ PHONE-ONLY | Search sheet opens (`screenshots/02-search-sheet.png`) but **"No threads yet"** — no live daemon mirror on sim. |
| 3 | Same thread — ~35 turns, scroll responsive | ⏸ PHONE-ONLY | No seeded long thread in sim DB; `threadDetail` seam → empty (`screenshots/07-thread-detail-empty.png`). |
| 4 | Fetch-on-open (~3s) fills transcript | ⏸ PHONE-ONLY | Requires paired live host conversation ledger. |
| 5 | Scroll ↑ → **↓** jump arrow to tail | ⏸ PHONE-ONLY | No long thread to exercise; unit logic exists (`FlightRecorderTimelineTests` pass) but UI not driven. |
| 6 | Proof/receipt chip under assistant turn | ⏸ PHONE-ONLY | No completed run thread on sim. |
| 7 | **⋯** → **Flight Recorder** timeline | ⏸ PHONE-ONLY | No thread with events; assembler tests ✅ (`swift test --filter FlightRecorderTimelineTests` 8/8). |
| 8 | Live status pill (Thinking / Editing…) | ⏸ PHONE-ONLY | Requires live editing run on paired host. |
| 9 | Turn diff card + session pill → review sheet | ⚠️ BLOCKED (sim) | **Fixture layer ✅** `ReviewModelsTests` 14/14 (seeded JSON). **UI sheet not reachable** — `LANCER_DESTINATION=review` seam removed; no live diff without host. |
| 10 | Review line long-press → Attach comment | ⚠️ BLOCKED (sim) | Same as #9; comment queue formatting covered in `ReviewModelsTests`. |
| 11 | Composer **+** → Context → Photo/File → send | ✅ PASS (UI seam) | Context sheet shows Photos / Screenshots / Camera / Files (`screenshots/04-context-attach.png`). **Round-trip dispatch** ⏸ PHONE-ONLY. |
| 12 | Exactly **one** command-center repo row | ⏸ PHONE-ONLY | Sim shows 0 repos (`screenshots/01-workspaces-seeded.png`). **Catalog logic ✅** `WorkspaceRepoCatalogTests` 18/18 incl. dedup fixture. |
| 13 | Agents row → tap Mac session → direct chat | ⏸ PHONE-ONLY | Agents section unreachable on sim (no machine). |
| 14 | Low-risk composer send round-trip | ⏸ PHONE-ONLY | Composer shows "Add a repo first" with 0 repos (`screenshots/05-composer-repo-picker.png`). |

### REL-1 re-test block (post-#110)

| # | Item | Status | Evidence |
|---|------|--------|----------|
| R1 | Force-quit → first send without Retry | ⏸ PHONE-ONLY | Relay pairing + live dispatch; sim not paired to production relay. |
| R2 | First send after airplane-mode reconnect | ⏸ PHONE-ONLY | Same. |
| R3 | Pairing sheet TTL countdown | ⏸ PHONE-ONLY | Pairing sheet not opened (would risk relay slot). UI exists in codebase; not exercised. |
| R4 | Expired code → "Pairing code expired" | ⏸ PHONE-ONLY | Requires live pair flow. |
| R5 | Fresh code re-pair | ⏸ PHONE-ONLY | Owner phone holds slot — **do not pair sim**. |
| R6 | Re-run #1–4 on integrated build | ⏸ PHONE-ONLY | Depends on phone paired state + long thread. |

---

## Publish readiness checklist (simulator-exercisable subset)

### A — Verified GREEN (re-checked this pass)

| Item | Status | Evidence |
|------|--------|----------|
| LancerKit SPM build + tests | ✅ PASS | `cd Packages/LancerKit && swift build` exit 0; `swift test` → **698 tests / 113 suites** pass (`/tmp/lancer-beta-20260714/swift-test.log`). |
| lancerd Go tests | ✅ PASS | `cd daemon/lancerd && go test ./...` exit 0 (46s). |
| App-target simulator build | ✅ PASS | `xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,id=095F8B3A-…' -derivedDataPath /tmp/lancer-beta-20260714/DerivedData build` → **BUILD SUCCEEDED** (86.7s). |

### B — Engineering (simulator lane)

| Item | Status | Evidence |
|------|--------|----------|
| B3 — Green app-target build | ✅ PASS | See build command above. |
| B7 — Feature-wiring audit (navigation reachability) | ❌ FAIL | Profile → Trusted Machines ✅ (`screenshots/06-profile.png`, `03-trusted-machines.png`). **No Policy & Governance / audit / usage surfaces** in Profile or Workspaces shell. `LANCER_DESTINATION=settings` **not implemented** (UITest fail). |
| B8 — Empty/loading/error + a11y sweep | ⚠️ BLOCKED | Empty states ✅ (search, thread detail, PR detail, workspaces). **Dark mode:** no in-app appearance control found in Workspaces shell; `simctl ui appearance` documented no-op. **VoiceOver / Dynamic Type:** not spot-checked this pass. |
| B10 — Tier 0 live Cursor shell E2E | ⏸ PHONE-ONLY | Isolated localhost relay fixture (`scripts/validation/relay-approval-e2e.sh`) still targets **production Fly relay** — **not run** (would pair sim to shared relay). SSH `relay-regression.sh` uses resident `~/.lancer` daemon — **not provably isolated** from owner pairing. |
| B11b — Emergency Stop P0 | ⚠️ BLOCKED | **No Emergency Stop UI** found in `AppFeature` navigation. Daemon primitive exists (`dispatch.go` `emergencyStopped`) but owner-facing control not reachable in sim. |

### C — Tests remaining

| Item | Status | Evidence |
|------|--------|----------|
| C1 — Live E2E remote host | ⏸ PHONE-ONLY | Owner-gated. |
| C2 — Physical APNs app closed | ⏸ PHONE-ONLY | Sim cannot receive real APNs (`LancerApp.swift` delegate comment). |
| C3 — Expand app-target UI suite | ❌ FAIL | 6/9 executed UITests failed — stale selectors/seams (see below). |
| C4 — Reconnect/session-loss tests | ⏸ PHONE-ONLY | iOS-side background/network not exercised. |
| C7 — Two-device CloudKit QA | ⏸ PHONE-ONLY | CloudKit sync no-op on sim by design. |

---

## Dependency-order execution log

### 1) Build / install / launch / basic navigation

| Check | Status | Evidence |
|-------|--------|----------|
| App-target build @ SHA | ✅ PASS | `xcodebuild … build` SUCCEEDED |
| Install + launch Workspaces shell | ✅ PASS | `xcrun simctl install` + `launch` pid 19340+; `screenshots/01-workspaces-seeded.png` |
| Workspaces title + composer chrome | ✅ PASS | "Workspaces", "Plan, ask, build…" visible |
| Profile avatar opens sheet | ✅ PASS | `LANCER_DESTINATION=profile` → Profile sheet (`screenshots/06-profile.png`) |
| Search affordance | ✅ PASS | `LANCER_DESTINATION=search` (`screenshots/02-search-sheet.png`) |

### 2) Workspaces / search / repo / long thread / scroll / receipt / Flight Recorder

| Check | Status | Evidence |
|-------|--------|----------|
| Search UI | ✅ PASS | Sheet + filter chip "All" |
| One repo row (command-center) | ⏸ PHONE-ONLY | 0 repos on sim |
| Long thread render/scroll | ⏸ PHONE-ONLY | No data |
| Down-arrow jump | ⏸ PHONE-ONLY | No long thread |
| Receipt chip | ⏸ PHONE-ONLY | No completed run |
| Flight Recorder menu | ⏸ PHONE-ONLY | No thread with events |

### 3) G2 / P1b diff card, session pill, review, line comment

| Check | Status | Evidence |
|-------|--------|----------|
| **Seeded** fixture decode + data source | ✅ PASS | `swift test --filter ReviewModelsTests` 14/14 |
| **Live** diff card + session pill + review sheet UI | ⏸ PHONE-ONLY | No connected machine / conversation |
| Line-comment-to-composer UI | ⚠️ BLOCKED (sim) | Review sheet not openable without live thread or removed `review` seam |

### 4) Composer / vendor picker / context attachments

| Check | Status | Evidence |
|-------|--------|----------|
| Composer opens (repo picker state) | ✅ PASS | `screenshots/05-composer-repo-picker.png` — Claude Code + Haiku chips |
| Context Photo/File picker seams | ✅ PASS | `screenshots/04-context-attach.png` |
| Attachment chip states (live upload) | ⏸ PHONE-ONLY | No dispatch path on sim |

### 5) Empty / loading / error / light-dark / a11y

| Check | Status | Evidence |
|-------|--------|----------|
| Workspaces empty (0 repos) | ✅ PASS | `screenshots/01-workspaces-seeded.png` |
| Search empty | ✅ PASS | `screenshots/02-search-sheet.png` |
| Thread detail empty | ✅ PASS | `screenshots/07-thread-detail-empty.png` |
| PR detail honest empty | ✅ PASS | `screenshots/08-pr-detail.png` — "Not available yet" |
| Agents unreachable error | ✅ PASS | `screenshots/01-workspaces-seeded.png` |
| Dark mode toggle | ⚠️ BLOCKED | No control found in shell |
| Dynamic Type / VoiceOver | ⚠️ BLOCKED | Not exercised this pass |

### 6) Settings / trusted machines / policy / Emergency Stop

| Check | Status | Evidence |
|-------|--------|----------|
| Trusted Machines reachable | ✅ PASS | Profile → Connections → Trusted Machines; direct seam `LANCER_DESTINATION=trustedMachines` |
| Trusted Machines UI | ❌ FAIL (UX) | 3× "Relay host" + duplicate "Dead pairings" all **"pairing invalid"** (`screenshots/03-trusted-machines.png`) — stale sim keychain ghosts, not production phone |
| Policy & Governance reachability | ❌ FAIL | Not in Profile/Workspaces navigation |
| Emergency Stop UI presence | ⚠️ BLOCKED | Not implemented in app shell (B11b) |

### 7) Automated tests

| Suite | Status | Evidence |
|-------|--------|----------|
| LancerKit `swift test` (full, sequential) | ✅ PASS | 698/698 |
| `go test ./...` (lancerd) | ✅ PASS | ok |
| App-target build (re-verify) | ✅ PASS | Same DerivedData tree |
| `CursorShellLiveApprovalTests` | ❌ FAIL | `testLiveShell_PendingApprovalBannerApprove` — `cursor.review.approve` not found; `LANCER_DESTINATION=review` seam missing. xcresult: `/tmp/lancer-beta-20260714/xcresults-live-approval.xcresult` |
| `LegacyUIRemovalTests` | ❌ FAIL | 4/5 fail: `settings`, `inbox` destinations missing; `App Settings` row missing; `cursor-composer-tap` missing. 1 pass: `testDefaultLaunch_NoLegacyChrome`. xcresult: `/tmp/lancer-beta-20260714/xcresults-legacy.xcresult` |
| `HomeButtonTapTests` | ❌ FAIL | `testProfileDrawerOpensFromAvatar` — expects "Settings" label; Profile sheet shows "Profile" only. `testWorkspacesComposerOpens` ✅. xcresult: `/tmp/lancer-beta-20260714/xcresults-home.xcresult` |
| `CursorAppShellExhaustiveTests` | ⚠️ BLOCKED | Not run — targets removed `LANCER_CURSOR_SHELL=1` mock tab shell; would not reflect production `AppRoot`. |

**Note:** Did not run concurrent Swift test suites (Keychain isolation per `RelayMachineMigrationTests`).

### 8) Isolated localhost live loop

| Check | Status | Evidence |
|-------|--------|----------|
| Relay live loop (R1/R2 / dispatch / APNs) | ⏸ PHONE-ONLY | `relay-approval-e2e.sh` pairs sim to **production** Fly relay (forbidden). `relay-regression.sh` uses shared `~/.lancer` resident daemon (not proven isolated from owner phone slot). **Not attempted.** |

---

## Simulator-visible defects and resolution

| ID | Final status | Resolution |
|----|--------------|------------|
| SIM-1 | ✅ fixed | UITests now target the Workspaces/Profile/in-thread shell; full target 22 executed, 2 owner-gated skips, 0 failures (`4a6677b7`). |
| SIM-2 | ✅ fixed | `.pairingInvalid` machines are excluded from Paired and remain only under Dead pairings; 7 RelayFleetStore tests pass (`a566425f`). |
| SIM-3 | ✅ fixed | Profile → Settings navigation and current selectors are covered by the passing full UI suite (`4a6677b7`). |
| SIM-4 | ⚠️ open by design | Settings shows honest deferred Policy copy; no misleading Emergency Stop ships. Atomic stop and functional policy Apply remain product work. |
| SIM-5 | ⚠️ docs follow-up | Runtime source of truth is the Workspaces-only root. Broader architecture wording should be reconciled separately. |

---

## Screenshot index

All under `docs/test-runs/2026-07-14-beta-simulator-pass/screenshots/`:

| File | Description |
|------|-------------|
| `01-workspaces-seeded.png` | Workspaces root, 0 repos, agents unreachable |
| `02-search-sheet.png` | Search empty state |
| `03-trusted-machines.png` | Stale invalid relay pairings |
| `04-context-attach.png` | Context attach (Plan/Draft, Photos/Files) |
| `05-composer-repo-picker.png` | New chat composer, Claude Code/Haiku, no repo |
| `06-profile.png` | Profile sheet, 0 trusted machines |
| `07-thread-detail-empty.png` | Thread detail empty state |
| `08-pr-detail.png` | PR detail "Not available yet" |

---

## Commands reference

```bash
# Preflight
df -h / /Users/roshansilva/Documents/command-center
./scripts/check-disk-budget.sh

# Verify SHA
git rev-parse HEAD   # c90bed67…

# App build
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' \
  -derivedDataPath /tmp/lancer-beta-20260714/DerivedData build

# Install + launch (example)
xcrun simctl install booted /tmp/lancer-beta-20260714/DerivedData/Build/Products/Debug-iphonesimulator/Lancer.app
env SIMCTL_CHILD_LANCER_DESTINATION=search SIMCTL_CHILD_LANCER_SEED_DEMO=1 \
  xcrun simctl launch booted dev.lancer.mobile -onboardingSeen YES

# SPM + Go
cd Packages/LancerKit && swift build && swift test
cd daemon/lancerd && go test ./...

# UITest (sequential, not parallel)
xcodebuild test -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' \
  -derivedDataPath /tmp/lancer-beta-20260714/DerivedData \
  -only-testing:LancerUITests/<TestClass>
```

---

## Minimized physical-phone checklist (owner only)

Run on **owner iPhone** already paired to production relay — **do not** re-pair sim afterward without re-pairing phone.

- [ ] **Install final SHA** `a566425f`; open Lancer and confirm one connected machine with no reconnect loop.
- [ ] **Conversation ledger:** search `fix triple`, open the long command-center thread, confirm ~35 turns fetch, smooth scrolling, tail-jump arrow, receipt chip, and Flight Recorder.
- [ ] **Live editing/review:** run a harmless file edit; confirm status pill, turn diff card, session pill, review sheet Modified/All Files, visible hunks, and line-comment attachment.
- [ ] **Attachment round-trip:** send one Photo or File through Context and verify it reaches the Mac-side run.
- [ ] **Workspace hygiene:** exactly one command-center row; no duplicate `pairing invalid` machine in Paired.
- [ ] **Agent continuity:** tap the active Mac session and confirm direct chat opens with the correct transcript.
- [ ] **Low-risk dispatch:** send a harmless prompt from the composer and verify completion plus receipt.
- [ ] **Resume/reconnect:** force-quit and verify the first send needs no Retry; then toggle airplane mode, reconnect, and verify the first send again.
- [ ] **App-closed APNs:** force-quit Lancer, trigger an approval, receive the lock-screen notification, Approve or Reject, and verify the host audit/decision.
- [ ] **Basic device UX:** background/foreground once; spot-check Dynamic Type and VoiceOver on Workspaces, Profile/Settings, composer, approval card, and review sheet.

### Release decisions that phone testing cannot close

- [ ] **B11b — Atomic Emergency Stop:** implement the real daemon-backed atomic control or record an explicit owner release exception.
- [ ] **Policy & Governance Apply:** implement a functional host-backed surface or record an explicit beta deferral. Current Settings copy is intentionally non-interactive.

---

*Report updated after integration through `a566425f`. `simurgh/` remains untouched.*
