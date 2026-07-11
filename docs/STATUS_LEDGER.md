# Lancer status ledger

**Last updated:** 2026-07-10  
**Active branch:** `feat/in-thread-questions` @ `0cf5f1e0` (M1–M3 complete; landing on `master`) — open this file first for current priority, canonical doc map, and branch status.  
**`master` tip:** `77488c11` until this branch merges — re-check `git rev-parse HEAD` / `gh pr list` before citing.

> **Superseded 2026-07-10:** the Wave 0 chat-overhaul work (`feat/chat-overhaul-w0a`) and the old
> `AppFeature/CursorStyle/` live-bridge shell it depended on were replaced by a **scorched-earth
> frontend wipe + rebuild** (`80407933` onward) — `CursorStyle`/`DesignSystem` no longer exist in the
> tree. Do **not** resurrect Wave 0 or cite `CursorStyle` as current; `AGENT_READ_FIRST.md`'s mention
> of it is stale pending its own refresh. The rebuild (Cursor-visual Workspaces-root shell, M2 pairing,
> M3 live send/poll, M4 in-thread approve/deny) landed directly on `master` through `77488c11` and is
> the current source of truth — see `docs/plans/2026-07-10-frontend-rebuild-Plan.md` +
> `docs/plans/2026-07-10-frontend-rebuild-Status.md`.
>
> **Sidebar/Command Home IA refs scrubbed from active docs 2026-07-08** (A2 audit, PR #53); historical
> evidence files may still mention the old shell. Cross-check any "Fixed"/"Shipped"/"PASS" claim here
> against `git log` / `gh pr list`.

Living trackers (update these when code or tests change):

- Implementation status → [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md)
- Feature scope decisions → [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md)
- Full feature list with wireframe links → [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md)
- Agent read order → [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md)
- Chat UI port map (competitor borrow) → [`docs/product/2026-07-09-chat-ui-port-map.md`](product/2026-07-09-chat-ui-port-map.md)
- Cross-device continuity study → [`docs/product/2026-07-09-cross-device-continuity-study.md`](product/2026-07-09-cross-device-continuity-study.md)
- Feature × competitor matrix → [`docs/product/2026-07-09-feature-improvement-matrix.md`](product/2026-07-09-feature-improvement-matrix.md)
- Production / TestFlight burn list → [`docs/product/2026-07-09-production-readiness-gaps.md`](product/2026-07-09-production-readiness-gaps.md)

---

## Current priority (engineering)

**Frontend scorched wipe + rebuild + sim dogfood (2026-07-10):** the iOS UI was rebuilt from scratch as
a thin Apple-native Cursor-visual shell (Workspaces-root IA, no tab bar, no `DesignSystem` module) on
top of surviving engines (`SessionFeature` / relay / GRDB). All of the following landed **directly on
`master`** through `77488c11` (not a long-lived side branch):

| Stage | Status | Evidence |
|-------|--------|----------|
| Scorched wipe (`80407933`) | **Landed** | deleted `CursorStyle`, `DesignSystem`, old chat UI |
| Visual rebuild Sections 1–7 (Workspaces, Profile, Composer, RepoPicker/AddRepo, ThreadList/Search, Context, ThreadDetail/PR) | **Landed** (`2c44728d`) | `build_sim` green each section |
| M2 — Settings pairing + trusted machines | **Landed** (`97071246`) | real relay pairing/list/remove |
| M3 — live thread send + poll-until-reply | **Landed** (`be2e1650`) | real `ShellLiveBridge` → `ConversationSyncCoordinator` |
| M4 — in-thread Approve/Deny | **Landed** (`d1d5f218`) | real `RelayApprovalIngest` → `ApprovalRelay` |
| Sim/Device-Hub dogfood D0–D8 | **ALL PASS** (`77488c11`) | [`docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md`](test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md) — pair, send/reply, approval card, approve/deny (audit-logged), remove-machine, all proven live against a real local `lancerd` + relay, Simulator only |

Full detail: [`docs/plans/2026-07-10-frontend-rebuild-Plan.md`](plans/2026-07-10-frontend-rebuild-Plan.md) +
[`docs/plans/2026-07-10-frontend-rebuild-Status.md`](plans/2026-07-10-frontend-rebuild-Status.md).

**In-thread Question cards (2026-07-10) — M1–M3 DONE on `feat/in-thread-questions` @ `0cf5f1e0`:**

| Stage | Status | Evidence |
|-------|--------|----------|
| M1 — `RelayQuestionIngest` + in-thread card on `LiveThreadView` | **Done** (`898e24fc`) | real `agentQuestion` → card |
| M2 — unlock AskUserQuestion (`--permission-prompt-tool stdio`) + relay wire fix | **Done** (`30a28e26`) | pending → answered audited |
| M3 — same-turn stdio `control_request`/`control_response` responder | **Done** (`0cf5f1e0`) | [`docs/test-runs/2026-07-10-in-thread-questions-dogfood/M3.md`](test-runs/2026-07-10-in-thread-questions-dogfood/M3.md) — assistant reply **"You chose Red."** |

Plan/Status: [`docs/plans/2026-07-10-in-thread-questions-Plan.md`](plans/2026-07-10-in-thread-questions-Plan.md) +
[`docs/plans/2026-07-10-in-thread-questions-Status.md`](plans/2026-07-10-in-thread-questions-Status.md).
Owner-gated leftovers only: other-vendor responders, card polish, physical device.

**Physical-device work is explicitly DEFERRED by owner** — do not ask for phone time; prove features on
Simulator + a real local `lancerd`/relay instead (the sim-dogfood pattern above). Deferred items, no
urgency:

- Physical-phone re-proof of the rebuild (pair → send → approve/deny by real finger-tap, not code review)
- APNs push while the app is closed/backgrounded (Simulator cannot receive production push at all)
- Dynamic Island / Live Activity for the relay-dispatch approval card

**Ranked next (confirm with owner before starting):**

1. Clear the 2 pre-existing stale "Relay host" dead pairings surfaced during dogfood (cosmetic, not urgent).
2. Production P0s from burn list — GCS `lancerd` publish, VPS C1, CloudKit Production schema (D2) — owner-gated.
3. Away Launch Composer remains deferred until owner asks.
4. Question-card polish / Codex·Kimi·OpenCode same-turn — only if owner asks.

**Tier 0 exit bar** (historical — superseded by the rebuild's own D0–D8 sim-dogfood proof above, kept for context):

> pair → dispatch prompt → receive approval → approve/deny → follow-up/continue

This bar was previously tracked against the old `CursorStyle` shell (Codex `019f3763`, 2026-07-06) and
its physical-device re-proof was left PENDING as of the last ledger refresh. That shell no longer
exists — the bar is now satisfied by the rebuild's Simulator-only D0–D8 pass above. Physical-device
re-proof of the **new** shell is deferred per owner instruction (2026-07-10), not pending as a gap.

**Unfrozen / merged (2026-07-07–08):** proof receipts + home attention (Layers 0–3, #34); approve-and-remember (#47); deep-link auth/billing paths (#48); Siri entity intents D2/D3 (#46), I1 (#38), I2 (#41), I3 (#43), E3 voice-answer (#45); question/Ladder pipeline E1 (#49) + QuestionCardView E2 (#44); gated git/PR ship actions G (#50); Proof Reel H1 (#51); 5c lock-screen delivery fix (#52); A2 dead-code cleanup (#55); settings feedback rows (#56); A3 design tokens (#57); observed sessions J1–J2 (#54, #58); Return-to-Desk J3 (#59); push `/secret-request` + `/question` routes (#62); append-retry offline fix (#19); daemon/conn test deflake (#60, #61).

**Do not wholesale-merge** `.claude/worktrees/amazing-mayer-246fef` — deletion-heavy diff; cherry-pick verified slices only. See [`docs/design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md`](design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md).

---

## Layer 4 exit bar (B-EXIT, 2026-07-08 evening)

Automated verification on `732071a7`:

| Bar item | Result | Evidence |
|----------|--------|----------|
| `go test ./...` (daemon) | **PASS** | `ok lancer/lancerd 44.197s`; `ok lancer/lancerd/policy 0.227s` |
| `swift test` (LancerKit) | **PASS** | 13 tests in 2 suites, 0 failures |
| App-target build (iOS sim) | **PASS** | XcodeBuildMCP `build_sim` on iPhone 17 Pro / iOS 27 (18.8s) |
| `relay-approval-e2e.sh` (approval + receipt) | **PASS** | xcodebuild rc=0, hook rc=0, receipt probe rc=0 (2026-07-08 23:52 UTC) |
| `relay-approval-e2e.sh` question round-trip | **OPEN** | Script has receipt probe only; no question assertion |
| Exhaustive UI tests post-A3 | **Not re-run** | Last PASS 2026-07-06 (`user-ready-tier0-2026-07-06/`) — fresh screenshot pass needed |
| Dual iOS 26 + iOS 27 build | **Blocked** | Only iOS 27.0 runtime installed on this Mac |
| Owner device question-loop proof | **OPEN** | No `docs/test-runs/` record yet |

---

From Codex `019f2dec` (2026-07-04), confirmed unrun by `019f2f6d`:

| Gate | Target | Deadline | Local evidence |
|------|--------|----------|----------------|
| Away Mode pricing validation | 10 contacted / 5 repeat-use / 3 paying / 1 team | **2026-07-21** | None found in repo |
| Design-partner interviews | Per [`docs/validation-cycle-v1.md`](validation-cycle-v1.md) | — | Plan only, not completed |

**Pricing target (unreconciled):** $25/mo solo · $99/mo team vs dormant StoreKit IAP + live Stripe cloud entitlement.

---

## Canonical doc map

> **Doc purge (2026-07-06):** pre–Jul-5 planning artifacts (V1_* specs, `LAUNCH_AUDIT`, July-4 strategy batch, `superpowers/`, competitive-intelligence, wwdc26 audit, design-redo, design-questions, older `test-runs/`) were removed from the repo. Scope and evidence live in the table below — do not recreate deleted paths.

| Question | Read this | Not this |
|----------|-----------|----------|
| What is Lancer / V1 scope? | [`ARCHITECTURE.md`](../ARCHITECTURE.md) §0.1 + §4.1 | Purged V1_* specs, July-4 strategy batch, legacy sidebar screenshots |
| Feature scope + rationale | [`docs/product/2026-07-05-lancer-feature-master-plan.md`](product/2026-07-05-lancer-feature-master-plan.md) | Purged July-4 strategy docs (master plan §1 is the disposition record) |
| Shipped vs mocked vs gap | [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](product/2026-07-06-feature-implementation-gap-matrix.md) | Stale "mock only" comments in code |
| Sortable feature backlog | [`docs/product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md) | Re-deriving from chat transcripts |
| Implementation dispatch (lanes + worktrees) | [`docs/product/2026-07-06-implementation-dispatch-plan.md`](product/2026-07-06-implementation-dispatch-plan.md) | Ad-hoc agent prompts |
| Owner relay test session | [`docs/product/OWNER_RELAY_TEST_GUIDE.md`](product/OWNER_RELAY_TEST_GUIDE.md) | Re-reading full runbook each time |
| Wireframes / UI design | [`docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md`](design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md) | Superseded intermediate wireframe bundles (removed) |
| Screenshot evidence (Tier 0) | [`docs/test-runs/user-ready-tier0-2026-07-06/`](test-runs/user-ready-tier0-2026-07-06/), [`docs/test-runs/composer-verify-2026-07-06/`](test-runs/composer-verify-2026-07-06/) | — |
| Device proof (D0.2 / 5c) | [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md) (**PASS**), morning FAIL [`test-runs/2026-07-08-tier0-device-proof-results.md`](test-runs/2026-07-08-tier0-device-proof-results.md), [`test-runs/2026-07-08-5c-root-cause.md`](test-runs/2026-07-08-5c-root-cause.md) | — |
| 105-item wireframe checklist | [`docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md`](design-audit/2026-07-05-feature-checklist-for-wireframing.md) | — |
| Away workflow spec | [`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`](product/2026-07-04-v1-paid-away-workflow-spec.md) | — |
| Launch / TestFlight gates | [`docs/PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md) | — |
| Agent working rules | [`AGENTS.md`](../AGENTS.md) + [`docs/AGENT_READ_FIRST.md`](AGENT_READ_FIRST.md) | — |
| Session archaeology (Jul 3–6) | [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md) | Re-running full transcript audits |

**Removed 2026-07-06 (declared); stragglers actually deleted 2026-07-08 (A2 audit):** V1_* specs, `LAUNCH_AUDIT`, July-4 product strategy batch, `superpowers/`, competitive-intelligence, wwdc26 audit, design-redo, design-questions, old sidebar handoffs, `workflows/01-06`, `screenshots/current`, `lancer-ui-prototype/`, pre–Jul-6 `test-runs/`. Scope lives in master plan + `FEATURE_BACKLOG.md`.

---

## Design & wireframe index

**Primary bundle:** [`docs/design-audit/lancer-workflows-2026-07-05/`](design-audit/lancer-workflows-2026-07-05/)

| Artifact | Path |
|----------|------|
| Master report | `MASTER-REPORT.md` |
| Onboarding | `artifacts/01-onboarding.html` |
| Home / Away Digest | `artifacts/02-home.html` |
| Workspaces | `artifacts/03-workspaces.html` |
| Launch setup / contract | `artifacts/04-launch-setup.html` |
| Work Thread / Proof | `artifacts/05-work-thread.html` |
| Review & Diff | `artifacts/06-review-diff.html` |
| Fast follows | `artifacts/07-fast-follows.html` |
| Ship & History | `artifacts/08-ship-history.html` |
| Platform gaps | `artifacts/09-platform-gaps.html` |
| Settings | `artifacts/10-settings.html` |
| Combined + interactive | `artifacts/11-combined-all-workflows.html`, `12-interactive-prototype.html` |

**A3 Cursor design reference (2026-07-08):** committed `c461d56b` — screen-map + light/dark screenshots for token baseline (#57).

**Screenshot evidence (2026-07-06):**

- [`docs/test-runs/user-ready-tier0-2026-07-06/`](test-runs/user-ready-tier0-2026-07-06/) — 21/21 `CursorAppShellExhaustiveTests` attachments
- [`docs/test-runs/composer-verify-2026-07-06/`](test-runs/composer-verify-2026-07-06/) — live + mock composer/work-thread captures

---

## Branch / merge status

| Item | State |
|------|-------|
| `master` (`77488c11`) | Current tip. Includes everything below plus the 2026-07-10 scorched wipe + Cursor Workspaces-root rebuild (M2–M4) + sim dogfood D0–D8 PASS (see Current priority above). iOS **26.0** deployment target. The old live-Cursor-shell / `CursorStyle` referenced in the rows below was deleted by the wipe — historical only. |
| Layers 0–3 integration | **Merged** — PR #34 (`2e33b434`…`c626e29a` stack): proof receipts, home attention, Siri D1 entities, relay delivery fixes |
| Tier 0 wave (#27–#32) | **Merged** — Cursor shell polish, live approval sync (#32), UITest stabilization |
| Layer 4 lanes | **Merged** — #44–#51 (E1/E2/G/H1), #45 (E3), #46–#48 (D2/D3, A4, deeplink), #52 (5c fix) |
| Layer 5–6 / J lanes | **Merged** — #54–#59 (J1 observed sessions, J2 UI, J3 Return-to-Desk), #55–#57 (A2 cleanup, settings feedback, A3 tokens) |
| Push / reliability (Jul 8) | **Merged** — #19 append retry, #60 daemon deflake, #61 conn-state deflake, #62 push routes |
| Siri Phase 2 (I1–I3) | **Merged** — #38 (StartAgentRun), #41 (CoreSpotlight), #43 (iOS 27 App Intents); iOS 27 APIs gated `swift(>=6.4)` |
| A3 surface rebuild (R1–R4) | **Merged** — #63 (Workspaces), #64 (Composer), #65 (Thread/PR/diff), #66 (Lancer surfaces + Review) |
| `codex/tier-0-live-cursor-shell` | Superseded by #28–#34 merges; branch may still exist — treat `master` as source of truth |
| `claude/amazing-mayer-246fef` | Active worktree — **do not wholesale merge** |
| Jul 4–5 design-audit bundle | On disk; A3 reference screenshots committed `c461d56b`; remainder may still be untracked |

---

## Open P0 / P1 (correctness)

From master plan §7 + gap matrix + Codex `019f2f6d`:

| Gap | Severity | Status |
|-----|----------|--------|
| BiometricGate fail-open (no passcode) | P0 | **Moot — removed entirely** on `master` 2026-07-07; nothing left to validate |
| Emergency stop non-atomic | P0 | **Fixed** — daemon latch + RPC (tier-0 branch, merged via #28/#34) |
| Tier 0 D0.2 / 5c physical-device gate | P0 | **Historical PASS** 2026-07-08 evening on `732071a7` (pre-wipe shell) — [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md); Simulator-only equivalent re-proven post-wipe 2026-07-10 (D0–D8, see Current priority); **physical-device re-proof of the new shell DEFERRED by owner** (2026-07-10), not pending as a gap |
| JWT HS256-only | P1 | Open |
| StoreKit IAP dormant vs Stripe cloud entitlement | P1 | Open — billing reconciliation needed |
| Watch app not embedded in iOS target | P1 | **Cut** — owner decision Jul 8; do not schedule |
| Daemon single relay pairing slot | P2 | Open by design |
| Audit chain no external anchor | P1 | Open |

---

## Owner-gated checklist

1. **Tier 0 live loop** on physical iPhone + running `lancerd` — [`docs/LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md) — **Historical PASS** (2026-07-08 evening on `732071a7`, pre-wipe shell); Simulator-only equivalent re-proven post-wipe (D0–D8, 2026-07-10); **physical re-proof DEFERRED by owner**, no rush
2. **APNs lock-screen approve (5c)** — **Historical PASS** (`732071a7`, pre-wipe shell); **DEFERRED by owner** on the new shell — Simulator cannot receive production push at all, needs a real device when the owner has time
3. **Jul 21 validation gate** — run or explicitly descope
4. **Away Launch Composer** — next product lane (wireframes `04-launch-setup.html`), deferred until owner asks

---

## Jul 7–8 session delta (vs Jul 5–6 ledger)

Major merges on `master` since the prior ledger refresh:

- **Layers 0–3** (#34): `lancer.proof/v0` receipt pipeline, needs-you-first home attention, IntentsKit Siri entities (D1), relay approval-delivery fixes
- **Layer 4**: question/Ladder events E1 (#49), QuestionCardView E2 (#44), voice-answer Siri E3 (#45), gated ship actions G (#50), Proof Reel H1 (#51)
- **Layer 0 polish**: approve-and-remember A4 (#47), entity intents D2/D3 (#46), deeplink auth/billing fix (#48)
- **Siri**: I1 Phase 2 resurrect (#38), I2 CoreSpotlight (#41), I3 iOS 27 App Intents (#43)
- **Cleanup + design**: A2 legacy UI/docs delete (#53, #55), A3 design tokens (#57), settings feedback (#56)
- **Observed sessions + continuity**: J1 relay mirror (#54), J2 "On your Mac" UI (#58), J3 Return-to-Desk (#59)
- **5c + reliability**: lock-screen decision delivery fix (#52); push `/secret-request` + `/question` (#62); append retry (#19); test deflake (#60, #61)
- **A3 surface rebuild** R1–R4 merged (#63–#66) Jul 8 evening
- **5c content-hash fix** committed `732071a7` — D0.2 / 5c final PASS
- **Docs**: device-proof results + terminal research (`566dd156`, `7e991c6f`), A3 design reference (`c461d56b`)

Prior Jul 5–6 delta (still accurate): Codex sessions `019f2dec`–`019f3763` chain, wireframe bundle indexed, `ARCHITECTURE.md` §0.1 Cursor shell refresh.

---

## Authoritative Codex session chain

| Session | Role |
|---------|------|
| `019f2dec` | Away Mode with proof; Question Ladder; Clips/`lancer.proof`; pricing + Jul 21 gate |
| `019f2ebf` | Feature-by-feature V1 prune → `v1-paid-away-workflow-spec.md` |
| `019f2f6d` | Independent verification — 21/21 CONFIRMED; validation unrun |
| `019f3763` | Tier 0 engineering pivot; consolidated status; freeze Tier 2 |

Full inventory: [`docs/audits/2026-07-06-conversation-audit.md`](audits/2026-07-06-conversation-audit.md)

---

## SSOT implementation decisions (this pass)

Plan defaults applied (owner approved execution without alternate answers):

- Extend morning Claude audit — promote scratchpad to `docs/audits/`
- Split doc set: this ledger + `AGENT_READ_FIRST` + `FEATURE_BACKLOG`
- Feature scope: Tier 0 tracker + full master-plan inventory
- Write to main `command-center` repo under `docs/`
