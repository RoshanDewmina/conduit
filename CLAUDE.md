# CLAUDE.md — Conduit iOS codebase guide

@AGENTS.md

The shared, cross-agent contract — what Conduit is, the source-of-truth docs, the working rules,
and the verification gate — is imported above from `AGENTS.md`. This file adds only the
Claude-specific execution model and tooling. For product truth read `ARCHITECTURE.md` **§0.1**
(current-state snapshot: implemented / partial / planned / deprecated) and **§4.1** (navigation):
the app home is a **sidebar / Command Home shell** with durable chat threads, **not** a tab bar
(`enum Tab` in `AppRoot.swift` is vestigial). `docs/CONDUIT_PROJECT_DOSSIER.md` is archived — don't cite it.

## Path-scoped rules & skills

Area-specific detail lives in `.claude/rules/` and loads only when you open a matching file:

- `ios-ui-and-gallery.md` — gallery harness, screenshots, design system (AppFeature / DesignSystem)
- `terminal-blocks.md` — unified-PTY → BlockRenderer pipeline + invariants (SessionFeature / TerminalEngine)
- `go-daemon.md` — Go build/test + `dispatch.go` adapter rules (daemon/**)

Project **skills** are in `.claude/skills/` (invoke with the `Skill` tool): start a non-trivial
task with `conduit-context-onboarding`; gate "done" with `conduit-verification-gate`; touching
`daemon/conduitd/dispatch.go` → `vendor-cli-adapter-audit`; parallel work → `conduit-parallel-handoff`.

## Execution model — Claude plans & verifies, opencode/deepseek executes

**Owner's standing directive (2026-06-16):** in this repo Claude does the *thinking* — planning,
decomposition, precise specs, and verification — and delegates *code/file edits* to opencode
`deepseek-v4-flash` agents. **Default to NOT editing source yourself; dispatch instead.** (Meta /
config / planning-doc edits the owner asks Claude to make directly — like this file — are done by Claude.)

```bash
opencode run -m openrouter/deepseek/deepseek-v4-flash --variant high --dir "<dir>" "<precise prompt>"
```

Use the **paid** OpenRouter `deepseek-v4-flash`, not `opencode/deepseek-v4-flash-free` (the free
tier hangs indefinitely on concurrent dispatch). `--dangerously-skip-permissions` is **not** a
valid flag on the installed opencode (1.17.7) — omit it. Run via `Bash run_in_background` for
concurrency; spell out exact files, boundaries, and acceptance checks (deepseek is a weak executor).

**Be aggressive about parallelism.** The one hard rule: parallel agents must not write the same
files — isolate by a distinct output file per agent, or a separate branch/worktree on a shared tree.

**Always verify — never trust deepseek output blind.** Re-run the authoritative gate yourself
(see "Verify before claiming done" in `AGENTS.md`) and re-dispatch with corrections on any failure.

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
