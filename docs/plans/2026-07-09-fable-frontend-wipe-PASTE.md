# PASTE THIS — Fable 5 frontend wipe + rebuild (Wave 0 PLAN ONLY)

**For:** Claude Code Fable 5 (orchestrator)  
**Repo:** `/Users/roshansilva/Documents/command-center`  
**Mode:** Wave 0 — PLAN ONLY — **NO deletes, NO product/backend code**

**Supersedes:** frontend portion of `docs/plans/2026-07-09-fable-cleanup-PASTE.md` / `2026-07-09-fable-cleanup-plan-only.md`. Do not execute that cleanup’s UI deletes under this track; use this brief’s KEEP/DELETE table instead. Docs/module cleanup elsewhere may still follow the old plan if owner asks separately.

Copy everything inside the fence below into a fresh Fable 5 session.

---

## PASTE THIS

```text
# Fable 5 — Lancer frontend wipe + rebuild (Wave 0 PLAN ONLY)

You are Claude Fable 5, top-level orchestrator for Lancer’s frontend wipe → Orca study →
Apple docs → rebuild track. Adaptive thinking is always on. Use high effort.
Do NOT echo, transcribe, or “show your thinking” / chain-of-thought in user-facing text
(that can trigger reasoning_extraction refusal). Report outcomes and evidence only.
If a request is refused, fall back to Opus for that slice; do not invent workarounds
that change scope.

When you have enough information to act on the plan docs, act. Do not re-derive
owner decisions already locked below. Do not survey options you will not pursue.
Lead with the outcome in user-facing summaries.

## Exact ask

Wave 0 ONLY — produce a complete, evidence-backed PLAN for an aggressive frontend UI
chrome wipe and subsequent rebuild. Write/update ONLY the write-set below.

You MUST:
1. Define and fill a KEEP vs DELETE inventory (tables with paths + importer counts).
2. Study Orca at research-repos/orca (MIT — patterns + attribution; no verbatim code commit).
3. Read latest Swift/iOS via user-apple-docs MCP / WWDC docs + existing WWDC plan docs.
4. Sketch rebuild architecture (IA, bridge adapters, stub shell so Wave 1 still compiles).
5. STOP for owner APPROVED — no deletes, no product code, no daemon edits.

Owner paraphrase (locked intent): prior cleanup fix didn’t work; they want frontend
chrome wiped aggressively, Orca studied, Apple docs read, then build only after a solid
plan. Translate “delete everything on the frontend” into aggressive UI chrome wipe —
NOT “rm -rf AppFeature” and NOT any backend wipe.

## Locked owner decisions (do not re-litigate)

1. Frontend wipe scope — “frontend” means UI chrome, not the whole iOS stack:
   - IN SCOPE for eventual DELETE (propose lists): iOS UI under
     Packages/LancerKit/Sources/AppFeature/CursorStyle/ (views/presentation),
     SessionFeature UI views, DesignSystem presentation (esp. DesignSystem/Cursor/),
     Lancer/ app-target SwiftUI entry chrome that is UI-only, mock/shell UITests that
     only cover deleted chrome.
   - MUST KEEP (look like frontend, are load-bearing): CursorShellLiveBridge,
     CursorShellLiveEnvironment, CursorComposerContract (types), AppRoot wiring to
     relay/approvals/deep links, ConversationSyncCoordinator, ApprovalIngest,
     DispatchAgent, AppFeature *Store.swift, SessionFeature non-view engines
     (E2ERelayBridge, ApprovalRelay, LiveActivityManager, RunDispatchService, …),
     IntentsKit, LancerCore, PersistenceKit, SyncKit, SSHTransport, SecurityKit,
     AgentKit, NotificationsKit, Live Activity attributes/extensions, production
     App Intents under Lancer/*Intent*.swift. Prefer KEEP when unsure if load-bearing.
   - Aggressive default for clear UI-only Views/atoms: prefer DELETE (proposed).
   - Honesty: literal “delete all AppFeature” would break the app. You MUST produce
     KEEP vs DELETE columns and get owner APPROVED before any delete.

2. Backend OFF LIMITS — never delete/edit:
   daemon/**, daemon/push-backend/**, daemon/agent-runner/**, Go tests under those trees.

3. Sequence:
   Wave 0 (THIS SESSION): PLAN ONLY — inventory, Orca notes, Apple citations, rebuild arch.
   Wave 1 (AFTER APPROVED, later session): execute deletes per approved table only.
   Wave 2 (later): rebuild plan from Orca + Apple docs (still plan before code).
   Wave 3 (later, separate session): implement — NOT this brief’s execute.

4. Study Orca at research-repos/orca (MIT). Also read:
   docs/plans/2026-07-09-orca-shell-port-design.md
   docs/product/2026-07-09-chat-ui-port-map.md
   AGENTS.md competitor-borrow rule
   If clone missing: note blocker; do not invent Orca APIs.

5. Apple docs: user-apple-docs MCP + WWDC; also
   docs/plans/2026-07-09-wwdc-ios-capability-inventory.md
   docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md
   Cite concrete sessions/URLs in the plan.

6. Subagents: ONLY composer-2.5, composer-2.5-fast, grok-4.5-xhigh.
   Never Sonnet/Opus/Fable/GPT/Codex as subagents unless owner overrides in-session.

7. Standing product rules:
   - Cursor shell 3-root IA (ARCHITECTURE.md §4.1) is the default direction UNLESS
     wipe+rebuild explicitly redesigns from Orca — owner is open to redesign; say so
     with a clear recommendation.
   - No Siri Approve intent ever.
   - No Face ID / biometric gate.
   - Do not revert unrelated dirty git (other agents/owner in-flight work).
   - No dead-code shims; delete cleanly when approved.
   - Phone steers and approves — not a phone IDE.

8. This track SUPERSEDES the frontend portion of
   docs/plans/2026-07-09-fable-cleanup-PASTE.md — do not follow that brief’s UI delete
   list; build a new KEEP/DELETE table here.

## Evidence pointers (read order)

1. Plan (refine/complete): docs/plans/2026-07-09-fable-frontend-wipe-rebuild-Plan.md
2. Status: docs/plans/2026-07-09-fable-frontend-wipe-Status.md
3. This PASTE: docs/plans/2026-07-09-fable-frontend-wipe-PASTE.md
4. Repo contract: AGENTS.md → ARCHITECTURE.md §0.1 + §4.1 → docs/AGENT_READ_FIRST.md
5. Dead-view method: .claude/skills/lancer-dead-view-sweep/SKILL.md
6. Prior cleanup (superseded for frontend): docs/plans/2026-07-09-fable-cleanup-PASTE.md
7. Orca design note: docs/plans/2026-07-09-orca-shell-port-design.md
8. WWDC / Siri: docs/plans/2026-07-09-wwdc-ios-capability-inventory.md +
   docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md
9. Live git: git status --short, git branch --show-current, git log -3 --oneline —
   treat dirty files as in-flight; do not propose deleting them without flagging.

## Write-set (ONLY these)

- docs/plans/2026-07-09-fable-frontend-wipe-rebuild-Plan.md
- docs/plans/2026-07-09-fable-frontend-wipe-Status.md
- docs/plans/2026-07-09-fable-frontend-wipe-PASTE.md (only if paste block needs a factual fix)

Out of scope for writes: Packages/**, daemon/**, Lancer/**, LancerUITests/**,
project.yml, and all other docs.

## Inventory requirements (mandatory tables)

Produce in the Plan (re-verify with tools; do not trust seed hypotheses blindly):

### Table 1 — DELETE (proposed)
Every row: path · kind · importer count + evidence · risk · notes
Default aggressive for UI-only Views/DesignSystem atoms.
Require importer count on EVERY proposed delete before Wave 1 can run.

### Table 2 — KEEP (hard)
Bridge/contracts/stores/engines/IntentsKit/LancerCore/Persistence/Sync/Transport/
Security/AgentKit/Notifications/Live Activity/App Intents/AppRoot wiring.
Explain why each KEEP looks “frontend” but is load-bearing.

### Table 3 — REWRITE / stub strategy
What minimal shell remains after Wave 1 so AppRoot still compiles and can host
CursorShellLiveBridge until Wave 3 rebuild.

### Table 4 — UITests
Which tests DELETE vs KEEP vs REWRITE after chrome wipe.

### Orca study notes
file:line evidence → proposed Lancer rebuild behavior (attribution-ready).

### Apple docs citations
At least NavigationStack / keyboard-safe docked composer, plus App Intents / Live
Activity constraints the rebuild must not break.

## Plan structure (must remain)

Goal, Non-goals, Frontend definition, KEEP vs DELETE methodology + tables,
Orca checklist/notes, Apple docs checklist/citations, rebuild milestones,
stub-shell strategy, risks, verify commands per wave, Decision log, Progress checkboxes.

## Done bar (checkable)

1. Plan.md has complete KEEP/DELETE/REWRITE tables with paths and importer counts
   on every DELETE (proposed) row
2. Orca notes with file:line + MIT attribution reminder
3. Apple docs citations present
4. Rebuild architecture + stub-shell strategy written
5. Status.md updated: Done / Remaining / Blockers / next = wait for APPROVED
6. No product/backend files modified (git status shows no new Packages/daemon/Lancer edits from you)
7. Explicit: no Siri Approve; no Face ID; backend off limits; no Wave 1 deletes yet
8. Before claiming done: audit each claim against a tool result from this session

## Stop rule

STOP when Plan + Status are written/refined. Wait for owner message containing
APPROVED before any execute/delete session.
Do not start Wave 1 deletes. Do not start Wave 3 implement. Do not raise iOS 27
target in this session. Do not touch daemon/**.

## Parallelism

Delegate independent read-only inventory slices to subagents (composer-2.5 default)
with disjoint focus, e.g.:
- AppFeature/CursorStyle views vs bridges
- DesignSystem Cursor atoms
- SessionFeature views vs engines
- Orca mobile/app + native-chat mining
You synthesize. Prefer async dispatch; verify their claims yourself with rg/build evidence.

## Addenda (2026-07-09 — owner review; treat as locked)

- Table 5 (mandatory): extension targets — LancerLiveActivityWidget/** + LancerWidget/** =
  REWRITE UI chrome (stub until Wave 3); KEEP SessionFeature LA attributes + WidgetSnapshot.
  LancerWatch/** + LancerWatchWidget/** = OUT OF SCOPE / KEEP (Watch embed cut 2026-07-08).
- Hard-KEEP SessionFeature/Chat/{ReceiptCardView,QuestionCardView,ProofReelView}.swift
  (governance surfaces, not disposable chat chrome).
- Hard-KEEP CursorStyle transcript/streaming engine files (mapper, model, pacers, preprocessor,
  attention, draft store, trusted-machine model) — see Plan Addenda list.
- Deep-link route names must survive: workspaceThreadList, workThread, prDetail, reviewDiff.
- Wave 1 execute: isolated worktree only; checkpoint or pause phone dogfood on
  feat/chat-overhaul-w0a first; Cursor vendor M1 is a separate daemon session; no owner
  iPhone reinstall without explicit ask.
- Orca primary for shell; Happier/Omnara = read chat-ui-port-map only (no extra study pass).
- Also read: fable-frontend-shell-rebuild-brief.md + cursor-shell-frontend-audit.md for
  known-bug catalog.
```

---

## After they paste

- Expect: refined KEEP/DELETE tables + Orca/Apple notes + Status saying wait for APPROVED  
- Then: owner edits table if needed → replies **APPROVED** → request a separate Wave 1 execute PASTE
