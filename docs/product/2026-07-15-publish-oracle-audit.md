# Publish oracle audit — 2026-07-15

**Method:** live code and git first; current canonical docs second; historical reports only as routing evidence  
**Inputs:** `AGENTS.md`, [`STATUS_LEDGER.md`](../STATUS_LEDGER.md), [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md), [`PUBLISH_READINESS_CHECKLIST.md`](../PUBLISH_READINESS_CHECKLIST.md), [`lancer-daily-driver-definition.md`](2026-07-10-lancer-daily-driver-definition.md), current source, git history, and existing test evidence  
**Audited snapshot:** `master` @ `ba73c130` (re-run `git rev-parse HEAD` before acting)

**Publish-ready? No.** Current-tip physical-device Tier 0/5c proof is pending, the 5-of-7 daily-use exit bar is unmet, and external publish operations remain owner-gated.

## Evidence labels

| Label | Meaning |
|---|---|
| **Current verified** | Inspected in current code and supported by a fresh focused command in this audit pass |
| **Code present** | Current implementation inspected; live/device behavior not re-proven here |
| **Historical only** | Prior evidence exists, but not on the audited tip |
| **Pending** | Required proof or owner action has not happened |

## Proof-video status

| Meaning | Status | Evidence |
|---|---|---|
| **5c device recording** | **Pending**, not paused | Current-tip physical-phone proof still requires phone re-pair and the [`LIVE_LOOP_RUNBOOK`](../LIVE_LOOP_RUNBOOK.md) path |
| **Proof Reel in-app playback** | **Code present; current product form excluded from MVP** | `ProofReelModelTests` passed in this audit pass; the [daily-driver definition](2026-07-10-lancer-daily-driver-definition.md) says “NEVER (v0 form)” |
| **Pocket Trace / harness proof video** | **V2 concept only** | [`2026-07-07-harness-feature-borrow-report.md`](2026-07-07-harness-feature-borrow-report.md); no current implementation claim |

## Current feature map

### Current verified or code-present

| Area | Status | Evidence |
|---|---|---|
| Production root | **Current verified** | `AppRoot.readyRoot` routes to `AppFeature/Workspaces/WorkspacesView.swift`; retired `AppFeature/CursorStyle/` and `LANCER_CURSOR_SHELL*` flags have zero current-tree matches |
| Emergency Stop daemon primitive | **Current verified** | `agent.emergencyStop` latch/RPC exists; five focused Go tests passed in this audit pass |
| Proof Reel model | **Current verified** | Current source plus focused Swift tests |
| Flight Recorder timeline | **Current verified** | Current source plus focused Swift tests |
| Attachments and transcript surfaces | **Code present** | Current composer/live-thread attachment upload and rendering paths inspected; no new physical-device claim |
| Artifact card implementations | **Code present** | Current card/detail code exists; real-navigation/live-data reachability still needs the feature-wiring audit |
| Relay generation guard and July 15 reliability changes | **Code present** | Merged git history and current source; see evidence-integrity caveat below before repeating the 10/10 claim |

### Pending proof

| Area | Status | Required oracle |
|---|---|---|
| Governed loop + lock-screen approval | **Historical PASS only** on `732071a7`; current-tip re-proof pending | Physical device 5c |
| Emergency Stop phone behavior | Daemon primitive passes focused tests; owner-reachable UI/policy behavior not proven here | Sim live loop, then physical device/owner sign-off |
| Composer, continuation, and thread hydration | Code has advanced since the old backlog snapshot; current live behavior not classified from docs alone | Sim live loop + targeted UI proof |
| Artifact cards in real navigation | Implementations exist; reachability and live payload coverage need re-check | Feature-wiring audit + sim |
| Archive/signing/App Store operations | Pending and owner-gated | App-target archive + owner operations |

### Outside the dogfood MVP

Away Launch Composer · Question Ladder · Proof Matrix / Device Matrix / Auto Bug Replay · Mobile QA Annotation · loop primitive · deep Siri iOS 27 layer · hosted-cloud UI · full PTY as the primary experience · Watch · biometric gates · Proof Reel in its v0 form.

## Evidence-integrity corrections

1. `PUBLISH_READINESS_CHECKLIST.md` still contains a stale B10 instruction for `LANCER_CURSOR_SHELL_LIVE=1`; that shell and flag were removed before this audit snapshot. Re-proof the governed loop through the current Workspaces UI.
2. `STATUS_LEDGER.md` cites `docs/test-runs/2026-07-15-reconnect-10x-sim/README.md`, but that file is absent from the audited checkout and `HEAD`. Treat 10/10 as an unindexed claim until its durable evidence is restored or regenerated.
3. [`dogfood-log.md`](../dogfood-log.md) already has July 13–14 entries. Dogfooding has **started**, but the recorded 5-of-7 full-loop exit bar is not met.
4. Feature labels from `FEATURE_BACKLOG.md` and the publish checklist conflict with newer code in several places. Use them as queues, not proof; inspect current navigation and bound data before reclassifying.

## Remaining gates

| Gate | Status |
|---|---|
| Phone re-pair | **Owner action required** before device work |
| Tier 0 / 5c on current tip | **Pending** |
| Emergency Stop owner/device behavior | **Pending validation**; daemon primitive is implemented |
| Five successful physical-phone days out of seven | **Started, exit bar unmet** |
| Remote-host E2E | **Owner-gated** |
| Production burn list: lancerd distribution, VPS, CloudKit Production | **Owner-gated** |
| App-target archive, App Store metadata, StoreKit sandbox proof | **Pending/owner-gated** |

## Real bug-fix oracle pilot — not yet executed

The pilot is the actual “are our tools complete?” test. Do not substitute a unit test or another inventory.

1. Confirm the owner phone is safely re-paired and the isolated Simurgh run cannot overwrite owner state.
2. Acquire a Simurgh lease through MCP; never select a raw simulator UDID.
3. Choose one small, real, reproducible, non-security bug from current behavior. Avoid using pairing or Emergency Stop as the first pilot because they are high-risk cross-system paths.
4. Reproduce it, then drive the fix through Lancer against live `lancerd`.
5. Capture before/after behavior, exact build/test output, and `audit.log` evidence under `docs/test-runs/<date>-<slug>/`.
6. Apply the `agent-oracle-harness` risk tier: one contextual independent review for ordinary behavioral work; two reviews plus owner sign-off for high-risk work.
7. Independently re-run the matching oracle, release the lease, and record every missing tool or skill.

### Pilot scorecard

| Step | Result | Notes |
|---|---|---|
| Safe owner-state boundary confirmed | Not run | Phone re-pair is owner-gated |
| Simurgh lease acquired | Not run | Simurgh MCP is not available in the current Codex session |
| Real bug reproduced | Not run | Select only after the live environment is safe |
| Fix driven through Lancer | Not run | |
| Before/after + audit evidence captured | Not run | |
| Risk-tiered independent review | Not run | |
| Oracle re-run and lease released | Not run | |
| Missing tools/skills recorded | Pending | Simurgh MCP availability is already one blocker |

## Regeneration rule

Regenerate this audit from the current commit, live navigation/bound data, canonical status documents, and evidence files that actually exist. Never promote a generated report, old session, or missing evidence link into current truth.
