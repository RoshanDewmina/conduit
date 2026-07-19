# 2026-07-19 feature-sweep rollup

**Synthesized:** 2026-07-19 ~21:20 UTC-4  
**Baseline tip:** `origin/master` @ `7c4b1eca`  
**Inventory sources:** `.worktrees/sim-l1-core`…`sim-l8-accounts`, `.worktrees/cursor-cli-adapter`, `worktrees/lancer/plan-feature-matrix-2026-07-19`, open PRs #185–#188  
**Prod pairing:** **intact** (`~/.lancer/relay-pairing.json` mtime 2026-07-19 10:26; L4 used `LANCER_STATE_DIR=/tmp/l4-gov-state`)

Status legend: **PASS** = lane bar met with committed evidence · **PARTIAL** = some gate evidence, sim/live incomplete · **FAIL** = attempted and failed · **MISSING** = no report / agent never finished.

---

## Summary table

| Track | Status | Evidence / pointer | Notes |
|---|---|---|---|
| **Plan matrix** | **PASS** | [PR #188](https://github.com/RoshanDewmina/conduit/pull/188) · `docs/test-runs/2026-07-19-plan-feature-matrix/` | Docs-only audit; G1 passed; G2/B1 device evidence still open |
| **L1 Core loop** | **MISSING** | `.worktrees/sim-l1-core` → `L1/screenshots/` empty | Worktree created @ `7c4b1eca`; no REPORT, no Simurgh lease artifact |
| **L2 Chat** | **PARTIAL** | `L2/disk-budget.txt` | Disk-budget check **FAIL** (19 worktrees outside approved root); uncommitted `LancerUITests/SimFeatureLaneL2Tests.swift`; no sim run |
| **L3 Chrome** | **MISSING** | `.worktrees/sim-l3-chrome` → `L3/screenshots/` empty | Branch `test/sim-l3-chrome` @ `ead06eeb` (not tip); no lane report |
| **L4 Governance** | **PARTIAL** | `L4/go-test-governance-rpc.tail.txt` (**PASS**), isolated state, lease JSON | Go E2E router tests PASS; swift test log truncated mid-build; `pair.log` QR emitted under isolated state (prod untouched) |
| **L5 Widgets / LA** | **MISSING** | no `L5/` artifacts in worktree | Worktree on `960ee943` (#187 tip); sibling PR #185/#187 cover code, not this lane’s sim evidence |
| **L6 Siri** | **FAIL** | `L6/xcodebuild-build.tail.txt` | `xcodebuild: error: 'Lancer.xcodeproj' does not exist` (forgot `xcodegen` / project generate before build) |
| **L7 Review** | **MISSING** | no `L7/` artifacts | Worktree @ `7c4b1eca`; agent never wrote report |
| **L8 Accounts** | **FAIL** | `L8/swift-test.excerpt.txt` | `swift test` build failed (`PermissionModeSetResult` not in scope in `DaemonChannel.swift`); Simurgh acquire still waiting (~10m+) |
| **Vendor free-model smoke** | **MISSING** | `docs/test-runs/2026-07-19-vendor-free-model-smoke/` absent | Codex/OpenCode smoke agent transcript is user-prompt only (never ran) |
| **Cursor CLI adapter** | **PARTIAL** | [PR #190](https://github.com/RoshanDewmina/conduit/pull/190) · `feat/cursor-cli-adapter` @ `387824ba` | `go test ./...` PASS; focused Swift 22/22 PASS; **needs Sonnet/Fable full-diff review** (`dispatch.go`) before merge |

### Open PRs (related)

| PR | Title | Role vs sweep |
|---|---|---|
| [#185](https://github.com/RoshanDewmina/conduit/pull/185) | fix(ios): clear stale Home Screen approvals widget count | Widget polish — merge + device confirm still owed |
| [#186](https://github.com/RoshanDewmina/conduit/pull/186) | test(ios): Siri Shortcuts phrase dogfood harness + report | Siri harness — not a substitute for L6 sim lane |
| [#187](https://github.com/RoshanDewmina/conduit/pull/187) | fix(ios): Siri sim dogfood + Agents widget dedupe/aesthetics | Overlaps L5/L6 code; lane evidence still MISSING |
| [#188](https://github.com/RoshanDewmina/conduit/pull/188) | docs: 2026-07-19 plan/feature matrix audit | **DONE** plan inventory |
| [#189](https://github.com/RoshanDewmina/conduit/pull/189) | docs: 2026-07-19 feature-sweep rollup | **This rollup** |
| [#190](https://github.com/RoshanDewmina/conduit/pull/190) | feat(daemon): Cursor Agent CLI as dispatchable vendor | Cursor MVG — review before merge |

---

## Per-lane detail

### L1 — Core loop — MISSING
- Worktree: `/Volumes/LancerDev/lancer/.worktrees/sim-l1-core` (detached `7c4b1eca`)
- Only empty `docs/test-runs/2026-07-19-sim-feature-lanes/L1/screenshots/`
- **Re-dispatch blocker:** agent exited without Simurgh lease / REPORT; re-run with mandatory `REPORT.md` + `lease_release`

### L2 — Chat — PARTIAL
- Disk budget script ran; **FAIL** on “worktrees outside `/Volumes/LancerDev/worktrees`” (process/hygiene, not product)
- UITest scaffold present but uncommitted; no xcodebuild/UITest evidence
- **Re-dispatch:** skip budget-as-hard-fail; run focused chat UITests under Simurgh

### L3 — Chrome / shell — MISSING
- Empty `L3/screenshots/`; worktree tip diverged (`ead06eeb` monetization commit)
- **Re-dispatch:** reset worktree to `origin/master`, deep-link UITests (`LANCER_DESTINATION`)

### L4 — Governance — PARTIAL
- **PASS:** `go test` E2ERouter EmergencyStop / AuditTail / PermissionMode* (`ok lancer/lancerd`)
- Isolated pairing intent recorded; prod pairing presence snapshot confirms tip pairing file untouched
- Swift governance filter did not finish cleanly in log
- **Finish bar:** complete `swift test --filter 'Policy|Audit|Emergency'` + optional Settings UITest; write `L4/REPORT.md`

### L5 — Widgets / Live Activity — MISSING
- No lane directory written; code lives on #185/#187
- **Re-dispatch:** Simurgh + `LiveActivity*` / `WidgetSnapshot*` / `ApprovalStale*` filters; do not re-pair prod

### L6 — Siri — FAIL
- Simurgh exec reached xcodebuild; project path missing (`Lancer.xcodeproj` not generated)
- Related evidence exists on #186/#187 branches (`2026-07-19-siri-*`) but not under this lane path
- **Re-dispatch:** `xcodegen generate` (or open via existing project) before `simurgh exec … build/test`

### L7 — Review — MISSING
- No artifacts
- **Re-dispatch:** `LANCER_DESTINATION=review` UITest; note Edit-tool red/green sheet regression status

### L8 — Accounts — FAIL
- `swift test --filter 'VendorAccountStoreTests|RunningAgentsMappingTests|…'` → build error on `PermissionModeSetResult`
- Simurgh lease acquire hung waiting for capacity
- **Re-dispatch:** fix/build against tip that compiles; acquire lease only after kit builds; release any stuck acquires

---

## Vendor free-model smoke — MISSING

- Expected path `docs/test-runs/2026-07-19-vendor-free-model-smoke/` **does not exist** anywhere under `/Volumes/LancerDev`
- Agent `ea81bdf9` transcript contains only the launch prompt
- **Re-dispatch:** isolated `LANCER_STATE_DIR` + `HOME`; never touch prod pair; Codex/OpenCode free models; write per-vendor PASS/FAIL with argv + exit

---

## Cursor CLI adapter — mid-flight (verified this session)

| Gate | Result |
|---|---|
| Worktree | `/Volumes/LancerDev/lancer/.worktrees/cursor-cli-adapter` · branch `feat/cursor-cli-adapter` |
| Commit | `387824ba` on `feat/cursor-cli-adapter` |
| `cd daemon/lancerd && go test ./... -count=1` | **PASS** (lancerd / policy / terminal) |
| `swift test --filter 'AgentRegistryTests\|DispatchVendorSelectionTests\|RunningAgentsMappingTests'` | **PASS** 22 tests |
| Remote PR | [#190](https://github.com/RoshanDewmina/conduit/pull/190) |
| Merge gate | **Sonnet/Fable full-diff review required** (`dispatch.go`, doctor, stream-json) |

Scope: Cursor `agent -p --output-format stream-json --trust` argv + continue/resume; stream-json parsing; doctor detect `agent`; iOS picker/Accounts entry; `LANCER_CURSOR_FORCE=1` opt-in for `--force` (fail-closed default).

---

## B1 device evidence (still P0 — owner-gated)

From plan audit STATUS (#188) — unchanged by this sim fan-out:

1. Lock-screen approve on tip (app-closed APNs → approve → resume) — checklist rows empty of evidence files  
2. Follow-up + receipt evidence  
3. Emergency Stop device proof (daemon merged; phone live row open)  
4. Dogfood log / 5-of-7 discipline  

Sim lanes **cannot** substitute for B1.

---

## Ranked next 3 actions

1. **Owner B1 device re-proof (P0)** — fill `docs/test-runs/2026-07-19-b1-tier0-reproof/` rows 3–7 with screenshots/audit; without this G2 cannot pass.  
2. **Land Cursor adapter PR + Sonnet review** — code verified locally; do not merge `dispatch.go` without sensitive-path review; then live smoke one Cursor free/paid model under isolated state.  
3. **Re-dispatch failed/missing sim lanes serially (not 8-way)** — Simurgh capacity + disk-budget noise killed parallelism; priority order **L4 finish → L6 (xcodegen) → L1 → L5**; park L2 budget FAIL as hygiene; fix L8 compile before retest; run vendor Codex/OpenCode smoke as a single daemon-only agent.

---

## Worktree inventory (fan-out relevant)

| Path | Branch / HEAD | Role |
|---|---|---|
| `.worktrees/sim-l1-core` … `sim-l8-accounts` | mostly detached `7c4b1eca` | Lane sandboxes |
| `.worktrees/cursor-cli-adapter` | `feat/cursor-cli-adapter` | Cursor vendor MVG |
| `.worktrees/widget-stale-approvals` | `fix/widget-stale-approvals` | PR #185 |
| `worktrees/lancer/siri-sim-and-aesthetics` | `fix/siri-sim-and-aesthetics` | PR #187 |
| `worktrees/lancer/plan-feature-matrix-2026-07-19` | `docs/2026-07-19-plan-feature-matrix` | PR #188 |
| `.worktrees/feature-sweep-rollup-2026-07-19` | `docs/2026-07-19-feature-sweep-rollup` | **this rollup** |
