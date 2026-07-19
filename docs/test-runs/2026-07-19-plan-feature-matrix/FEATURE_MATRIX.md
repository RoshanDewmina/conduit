# Lancer plan / feature matrix — 2026-07-19

**Baseline tip:** `origin/master` @ `7c4b1eca`  
**Plans read:** `docs/STATUS_LEDGER.md` (stale hub) · `docs/SHIP_PLAN.md` · `docs/plans/2026-07-19-daily-driver-roadmap.md` · `docs/product/2026-07-10-lancer-daily-driver-definition.md` · `docs/product/FEATURE_BACKLOG.md` · `ARCHITECTURE.md` §0.1 · `docs/plans/orchestrator-state.md` (top 2026-07-19 entries) · test-runs `2026-07-16-daily-use-audit`, `2026-07-16-untested-feature-sweep`, `2026-07-18-live-activity-sim`, `2026-07-19-b1-tier0-reproof`, `2026-07-19-siri-*` (on PR branches / worktrees)  
**Open PRs:** #185 · #186 · #187  
**Status summary:** [`STATUS.md`](STATUS.md)

Status values: **Implemented** = in master + used; **Partial** = code present, unproven or incomplete UX; **Planned** = roadmap only / unwired / deferred.

---

## 1. Plan adherence (daily-driver / ship)

| Workstream | Plan claim | Reality @ `7c4b1eca` | Drift |
|---|---|---|---|
| A1 night stack merge | DONE | Done (G1) | None |
| A2 phone re-pair | DONE | Pair `676174` live 2026-07-19 | None |
| A3 zero-output failure | DONE #179 | Merged | None |
| B1 Tier 0 device re-proof | In progress | Checklist only; LA confirmed; approve/follow-up/E-stop evidence files missing | **Blocked on owner evidence** |
| B2 E-stop atomic daemon | DONE #178 | Daemon merged; device proof → B1 | Device half open |
| C1 iOS 27.0 target | SHIP_PLAN workstream C | **Done on master** (`project.yml` / Package `.iOS(.v27)`) | Ahead of “Aug prep” narrative in older STATUS_LEDGER |
| C2–C3 deep Siri / utterance table | Phase 3 / G2 window | Phase 1 AppIntents on device harness (#186); deep Siri parked `#16/#24` | Parallel to incomplete B1 (plan says B before C) |
| D1–D2 blast-radius / evidence bundles | GA trust set | Not started | On schedule if B1 clears mid-Aug |
| MVP exit (5/7 dogfood) | Phase 1 | Dogfood log sparse since 07-14 | **Largest process gap** |
| G1 residue empty | PASSED at `5f35e31f` | #185–#187 open | Soft drift — new polish PRs |

---

## 2. Complete feature inventory

| Feature | Area | Status | Last tested? | Evidence path | Gap |
|---|---|---|---|---|---|
| E2E relay pairing + trusted machines | Core / MVP1 | Implemented | 2026-07-19 pair live | `SHIP_PLAN` §7; B1 CHECKLIST pre-state | Sim pair orphans phone (single slot) |
| Workspaces home (repo-first) | Shell | Implemented | 2026-07-16 sim | `test-runs/2026-07-16-daily-use-audit/L3-*` | Needs-You banner incomplete |
| Thread list (recency) | Chat | Implemented | 2026-07-16 untested sweep | `…/untested-feature-sweep` #15/#16 PASS | Needs-you-first ordering ❌ |
| Needs-You hub / global ingest | Chat / MVP2 | Partial | 2026-07-16 audit FAIL/P0 | `daily-use-audit/GAP_LIST.md` G1 | Approvals only if thread open |
| Composer → dispatch (repo/agent/model) | Chat / MVP4 | Implemented | 2026-07-16 LB PASS | `untested-feature-sweep` #13 | Machine picker when >1 host ❌ |
| Live thread + streaming | Chat / MVP3 | Implemented | 2026-07-16 L1 sim | `daily-use-audit/L1-core-loop.md` | Device tip re-proof owed |
| Follow-up / continue (same vendor session) | Chat / MVP3 | Implemented | Sim 07-16; device B1 row 6 open | L1; B1 CHECKLIST | Tip device evidence missing |
| Inline approval card | Approvals / MVP3 | Implemented | 2026-07-16 LB + C3 | untested-sweep #6 PASS | FX7 review-pill chain C4 owed |
| Question cards (plain) | Approvals | Partial | Night stack / in-thread | historical `2026-07-10-in-thread-questions-dogfood` | Ladder UI deferred; mutation Siri SKIP |
| Pending-approvals banner | Approvals | Implemented | 2026-07-16 LB | untested-sweep #4 PASS | — |
| Push + lock-screen approve | Approvals / MVP5 | Partial | Historical 07-08; tip **unproven** | `2026-07-08-tier0-*`; B1 rows 3–4 empty | **P0 tip re-proof** |
| APNs app-closed / sandbox fallback | Push | Implemented | 2026-07-19 LA stack | orchestrator-state; #182–#184 | Alert-approve path still owner row |
| Live Activity (push-to-start) | Hands-free / P2 | Implemented | 2026-07-19 owner ×2 | B1 CHECKLIST; orchestrator 14:50 ET | Island only when backgrounded; widget device confirm OPEN |
| Home Screen Agents widget | Widgets | Partial | Unit/sim on #187 | `2026-07-19-siri-sim-dogfood`; PR #187 | Dedupe/aesthetics in open PR; device confirm |
| Home Screen Pending Approvals widget | Widgets | Partial | Unit tests #185 | PR #185 | Stale count fix not merged; device confirm |
| Emergency Stop (phone) | Governance / MVP6 | Partial | Daemon #178 Go-proven; harness BLOCKED historically | #178; untested-sweep #1; B1 row 7 | **Device proof owed** |
| Policy presets / matrix (Settings) | Governance | Partial | Relay mode picker PARTIAL 07-16 | Lane P + LC4; #144 | Full YAML still SSH-gated; phone UI re-proof |
| Audit trail (relay tail) | Governance | Implemented | 2026-07-16 LC4 PASS | untested-sweep #3 | — |
| Permission-mode pill | Chat | Implemented | 2026-07-16 LB | untested-sweep #12 | — |
| Background-tasks pill | Chat | Partial | Code FX10+#181; live re-proof owed | #141/#181; untested-sweep #10 | Device confirm |
| Agents section (running / honesty) | Shell | Partial | Continuity fixes; false unreachable historical | daily-use G7; #187 dedupe | Honesty + widget sync |
| Onboarding / first-run | Shell | Implemented | 07-16 Connect PASS | untested-sweep #5 | Fresh-onboarding blank attempt historical |
| Settings / Profile | Shell | Implemented | 07-16 L4 | `L4-governance.md` | Usage Accounts view shipped 07-18 |
| Attachments (photo/file) | Chat | Partial | 07-14/15 gates | `2026-07-12-h-attachments-gate`; night stack | Claude-only attach constraint in dispatch |
| Receipt / proof glance | Trust / P2 | Partial | Code + menu #147 claimed | untested-sweep #17 BLOCKED harness | filesTouched retest; D2 bundles Planned |
| Blast-radius on approval | Trust / D1 | Partial | Field exists; D1 walk Planned | ARCHITECTURE §0.1; SHIP_PLAN D1 | Preflight walk not done |
| Interactive terminal (relay PTY) | Terminal | Implemented | 07-16 F-final PASS | `LF-final-report.md` | Orca depth deferred V2 |
| Desktop session history / decrypt | Terminal | Implemented | 07-15 DesktopSessionDecrypt UITest | night stack / CHANGELOG | — |
| Cross-device CloudKit sync | Continuity | Partial | Code; 2-device unverified | ARCHITECTURE §0.1 | Physical multi-device open |
| Observed session attach | Continuity | Partial | Code + LA observed trigger | #176 area; orchestrator | Tip dogfood thin |
| Siri Phase 1 (status/deny/pause/stop/answer) | Siri / P2 | Partial | 2026-07-19 AppIntents device harness | `2026-07-19-siri-shortcuts-phrase-dogfood.md` (#186) | Spoken Hey Siri + live mutations owner; sim `run()` Code=800 |
| Siri negative: no Approve intent | Siri safety | Implemented | 2026-07-19 metadata + harness | same; `autoShortcuts` = 9 | Owner spoken negative still owed |
| Deep Siri / LongRunningIntent (iOS 27) | Siri / P3 | Planned | Parked #16/#24 | Siri roadmap | Not merged |
| Spotlight / entities | Siri | Partial | Unit IntentsKit | IntentsKitTests | Device indexing thin |
| Watch app / widgets | Watch | Partial / cut primary | Code retained | ARCHITECTURE; FEATURE_BACKLOG | Not V1 surface |
| Hosted-cloud execution UI | V2 | Planned (code retained) | — | ARCHITECTURE deferred | Frozen |
| Away Launch Composer / contract chips | Away Mode | Planned | — | FEATURE_BACKLOG; MVP excluded | Deferred |
| Question Ladder / voice answer | Chat | Planned | — | daily-driver definition LATER | Deferred |
| PR detail / merge from phone | Ship | Partial (honest empty) | 07-16 #22 PASS empty | untested-sweep | Merge maybe NEVER |
| Flight Recorder / work search | Search | Partial | Harness BLOCKED | untested-sweep #23 | Retest after #7 chain |
| Review pill → sheet | Approvals UX | Partial | C4 FAIL harness | untested-sweep #7 | Live re-proof owed |
| File viewer / add comment | Review | Partial | BLOCKED on #7 | untested-sweep #8/#9 | — |
| StoreKit Founder's Edition | Launch / E | Partial | Spine exists; framing | SHIP_PLAN decision 6 | Pre-GA framing only |
| Managed AI credits / Stripe | Billing | Planned | Design docs 07-16 | product design/plan | Unfrozen design; not GA-critical path |
| TestFlight upload | Launch | Implemented | 2026-07-17 upload claimed | STATUS_LEDGER (stale hub) | ASC dogfood / IAP sandbox owner |
| Reconnect / relay generation-guard | Relay | Partial | 10/10 sim claimed **no committed bundle** | STATUS_LEDGER integrity gap | Re-prove or restore evidence |
| Mid-run feedback queue | Chat | Partial | Harness BLOCKED | untested-sweep #11 | — |
| Tool-call label dedup | Chat | Partial | Harness BLOCKED | untested-sweep #14 | — |
| Todo checklist activity | Chat | Partial | Harness BLOCKED | untested-sweep #18 | — |
| Full-tools toggle | Dispatch | Implemented | Night stack | CHANGELOG `77da7612` era | — |
| Auth-preflight cold probe | Dispatch | Implemented | Phone Hi launch PASS #145 | untested-sweep | — |
| Accounts & Usage (vendor) | Settings | Implemented | 2026-07-18 merge wave | CHANGELOG #170–#175 | Live usage query thin |
| Loop primitive (`lancer_loop_*`) | Control plane | Planned | — | ARCHITECTURE Planned | Not started |
| Swarm overview lanes | P3 | Planned | — | roadmap P3.2 | Not started |

### Vendor adapters (load-bearing)

| Vendor | `dispatch.go` agentArgv/continue/resume | Doctor | `hookWiredForAgent` | Last tested / notes | Gap |
|---|---|---|---|---|---|
| **Claude Code** | Yes (`claudeCode`) | PATH + hooks check | **true** when settings wired | Primary dogfood path; C3 approve→launch | Shim PATH warn possible |
| **Codex** | Yes | PATH + hooks **+ trust** check | **true** when `codexHookWired` | Live-status parity 07-18; trust can be `enabled=false` locally | Untrusted hook = silent skip |
| **OpenCode** | Yes | PATH + plugin | **true** when gate plugin wired | Plugin replace of fake hooks.json 07-01/02 | Re-verify on CLI upgrades |
| **Kimi** | Yes | PATH + hooks install (warn unverified) | **false** (fail-closed) | Membership **402**; stream not live-verified | Billing blocks live gate proof |
| **Pi** | Yes (`--mode json`, continue/session) | PATH + extension check | **false** until veto live-fire | Launch/stream/resume 07-18; OpenRouter 402 | Extension installed-but-unverified |
| **Cursor** | **No** argv cases | Not in `checkAgentCLIs` | **false** (default) | `normalizeAgentSource` alias only (“upcoming”) | **Not a dispatchable vendor** |

Evidence: `daemon/lancerd/dispatch.go` (cases), `server.go` `hookWiredForAgent`, `doctor.go` checks, `agent_registry.go` normalize, CHANGELOG 2026-07-18 vendor-parity wave.

---

## 3. Test lanes (parallel simulator workflow agents)

Each lane is file-disjoint enough for parallel Simurgh leases. Prefer **isolated `LANCER_STATE_DIR`**; never run bare `lancerd pair` against production `~/.lancer`.

### Lane A — Core loop (pair → dispatch → approve → follow-up)

**Features:** pairing, composer dispatch, live thread, inline approval, follow-up, permission-mode pill  
**Verify:**
```bash
# Daemon
cd daemon/lancerd && go build ./... && go test ./...
# Kit
cd Packages/LancerKit && swift build && swift test --filter 'Relay|Approval|Session'
# App + live (Simurgh lease required)
simurgh lease_acquire …  # then:
simurgh exec <lease> -- xcodebuild -scheme Lancer -destination 'platform=iOS Simulator,id=<UDID>' build
# Live: build_run_sim / UITest pair+dispatch; screenshots → docs/test-runs/<date>-lane-a/
```
**Owner-gated extension:** B1 physical lock-screen path (not sim-substitutable).

### Lane B — Governance & stop

**Features:** policy relay picker, audit tail, emergency stop UI, allow-always  
**Verify:**
```bash
cd daemon/lancerd && go test ./... -count=1
cd Packages/LancerKit && swift test --filter 'Policy|Audit|Emergency'
# UITest: Settings → Policy/Audit; E-stop confirm sheet
```

### Lane C — Chat chrome & artifacts

**Features:** tool cards, receipt/proof menu, bg-tasks pill, mid-run queue, attachments, review pill  
**Verify:**
```bash
cd Packages/LancerKit && swift test --filter 'BackgroundTasks|Artifact|Attachment|WidgetSnapshot'
# UITest LiveThread + Review deep-link LANCER_DESTINATION=review
```

### Lane D — Terminal & Agents honesty

**Features:** relay terminal open/use, Agents section, observed sessions, desktop history  
**Verify:**
```bash
cd daemon/lancerd && go test ./terminal ./...
cd Packages/LancerKit && swift test --filter 'Terminal|RunningAgents|DesktopSession'
# UITest: Trusted Machines → Open Terminal; Agents tap-through
```

### Lane E — Widgets & Live Activity (sim)

**Features:** Dynamic Island / LA local request, Agents widget dedupe, Pending Approvals snapshot TTL  
**Verify:**
```bash
cd Packages/LancerKit && swift test --filter 'LiveActivity|WidgetSnapshot|RunningAgentsWidget|ApprovalStale'
simurgh exec <lease> -- xcodebuild -scheme LancerKitTests -only-testing:LancerKitTests/LiveActivityRunningAgentsWidgetTests test
# UITest: LiveActivityIslandCapture / DispatchProof (expect island quirks in foreground)
```
**Device:** owner confirm Home Screen widgets + closed-app LA (orchestrator OPEN).

### Lane F — Siri / App Intents

**Features:** 9 shortcuts, entities, negative no-Approve, navigation  
**Verify:**
```bash
cd Packages/LancerKit && swift test --filter 'IntentsKit|SiriNavigation'
# Device (preferred): TEST_RUNNER_LANCER_APPINTENTS_LIVE=1 UITest LancerShortcutsPhraseLiveExecutionTests
# Sim: discovery + negative only; live run() expect Code=800
```
**Owner-gated:** spoken Hey Siri checklist in `2026-07-19-siri-shortcuts-phrase-dogfood.md`.

### Lane G — Vendor adapters (daemon-only parallel OK)

**Features:** Claude/Codex/OpenCode/Kimi/Pi argv + hooks; Cursor negative (unsupported)  
**Verify:**
```bash
cd daemon/lancerd && go test ./... -count=1
# Skill: vendor-cli-adapter-audit before trusting any adapter change
# Live smoke per vendor with isolated HOME / LANCER_STATE_DIR; expect Kimi/Pi billing 402
```

### Lane H — Shell / onboarding / Workspaces IA

**Features:** onboarding, Connect keypad, All Repos cache, thread filters, profile, search overlay  
**Verify:**
```bash
# App-target UITests with LANCER_DESTINATION deep-links
simurgh exec <lease> -- xcodebuild … -only-testing:LancerUITests/<Suite>
```

---

## 4. Sibling-agent scoping cheat sheet

| Agent | Lane | Do not touch |
|---|---|---|
| Core-loop sim | A | production `~/.lancer`, physical reinstall |
| Governance | B | `dispatch.go` without Sonnet review |
| Chat chrome | C | widget App Group keys owned by E/#185 |
| Terminal/Agents | D | LA ActivityKit files owned by E |
| Widgets/LA | E | Siri intent metadata owned by F |
| Siri | F | daemon vendor hooks owned by G |
| Vendors | G | iOS UI |
| Shell IA | H | relay pairing slot (coordinate with A) |

---

## 5. Sources (evidence index)

| Source | Use |
|---|---|
| `docs/SHIP_PLAN.md` §2–§7 | Gate truth (G1 PASSED; G2—) |
| `docs/plans/2026-07-19-daily-driver-roadmap.md` | P1–P3 feature IDs |
| `docs/product/2026-07-10-lancer-daily-driver-definition.md` | MVP 1–6 + exclusions |
| `ARCHITECTURE.md` §0.1 | Implemented / Partial / Planned code snapshot (dated 07-15; E-stop note superseded by #178) |
| `docs/test-runs/2026-07-16-untested-feature-sweep/GAP_LIST.md` | 24-candidate scoreboard |
| `docs/test-runs/2026-07-16-daily-use-audit/GAP_LIST.md` | MVP map + P0 ingest/E-stop/push |
| `docs/test-runs/2026-07-19-b1-tier0-reproof/CHECKLIST.md` | Device proof rows |
| `docs/test-runs/2026-07-18-live-activity-sim/` | Sim LA captures |
| PR #186 / #187 test-run docs | Siri + widget aesthetics |
| `docs/plans/orchestrator-state.md` (2026-07-19 tops) | LA device confirm; deploy tip |
| `docs/dogfood-log.md` | Retention signal (stale) |
