# Fable brief — vendor CLI adapter parity + Orca-inspired account/usage view

**Prepared:** 2026-07-18, by a Sonnet 5 device-testing session, after three parallel research
passes (Lancer's own adapter code, `research-repos/opencode` + `research-repos/pi` fresh
clones, `research-repos/orca`). This file is the paste-ready brief; copy the block below to
Fable. Kept here as a durable record since it's long enough to be worth citing later.

---

## PASTE THIS

You are Fable 5, orchestrating this session per `docs/ENGINEERING_PROCESS.md`. Use the
`swarm-orchestrator` skill for execution (frugal token routing — Cursor CLI Grok 4.5 high /
Composer 2.5 as primary coders, Sonnet 5 high as fallback + sensitive-path reviewer only) and
the `lancer-verification-gate` skill as the acceptance check for every phase before calling it
done. Read `AGENTS.md`, `CLAUDE.md`, `docs/agent-contract.md`, and
`.claude/skills/vendor-cli-adapter-audit/` (the full skill, not just its matrix doc) before
starting anything.

Repo: `/Volumes/LancerDev/lancer`. Current `origin/master` tip: `69a6f490` (2026-07-17). A prior
session left the branch `cursor/desktop-history-and-terminal-3510` with device-testing fixes
uncommitted in a worktree at `/Volumes/LancerDev/worktrees/lancer/device-build` — that work is
unrelated to this brief; do not touch it, and re-verify current master tip yourself before
starting (it may have moved).

### Why this brief exists

The owner asked for full vendor-CLI parity (Codex, OpenCode, Kimi Code, Pi — all "100%
functional like Claude Code") plus an Orca-inspired multi-account usage/switching view. Three
research passes already happened this session so you don't have to re-derive them — cite the
findings below, verify anything load-bearing yourself before building on it (CLI flags
especially — `vendor-cli-adapter-audit`'s discipline applies), but don't re-run the research.

### Research finding 1 — Lancer's current per-vendor adapter gap (verified against live source this session)

`daemon/lancerd/dispatch.go`'s `agentArgv`/`continueArgv`/`resumeArgv` switches (lines
121-190, 196-240, 260-304) actually route four vendors: `claudeCode`, `codex`, `kimi`,
`opencode`. `agent_registry.go:18-28` also normalizes `cursor`/`gemini`/`copilot` as known ids
but none hit a case in any argv builder — placeholders only, not real vendors. **Pi is absent
everywhere** — zero hits for `earendil`/`pi-coding-agent`, no case anywhere — a from-scratch
vendor add.

Gap matrix, Claude Code = 100% baseline:

| Capability | Claude Code | Codex | OpenCode | Kimi Code | Pi |
|---|---|---|---|---|---|
| Transcript → `SessionMessage` | Full (`claude_transcript_adapter.go:205-316`) | Full (`codex_session_reader.go:191-230`) | Full (`opencode_session_reader.go:136-173`) | Full (`kimi_session_reader.go:130-210`) | **None — no reader file** |
| Live-status streaming (tool/thinking/streaming events mid-run) | Full (`dispatch.go:1144-1168`) | Partial — tool+streaming, no thinking (`dispatch.go:1315,1326,994`) | Partial — tool+streaming, no thinking (`dispatch.go:1278,1304`) | **None** — role-based branch (`dispatch.go:1348-1360`) emits raw text only, calls no `emitLiveStatus*` | N/A, vendor doesn't exist |
| Resume/continue | `--continue`/`--resume <id>`, live-verified 2026-06-30 | `exec resume --last`/`<id>`, live-verified 2026-06-30 | `run --continue`/`--session <id>`, live-verified 2026-06-30 | Flags built (`dispatch.go:225-230,289-294`) but **explicitly not live-smoke-tested** — doc comment at `dispatch.go:257-259` warns Kimi CLI hit a billing check before stdout, "re-verify before relying on it in production" | None built |
| Approval/permission hook | Installed + wired (`hook_install.go`, 263 lines; `claudeHookWired`, `server.go:625-636`) | **None** — `hookWiredForAgent`'s `default:` returns false (`server.go:632-634`, comment: "Codex/Kimi have no per-action hook, so those stay fail-closed"); an unwired `docs/codex-hooks.json` draft exists with zero `daemon/lancerd/*.go` references | Installed + wired (`opencode_hook.go` + `opencode_plugin_install.go`, `tool.execute.before` plugin) | **None** — same fail-closed default, no draft even exists | None |
| CLI verification in `doctor.go`'s `checkAgentCLIs` | Present | Present | Present | **Omitted from the list** (`doctor.go:229`) despite being in `agentBinaries`/`installedAgents()` — an internal inconsistency | Not present; skill's own matrix doc is a month stale |

**Net read, in priority order:** Codex and Kimi are permanently fail-closed on per-action
approval — every tool call from either escalates through a coarser launch-time gate instead of
a per-tool hook. **This is a correctness/security gap, not a parity nice-to-have** — fix it
first. Kimi is furthest behind overall (no live status, unverified resume, no hook, doctor
blind spot). Pi is a from-scratch build on every axis.

### Research finding 2 — OpenCode and Pi CLI formats (fresh clones this session, gitignored, never commit into Lancer's history)

Both cloned at `research-repos/opencode` and `research-repos/pi`. Re-verify anything below
against the actual installed binaries per the vendor-cli-adapter-audit skill before wiring —
this is what a clone told us today, not a live-tested contract.

**OpenCode (`sst/opencode`).** Session storage is **SQLite**, not flat files — DB at
`Global.Path.data/opencode.db` (`packages/core/src/global.ts:10-21`, base dir
`~/.local/share/opencode`), Drizzle tables in `packages/core/src/session/sql.ts`:
`SessionTable`, `MessageTable` (one row/message, JSON blob), `PartTable` (one row/part, FK to
message). Headless: `opencode run [msg] --format json` streams one JSON object per line to
stdout (`packages/opencode/src/cli/cmd/run.ts:678-691`); event types `tool_use`, `step_start`,
`step_finish`, `text`, `reasoning`, `error`. `opencode serve` starts a headless HTTP server with
a full OpenAPI spec + generated TS SDK — the CLI itself is just an SSE client
(`sdk.event.subscribe()` → `message.updated`/`message.part.updated`). Resume:
`--continue`/`-c` (most recent root session), `--session <id>`/`-s`, `--fork` (requires `-c` or
`-s`).

**OpenCode's plugin/hook system is directly relevant to closing the Codex/Kimi approval gap
conceptually** (`packages/plugin/src/index.ts:76`): `Hooks` includes
`"permission.ask"?: (input, output: {status: "ask"|"deny"|"allow"}) => Promise<void>` (line
261 — the pre-execution approval callback), `"tool.execute.before"` (266-269, can mutate args
or throw to veto), `"tool.execute.after"` (274-281). This is Lancer's OWN existing
`opencode_hook.go`/`opencode_plugin_install.go` mechanism already using this — confirms the
pattern works and is the reference implementation for Phase 2's Codex-hook work below.

**Pi (`earendil-works/pi`, package `@earendil-works/pi-coding-agent`, bin `pi`).** Session
storage: JSONL at `~/.pi/agent/sessions/--<sanitized-cwd>--/<ISO-timestamp>_<sessionId>.jsonl`
(`packages/coding-agent/src/core/session-manager.ts:469-474,884`; overridable via
`--session-dir`/`PI_CODING_AGENT_SESSION_DIR`). First line is a `SessionHeader{type:"session",
id,timestamp,cwd,parentSession}`; rest are `SessionEntry{type:"message",message:AgentMessage}`.
`AgentMessage` shapes (`packages/ai/src/types.ts:327-417`):
`UserMessage{role:"user",content}`;
`AssistantMessage{role:"assistant",content:(TextContent|ThinkingContent|ToolCall)[]}` where
`ToolCall{type:"toolCall",id,name,arguments}`,
`ThinkingContent{type:"thinking",thinking,thinkingSignature?}`;
`ToolResultMessage{role:"toolResult",toolCallId,toolName,content,isError}`.

Headless modes: `--print`/`-p` (text) and **`--mode json`** (event stream, one
`JSON.stringify(event)` per line via `session.subscribe()`) — `AgentEvent` union
(`packages/agent/src/types.ts:415-430`): `agent_start`, `agent_end`, `turn_start`, `turn_end`,
`message_start/update/end`, `tool_execution_start/update/end{toolCallId,toolName,args,result,
isError}`. There's also **`--mode rpc`**: true JSON-RPC over stdin/stdout
(`modes/rpc/rpc-types.ts:1-72`) with commands `prompt`, `steer`, `abort`, `get_state`,
`set_model`, `compact`, `bash`, `fork`, `get_entries`, `get_tree`. Resume:
`-c`/`--continue` (most recent), `-r`/`--resume` (interactive picker — not usable headless),
`--session <id|path>`, `--session-id <id>` (open-or-create), `--fork <id|path>`.

Pi's hook system: `.pi/extensions/*.ts` exporting `default function(pi: ExtensionAPI)`;
`on(event:"tool_call", handler)` where `ToolCallEvent{toolCallId,toolName,input}` has a
mutable `input` and returning `{block?, reason?}` cancels the call pre-execution; paired
`on("tool_result", ...)` for post-execution. `packages/agent/docs/hooks.md` documents a
broader forthcoming `AgentHarnessHooks` abstraction with the same block/reason semantics —
worth checking if it's landed by the time you build this, it may be the better integration
point than the extension API.

**Decide, don't assume:** for Pi's approval hook, evaluate `.pi/extensions/` tool_call
interception vs. `--mode rpc`'s `steer`/`abort` commands against Lancer's existing
PreToolUse-hook architecture (`hook_install.go`, `agent-hook` CLI subcommand,
`docs/lancer-hook.sh`) before picking one — they're architecturally different (in-process
extension vs. out-of-process RPC control) and the choice affects how much of the existing hook
plumbing can be reused.

### Research finding 3 — Orca's account/usage patterns (`research-repos/orca`, MIT licensed, Copyright 2026 Lovecast Inc — verbatim-portable with attribution)

**Account model:** per-vendor account list, UUID-keyed. `ClaudeManagedAccount`
(`src/main/claude-accounts/service.ts:87-181`) — `{id, email, authMethod, organizationUuid/
Name, managedAuthPath, timestamps}`, stored in `settings.claudeManagedAccounts`. Parallel
`src/main/codex-accounts/service.ts` (1041 lines, same shape). Per-runtime selection state
(`src/main/claude-accounts/runtime-selection.ts:1-42`) — `{host: accountId|null, wsl: {...}}`.

**⚠️ CONFIRMED FINDING, checked twice this session with independent broad greps (round-robin,
load-balance, spread/distribute, rotate, pool, weighted, least-used, `nextAccount`,
`pickBest`, `onRateLimit`, `autoSwitch`, "evenly", "balance" — across `src/main` and the
account-service/rate-limit files specifically): Orca has NO automatic or load-spreading
account switching. None. The owner initially believed otherwise and asked for a re-check;
the re-check confirms the original finding.** `selectAccount`/`selectAccountForTarget`
(`service.ts:114-123`) are only ever called from a manual UI click handler
(`AccountsPane.tsx:683`, `runClaudeAccountAction`). After a switch,
`RateLimitService.refreshForClaudeAccountChange` (`rate-limits/service.ts:368-388`) only
re-displays usage for the account just picked — it never decides which account to pick. There
is a live-session-safety guard (`live-pty-gate.ts`) and a restart-nudge toast
(`AccountsPane.tsx:697-717`), but no auto-restart or auto-reroute of in-flight work. **Do not
build automatic/rate-limit-triggered account rotation** — it isn't Orca precedent, it would be
new unscoped decision-engine logic, and the owner didn't ask for it once this was clarified.
Build the manual switcher; that's the real, portable, validated pattern.

**Usage tracking**, two local/vendor-direct sources: (a) token/turn/cost — parses local Claude
Code CLI transcript JSONL from `~/.claude/projects`
(`src/main/claude-usage/scanner.ts:46`), aggregated per day/project/worktree
(`claude-usage/types.ts:20-50`); Codex has an analogous scanner. (b) rate-limit/cap status —
direct HTTPS to Anthropic's own OAuth usage endpoint
(`OAUTH_USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'`,
`rate-limits/claude-fetcher.ts:47`) with a hidden-PTY fallback. **Lancer should NOT build a
parallel local-file usage scanner** — the vendor session-reader files audited in finding 1
already parse token/tool data per vendor for the transcript pipeline; reuse that plumbing for
usage display instead of re-deriving it Orca-style.

**Credential storage**: macOS Keychain via shelled-out `security` CLI
(`src/main/claude-accounts/keychain.ts:1-100`) — two service namespaces, the CLI's own active
credential (`'Claude Code-credentials'`, optionally suffixed by a config-dir hash — **confirmed
live on the owner's own Mac this session**, this exact naming is real) and Orca's managed
per-account stash (`'Orca Claude Code Managed Credentials'`, keyed by `accountId`). **Port the
CONCEPT, not the code** — Lancer is Swift/iOS, not Electron/Node, so use `SecurityKit`'s native
`SecItem` API directly (`kSecAttrAccount`/`kSecAttrService` per managed account, proper
access-control flags) instead of shelling out to anything. The owner separately had a small
personal shell script built this session (`~/bin/claude-account`, outside this repo, not
Lancer code, do not touch it) that proves this exact Keychain-swap mechanism works against the
real `Claude Code-credentials` item — useful as a working reference for the concept, not code
to port.

**UI reference files** (for later SwiftUI porting, read for pattern only — this is a very
different tech stack): `src/renderer/src/components/settings/AccountsPane.tsx` (1835 lines,
full settings screen), `feature-wall/agents-orchestration/UsageAccountsCard.tsx` (compact
per-vendor connected/disconnected card), `status-bar/StatusBar.tsx` +
`StatusBarUsageEmptyCta.tsx` (persistent usage indicator), `CodexRestartChip.tsx`
(post-switch restart-safety chip).

### Phases — execute in order, each independently mergeable, each gated by `lancer-verification-gate` before moving on

**Phase 0 — refresh the stale map.** `.claude/skills/vendor-cli-adapter-audit/
references/vendor-cli-matrix.md` is a month stale. Re-run its own `which`/`--version`/`--help`
discipline against every installed CLI (claude, codex, opencode, kimi, and check whether `pi`
is installed on this machine at all) before touching any dispatch code, and update the matrix
doc as this phase's sole deliverable. This is cheap and catches drift before it wastes work in
later phases.

**Phase 1 — correctness fixes (do this before any parity/feature work).** Wire a real
per-action approval hook for Codex and Kimi, closing the fail-closed gap in
`hookWiredForAgent` (`server.go:632-634`). For Codex: the unwired `docs/codex-hooks.json` /
`docs/codex-lancer-hook.sh` draft may already have the right shape — audit it against Codex's
actual current hook/plugin capability (verify via `codex --help`, don't assume the draft is
still accurate) before wiring it in. For Kimi: no draft exists, design one from scratch,
referencing OpenCode's already-working `opencode_hook.go`/`opencode_plugin_install.go` as the
Lancer-side integration pattern to mirror. Also: live-smoke-test Kimi's resume path (currently
flagged unverified — `dispatch.go:257-259`) and fix `doctor.go`'s `checkAgentCLIs` list to
include Kimi. This phase touches `dispatch.go`, `hook_install.go`, `server.go` — sensitive
paths per `AGENTS.md`, full-diff review required, no routine auto-merge.

**Phase 2 — Codex/OpenCode/Kimi full live-status parity.** Add thinking-state streaming for
Codex and OpenCode (both currently emit tool+streaming but not thinking). Add full live-status
streaming for Kimi (currently emits raw text only) — same `emitLiveStatusThinking/Streaming/
Tool` family Claude Code's branch already uses (`dispatch.go:1144-1168`), applied to Kimi's
stream-parsing branch. Verify against Kimi's actual JSON stream shape live, don't assume
symmetry with Claude's shape.

**Phase 3 — Pi adapter, from scratch.** In order: (a) transcript reader parsing Pi's JSONL
session format (finding 2 above has the exact schema) into Lancer's neutral `SessionMessage`
struct, mirroring the existing four `*_session_reader.go`/`*_transcript_adapter.go` files'
structure; (b) live-status streaming via `--mode json`'s `AgentEvent` stream; (c) resume via
`-c`/`--session`/`--fork`; (d) the approval hook, per the decision made in finding 2's "decide,
don't assume" note; (e) `doctor.go` CLI verification entry. Each sub-step should be its own
small PR per the swarm-orchestrator's disjoint-write-set discipline, not one giant Pi commit.

**Phase 4 — Orca-inspired account/usage view (iOS side).** Only start after phases 1-3 are
merged (this phase is additive UI, not corrective, and has no reason to block or race the
daemon-side work). Build: (a) a per-vendor account model backed by `SecurityKit`'s native
Keychain API (not the Orca TS code, not a `security` CLI shell-out — this is iOS-native); (b) a
**manual** account switcher UI, modeled on `AccountsPane.tsx`'s pattern (list, add/
reauthenticate/remove/select, a restart-safety notice if a live session is active) — explicitly
NOT automatic/load-balanced switching, per the confirmed research finding above; (c) a usage
display sourced from Lancer's own existing per-vendor session-reader token/tool data (finding 1
files), not a new Orca-style local-file scanner. UI reference files are listed in finding 3
above — port the pattern, write fresh SwiftUI.

### Constraints (apply throughout)

- Every phase gets a `lancer-verification-gate` pass before being called done — LancerKit
  `swift build`/`swift test` for iOS-side work, `go build ./... && go vet ./... && go test
  ./...` from `daemon/lancerd` for daemon-side work, and the app-target `XcodeBuildMCP` build
  for anything touching `#if os(iOS)` files (plain SPM `swift build` silently skips those —
  see `CLAUDE.md` "Tooling gotchas").
- `dispatch.go`, `hook_install.go`, and any new hook-wiring code are sensitive paths — full-diff
  review by Sonnet/Fable, never routine Cursor auto-merge, per `AGENTS.md`.
- Never assume a CLI flag or output shape from documentation or a cloned repo's source without
  confirming against the actually-installed binary on this machine (`vendor-cli-adapter-audit`
  discipline) — CLIs drift, and the OpenCode/Pi findings above are from source reading, not
  live-execution proof.
- `research-repos/{opencode,pi,orca}` stay gitignored, read-only references — never commit
  their code into Lancer's history; port patterns and concepts, write fresh Swift/Go.
- Report back to the owner at each phase boundary with the swarm-orchestrator skill's 5-line
  digest (merged / in-flight / blocked / next / decisions-needed) backed by actual command
  output, not self-report.

### Done when

All four phases (0-4) are merged to master, each with its own gate evidence attached to the
PR/commit. Phase 1's hook fixes are live-smoke-tested against a real paired daemon (not just
unit-tested) before being called closed, since a silently-broken approval hook is a security
regression, not a cosmetic one.
