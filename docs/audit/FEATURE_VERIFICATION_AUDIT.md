# Conduit — Feature Verification Audit ("built vs actually-works")

**Date:** 2026-06-15
**Auditor pass:** static data-path trace + live read-only probe against the running VPS daemon.
**Subject:** the 15–18 competitor-research features claimed in
`~/Downloads/conduit-competitor-research-implementation-report.md`.
**Method:** for each feature, trace iOS view → store → `DaemonChannel` RPC → daemon handler,
then probe the live daemon where cheap. Verdicts cite `file:line`.

## Live environment used

- `ssh hermes-box` → `silvapulle@100.83.108.60`, **conduitd `0.2.0-vps-20260615`**, resident
  daemon running, socket `~/.conduit/conduitd.sock`, audit log with 2 real entries
  (`escalate` + `approve`, hash-chained).
- The resident daemon allows **one** attach client; the app's `conduitd serve` was **not**
  attached during the audit, so I attached with the proper `{"op":"attach"}` handshake and
  issued read-only RPCs directly. Raw live results are quoted per-feature below.

---

## Verdict summary

| # | Feature | Verdict | One-line evidence |
|---|---|---|---|
| 1 | conduit doctor (CLI) | **WORKS-LIVE** | `conduitd doctor` → 10 ok / 1 warn / 0 fail on VPS |
| 2 | `agent.doctor` RPC + DoctorView | **WIRED-UNPROVEN→LIVE** | RPC returns 6 real computed checks; DoctorView binds `actions.runDoctor()` |
| 3 | Tamper-evident audit (verify/export) | **WORKS-LIVE** | `agent.audit.verify`→`{valid:true,entryCount:2}`; export returns chained JSONL |
| 4 | Policy simulator | **WORKS-LIVE** | live `agent.policy.simulate` replayed the real audit entry → `asked:1, ruleHits:[default:ask]` |
| 5 | Scoped allow-always (expiry/revoke) | **MIXED: daemon WIRED / iOS MOCK-ONLY** | match.go honors expiry/repo/path; iOS scope sheet writes **UserDefaults only**, `buildPolicyYAML` is dead code |
| 6 | Loop object | **WIRED-UNPROVEN** | GRDB-backed store + `agent.loop.update`/`list` real; live list empty (no producer yet) |
| 7 | Proof card | **WIRED-UNPROVEN** | AgentRunDetailView builds a real model from live run state; gallery variants are mock |
| 8 | Privacy badge | **WIRED w/ FALLBACK** | binds `isLocalModel`/`dataLeavesHost` but daemon never sets them → falls back to `local` flag |
| 9 | Quota / spend guardrails | **STUB / NO-OP** | live `agent.quota.status`→`{providers:null,alerts:null}`; `updateProviderSpend` only ever called by RPC, never internally |
| 10 | Host-health guard | **WIRED-LIVE (Linux-degraded)** | live health real, but all battery/sleep/lid logic is macOS-only → null on the Linux VPS |
| 11 | Secrets broker | **WIRED-UNPROVEN** | full store + 6 RPCs; live `agent.secret.list`→`{secrets:[],pending:[]}` |
| 12 | Worktree / branch board | **NOT-WIRED / NO-OP** | `DaemonChannel.fetchWorktrees()` `return []`; no `agent.worktree.*` RPC; GitClient methods have **no callers** |
| 13 | CI / PR webhooks | **NOT-WIRED (broken path)** | iOS calls RPC `agent.ci.recent` which **conduitd does not register**; webhook lives only in push-backend, never bridged |
| 14 | Adapter SPI + conduit-mcp | **WIRED-UNPROVEN** | real stdio MCP server shelling to `conduitd agent-hook`; not exercised this pass |
| 15 | Blocked-state OS | **MOCK-ONLY (gallery)** | `AgentStatusBar`/`DSBlockedReasonRow` instantiated only in DebugGalleryView; real producer hardcodes `blockedReason: nil` |
| 16 | opencode status path fix | **PARTIAL: path fixed / usage STUB** | path corrected to `~/.config/opencode/opencode.json`; `opencodeUsageUSD` hard-returns `(0,nil,false)` |

**Counts:** WORKS-LIVE 3 · WIRED-LIVE(degraded) 1 · WIRED-UNPROVEN 4 (+1 doctor-RPC) ·
MIXED/PARTIAL 3 · MOCK-ONLY 1 · STUB/NO-OP 1 · NOT-WIRED 2.

**Most at risk — "look real, aren't":**
1. **Quota/Spend Guardrails** — renders cards, real RPC, but daemon never feeds spend → always empty/zero.
2. **Worktree/Branch Board** — full 3-column UI, but `fetchWorktrees()` is a literal `return []`.
3. **CI/PR Integration** — UI section + loader present, but the RPC it calls doesn't exist on conduitd.
4. **Scoped Allow-Always** — sheet offers repo/path/expiry/revoke, but those choices never reach the daemon (UserDefaults only); `buildPolicyYAML` dead.
5. **Blocked-State OS** — the "why am I blocked" row only renders in the gallery; production sessions never feed it a reason.

---

## Per-feature detail

### 1–2. Doctor (CLI + RPC) — WORKS-LIVE / WIRED→LIVE
- **CLI** `daemon/conduitd/doctor.go:71` `collectDoctorResults` runs 11 real checks. Live:
  `conduitd doctor` → `10 ok, 1 warnings, 0 failures` (the warn is "policy.yaml absent → default-ask", desired).
- **RPC** `agent.doctor` (`server.go:504`) → `collectDoctorReport()` (`server.go:1105`) is a **separate** 6-check report.
  Live probe returned real data: `daemon-version` pass, `hooks-installed` fail (`Missing config for: codex, opencode`),
  `agent-auth` error (`No API keys found`), `policy-parseable` pass, `fs-permissions` pass, `local-models` none.
- **iOS** `SettingsFeature/DoctorView.swift:20-29` binds `actions.runDoctor()` → real channel RPC. No mock.
- **Verdict:** Ship. This is genuinely real and the most honest feature in the batch.

### 3. Tamper-evident audit — WORKS-LIVE
- `audit.go`: SHA-256 hash chain (`computeEntryHash` :58, `PrevHash` linking :97-102), `Verify()` :141 recomputes
  the chain and reports `BrokenAt`, `exportJSONL()` :188.
- **Live:** `agent.audit.verify` → `{valid:true, entryCount:2, firstTimestamp:..., lastTimestamp:...}`;
  `agent.audit.export` returns the two entries with linked `hash`/`prevHash`. The on-disk log confirms
  entry 2's `prevHash` == entry 1's `hash`.
- **iOS** `AuditView.swift:40-65` binds `verifyAudit()`/`exportAudit()`; `AuditExportDocument` for share-sheet export.
- **Gap:** no unit test covers `Verify()` tamper detection (no `BrokenAt` test in `audit_test.go`). Logic is proven *valid* live but never proven to *catch* a flipped byte. Add a tamper test before marketing "tamper-evident".
- **Verdict:** Ship; add the negative test.

### 4. Policy simulator — WORKS-LIVE
- `policy/simulate.go:44` `Simulate` replays audit entries through the real `Evaluate`; `LoadAuditEntries` :119
  reads the actual `~/.conduit/audit.log`. Server wrapper `server.go:148 simulatePolicy`.
- **Live:** `agent.policy.simulate` with `default: ask` → `{totalActions:1, asked:1, ruleHits:[{ruleID:"default:ask",
  effect:"ask", count:1, sampleCommands:["ls -la ~"]}], riskDistribution:{low:1}}`. Correctly classified the
  real escalate entry. **This is the standout: it operates on real history.**
- **iOS** `PolicySimulatorView.swift` + `DaemonChannel.simulatePolicy(yaml:periodDays:)`.
- **Caveat:** value scales with audit history depth; on a fresh host it's near-empty (only 1 entry today).
- **Verdict:** Ship. Strong trust-builder.

### 5. Scoped allow-always — MIXED (daemon WIRED, iOS MOCK-ONLY)
- **Daemon real:** `policy/types.go:55-59` adds `Repo/PathPattern/ExpiresAt/TimeWindow/CreatedAt`; `policy/match.go:33-66`
  honors expiry (skips expired rules), repo glob vs CWD, and pathPattern glob. `applyDecision` :262 →
  `appendAllowAlways(event)` creates a basic allow rule on `approveAlways`.
- **iOS cosmetic:** `InboxView.swift:648 persistScopedAllowAlwaysRule` writes the scope/expiry/path choices to
  **`UserDefaults["inbox.allowAlwaysRules"]` only**. `buildPolicyYAML` (:683) — which would translate scope to a real
  daemon rule — is **dead code (zero callers)**. `PolicyEditorView.swift:139/195` reads & "revokes" that same local
  list, disconnected from the daemon's policy file.
- **Net:** "allow always" creates a *basic* unscoped daemon rule (works), but the **repo/path/time-window scoping and
  the one-tap revoke are not enforced** — they're a local UI illusion. `TimeWindow` field is also stored but never
  read in match (only `ExpiresAt` is).
- **Verdict:** Fix before claiming "scopes + expiry + one-tap revoke". Wire `buildPolicyYAML` → `agent.policy.set`,
  and make PolicyEditor read/revoke real daemon rules (`agent.policy.get`).

### 6. Loop object — WIRED-UNPROVEN
- `Loop.swift`, `LoopRepository.swift` (GRDB), `AppDatabase.swift` v9 migration, `LoopStore.swift:33-76`
  (durable GRDB + `channel.updateLoop` mirror), `agent.loop.update`/`agent.loop.list` (`server.go:700/715`,
  `upsertLoop` persists to disk).
- **Live:** `agent.loop.list` → `{loops:[]}`. Real store, nothing creating loops yet (no agent run constructs a Loop).
- **Verdict:** Keep the model; it's the data spine for Proof/Worktree/CI. Needs a *producer* (dispatch/session → Loop).

### 7. Proof card — WIRED-UNPROVEN
- `AgentRunDetailView.swift:24 / :250 buildProofModel()` builds a **real** `ProofCardModel` from live run state
  (approvals asked/decided, totalCost, terminal status) and shows it on terminal runs. Gallery `proof` route uses
  4 mock variants (expected for a gallery).
- **Caveat:** the CI sub-section of the card depends on CI events, which never load (see #13); tests/diff sections
  depend on run metadata being populated by the dispatch path.
- **Verdict:** Ship the card; it degrades gracefully. Its richness tracks how much real run metadata #6/#13 supply.

### 8. Privacy badge — WIRED with FALLBACK
- `FleetView.swift:396 privacyVariant`: prefers `a.isLocalModel`/`a.dataLeavesHost`, else falls back to the legacy
  `a.local` bool. **No daemon code sets `isLocalModel`/`dataLeavesHost`** (grep over `daemon/` → none), so the
  badge today is driven entirely by the pre-existing `local` heuristic, not by the new fields.
- **Verdict:** Cosmetically fine (shows Local vs not). To make "Local — nothing leaves host" *true*, the status
  readers must actually detect local-model usage and set the new fields. Until then it's the old signal in new paint.

### 9. Quota / spend guardrails — STUB / NO-OP
- iOS is genuinely wired: `QuotaGuardStore.swift:19/39 setChannel + refresh`→`channel.getQuotaStatus()`,
  refreshed on connect (`AppRoot.swift:1220-1223`).
- **Daemon is empty:** `dispatch.go:465 getQuotaGuard` ranges `d.providerSpend`, but **the only caller of
  `updateProviderSpend` is the RPC handler** (`server.go:697`) — *nothing inside the daemon feeds spend from actual
  dispatched runs* (grep: `updateProviderSpend` has no internal caller). So the map stays empty.
- **Live:** `agent.quota.status` → `{providers:null, alerts:null}`. Caps can be set via RPC but there's no spend to
  compare against. Burn-rate/projection math (`:319-377`) is real but starved of input.
- **Verdict:** Fix or cut. The burn-rate engine is good; it needs the dispatcher to call `updateProviderSpend`
  on run cost (or the daemon to read provider usage). As-is it shows $0/empty against a real host.

### 10. Host-health guard — WIRED-LIVE (degraded on Linux)
- `health.go:38 collectHostHealth` real; `agent.host.health` (`server.go:590`). `HostHealthStore.swift:38` binds
  `slot.channel.getHostHealth()`.
- **Live (Linux/arm64 VPS):** `{hostname:"hermes-box", status:"healthy", networkReachable:true, uptime:3636,
  hooksInstalled:true, localModelEndpoints:[ollama:false, lm-studio:false]}`. **No battery/sleep/lid fields** —
  `collectMacHealth` (`pmset`) is gated `runtime.GOOS=="darwin"` (`:51`), so the headline "sleep/lid warning,
  caffeinate" value is **macOS-host-only**; on Linux the guard degrades to uptime + network + model probes.
- **Verdict:** Ship for what it is, but the marketed "lid/sleep/battery" pitch only fires when the *host* is a Mac.
  Label accordingly; Linux/VPS hosts get a thinner health card.

### 11. Secrets broker — WIRED-UNPROVEN
- `secrets.go` JSON-file store + 6 RPCs (`server.go:736-810`), `DSCredentialRequestCard`, SecretsStore lives inside
  `SettingsFeature/SecretsView.swift:20-82` (note: report claims `AppFeature/SecretsStore.swift` — that file does
  **not** exist; functionality is in SecretsView). Real channel wiring.
- **Live:** `agent.secret.list` → `{secrets:[], pending:[]}`. No agent exercises the broker yet (no `agent.secret.request`
  emitter in the hook path observed).
- **Verdict:** Real plumbing, unexercised. P2 — defer hardening; don't market "raw secret never enters agent context"
  until an agent actually round-trips a request.

### 12. Worktree / branch board — NOT-WIRED / NO-OP
- `WorktreeBoardView.swift` (3-column UI) reachable via `FleetView.swift:151`. `WorktreeStore.swift:61` calls
  `channel.fetchWorktrees()` — which is **`return []`** with the comment *"This will be wired to the daemon protocol
  when the bridge-side worktree endpoint is implemented"* (`WorktreeStore.swift:76-82`).
- No `agent.worktree.*` RPC exists in `server.go`. The new `GitClient` methods (`listBranches`, `changedFiles`,
  `latestCommit`, `parseNameStatus`) have **zero callers** in the app.
- **Verdict:** Cut from v1 (or hide the nav row). It is a finished-looking board over an empty data source.

### 13. CI / PR webhooks — NOT-WIRED (broken path)
- `push-backend/webhooks.go` is a real GitHub receiver (HMAC verify, ring buffer) — but it lives in **push-backend**,
  a different process from conduitd.
- iOS `DaemonChannel.recentCIEvents` (`:327`) calls RPC **`agent.ci.recent`**, which **conduitd does not register**
  (grep `daemon/` → not found) → "method not found", swallowed by `try?` in `FleetView.swift:451` → `[]`.
- Nothing bridges push-backend CI events → conduitd → app. The webhook buffer is write-only from the app's POV.
- **Verdict:** Cut from v1. To revive: either expose CI via push-backend directly to the app, or add a conduitd
  `agent.ci.recent` that proxies push-backend.

### 14. Adapter SPI + conduit-mcp — WIRED-UNPROVEN
- `conduit-mcp/main.go:97-178`: real stdio MCP server; `tools/call` shells out to `conduitd agent-hook --kind ...`
  and denies on nonzero exit. `docs/adapter-spi.md` documents Class A/B. Builds (`go 1.22` module).
- Not exercised this pass (would need a Goose/Cline client). The hook path it targets *is* proven (Phase 3 approve loop).
- **Verdict:** Keep as an extensibility bet; low risk because it reuses the proven `agent-hook` chokepoint. Don't
  headline specific agents (Goose/Cline/Roo/Kilo) until one is demoed end-to-end.

### 15. Blocked-state OS — MOCK-ONLY (gallery)
- `BlockedReason.swift` + `AgentStateContext` + `DSBlockedReasonRow` are real types. But `AgentStatusBar` (the only
  consumer of `DSBlockedReasonRow`) is instantiated **only in `DebugGalleryView.swift:612/898`**. The real producer
  `LoopRepository.swift:139` hardcodes `blockedReason: nil`.
- **Verdict:** The "why am I blocked?" UX does not exist in production flow. Fix is high-value (it's the P0 research
  pain) but small: feed a real `BlockedReason` from the approval/session state into a status bar that ships in the
  session/inbox, not just the gallery.

### 16. opencode status path fix — PARTIAL
- Path corrected to `~/.config/opencode/opencode.json` (`agent_status_opencode.go:23/29`), model read is real.
- `opencodeUsageUSD` (`:33-36`) is a **hard stub**: `if !fileExists(dbPath) { return 0,nil,false }` then
  `return 0,nil,false` unconditionally — opencode spend is **never** read (SQLite driver intentionally omitted).
- **Verdict:** Path fix legit; opencode usage/$ is permanently zero until a SQLite read lands. Don't show opencode
  spend as authoritative.

---

## Ship vs cut vs fix (v1 — thesis: "supervision, not mobile IDE")

**SHIP (real, on-spine, trust-building):**
- conduit doctor (CLI + RPC) — proven.
- Tamper-evident audit — proven; add the negative/tamper unit test.
- Policy simulator — proven; best differentiator of the batch.
- Proof card — real, degrades gracefully.
- Host-health guard — ship but **honestly label** (lid/sleep/battery = Mac-host only).

**FIX before launch (look real, aren't — but high value):**
- **Blocked-state OS** — wire a real `BlockedReason` into a shipping status bar (P0 research pain; small fix).
- **Scoped allow-always** — make scope/expiry/revoke actually hit the daemon (`buildPolicyYAML`→`agent.policy.set`;
  PolicyEditor reads/revokes real rules). Otherwise downgrade the UI to "allow always" (no scope claims).
- **Quota/spend guardrails** — feed `updateProviderSpend` from real run cost, or cut. Empty cards erode trust.

**CUT / hide from v1 (finished UI over no data):**
- **Worktree/branch board** — `fetchWorktrees()` returns `[]`; hide the nav row.
- **CI/PR integration** — calls a nonexistent RPC; hide the section until bridged.

**DEFER (real plumbing, unexercised — fine to keep dark):**
- Secrets broker, Adapter SPI + conduit-mcp, Loop object (needs a producer), Privacy badge "local-proof" fields.

## Prioritized shortlist — highest-value things to actually make work

1. **Blocked-state reason in production UI.** Smallest fix, biggest research-aligned payoff ("silent blocking" was the
   #1 pain). Feed `Approval`/session state → `BlockedReason` → a status bar that ships outside the gallery.
2. **Quota spend actually accrues.** Have the dispatcher call `updateProviderSpend(provider, runCost)` on run
   completion. Turns a $0 stub into a live burn-rate guard with the math already written.
3. **Scoped allow-always reaches the daemon.** Wire `buildPolicyYAML`→`agent.policy.set`; PolicyEditor reads real
   rules via `agent.policy.get` and revokes server-side. The daemon match logic is already correct.
4. **Audit tamper negative test.** Cheap; converts "valid live" into provable "catches a flipped byte" for the
   tamper-evident marketing claim.
5. **Loop producer.** One writer (dispatch/session → `LoopStore.upsert`) lights up Loop list, Proof card richness,
   and gives Worktree/CI somewhere real to attach later.

## Notes / report inaccuracies found
- `AppFeature/SecretsStore.swift` does not exist; the store is embedded in `SettingsFeature/SecretsView.swift`.
- The report lists `ProofCardView.swift` twice in the DesignSystem manifest.
- "All features built / build clean" is accurate at the *compile* level, but compile-clean ≠ data-flowing:
  #9/#12/#13/#15 compile and render yet have no live data path.
