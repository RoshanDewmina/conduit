# Fable Orchestration Brief — Cleanup + Roadmap (Parallel)

**For Milroy** — read Part 1, attach screenshots, then paste Part 2 into Claude Code (`--model fable` or `claude-fable-5-thinking-high` in cursor-agent terms). Full plan context: [`.cursor/plans/fable_cleanup_orchestration_brief_ef922476.plan.md`](../../.cursor/plans/fable_cleanup_orchestration_brief_ef922476.plan.md).

Verified on this machine **2026-07-08 ~14:30 local**: `cursor-agent` at `/Users/roshansilva/.local/bin/cursor-agent`, `main` at `3a664899` (PR #38 I1 merged). Open PRs: **#41** I2, **#43** I3, **#45** E3.

---

## Part 1 — Milroy pre-flight

### Attach before sending

- Design screenshots (visual source of truth for rebuild)
- Fill in the screen list in Part 2 Phase A3: suggested **Home / Workspaces**, **Work Thread**, **Review**, **Composer**, **Receipt card**, **Question card**, **Proof Reel** — edit to match what you attach

### Session ID correction

| You may have saved | Actual conversation | Transcript |
|---|---|---|
| `6c73825b` (generation id) | `96657fd6-6db9-4879-a5f5-45c073fcf4d5` | `~/.cursor/projects/Users-roshansilva-Documents-command-center/agent-transcripts/96657fd6-.../96657fd6....jsonl` |
| `d894d183` (generation id) | `83d15474-5214-4576-8832-e3d20d476dcd` | `~/.cursor/.../83d15474.../83d15474....jsonl` |
| (also include) | `153c7ce1-2f5b-4e09-a106-d214664cfcb8` | `~/.cursor/.../153c7ce1.../153c7ce1....jsonl` |
| `afab6d27` | Claude Code | `~/.claude/projects/...-lancer-orchestration-cont-a4f530/afab6d27....jsonl` |
| "Continue code session" | `511c29bb-9d4a-40eb-9632-093547d6744c` | `~/.claude/projects/...-lancer-ios-orchestration-f491ad/511c29bb....jsonl` |

### Model filter (subagents)

Subagents dispatched via `cursor-agent` must use **`claude-sonnet-5-high` only** (display: "Sonnet 5 1M"). Do not use `claude-sonnet-5-xhigh`, `-max`, `-thinking-*`, `claude-opus-*`, `claude-fable-*`, `composer-2.5`, or gpt/codex models. Fable itself runs in **Claude Code Fable 5** (orchestrator only — not a `cursor-agent` slug).

### cursor-agent canary (run once before first dispatch)

```bash
cursor-agent --list-models | rg 'claude-sonnet-5-high|claude-sonnet-5'
cursor-agent status    # auth check
```

**Latency (verified 2026-07-08):** `cursor-agent -p` on a trivial echo prompt took **~82s** and returned `canary-ok` (exit 0). Slow startup, not a hang — but budget ~90s+ per headless dispatch or use interactive mode for tight loops. If a run exceeds ~10 min with no output, kill and retry once. Docs: [cursor.com/docs/cli/headless](https://cursor.com/docs/cli/headless), [cursor.com/docs/cli/reference/parameters](https://cursor.com/docs/cli/reference/parameters).

---

## Part 2 — Paste into Fable (below =====)

```
=====

You are Fable 5, top-level orchestrator for Lancer. You **plan, verify, and delegate** — you do not type application code except trivial one-line doc fixes. Implementation routes through **`cursor-agent` CLI** on this Mac (`/Users/roshansilva/.local/bin/cursor-agent`), from repo `/Users/roshansilva/Documents/command-center`.

**Your job is to figure out the plan.** This brief gives context, constraints, and tooling — not a step-by-step script. Decompose into lanes, write subagent prompts, verify acceptance yourself.

## 0. Read order (before dispatch)

Re-verify live repo over every doc (`git log -5`, `git status`, `gh pr list`).

1. **Prior sessions** — skim transcripts; capture original prompts + outcomes (paths in Part 1 table + appendix below)
2. **Roadmap specs (you authored):**
   - `docs/plans/2026-07-07-lancer-build-sequence-and-hands-free-layer.md`
   - `docs/plans/2026-07-07-lancer-layers-0-3-implementation-spec.md`
   - `docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md`
3. **Operating rules:** `docs/plans/2026-07-07-fable-cursor-orchestration-prompt.md`
4. **Repo contract:** `AGENTS.md` → `ARCHITECTURE.md` §0.1 + §4.1 → `docs/AGENT_READ_FIRST.md` → `docs/STATUS_LEDGER.md`
5. **Handoff:** `.cursor/plans/resume_lancer_orchestration_e03e2e52.plan.md`
6. **Memory:** `~/.claude/projects/-Users-roshansilva-Documents-command-center/memory/project_layer4_phase1_landed_2026-07-08.md`
7. **Screenshots** attached to this message — visual source of truth for rebuild. Missing screen → stop and ask Milroy.

**Live state at brief write (re-check):** `main` ≈ `3a664899`; #38 I1 merged; open **#41, #43, #45**; D0.2 checkpoint **5c FAILED** (`docs/test-runs/2026-07-08-tier0-device-proof-results.md`).

## 1. Mandate — two parallel tracks (separate worktrees)

Never two subagents on the same file.

### Track A — Cleanup + design rebuild

**Goal:** Remove dead/legacy UI and files that confuse humans and models; rebuild Cursor-shell components from attached screenshots.

**A1 Audit** — dispatch 2–3 **read-only** `claude-sonnet-5-high` cursor-agent subagents (`--mode plan` or explicit read-only prompt), disjoint slices:

| Slice | Focus |
|---|---|
| AppFeature (non-CursorStyle) | Vestigial `AppRoot` paths, `LANCER_DAEMON_E2E` / `LANCER_DESTINATION` seams |
| SessionFeature + DesignSystem | `DarkTranscriptComponents`, old card chrome on Receipt/Question/ProofReel |
| Docs + tests + scripts | Stale sidebar/Command Home/tab bar refs; duplicate plans |

Output: deletion/replacement table (path, why legacy, importers, action: delete | migrate | replace). Cross-check `LancerUITests/LegacyUIRemovalTests.swift`, `ARCHITECTURE.md` §4.1.

**A2 Delete** — `claude-sonnet-5-high` subagents; aggressive (owner-approved): unreachable legacy files, dead DEBUG seams, stale IA docs. Migrate live call sites to CursorStyle first. **Accept:** `swift build` in LancerKit + app-target build + `LegacyUIRemovalTests` + `CursorAppShellExhaustiveTests` green — paste output.

**A3 Rebuild** — `claude-sonnet-5-high` subagents; `AppFeature/CursorStyle/` + `SessionFeature/Chat/`; DesignSystem tokens; wire only via `CursorAppShell`. Screens: **[OWNER: list from attached screenshots]**. **Accept:** exhaustive-test case + screenshot in `docs/test-runs/` per surface.

Worktrees: `.worktrees/cleanup-audit` → `cleanup-delete` → `cleanup-rebuild` (A1 parallel; then serial A2→A3).

### Track B — Roadmap + P0 (parallel to A)

| Lane | Work | Model |
|---|---|---|
| B-P0 | Fix checkpoint **5c** — lock-screen approve, app closed/backgrounded. Phone UX OK; host got no decision. Read `docs/test-runs/2026-07-08-tier0-device-proof-results.md`, `docs/LIVE_LOOP_RUNBOOK.md` Phase 5c. | `claude-sonnet-5-high` |
| B-PR | Verify + merge/stack **#41, #43, #45** (re-check `gh pr list`) | You verify each |
| B-EXIT | Layer 4 exit bar: `go test ./...`, `swift test`, exhaustive UI tests, extended `relay-approval-e2e.sh`, dual-SDK app build | You run |

**B-P0 constraints:** Do not reinstall to owner's iPhone without asking. D0.2 re-run is interactive — you prepare, Milroy taps.

## 2. Reference — cursor-agent CLI (verified slugs)

Run `cursor-agent --list-models` before first dispatch; slugs drift.

| Tier | Slug | Use |
|---|---|---|
| Default | `claude-sonnet-5-high` | All implementation: mechanical work, UI from screenshots, wiring, table-driven tests |
| Hard | `claude-sonnet-5-high` | Same slug — 5c relay/security, widget-extension boundary, architecture, retry after fail |
| You | Fable 5 in Claude Code | Orchestrator only (not `cursor-agent`): planning, prompts, verification, conflict resolution |

**Subagents:** `claude-sonnet-5-high` only. Do not use `claude-sonnet-5-xhigh`, `-max`, `-thinking-*`, `claude-opus-*`, `claude-fable-*`, `composer-2.5`, or gpt/codex models.

**Dispatch patterns** (from [Cursor headless docs](https://cursor.com/docs/cli/headless)):

```bash
# Worktree
git fetch origin && git worktree add .worktrees/<lane> -b spec/<lane> origin/main

# Headless (if -p doesn't hang)
cursor-agent -p --force \
  --model claude-sonnet-5-high \
  --workspace /Users/roshansilva/Documents/command-center \
  --output-format json \
  "TASK: <id>
   WORKTREE: .worktrees/<lane>
   WRITE-SET: <exclusive files>
   SPEC: <verbatim>
   ACCEPT: <command — run and paste output>
   RULES: AGENTS.md; no approve Siri intent; no Face ID; Cursor shell only"

# If -p hangs: interactive in lane worktree
cd .worktrees/<lane> && cursor-agent --model claude-sonnet-5-high

# Timeout wrapper (macOS: brew install coreutils)
gtimeout 900 cursor-agent -p --force --model claude-sonnet-5-high --output-format json "..."
```

**Flags that matter:** `-p` print/headless; `--force` / `--yolo` allow file writes in scripts; `--workspace` pin cwd; `--output-format json|stream-json`; `--mode plan` read-only planning; `--list-models`; `cursor-agent status` for auth.

**Every subagent prompt must include:** exact write-set, spec excerpt, acceptance command verbatim, instruction to paste real command output before claiming done.

## 3. Orchestration discipline (don't re-derive)

- **You are expensive** — delegate implementation; re-run acceptance yourself; subagent "done" is a claim ([AGENTS.md](AGENTS.md) audit failure mode).
- **Disjoint write-sets** — one worktree per lane; never `cp` whole files across worktrees (diff/rebase only).
- **Scoped deviation:** This run uses cursor-agent, not Claude Code `Agent` tool — per Milroy; don't edit `CLAUDE.md` to make it default.
- **Navigation truth:** Cursor shell (`AppFeature/CursorStyle/`) only — not tab bar, not sidebar (`LegacyUIRemovalTests` guards).
- **Security:** No Siri approve intent ever; fail-closed; no Face ID (removed 2026-07-07); high-risk actions in-app only.
- **Stop and ask Milroy:** missing acceptance command; two failed attempts same bar; missing screenshot for a surface; PR merge conflict; Layer scope change.

## 4. Done bar (this session)

**Track A:** audit table delivered; legacy removed; screenshot-aligned components merged; `LegacyUIRemovalTests` green.

**Track B:** 5c root-caused + fix PR (or documented blocker); #41/#43/#45 merged or rescoped; Layer 4 exit bar run with honest gaps (iOS 26 sim may be unavailable — only Xcode-beta/iOS 27 on this Mac).

**Both:** `main` app-target build clean. Update `STATUS_LEDGER` / `PUBLISH_READINESS_CHECKLIST` only if facts changed.

Report at lane boundaries: shipped files/PRs, acceptance output verbatim, Sonnet 5 High vs Fable tally.
```

---

## Part 3 — Session appendix (skimmable)

**96657fd6** — Resumed crashed Fable orchestration after credit limit. Original: continue `afab6d27` + "Continue code session" (`511c29bb`). Later: diagnose slow Xcode builds; merge PR stack; run exit bar. Generation `6c73825b` = "Sure go ahead and merge and then lets do whatever is left."

**83d15474** — Interactive D0.2 owner device proof. Original: run Tier 0 checklist with owner on physical iPhone. Outcome: steps 0–5 partial pass; **5c lock-screen approve FAILED** (host no decision). Later: "Are we not going to test dynamic island and live activities?" Results: `docs/test-runs/2026-07-08-tier0-device-proof-results.md`.

**153c7ce1** — Turned Fable specs into localhost HTML artifacts. Then: "Lets get started with parallel lane worktrees… only Composer 2.5" — kicked off Layers 0–3 implementation lanes.

**afab6d27** — Fable continues after L0–3 merged. Dispatched L0 leftovers (A4, D2, D3, DL) + I1 Siri Phase 2; verified PR train; hit credit limits on Wave 2.

**511c29bb** ("Continue code session") — Resumed `afab6d27`; landed PRs #34–#38; dispatched Wave 2 (E1, G, H1, I2) before credit limit. Memory: `project_layer4_phase1_landed_2026-07-08.md`.

---

## cursor-agent canary result (2026-07-08)

`cursor-agent --list-models` — **OK**. Subagent slug confirmed: `claude-sonnet-5-high` (display: "Sonnet 5 1M"). Fable orchestrator runs in Claude Code Fable 5 — not via `cursor-agent`.

`cursor-agent -p --model claude-sonnet-5-high` on trivial echo prompt — **completed in ~82s**, output `canary-ok`, exit 0. Canary may use the same `claude-sonnet-5-high` slug as production dispatches. Slow cold start; Fable should budget ≥90s per `-p` dispatch or use interactive mode for many short tasks.
