# Daily-use workflow audit — GAP LIST

**Date:** 2026-07-16  
**Tip:** `origin/integration/2026-07-15-night` @ `b17b6172`  
**Worktree:** `.worktrees/daily-use-audit-2026-07-16`  
**Evidence root:** `docs/test-runs/2026-07-16-daily-use-audit/`  
**Scope:** gap list only — no fix PRs

---

## Owner digest (1 page)

### Top 5 blockers to daily use

1. **P0 — Approval home missing / machine-scoped ingest (MVP 3+5)** — Approvals only surface when the live thread for that machine is open; Workspaces has no Inbox. Push fragile after unpaired drop / backend restart. Evidence: `RelayApprovalIngest.swift` scope comment; night + L1 (DEBUG auto-approve hid card).
2. **P0 — Emergency Stop not in iOS Settings on tip (MVP 6)** — Night #135 claim is **false on `b17b6172`**: Policy & Governance is a deferred stub; no Emergency Stop button. Evidence: `L4-governance.md`, `AppSettingsView.swift`, UITests.
3. **P0 — Device push / lock-screen approve unproven on tip (MVP 5)** — L6 BLOCKED; sim pair orphaned phone (`583514`). Evidence: `L6-device-pass.md`.
4. **P1 — Agents section unreliable for dogfood** — "Checking for agents…" / "Machine unreachable" while relay can still dispatch. Evidence: `L2-00`, `L4-02-profile-sheet.png`.
5. **P1 — Composer still shows non-functional mic (#129 FAIL)** — `mic.fill` in `NewChatComposerView.swift:380`; visible on `L1-00`, `L1-20`.

### What passed (sim)

- Pair (re-pair `583514`) → dispatch → escalate → approve → continue → same-thread follow-up (`L1-core-loop.md`).
- Functional hook unblock (receipt `exitCode:0`; raw `HOOK_EXIT=$?` not instrumented).
- Workspaces repo list hydration (counts after pair).
- Mechanical: `go test` PASS; app-target `BUILD SUCCEEDED`.

### Still open (owner)

- Re-pair physical phone after sim audit.
- L6 checkpoints A/B/C (device §3, push-while-closed, Emergency Stop — Stop may still be missing in Settings).

---

## Ranked gaps

### P0 — blocks daily dogfood

| ID | Surface | MVP # | Gap | Evidence | Likely locus |
|---|---|---|---|---|---|
| G1 | approval / Workspaces | 3, 5 | Machine-scoped ingest; no Inbox home; card only if live thread open | L1 (DEBUG card fleeting); seed P0 A; `RelayApprovalIngest.swift` header comment (no runId on wire) | `RelayApprovalIngest.swift`; `LiveThreadView` pending card binding |
| G2 | push | 5 | Push while closed / lock-screen approve **unproven on tip**; unpaired drops approvals; resend WS-only | L6 BLOCKED; seed P0 A (`e2e_router.go` drop/resend) | push-backend `server.go`; `e2e_router.go` |
| G3 | emergency-stop / settings | 6 | **Emergency Stop + policy editor + audit feed absent** on tip Settings (deferred copy only) | `L4-governance.md`; `AppSettingsCopy.swift`; UITest `DeferredPolicyNoEmergencyStop` | `AppSettingsView.swift:63-74` |
| G4 | pairing | 1 | Sim pair orphans phone (single slot); key-mismatch on reused codes; 8s `waitForConnectedMachine` race vs ~21s auto-pair | L1 (`587341` mismatch → `583514`; race note) | `ShellLiveBridge.waitForConnectedMachine`; `lancerd pair` |

### P1 — hurts daily use

| ID | Surface | MVP # | Gap | Evidence | Likely locus |
|---|---|---|---|---|---|
| G5 | chat | 3 | Wall-of-prose assistant turns without tool chips when GRDB has only `output` events | L2 (CONFIRMED); `L1-20` | `LiveThreadView` → `ChatMarkdownBody`; chip hydration |
| G6 | chat | 3 | `"Bash Bash:"` duplicate loci still present (`claudeToolUseSummary` + `Bridge/LiveThreadTranscript.swift` prepend); string **not** seen in UI this run (no `tool_call` mirror events) | L2 | `claude_transcript_adapter.go`; `AppFeature/Bridge/LiveThreadTranscript.swift:124-126` |
| G7 | Workspaces / Agents | 2 | Agents "Checking…" / "Machine unreachable" while dispatch works | `L2-00`, `L4-02` | Agents continuity / hydration |
| G8 | composer | 4 | Non-functional mic still shown (#129 FAIL) | L3; `NewChatComposerView.swift:380` | same |
| G9 | onboarding | 1 | Fresh onboarding not demonstrated; blank white on attempt | `L3-00` | `OnboardingFeature` + launch args |

### P2 — polish

| ID | Surface | MVP # | Gap | Evidence |
|---|---|---|---|---|
| G10 | composer | 4 | Composer in-place morph **FAIL** (partial) — open/closed frames identical; morph vs sheet unproven | L3 |
| G11 | review | — | Review pill / sheet not exercised live | L3 N-A; code present |
| G12 | chat | 3 | §5.4/5.5/5.9 **FAIL** on tip (partial activity only; no bg-tasks pill; no mid-run queue / permission pill) — L2 re-dispatch blocked by sim contention | L2 |
| G13 | thread list | 2 | Thread-list rows + filters (#121/#134) **BLOCKED** (simctl/idb hang) | L3 |
| G14 | ops | — | Disk budget FAIL (40 worktrees outside approved root); tip-built lancerd ≠ resident binary | preflight |

---

## MVP pieces 1–6 map

| # | Piece | Audit verdict |
|---|---|---|
| 1 | Pairing + trusted machines | Sim PASS (with orphan/race caveats). Device re-pair **owner-gated**. |
| 2 | Thread list / needs-you-first | Partial — repo counts work; Agents unreliable; filters N-A. |
| 3 | Chat multi-turn + inline approval | Multi-turn PASS on sim. Inline card not screenshot (DEBUG auto-approve). Wall-of-prose P1. |
| 4 | Composer | Pill works; mic FAIL; morph PARTIAL. |
| 5 | Push + lock-screen approve | **BLOCKED** — L6. |
| 6 | Emergency stop | **FAIL on tip Settings** — deferred/absent. |

---

## Not bugs (accepted limitations)

- Siri live-execution device-only (§5.6).
- Emergency Stop stop-only / no in-app re-enable **when present** (§4) — moot until UI exists on tip.
- PR actions disabled without daemon RPC (§5.3).
- DEBUG seams / XCUITest required on this Mac (HID/idb flaky).

---

## Lane file index

- `L1-core-loop.md` — §3 PASS (hook functional)
- `L2-chat-transcript.md` — P0 B partial; §5.4/5.5/5.9 N-A
- `L3-shell-chrome.md` — mic FAIL; onboarding blank; Workspaces partial
- `L4-governance.md` — #135 deferred/absent on tip
- `L6-device-pass.md` — **BLOCKED** (owner re-pair)
- `screenshots/` — L1-* primary; L2/L3/L4 supporting
