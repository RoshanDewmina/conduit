# 2026-07-19 feature-sweep rollup

**Synthesized:** 2026-07-19 ~18:40 local (UTC-4)  
**Baseline tip:** `origin/master` @ `7c4b1eca` (+ lane branches cherry-pick #187 for L5 as noted on #192)  
**Inventory sources:** fan-out worktrees `sim-l1-core`…`sim-l8-accounts`; serial re-run [PR #192](https://github.com/RoshanDewmina/conduit/pull/192) (`sim/serial-lanes-2026-07-19`); L1 reply fix [PR #193](https://github.com/RoshanDewmina/conduit/pull/193); L5 writer fix [PR #194](https://github.com/RoshanDewmina/conduit/pull/194); vendor smoke [PR #191](https://github.com/RoshanDewmina/conduit/pull/191); open PRs **#185–#194**  
**Prod pairing:** **intact** (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26 throughout serial + L1 fix runs)

Status legend: **PASS** = lane bar met with committed evidence · **PARTIAL** = some gate evidence, sim/live incomplete · **FAIL** = attempted and failed · **MISSING** = no report / agent never finished · **NEEDS-FABLE** = implementation verified locally; sensitive-path review before merge.

---

## Summary table

| Track | Status | Evidence / pointer | Notes |
|---|---|---|---|
| **Plan matrix** | **PASS** | [PR #188](https://github.com/RoshanDewmina/conduit/pull/188) · `docs/test-runs/2026-07-19-plan-feature-matrix/` | Docs-only audit; G1 passed; G2/B1 device evidence still open |
| **L1 Core loop** | **PASS** | [PR #193](https://github.com/RoshanDewmina/conduit/pull/193) · [`L1/REPORT.md`](L1/REPORT.md) | Isolated relay pair + dispatch + **PONG** reply; push-backend 401 env-only (does not block local relay) |
| **L2 Chat** | **PARTIAL** | `L2/disk-budget.txt` | Disk-budget hygiene FAIL (worktree sprawl); no focused chat sim/UITest evidence |
| **L3 Chrome** | **MISSING** | `L3/STATUS.md` · empty screenshots | Parked; no lane REPORT |
| **L4 Governance** | **PASS** | [PR #192](https://github.com/RoshanDewmina/conduit/pull/192) · [`L4/REPORT.md`](L4/REPORT.md) | Go E2E + Swift governance filters + `SweepLaneC4Tests` **TEST SUCCEEDED** |
| **L5 Widgets / LA** | **PASS** | [PR #194](https://github.com/RoshanDewmina/conduit/pull/194) · [`L5/REPORT.md`](L5/REPORT.md) | Stale TTL + Agents/LA writers PASS; arrive/resolve was **test fixture TTL bug** (fixed); HS widget chrome skipped on sim |
| **L6 Siri** | **PASS** | [PR #192](https://github.com/RoshanDewmina/conduit/pull/192) · [`L6/REPORT.md`](L6/REPORT.md) | `xcodegen` before build; IntentsKit tests; AppShortcuts discovered |
| **L7 Review** | **MISSING** | `L7/STATUS.md` | Parked; no lane REPORT |
| **L8 Accounts** | **FAIL** | `L8/swift-test.excerpt.txt` | `PermissionModeSetResult` compile failure; not re-run on tip |
| **Vendor free-model smoke** | **PASS** | [PR #191](https://github.com/RoshanDewmina/conduit/pull/191) · `docs/test-runs/2026-07-19-vendor-free-model-smoke/` | Codex + OpenCode free-model smoke PASS (isolated state) |
| **Cursor CLI adapter** | **NEEDS-FABLE** | [PR #190](https://github.com/RoshanDewmina/conduit/pull/190) | `go test` + focused Swift 22/22 PASS locally; **Sonnet/Fable full-diff ack** on `dispatch.go` before merge |

### Open PRs (related)

| PR | Title | Role vs sweep |
|---|---|---|
| [#185](https://github.com/RoshanDewmina/conduit/pull/185) | fix(ios): clear stale Home Screen approvals widget count | Widget product fix — device confirm still owed |
| [#186](https://github.com/RoshanDewmina/conduit/pull/186) | test(ios): Siri Shortcuts phrase dogfood harness + report | Siri harness; complements L6 |
| [#187](https://github.com/RoshanDewmina/conduit/pull/187) | fix(ios): Siri sim dogfood + Agents widget dedupe/aesthetics | L5/L6 code overlap; merged into serial L5 stack |
| [#188](https://github.com/RoshanDewmina/conduit/pull/188) | docs: 2026-07-19 plan/feature matrix audit | Plan inventory |
| [#189](https://github.com/RoshanDewmina/conduit/pull/189) | docs: 2026-07-19 feature-sweep rollup | **This rollup** |
| [#190](https://github.com/RoshanDewmina/conduit/pull/190) | feat(daemon): Cursor Agent CLI as dispatchable vendor | **NEEDS-FABLE** sensitive-path review |
| [#191](https://github.com/RoshanDewmina/conduit/pull/191) | docs: vendor free-model smoke (Codex + OpenCode PASS) | Vendor smoke evidence |
| [#192](https://github.com/RoshanDewmina/conduit/pull/192) | docs: serial Simurgh re-run L4/L6/L1/L5 (one lease) | Serial lane reports L4/L6 + initial L1/L5 |
| [#193](https://github.com/RoshanDewmina/conduit/pull/193) | fix(sim): unblock L1 core-loop reply path | **L1 PASS** — notification skip + connect race fixes |
| [#194](https://github.com/RoshanDewmina/conduit/pull/194) | fix(ios): L5 PendingApprovals writer arrive/resolve (TTL fixtures) | **L5 PASS** — test fixture wall-clock TTL |

---

## Serial re-run arc (for traceability)

| Track | Fan-out (#189) | After serial (#192) | Current |
|---|---|---|---|
| L4 | PARTIAL | **PASS** | **PASS** |
| L6 | FAIL | **PASS** | **PASS** |
| L1 | MISSING → PARTIAL | PARTIAL | **PASS** (#193) |
| L5 | MISSING → PARTIAL | PARTIAL (PendingApprovals writer) | **PASS** (#194) |

Method: one Simurgh lease (`lease-242`); isolated `LANCER_STATE_DIR`; L6 required `xcodegen generate`; L5 stacked #187 widget commits; L1 fix branch `lease-244` with harness order `pair` → `daemon` → launch + `LANCER_SKIP_NOTIFICATION_PROMPT`.

---

## Per-lane detail (unchanged / open lanes)

### L2 — Chat — PARTIAL
- Disk budget script FAIL is process hygiene, not product regression.
- **Next:** focused chat UITests under Simurgh; do not block sweep on budget alone.

### L3 — Chrome — MISSING
- **Next:** reset worktree to tip; `LANCER_DESTINATION` deep-link UITests.

### L7 — Review — MISSING
- **Next:** `LANCER_DESTINATION=review` UITest + Edit-tool sheet status.

### L8 — Accounts — FAIL
- Build error on `PermissionModeSetResult` in `DaemonChannel.swift`.
- **Next:** compile fix on tip, then re-run filtered `swift test` under Simurgh.

---

## Vendor free-model smoke — PASS ([#191](https://github.com/RoshanDewmina/conduit/pull/191))

Codex and OpenCode free-model classification smoke completed under isolated state; per-vendor logs under `docs/test-runs/2026-07-19-vendor-free-model-smoke/`. Cursor live smoke remains gated on #190 merge + review.

---

## Cursor CLI adapter — NEEDS-FABLE ([#190](https://github.com/RoshanDewmina/conduit/pull/190))

| Gate | Result |
|---|---|
| `cd daemon/lancerd && go test ./... -count=1` | **PASS** |
| `swift test --filter 'AgentRegistryTests\|DispatchVendorSelectionTests\|RunningAgentsMappingTests'` | **PASS** 22 tests |
| Merge gate | **Fable/Sonnet full-diff ack** (`dispatch.go`, doctor, stream-json) |

---

## B1 device evidence (still P0 — owner-gated)

Unchanged by sim lanes — lock-screen approve, follow-up/receipt, Emergency Stop on device, dogfood discipline. Sim **cannot** substitute.

---

## Ranked next actions

1. **Owner B1 device re-proof (P0)** — checklist rows in `docs/test-runs/2026-07-19-b1-tier0-reproof/`.  
2. **Cursor #190 — Fable/Sonnet ack** then isolated Cursor model smoke.  
3. **Parked lanes** — L3/L7 MISSING; L8 compile fix + retest; L2 chat UITests; optional owner push-backend secrets for APNs/LA push proof (not core reply).

---

## Worktree inventory (relevant)

| Path | Branch | Role |
|---|---|---|
| `.worktrees/sim-serial-lanes` | `sim/serial-lanes-2026-07-19` | PR #192 evidence |
| `.worktrees/widget-stale-approvals` | `fix/l1-reply-path` / `fix/l5-pending-approvals-writer-test` | PR #193 / #194 |
| `.worktrees/cursor-cli-adapter` | `feat/cursor-cli-adapter` | PR #190 |
| `.worktrees/feature-sweep-rollup-2026-07-19` | `docs/2026-07-19-feature-sweep-rollup` | **this rollup** (#189) |
