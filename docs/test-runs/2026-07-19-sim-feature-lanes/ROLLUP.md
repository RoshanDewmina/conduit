# 2026-07-19 feature-sweep rollup

**Synthesized:** 2026-07-19 ~19:10 local (UTC-4)  
**Baseline tip:** `origin/master` @ `7c4b1eca` (+ #193/#194 cherry-picks on remaining-lanes worktree)  
**Inventory sources:** fan-out + serial (#192) + L1 (#193) + L5 (#194) + remaining lanes (`sim/remaining-lanes-2026-07-19`, `lease-247`); vendor (#191); Cursor (#190); open PRs **#185–#195**  
**Prod pairing:** **intact** (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26 throughout)

Status legend: **PASS** = lane bar met with committed evidence · **PARTIAL** = some gate evidence, sim/live incomplete · **FAIL** = attempted and failed · **MISSING** = no report / agent never finished · **NEEDS-FABLE** = implementation verified locally; sensitive-path review before merge.

---

## Summary table

| Track | Status | Evidence / pointer | Notes |
|---|---|---|---|
| **Plan matrix** | **PASS** | [PR #188](https://github.com/RoshanDewmina/conduit/pull/188) · `docs/test-runs/2026-07-19-plan-feature-matrix/` | Docs-only audit; G1 passed; G2/B1 device evidence still open |
| **L1 Core loop** | **PASS** | [PR #193](https://github.com/RoshanDewmina/conduit/pull/193) · [`L1/REPORT.md`](L1/REPORT.md) | Isolated relay pair + dispatch + **PONG** reply; push-backend 401 env-only (does not block local relay) |
| **L2 Chat** | **PASS** | [`L2/REPORT.md`](L2/REPORT.md) | Offline seeded transcript UITest **TEST SUCCEEDED**; follow-up dispatch offline PARTIAL (expected) |
| **L3 Chrome** | **PASS** | [`L3/REPORT.md`](L3/REPORT.md) | Workspaces + composer/profile/settings/search/addRepo/repoPicker deep-links |
| **L4 Governance** | **PASS** | [PR #192](https://github.com/RoshanDewmina/conduit/pull/192) · [`L4/REPORT.md`](L4/REPORT.md) | Go E2E + Swift governance filters + `SweepLaneC4Tests` **TEST SUCCEEDED** |
| **L5 Widgets / LA** | **PASS** | [PR #194](https://github.com/RoshanDewmina/conduit/pull/194) · [`L5/REPORT.md`](L5/REPORT.md) | Stale TTL + Agents/LA writers PASS; arrive/resolve was **test fixture TTL bug** (fixed); HS widget chrome skipped on sim |
| **L6 Siri** | **PASS** | [PR #192](https://github.com/RoshanDewmina/conduit/pull/192) · [`L6/REPORT.md`](L6/REPORT.md) | `xcodegen` before build; IntentsKit tests; AppShortcuts discovered |
| **L7 Review** | **PASS** | [`L7/REPORT.md`](L7/REPORT.md) | Restored DEBUG `LANCER_DESTINATION=review` fixture sheet; Edit-tool red/green still known MISSING |
| **L8 Accounts** | **PASS** | [`L8/REPORT.md`](L8/REPORT.md) | Prior FAIL was truncated SPM log — tip already compiles; 15 Swift + accounts UITest PASS |
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
| L8 | FAIL | — | **PASS** (`lease-247`) |
| L2 | PARTIAL | — | **PASS** (`lease-247`) |
| L3 | MISSING | — | **PASS** (`lease-247`) |
| L7 | MISSING | — | **PASS** (`lease-247`; Edit-tool gap noted) |

Method: remaining lanes used one Simurgh lease (`lease-247`); tip + #193/#194; isolated `LANCER_STATE_DIR`; never bare prod `lancerd pair`. L8 prior FAIL was a false positive (SPM fetch truncated). L7 restored DEBUG `review` destination for fixture `ReviewSheetView`.

See also [`ROLLUP-remaining.md`](ROLLUP-remaining.md).

---

## Per-lane detail (remaining lanes closed)

### L2 — Chat — PASS
- Focused `SimFeatureLaneL2Tests` offline seed: thread list, transcript, tool chips, follow-up UI.
- Disk-budget hygiene FAIL remains process noise, not a product gate.

### L3 — Chrome — PASS
- Deep-link UITests for Workspaces root + composer/profile/settings/search/addRepo/repoPicker.

### L7 — Review — PASS
- `ReviewModelsTests` 16/16 + `LANCER_DESTINATION=review` fixture sheet UITest.
- **Edit-tool red/green sheet** still MISSING (CursorStyle deletion) — separate follow-up.

### L8 — Accounts — PASS
- Tip compiles; VendorAccountStore + RunningAgentsMapping 15 tests; accounts destination UITest.

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
3. **Edit-tool red/green sheet** — optional follow-up (L7 noted MISSING); device confirm #185/#187 widgets.

---

## Worktree inventory (relevant)

| Path | Branch | Role |
|---|---|---|
| `.worktrees/sim-serial-lanes` | `sim/serial-lanes-2026-07-19` | PR #192 evidence |
| `.worktrees/widget-stale-approvals` | `fix/l1-reply-path` / `fix/l5-pending-approvals-writer-test` | PR #193 / #194 |
| `.worktrees/sim-remaining-lanes` | `sim/remaining-lanes-2026-07-19` | L8/L2/L3/L7 + review destination fix |
| `.worktrees/cursor-cli-adapter` | `feat/cursor-cli-adapter` | PR #190 |
| `.worktrees/feature-sweep-rollup-2026-07-19` | `docs/2026-07-19-feature-sweep-rollup` | **this rollup** (#189) |
