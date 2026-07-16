# CLAUDE.md — Lancer iOS codebase guide

@AGENTS.md

The shared, cross-agent contract — what Lancer is, the source-of-truth docs, the working rules,
and the verification gate — is imported above from `AGENTS.md`. This file adds only the
Claude-specific execution model and tooling.

**Before any non-trivial task:** read [`docs/AGENT_READ_FIRST.md`](docs/AGENT_READ_FIRST.md) (task read-order + standing instructions). Owner hub: [`docs/STATUS_LEDGER.md`](docs/STATUS_LEDGER.md).

For product truth read `ARCHITECTURE.md` **§0.1**
(current-state snapshot: implemented / partial / planned / deprecated) and **§4.1** (navigation):
the app home is **Workspaces** (`AppRoot.readyRoot` → `NavigationStack { WorkspacesView() }`),
**not** a tab bar (`enum Tab` in `AppRoot.swift` is vestigial). DEBUG deep-links use
`LANCER_DESTINATION`. `docs/LANCER_PROJECT_DOSSIER.md` is archived — don't cite it.

## Path-scoped rules & skills

Area-specific detail lives in `.claude/rules/` and loads only when you open a matching file:

- `ios-ui-and-gallery.md` — iOS UI/debug seams, screenshots, design system (AppFeature / DesignSystem)
- `terminal-blocks.md` — unified-PTY → BlockRenderer pipeline + invariants (SessionFeature / TerminalEngine)
- `go-daemon.md` — Go build/test + `dispatch.go` adapter rules (daemon/**)

Project **skills** are in `.claude/skills/` (invoke with the `Skill` tool): start a non-trivial
task with `lancer-context-onboarding`; gate "done" with `lancer-verification-gate`; touching
`daemon/lancerd/dispatch.go` → `vendor-cli-adapter-audit`; parallel work → `lancer-parallel-handoff`;
owner asks "what's next?" / wants a paste-ready brief → global `prompt-crafting` (`agent-brief` mode); new/fuzzy feature →
`agent-feature-loop`; tool-hop or dying context → `agent-session-handoff`.

## Execution model — Fable orchestrates, Cursor CLI codes, Sonnet 5 is fallback + sensitive paths

**Owner's standing directive (2026-07-10, supersedes 2026-07-06 tiers):** full policy in
[`docs/ENGINEERING_PROCESS.md`](docs/ENGINEERING_PROCESS.md); living orchestrator state in
[`docs/plans/orchestrator-state.md`](docs/plans/orchestrator-state.md)
(+ `swarm-orchestrator` skill). opencode/deepseek remain retired. Summary:

1. **Fable 5 (main session) orchestrates**: specs, decomposition, routing, arbitration,
   integration debugging, full-diff review of sensitive paths. Token conservation is an owner
   priority — Fable thinks, cheaper models type. (Meta/config/doc edits the owner asks for
   directly are done in-session, not dispatched.)
2. **Cursor CLI is the coder**: `agent -p "<spec>" --model <slug> --output-format json --force`
   in the task's worktree. **Grok 4.5 high** = default implementer; **Composer 2.5** =
   mechanical edits + first-pass diff-review summaries. Verify slugs with `agent models` first.
3. **Claude Sonnet 5 (high) via the `Agent` tool** only for: tasks Cursor failed twice; work
   needing repo skills / XcodeBuildMCP (simulator screenshots, UI-test evidence, device builds);
   security-sensitive implementation (`dispatch.go`, `policy/`, approval/content-hash, Security*,
   relay protocol) — which also always gets Sonnet-or-Fable full-diff review.

**When escalating to Fable, the prompt must be unambiguous and evidence-backed — never a vague
"figure this out":**

- State exactly what is being asked and the exact scope of what Fable should decide or produce.
- State exactly what blocked Opus/Sonnet already — the specific failure, ambiguity, or dead end —
  so Fable isn't repeating work that's already been tried and ruled out.
- Attach concrete evidence: exact `file:line` references, full error output or stack traces verbatim
  (not paraphrased), the exact commands run and their exact output, and any docs/specs already
  consulted. Fable should not have to re-derive context that already exists.
- State exactly what "done" looks like — a concrete, checkable bar (a passing test, a specific
  build command's clean output, a specific behavior reproduced or fixed) — not "does this seem right."

This shape (explicit ask, explicit blocker, verbatim evidence, explicit done-bar) is the Fable-brief
template — it worked well in the 2026-07-04 security-hardening brief (`e2be79fb`) and should be
reused verbatim rather than re-derived each time.

**Be aggressive about parallelism.** The one hard rule: parallel agents must not write the same
files — isolate by a distinct output file per agent, or a separate branch/worktree on a shared tree.

**Always verify — never trust subagent output blind**, at either tier. Re-run the authoritative
gate yourself (see "Verify before claiming done" in `AGENTS.md`) and re-dispatch with corrections
on any failure. A subagent's own "finished" label is not proof of completion — check its actual
`<result>` content; a result that is itself an error string (e.g. a session-limit message) means
verification never happened, not that it passed.

## Tooling gotchas

- **`AskUserQuestion` accepts at most 4 options per question.** A 5+ item list needs to be split
  across two questions, or it fails with a schema `InputValidationError` (max 4).

## MCP tooling — prefer over raw shell for Apple-platform work

`.mcp.json` (project scope, checked in) configures five servers; approve them on first launch.
Reach for them before raw `xcodebuild` / `xcrun` / shell — they return structured JSON (error
`file:line`, per-test results, view hierarchies) and don't depend on shell env propagation.

| Server | Prefix | Reach for it when |
|---|---|---|
| **XcodeBuildMCP** | `mcp__XcodeBuildMCP__*` | Build / run / test the **app target**; simulator lifecycle; install / launch; `screenshot`; UI automation; coverage; physical-device build/test + LLDB |
| **xcode** (needs Xcode.app open) | `mcp__xcode__*` | Live diagnostics, SwiftUI `RenderPreview`, Swift REPL, `GetTestList` / `RunSomeTests` |
| **apple-docs** | `mcp__apple-docs__*` | Apple framework/API + WWDC + sample code — use **before guessing** any SwiftUI / UIKit / Foundation / concurrency API |
| **context7** | `mcp__context7__*` | **Third-party** library docs (SwiftNIO, swift-crypto, Citadel) — `resolve-library-id` → `query-docs` |
| **ios-simulator** | `mcp__ios-simulator__*` | On-screen state / tap targets by accessibility tree (`ui_describe_all` / `ui_find_element`) — better than eyeballing a PNG |

- **First build/run/test of a session:** call `mcp__XcodeBuildMCP__session_show_defaults` once to
  confirm project + scheme + simulator (`session_set_defaults` if missing); then `build_run_sim`
  can be called with empty args.
- Enabled XcodeBuildMCP workflows are the `XCODEBUILDMCP_ENABLED_WORKFLOWS` list in `.mcp.json`
  (edit + restart to change). Newly-enabled tools surface via ToolSearch — no context cost until used.

## Workflow & evidence

1. **Explore → implement → verify.** Understand the code and existing patterns first (Explore /
   the onboarding skill), reuse what exists, then change, then run the gate matching the blast radius.
2. **Evidence before "done".** Never claim success from inspection. State the command and its
   output — build result, `swift test` count, `go test` pass, a screenshot path. "Should work" is not done.
3. **On compaction, preserve:** the set of modified files, the current decision/approach, pending
   work, and the latest verification result — so the next window resumes without re-deriving them.
   (A `SessionStart(compact)` hook re-injects the load-bearing facts automatically.)
