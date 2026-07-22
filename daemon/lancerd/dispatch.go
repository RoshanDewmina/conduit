package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// expandHome resolves a leading "~" (or "~/...") to the user's home directory.
// exec.Cmd.Dir does not expand "~", so a dispatched run with cwd "~" would fail
// to chdir; resolve it here. An empty cwd is left empty (inherits the daemon's).
func expandHome(cwd string) string {
	if cwd == "~" || strings.HasPrefix(cwd, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(cwd, "~"))
		}
	}
	return cwd
}

// resolveDispatchCWD expands "~" then insists the directory exists. A relative
// or missing Dir makes Darwin's exec report
// `fork/exec <claude>: no such file or directory` even when the binary is
// present — which the phone previously surfaced as a hung "Starting…"
// (2026-07-09). Return a clear error instead of launching.
func resolveDispatchCWD(cwd string) (string, error) {
	resolved := expandHome(cwd)
	if resolved == "" {
		return "", nil
	}
	info, err := os.Stat(resolved)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("cwd does not exist: %s", resolved)
		}
		return "", fmt.Errorf("cwd not accessible: %s (%w)", resolved, err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("cwd is not a directory: %s", resolved)
	}
	return resolved, nil
}

// normalizeClaudeModel maps phone/OpenRouter-style model slugs onto Claude Code
// CLI aliases. The iOS ManagedModel enum historically sent values like
// "anthropic/claude-haiku-4", which Claude Code 2.x rejects with model_not_found
// (exit 1). Short aliases (haiku/sonnet/opus) resolve to the current CLI defaults.
func normalizeClaudeModel(model string) string {
	switch strings.TrimSpace(model) {
	case "", "haiku", "sonnet", "opus":
		return model
	case "anthropic/claude-haiku-4", "claude-haiku-4", "claude-haiku-4-5", "claude-haiku-4-5-20251001":
		return "haiku"
	case "anthropic/claude-sonnet-4", "claude-sonnet-4", "claude-sonnet-4-5", "claude-sonnet-5":
		return "sonnet"
	case "anthropic/claude-opus-4", "claude-opus-4", "claude-opus-4-5", "claude-opus-4-8":
		return "opus"
	default:
		// Pass through unknown IDs so newer CLI-accepted names still work.
		return model
	}
}

// claudeStrictMCPArgs disables loading of every configured MCP server for a
// claudeCode dispatch: this project's 5 dev-tooling servers (XcodeBuildMCP,
// xcode, apple-docs, context7, ios-simulator) AND, because MCP server config
// is user-scoped, whatever personal/global remote connectors the operator has
// connected (Figma, Gmail, Calendar, Vercel, etc.) — 23 servers total were
// observed loaded in a local measurement, none relevant to a phone-dispatched
// chat turn.
//
// Measured root cause (2026-07-14, local headless timing against installed
// claude 2.1.209 — the owner's reported "11.0s for a plain Hi" reproduced
// almost exactly, 11.278s wall clock, via the same argv shape fed the same
// way realLauncher feeds it: prompt delivered as a stream-json stdin message,
// not positionally, since --input-format stream-json requires that). The
// CLI's own stream-json "result" event carries `time_to_request_ms` (local
// process-spawn + hook-execution time before the API request is even sent)
// and `ttft_ms` (server-side time-to-first-token). Across every trial run,
// cold or warm, `time_to_request_ms` was 39-166ms — local overhead is NOT the
// bottleneck. The entire multi-second gap was `ttft_ms`: a cold prompt-cache
// write of the system prompt measured ttft_ms ~9,966ms with
// cache_creation_input_tokens ~20,214 (full MCP config); a repeat call within
// the cache TTL read the same prompt from cache in ttft_ms ~2-4s. The MCP
// server list (a tool-schema block for every connected server, most
// irrelevant to a plain chat reply) is the largest, most controllable
// component of that system prompt.
//
// --strict-mcp-config with an empty --mcp-config cut cache_creation_input_tokens
// from ~20,214 to ~15,345 in a direct back-to-back cold comparison, and cut
// ttft_ms from 9,966ms to 4,110ms (58%) in that same comparison; on a fully
// warm cache it still averaged ~15% faster with lower variance across 3
// back-to-back trials each (ttft_ms 3,407ms vs 3,929ms). It only removes
// which MCP servers load — it does not touch --permission-prompt-tool or
// --input-format (the live control channel for AskUserQuestion, itself a
// built-in tool unaffected by MCP config — confirmed present in the CLI's
// own "tools" list in both configurations) or CLAUDE.md/AGENTS.md/skill
// loading, so project-context awareness for the reply is unchanged.
var claudeStrictMCPArgs = []string{"--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`}

// agentArgv builds an explicit, shell-free argv for launching an agent with a
// prompt. Explicit argv (never `sh -c "<interpolated>"`) avoids command injection.
//
// fullTools is claudeCode-only (every other vendor ignores it): false (the
// default — flag absent on the wire decodes to the zero value) appends
// claudeStrictMCPArgs, same as this dispatch path's original unconditional
// behavior; true omits them so the phone's opt-in "Full tools" toggle gets a
// normal MCP-loaded turn (XcodeBuildMCP/apple-docs/context7 etc.) at the cost
// of the ~58% first-token-latency win strict mode buys. See claudeStrictMCPArgs'
// doc comment for the underlying measurement this trades off.
func agentArgv(agent, prompt, model string, fullTools bool) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		// --permission-prompt-tool stdio + --input-format stream-json together
		// are what actually open a LIVE bidirectional control channel for
		// AskUserQuestion — verified live 2026-07-10 (M3 probe, see
		// docs/plans/2026-07-10-in-thread-questions-Status.md): with
		// --permission-prompt-tool stdio alone (M2's fix), a "control_request"
		// line never appears on stdout at all — the CLI auto-denies the tool
		// call instantly ("Stream closed") regardless of whether stdin is a
		// live pipe or /dev/null. Adding --input-format stream-json is what
		// unlocks the real control_request/control_response protocol
		// (confirmed via a live probe: same argv minus --input-format never
		// emits control_request; with it, a real
		// {"type":"control_request","request":{"subtype":"can_use_tool",...}}
		// line appears and a {"type":"control_response",...} written back to
		// stdin genuinely resumes the SAME turn with the real answer — the
		// model's own final text reflected the injected answer, not a denial).
		//
		// The catch (also verified live): with --input-format stream-json the
		// CLI reads its initial user message from stdin as a
		// {"type":"user","message":{...}} line, NOT from a positional -p
		// argument — a positional prompt combined with --input-format
		// stream-json hangs forever waiting on stdin instead of using it. The
		// trailing "-p", prompt pair is deliberately KEPT here (for the
		// existing audit/display "command" string built from this same argv,
		// and for claudeStdinPromptArgv's test coverage); realLauncher strips
		// it from the actual exec argv and delivers prompt as the initial
		// stdin message instead — see claudeStdinPromptArgv's doc comment.
		argv := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio"}
		if !fullTools {
			argv = append(argv, claudeStrictMCPArgs...)
		}
		if m := normalizeClaudeModel(model); m != "" {
			argv = append(argv, "--model", m)
		}
		// The "-p", prompt pair must stay TRAILING: claudeStdinPromptArgv only
		// engages stdin-prompt mode when argv[len-2] == "-p". Appending flags
		// after it silently disabled that rewrite, so claude launched in
		// stream-json input mode with no stdin feed and exited on EOF with no
		// output (found live 2026-07-11, first model-specified dispatch ever).
		argv = append(argv, "-p", prompt)
		return argv, true
	case "codex":
		// --json emits structured NDJSON events; --dangerously-bypass flag is
		// required for headless dispatch (no TTY) — see docs/audit/CODEX_GATING.md.
		// -c model_reasoning_summary=auto unlocks reasoning items on the same
		// stream — verified live 2026-07-18 against codex-cli 0.144.6: without
		// this flag no item.completed{item:{type:"reasoning"}} line ever
		// appears; with it one does (see streamJSONOutput's "item.completed"
		// case, itemType=="reasoning").
		argv := []string{"codex", "exec", "--json", "-c", "model_reasoning_summary=auto"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CODEX_UNSAFE") == "1" {
			argv = append(argv, "--dangerously-bypass-approvals-and-sandbox")
		}
		return append(argv, prompt), true
	case "kimi":
		argv := []string{"kimi", "--prompt", prompt, "--output-format", "stream-json"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return argv, true
	case "opencode":
		// --thinking unlocks "reasoning" events on the same stream — verified
		// live 2026-07-18 against opencode 1.17.18: without this flag no
		// {"type":"reasoning",...} line ever appears; with it one does (see
		// streamJSONOutput's "reasoning" case).
		argv := []string{"opencode", "run", "--format", "json", "--thinking"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	case "pi":
		// --mode json emits one structured event per line (session, agent_start,
		// turn_start, message_start/end, message_update{assistantMessageEvent},
		// turn_end, agent_end, agent_settled, tool_execution_*) — verified live
		// 2026-07-18 against pi 0.80.10 (scratchpad/pi-smoke/pi-stream.jsonl,
		// pi-tool-stream.jsonl — see streamJSONOutput's pi cases). splitPiModel
		// separates a "provider/model-id" string into pi's own --provider and
		// --model flags (pi's --model alone also accepts a "provider/id"
		// pattern per --help, but the live-verified invocation this mirrors
		// used both flags explicitly: `pi --provider openrouter --model
		// deepseek/deepseek-v4-flash --mode json -p "..."`).
		//
		// The approval-extension `-e <path>` flag is NOT appended here — see
		// resumeArgv's pi case / installPiExtension (Phase 3(d)) for why it's
		// threaded in at the dispatcher level instead of baked into every
		// argv builder.
		argv := []string{"pi", "--mode", "json"}
		provider, modelID := splitPiModel(model)
		if provider != "" {
			argv = append(argv, "--provider", provider)
		}
		if modelID != "" {
			argv = append(argv, "--model", modelID)
		}
		return append(argv, "-p", prompt), true
	case "cursor":
		// Cursor Agent CLI (`agent`, also installed as `cursor-agent`).
		// Verified live 2026-07-19 against agent 2026.07.16-899851b:
		//   agent -p --output-format stream-json --trust "<prompt>"
		// exits 0 with system/user/thinking/assistant/result NDJSON; without
		// --trust headless fails fast EXIT 1 with "Workspace Trust Required"
		// — not a TTY hang. Prompt is a trailing positional arg (never
		// shell-interpolated).
		//
		// Tool-gating honesty (re-verified 2026-07-19): vendor `-p` "Has
		// access to all tools, including write and shell." With --trust and
		// WITHOUT --force, shell/write still auto-run (permissionMode
		// default). Omitting --force is NOT fail-closed for tools.
		// Lancer's real gate today is launch escalation only:
		// hookWiredForAgent("agent") stays false (no PreToolUse-equivalent),
		// so relaxLaunchEscalation keeps default-ask and launchRisk stays
		// medium — same class as unverified Kimi/Pi. After the owner allows
		// the *launch*, subsequent Cursor tools are ungated until a real
		// Cursor hook exists. Vendor --mode ask|plan is read-only (live-
		// verified) but is NOT the default argv: that would ship a planning
		// stub, not a coding agent. LANCER_CURSOR_FORCE=1 adds --force only
		// to skip remaining interactive denials; it is not a Lancer security
		// boundary (mirrors LANCER_CODEX_UNSAFE naming discipline, not
		// semantics).
		argv := []string{"agent", "-p", "--output-format", "stream-json", "--trust"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CURSOR_FORCE") == "1" {
			argv = append(argv, "--force")
		}
		return append(argv, prompt), true
	default:
		return nil, false
	}
}

// splitPiModel splits a Lancer model string of the form "provider/model-id"
// (e.g. "openrouter/deepseek/deepseek-v4-flash") into (provider, modelID) for
// pi's separate --provider/--model flags. A model with no "/" is returned as
// (provider="", modelID=model) — pi's own --model flag also accepts a bare
// "provider/id" pattern, but Lancer's model plumbing consistently prefixes
// with the provider (see normalizeClaudeModel's doc comment for the same
// convention on the claudeCode side), so a bare string with no separator is
// treated as a model id with no provider override.
func splitPiModel(model string) (provider, modelID string) {
	model = strings.TrimSpace(model)
	if model == "" {
		return "", ""
	}
	if i := strings.Index(model, "/"); i > 0 {
		return model[:i], model[i+1:]
	}
	return "", model
}

// continueArgv builds an explicit, shell-free argv that continues the most-recent
// vendor session in the run's cwd with a new prompt. It mirrors agentArgv (same
// streaming flags + per-vendor gating) so a continued run streams identically to
// the original. ok=false means the agent is unknown.
func continueArgv(agent, prompt, model string, fullTools bool) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		// --permission-prompt-tool stdio + --input-format stream-json: see
		// agentArgv's doc comment — same live-verified same-turn-continuation
		// protocol applies to a continued turn; realLauncher strips the
		// trailing "-p", prompt pair and delivers it over stdin the same way.
		argv := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--continue"}
		if !fullTools {
			argv = append(argv, claudeStrictMCPArgs...)
		}
		if m := normalizeClaudeModel(model); m != "" {
			argv = append(argv, "--model", m)
		}
		// "-p", prompt must stay trailing — see agentArgv's claudeCode case.
		argv = append(argv, "-p", prompt)
		return argv, true
	case "codex":
		// Resume the most-recent codex session non-interactively. Same headless
		// gating as agentArgv: codex needs the bypass env when no TTY is attached
		// (see docs/audit/CODEX_GATING.md). No new blast radius beyond dispatch.
		// -c model_reasoning_summary=auto: see agentArgv's codex case doc comment.
		argv := []string{"codex", "exec", "resume", "--last", "--json", "-c", "model_reasoning_summary=auto"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CODEX_UNSAFE") == "1" {
			argv = append(argv, "--dangerously-bypass-approvals-and-sandbox")
		}
		return append(argv, prompt), true
	case "kimi":
		argv := []string{"kimi", "--continue", "--prompt", prompt, "--output-format", "stream-json"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return argv, true
	case "opencode":
		// --thinking: see agentArgv's opencode case doc comment.
		argv := []string{"opencode", "run", "--continue", "--format", "json", "--thinking"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	case "pi":
		// --continue/-c continues the most-recently-modified session for the
		// launch cwd — verified live 2026-07-18 against pi 0.80.10 (per
		// --help; agentArgv's pi case doc comment covers the shared
		// --mode/--provider/--model shape). Unlike resumeArgv's pi case,
		// this does NOT target an exact session id — same
		// "latestInCwdFallback" semantics as every other vendor's continueArgv.
		argv := []string{"pi", "--continue", "--mode", "json"}
		provider, modelID := splitPiModel(model)
		if provider != "" {
			argv = append(argv, "--provider", provider)
		}
		if modelID != "" {
			argv = append(argv, "--model", modelID)
		}
		return append(argv, "-p", prompt), true
	case "cursor":
		// --continue resumes the previous session in cwd — verified live
		// 2026-07-19 against agent 2026.07.16-899851b (same session_id
		// retained; prior-turn context recalled). Same --trust /
		// LANCER_CURSOR_FORCE + launch-gate honesty as agentArgv (post-
		// launch tools remain ungated; see agentArgv "cursor" comment).
		argv := []string{"agent", "-p", "--continue", "--output-format", "stream-json", "--trust"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CURSOR_FORCE") == "1" {
			argv = append(argv, "--force")
		}
		return append(argv, prompt), true
	default:
		return nil, false
	}
}

// resumeArgv builds an explicit, shell-free argv that resumes the EXACT vendor
// session identified by sessionID (not "most recent in cwd", unlike
// continueArgv) with a new prompt. This targets a session discovered on disk
// by session_index.go's scan — started directly in a terminal, never
// dispatched by Lancer — so a phone-initiated follow-up must land in that
// precise session even when several terminal sessions share one project dir.
// Mirrors agentArgv/continueArgv (same streaming flags + per-vendor gating).
// ok=false means the agent is unknown or doesn't support resume-by-exact-id.
//
// Per-vendor resume-by-id flag confirmed against the locally installed CLI
// 2026-06-30 (claude 2.1.197, codex-cli 0.135.0, opencode 1.17.11, kimi
// 0.18.0 --help only — see continueRun's caller for the live-smoke caveat):
//   - claude:   -r/--resume <sessionId>  (verified live: same session_id retained)
//   - codex:    exec resume <SESSION_ID> [PROMPT]  (verified live: same thread_id retained)
//   - opencode: run -s/--session <id>  (verified live: same sessionID retained)
//   - kimi:     -S/--session <id>  (from --help only; kimi CLI errored on an
//     unrelated account/billing check during this session, so resume-by-id was
//     not live-smoke-tested — re-verify before relying on it in production.
//     Re-confirmed 2026-07-18: `kimi --prompt ... --output-format
//     stream-json` still returns provider.api_error: 402 (membership) on
//     this machine — an account/billing issue the owner must fix; nothing
//     in this codebase can resolve it. Still not live-smoke-tested.)
//   - pi:       --session <id>  (verified live 2026-07-18 against pi 0.80.10:
//     same session id retained, prior-turn context recalled — see this
//     function's pi case doc comment)
//   - cursor:   --resume <chatId>  (verified live 2026-07-19 against agent
//     2026.07.16-899851b: create-chat UUID + --resume retains session_id)
func resumeArgv(agent, sessionID, prompt, model string, fullTools bool) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		// --permission-prompt-tool stdio + --input-format stream-json: see
		// agentArgv's doc comment — same live-verified same-turn-continuation
		// protocol applies to a resumed turn; realLauncher strips the trailing
		// "-p", prompt pair and delivers it over stdin the same way.
		argv := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--resume", sessionID}
		if !fullTools {
			argv = append(argv, claudeStrictMCPArgs...)
		}
		if m := normalizeClaudeModel(model); m != "" {
			argv = append(argv, "--model", m)
		}
		// "-p", prompt must stay trailing — see agentArgv's claudeCode case.
		argv = append(argv, "-p", prompt)
		return argv, true
	case "codex":
		// codex exec resume <SESSION_ID> [PROMPT] resumes that exact conversation
		// (positional session id, not a flag). Same headless-bypass gating as
		// agentArgv/continueArgv — see docs/audit/CODEX_GATING.md.
		// -c model_reasoning_summary=auto: see agentArgv's codex case doc comment.
		argv := []string{"codex", "exec", "resume", sessionID, "--json", "-c", "model_reasoning_summary=auto"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CODEX_UNSAFE") == "1" {
			argv = append(argv, "--dangerously-bypass-approvals-and-sandbox")
		}
		return append(argv, prompt), true
	case "kimi":
		argv := []string{"kimi", "--session", sessionID, "--prompt", prompt, "--output-format", "stream-json"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return argv, true
	case "opencode":
		// --thinking: see agentArgv's opencode case doc comment.
		argv := []string{"opencode", "run", "--session", sessionID, "--format", "json", "--thinking"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	case "pi":
		// --session <id> resumes that EXACT session (not "most recent") —
		// live-verified 2026-07-18 against pi 0.80.10: the session event on
		// the resumed run's stdout repeated the SAME id, and the model
		// recalled prior-turn context (captured: scratchpad/pi-smoke/
		// pi-resume.jsonl; the two-turn on-disk session file this produced is
		// pi_session_reader_test.go's TestPiInspectAndSessionsDiscovery-style
		// evidence). NEVER use -r/--resume (interactive picker, hangs
		// headless — see agentArgv's pi case / the module doc comment above).
		argv := []string{"pi", "--session", sessionID, "--mode", "json"}
		provider, modelID := splitPiModel(model)
		if provider != "" {
			argv = append(argv, "--provider", provider)
		}
		if modelID != "" {
			argv = append(argv, "--model", modelID)
		}
		return append(argv, "-p", prompt), true
	case "cursor":
		// --resume <chatId> targets that exact Cursor chat — verified live
		// 2026-07-19 (create-chat UUID retained as session_id). Same
		// --trust / LANCER_CURSOR_FORCE + launch-gate honesty as agentArgv
		// (post-launch tools remain ungated).
		argv := []string{"agent", "-p", "--resume", sessionID, "--output-format", "stream-json", "--trust"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		if os.Getenv("LANCER_CURSOR_FORCE") == "1" {
			argv = append(argv, "--force")
		}
		return append(argv, prompt), true
	default:
		return nil, false
	}
}

// conversationLaunchParams carries what buildConversationArgv/
// launchConversationTurn need to dispatch a conversation-ledger turn (see
// conversation_rpc.go's conversationsAppend, the cross-device sync build
// handoff's Task 3). Agent/CWD/Model/BudgetUSD are already resolved by the
// caller — defaulted from the conversation's own row for a follow-up whose
// request omitted them, mirroring conversation_store.go's
// appendFollowUpTurn resolution — so the dispatched process's cwd/provider
// always match what the ledger recorded.
type conversationLaunchParams struct {
	Agent           string
	CWD             string
	Prompt          string
	Model           string
	BudgetUSD       float64
	VendorSessionID string // "" ⇒ no turn on this conversation has bound one yet
	IsNew           bool   // true ⇒ first turn of a brand-new conversation

	// Attachments are structured refs for this turn. Prompt stays the clean
	// user-typed text for audit/run/ledger; hostPath is injected only into the
	// ephemeral vendor prompt at the launch boundary (see vendorAttachmentPrompt).
	Attachments []conversationAttachmentReference

	// FullTools opts THIS turn out of claudeStrictMCPArgs (claudeCode only;
	// every other agent ignores it) — the phone composer's per-dispatch "Full
	// tools" toggle (default off ⇒ strict/fast). Threaded straight from this
	// turn's own request into whichever of agentArgv/continueArgv/resumeArgv
	// buildConversationArgv picks, never re-derived from an earlier turn on
	// the same conversation.
	FullTools bool

	// Contract mirrors dispatchParams.Contract — see conversationAppendRequest's
	// identical field (conversation_store.go) for why this exists: without it,
	// every receipt created through agent.conversations.append (the live
	// composer's start/continue path) silently lost goal/doneCriteria/
	// validationCommands even though a plain agent.dispatch carried them fine.
	Contract *runContract

	// worktreePath/worktreeRepoRoot: see the identical fields on dispatchParams —
	// same race, same fix, applied here too.
	worktreePath     string
	worktreeRepoRoot string
}

// buildConversationArgv selects which per-vendor argv to launch for a
// conversation-ledger-backed turn and reports the resume confidence the
// caller must surface in the agent.conversations.append response (see the
// cross-device sync build handoff's Task 3 and RPC Contract):
//
//   - IsNew (fresh conversation): agentArgv, resumeMode "new".
//   - Follow-up with a VendorSessionID already bound from a prior turn (via
//     bindVendorSession): resumeArgv targeting that EXACT session, resumeMode
//     "exact" — never "continue latest in cwd", which could silently land in
//     the wrong session when several sessions share a cwd.
//   - Follow-up with no bound VendorSessionID yet (the CLI hasn't emitted one,
//     or this vendor doesn't expose one): continueArgv (most-recent-in-cwd),
//     resumeMode "latestInCwdFallback" — degraded resume confidence, reported
//     to the caller rather than silently claimed as exact.
//
// ok=false (agent unknown / unsupported) mirrors agentArgv/continueArgv/
// resumeArgv's own ok semantics; resumeMode is still returned in that case so
// the caller can report it even though it's carrying no launchable argv.
func buildConversationArgv(p conversationLaunchParams) (argv []string, resumeMode string, ok bool) {
	switch {
	case p.IsNew:
		argv, ok = agentArgv(p.Agent, p.Prompt, p.Model, p.FullTools)
		return argv, "new", ok
	case p.VendorSessionID != "":
		argv, ok = resumeArgv(p.Agent, p.VendorSessionID, p.Prompt, p.Model, p.FullTools)
		return argv, "exact", ok
	default:
		argv, ok = continueArgv(p.Agent, p.Prompt, p.Model, p.FullTools)
		return argv, "latestInCwdFallback", ok
	}
}

type runContract struct {
	Goal               string   `json:"goal"`
	DoneCriteria       []string `json:"doneCriteria,omitempty"`
	ValidationCommands []string `json:"validationCommands,omitempty"`
}

const (
	contractMaxDoneCriteria       = 8
	contractMaxDoneCriterionChars = 200
	contractMaxValidationCommands = 4
)

func contractTooLarge(c *runContract) bool {
	if c == nil {
		return false
	}
	if len(c.DoneCriteria) > contractMaxDoneCriteria {
		return true
	}
	for _, crit := range c.DoneCriteria {
		if len(crit) > contractMaxDoneCriterionChars {
			return true
		}
	}
	return len(c.ValidationCommands) > contractMaxValidationCommands
}

func cloneRunContract(c *runContract) *runContract {
	if c == nil {
		return nil
	}
	return &runContract{
		Goal:               c.Goal,
		DoneCriteria:       append([]string(nil), c.DoneCriteria...),
		ValidationCommands: append([]string(nil), c.ValidationCommands...),
	}
}

func runContractToReceipt(c *runContract) *receiptContract {
	if c == nil {
		return nil
	}
	return &receiptContract{
		Goal:               c.Goal,
		DoneCriteria:       append([]string(nil), c.DoneCriteria...),
		ValidationCommands: append([]string(nil), c.ValidationCommands...),
	}
}

type dispatchParams struct {
	Agent       string       `json:"agent"`
	CWD         string       `json:"cwd"`
	Prompt      string       `json:"prompt"`
	BudgetUSD   float64      `json:"budgetUSD"`
	Model       string       `json:"model"`
	UseWorktree bool         `json:"useWorktree,omitempty"`
	Contract    *runContract `json:"contract,omitempty"`
	// FullTools — see conversationLaunchParams.FullTools's doc comment. Absent
	// on the wire (older clients) decodes to false ⇒ strict/fast, so this is
	// backward compatible with no co-deploy requirement.
	FullTools bool `json:"fullTools,omitempty"`

	// worktreePath/worktreeRepoRoot are set by runDispatch (never over the wire —
	// unexported) so dispatch() can record them on the run BEFORE launching the
	// process. Setting them only after launch returns (as attachRunWorktree once
	// did) raced a fast-exiting process's terminal-status event against the
	// run record's own creation, silently skipping worktree cleanup — see
	// TestRunDispatchWorktreeRetention.
	worktreePath     string
	worktreeRepoRoot string
}

type dispatchResult struct {
	RunID        string `json:"runId,omitempty"`
	Status       string `json:"status"`             // started | needsApproval | denied | budgetExceeded | error
	Decision     string `json:"decision,omitempty"` // allow | ask | deny
	Rule         string `json:"rule,omitempty"`
	Message      string `json:"message,omitempty"`
	WorktreePath string `json:"worktreePath,omitempty"`
	Isolated     bool   `json:"isolated,omitempty"`
	// CWD is the ~-expanded absolute path the run actually launched in — set
	// only on a successful "started" result. The phone persists this (not the
	// raw cwd it sent, which may be the literal "~") so a phone-dispatched
	// conversation and a terminal session in the same real directory group
	// together instead of silently diverging on string comparison.
	CWD string `json:"cwd,omitempty"`
}

// procHandle controls a launched agent process. Injectable for tests.
type procHandle struct {
	kill   func()
	pause  func()
	resume func()
	// writeControlResponse sends a raw control_response JSON line (no
	// trailing newline required) to the child's stdin. nil when this run has
	// no live bidirectional control channel (any agent other than a
	// claudeCode run launched with --input-format stream-json — see
	// claudeStdinPromptArgv). handleControlRequest is the only caller.
	writeControlResponse func(payload []byte) error
	// closeStdin closes the child's stdin (EOF). With --input-format
	// stream-json the CLI does NOT exit on its own once a turn's "result"
	// event is emitted — verified live 2026-07-10: it idles waiting for
	// another stdin message instead. streamJSONOutput calls this once it
	// observes "result" so the process still exits promptly (confirmed live:
	// ~0.5s to clean exit after closing stdin). Always non-nil on a procHandle
	// returned by realLauncher; a no-op when the run has no live stdin (never
	// opened). nil only on procHandles built by other launchFuncs (tests,
	// e2eFakeRelayLaunch) that don't set it — callers must nil-check.
	closeStdin func()
}

// emitFunc sends a JSON-RPC notification (method + params) to the attached phone.
type emitFunc func(method string, params any)

// launchFunc starts an agent process, streaming its stdout/stderr + status to
// emit (tagged with runID), and returns its control handle. Injectable for tests.
type launchFunc func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error)

// controlStdin serializes every write to a claudeCode child's stdin —
// the launch goroutine's one-time initial user message and the
// stdout-scanning goroutine's later control_response replies and final
// close-on-result EOF all go through the same mutex so they can never
// interleave or double-close the underlying pipe.
type controlStdin struct {
	mu     sync.Mutex
	w      io.WriteCloser
	closed bool
}

func (c *controlStdin) write(b []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	_, err := c.w.Write(b)
	return err
}

func (c *controlStdin) close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return
	}
	c.closed = true
	_ = c.w.Close()
}

// claudeStdinPromptArgv detects a claudeCode argv built with --input-format
// stream-json (agentArgv/continueArgv/resumeArgv's claudeCode case) and, if
// found, returns the argv with its trailing "-p", "<prompt>" pair replaced
// by a bare "-p" flag, plus the prompt text to deliver separately.
//
// Verified live 2026-07-10: in --input-format stream-json mode the CLI reads
// its initial user turn from a {"type":"user","message":{...}} line on
// stdin, not from a positional prompt argument — a positional prompt
// combined with --input-format stream-json hangs forever (the CLI waits on
// stdin for a message that never arrives; a bare "-p" with no positional arg
// plus a stdin-delivered message is what actually works). realLauncher uses
// this to build the real exec argv and know what to write to stdin; the
// ORIGINAL argv (still carrying the prompt positionally) is what
// dispatch()/continueRun()/resumeRun() use for the audit-log "command"
// string and what dispatch_test.go's TestAgentArgv/TestContinueArgv/
// TestResumeArgv assert against — this function is the only place that
// diverges from it.
//
// ok is false for every argv this doesn't apply to (any non-claudeCode
// vendor, or a claudeCode argv without --input-format stream-json, or an
// empty prompt) — the caller launches exactly as before with argv unchanged
// and no stdin pipe.
func claudeStdinPromptArgv(argv []string) (execArgv []string, prompt string, ok bool) {
	if len(argv) < 4 || argv[0] != "claude" {
		return nil, "", false
	}
	hasStreamInput := false
	for i := 0; i+1 < len(argv); i++ {
		if argv[i] == "--input-format" && argv[i+1] == "stream-json" {
			hasStreamInput = true
			break
		}
	}
	if !hasStreamInput {
		return nil, "", false
	}
	if argv[len(argv)-2] != "-p" {
		return nil, "", false
	}
	prompt = argv[len(argv)-1]
	if prompt == "" {
		return nil, "", false
	}
	execArgv = make([]string, 0, len(argv)-1)
	execArgv = append(execArgv, argv[:len(argv)-1]...) // keep everything through the bare "-p"
	return execArgv, prompt, true
}

func realLauncher(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
	// Build the child env with an augmented PATH first: under launchd the daemon
	// inherits a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin) that does not include
	// where the agent CLIs live (Homebrew, ~/.local/bin, Kimi's bin).
	env := agentLaunchEnvironment()
	if requiresLancerGate(argv) {
		// The Claude and OpenCode hooks are installed in each vendor's normal
		// settings scope. Gate them explicitly so only Lancer-dispatched runs
		// enter the approval path; an owner's interactive session is untouched.
		env = lancerGateEnvironment(env)
	}

	// Pi's per-action approval gate is an extension loaded per-run via
	// "-e <path>" (installPiExtension, Phase 3(d)). It is threaded here at
	// the single exec choke point — not in each argv builder — so every pi
	// launch path (new/continue/resume) picks it up exactly when the
	// extension file is installed, and the argv-builder tests stay pinned to
	// the pure CLI shape.
	argv = appendPiExtension(argv)

	// A claudeCode argv built with --input-format stream-json (agentArgv's
	// doc comment) needs its prompt delivered over stdin, not positionally —
	// see claudeStdinPromptArgv. execArgv is what actually gets exec'd;
	// argv (unchanged) is still what streamJSON-mode detection below reads.
	execArgv := argv
	stdinPrompt := ""
	useControlStdin := false
	if ea, p, ok := claudeStdinPromptArgv(argv); ok {
		execArgv, stdinPrompt, useControlStdin = ea, p, true
	}

	// Resolve the binary against the AUGMENTED PATH ourselves and pass an absolute
	// path. exec.Command resolves a bare name using the daemon's own (minimal)
	// PATH at call time — cmd.Env does NOT affect that lookup — so without this the
	// run fails "executable file not found in $PATH" under launchd.
	bin := execArgv[0]
	if !strings.Contains(bin, "/") {
		if resolved := lookPathIn(bin, env); resolved != "" {
			bin = resolved
		}
	}
	resolvedCWD, err := resolveDispatchCWD(cwd)
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(bin, execArgv[1:]...) // explicit argv, no shell
	cmd.Dir = resolvedCWD
	cmd.Env = env
	// Run the agent in its own process group so we can reap its whole subtree.
	// Agents like Claude Code spawn MCP server subprocesses that inherit our
	// stdout/stderr pipes; without a group to kill, those grandchildren outlive
	// the agent, hold the pipe write-ends open (so the pipes never EOF — see the
	// reaper below), and leak as orphans reparented to launchd.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// Use os.Pipe (not StdoutPipe/StderrPipe): cmd.Wait closes StdoutPipe readers
	// as soon as the process exits (see os/exec StdoutPipe docs), discarding any
	// unread stderr — the A3 zero-output failure. *os.File Stdout/Stderr are
	// inherited by the child and are NOT closed by Wait, so we can drain after
	// exit (with a grace timeout for MCP orphans that keep write-ends open).
	stdoutR, stdoutW, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	stderrR, stderrW, err := os.Pipe()
	if err != nil {
		_ = stdoutR.Close()
		_ = stdoutW.Close()
		return nil, err
	}
	cmd.Stdout = stdoutW
	cmd.Stderr = stderrW

	var stdinCtl *controlStdin
	if useControlStdin {
		stdinPipe, err := cmd.StdinPipe()
		if err != nil {
			_ = stdoutR.Close()
			_ = stdoutW.Close()
			_ = stderrR.Close()
			_ = stderrW.Close()
			return nil, err
		}
		stdinCtl = &controlStdin{w: stdinPipe}
	}

	if err := cmd.Start(); err != nil {
		_ = stdoutR.Close()
		_ = stdoutW.Close()
		_ = stderrR.Close()
		_ = stderrW.Close()
		return nil, err
	}
	// Parent closes write ends so Read sees EOF once the child (and any
	// inheriting orphans) close theirs.
	_ = stdoutW.Close()
	_ = stderrW.Close()

	proc := cmd.Process
	pid := 0
	if proc != nil {
		pid = proc.Pid
	}

	emitRunStatus(emit, runID, "running", nil)
	emitLiveStatusStarting(emit, runID)

	if stdinCtl != nil {
		// Deliver the turn's prompt as the initial stream-json user message —
		// verified live 2026-07-10: this is what --input-format stream-json
		// actually reads (see claudeStdinPromptArgv's doc comment). Best-effort:
		// a write failure here leaves the process with no input, which it will
		// itself error/exit on — the existing exit-status handling below still
		// reports that terminal status normally, same as any other launch failure.
		initMsg, merr := json.Marshal(map[string]any{
			"type":    "user",
			"message": map[string]any{"role": "user", "content": stdinPrompt},
		})
		if merr == nil {
			_ = stdinCtl.write(append(initMsg, '\n'))
		}
	}

	// Detect whether the agent was launched in stream-json mode so the stdout
	// reader can parse per-line JSON deltas instead of line-buffered chunks.
	streamJSON := false
	for i, a := range argv {
		if (a == "--output-format" && i+1 < len(argv) && argv[i+1] == "stream-json") ||
			(a == "--format" && i+1 < len(argv) && argv[i+1] == "json") ||
			a == "--json" {
			streamJSON = true
			break
		}
	}

	var seq int64
	var terminalOnce sync.Once
	var firstOutputOnce sync.Once
	var ttfoTimer *time.Timer

	cancelTTFO := func() {
		firstOutputOnce.Do(func() {
			if ttfoTimer != nil {
				ttfoTimer.Stop()
			}
		})
	}

	emitTerminal := func(status string, code *int) {
		terminalOnce.Do(func() {
			cancelTTFO()
			emitRunStatus(emit, runID, status, code)
		})
	}

	watchEmit := emit
	armTTFO := claudeFirstOutputTimeout > 0 && ttfoAppliesTo(argv) && pid > 0
	if armTTFO {
		watchEmit = func(method string, params any) {
			// Cancel only on real progress (stdout text / tool / control / result).
			// Raw stderr, init vendorSession, thinking liveStatus do NOT cancel.
			if ttfoEventIsProgress(method, params) {
				cancelTTFO()
			}
			if emit != nil {
				emit(method, params)
			}
		}
		capturedPID := pid
		capturedRunID := runID
		ttfoTimer = time.AfterFunc(claudeFirstOutputTimeout, func() {
			firstOutputOnce.Do(func() {
				// Kill only this process group — never a later reused pid.
				_ = syscall.Kill(-capturedPID, syscall.SIGKILL)
				if proc != nil {
					_ = proc.Kill()
				}
				n := atomic.AddInt64(&seq, 1)
				if emit != nil {
					emit("agent.run.output", map[string]any{
						"runId": capturedRunID, "stream": "stdout",
						"chunk": claudeColdStartTimeoutMsg + "\n", "seq": int(n),
					})
					emit("agent.run.resultError", map[string]any{
						"runId": capturedRunID, "error": claudeColdStartTimeoutMsg,
					})
				}
			})
		})
	}

	// Tee a bounded tail so a force-close during drain grace can still surface
	// why the run failed when stream readers saw no chunks.
	stdoutTail := &boundedTail{max: 8192}
	stderrTail := &boundedTail{max: 8192}
	stdoutReader := io.TeeReader(stdoutR, stdoutTail)
	stderrReader := io.TeeReader(stderrR, stderrTail)

	var streams sync.WaitGroup
	streams.Add(2)
	go streamOutput(watchEmit, runID, "stdout", stdoutReader, &seq, &streams, streamJSON)
	go streamOutput(watchEmit, runID, "stderr", stderrReader, &seq, &streams, false)

	go func() {
		code := exitCode(cmd.Wait())
		cancelTTFO()
		// Kill the agent's group (reaps MCP children that didn't detach).
		if proc != nil {
			_ = syscall.Kill(-proc.Pid, syscall.SIGKILL)
		}
		if stdinCtl != nil {
			stdinCtl.close()
		}

		if code == 0 {
			// Success: emit immediately. Orphan MCP holders can keep pipes open;
			// never gate a clean exit on streams.Wait (hangs "running" forever).
			emitTerminal("exited", &code)
			_ = stdoutR.Close()
			_ = stderrR.Close()
			streams.Wait()
			return
		}

		// Failure: drain readers before terminal status so stderr/raw-stdout
		// reach persistConversationEvent's runStderr / resultError maps before
		// takeRunStderr runs. Cap the wait — detached MCP orphans still need
		// a forced pipe close so we cannot hang.
		drained := make(chan struct{})
		go func() {
			streams.Wait()
			close(drained)
		}()
		select {
		case <-drained:
		case <-time.After(streamDrainGrace):
			_ = stdoutR.Close()
			_ = stderrR.Close()
			<-drained
		}
		_ = stdoutR.Close()
		_ = stderrR.Close()
		surfaceZeroOutputFailure(watchEmit, runID, &seq, stderrTail, stdoutTail)
		emitTerminal("failed", &code)
	}()

	return &procHandle{
		kill: func() {
			cancelTTFO()
			if proc != nil {
				// Kill the whole group so MCP grandchildren don't orphan.
				_ = syscall.Kill(-proc.Pid, syscall.SIGKILL)
				_ = proc.Kill()
			}
		},
		pause: func() {
			if proc != nil {
				_ = proc.Signal(syscall.SIGSTOP)
			}
		},
		resume: func() {
			if proc != nil {
				_ = proc.Signal(syscall.SIGCONT)
			}
		},
		writeControlResponse: func(payload []byte) error {
			if stdinCtl == nil {
				return nil
			}
			return stdinCtl.write(append(payload, '\n'))
		},
		closeStdin: func() {
			if stdinCtl != nil {
				stdinCtl.close()
			}
		},
	}, nil
}

func requiresLancerGate(argv []string) bool {
	if len(argv) == 0 {
		return false
	}
	// codex/kimi joined this list when their PreToolUse hook scripts landed
	// (codex_hook_install.go / kimi_hook_install.go): both scripts exit 0
	// unless LANCER_GATE=1, so omitting them here would make a trusted hook
	// silently no-op on dispatched runs — fail-open once hookWiredForAgent
	// relaxes the launch gate. Pi is deliberately absent: its gate is the
	// -e extension appended per-run by realLauncher (appendPiExtension),
	// which is its own opt-in — no env gating needed.
	switch argv[0] {
	case "claude", "opencode", "codex", "kimi":
		return true
	}
	return false
}

// relaxLaunchEscalation decides whether an agent *launch* (dispatch or continue)
// still needs pre-approval. Launching an agent isn't the dangerous act — the
// tools it runs are. When the per-action PreToolUse hook is verifiably wired for
// this agent, that hook is the real gate, so forcing an approval before every
// message is redundant and breaks normal chat. In that case a fail-closed
// *default* "ask" on the launch is relaxed to "allow".
//
// It is deliberately NOT relaxed (fail-closed) when:
//   - the ask came from an explicit policy rule (fromDefault == false) — the
//     author meant it, so we never silently downgrade an explicit rule;
//   - the agent's hook is not verifiably wired (hookWired nil or false) — e.g.
//     OpenCode, whose hook install is still a TODO (see install.go), and
//     Codex/Kimi, which have no per-action hook — so the launch escalates and the
//     owner is prompted, rather than running ungated;
//   - the effect is "deny" — always honored.
func relaxLaunchEscalation(effect string, fromDefault bool, argv []string, hookWired func(string) bool) string {
	if effect != "ask" || !fromDefault || len(argv) == 0 || hookWired == nil {
		return effect
	}
	if hookWired(argv[0]) {
		return "allow"
	}
	return effect
}

// launchRisk scores how risky *starting* an agent is — distinct from what the
// agent later does. For an agent whose per-action PreToolUse hook is verifiably
// wired (Claude today), every tool call is intercepted and gated, so the launch
// itself is low-risk and the bundled policy's `allow-low-readonly` lets a plain
// message ("Hi") run immediately. For a hook-less agent (Codex/Kimi, or Claude
// before `install`) the launch is the only guard, so it stays medium and the
// bundled `ask-medium` rule escalates it — fail-closed.
//
// This is why scoring every dispatch as medium (the old behavior) wrongly blocked
// even hook-wired agents: `ask-medium` matched as an explicit rule, which
// relaxLaunchEscalation never downgrades.
func (d *dispatcher) launchRisk(argv []string) int {
	if len(argv) > 0 && d.hookWired != nil && d.hookWired(argv[0]) {
		return 0 // low — the hook gates every subsequent tool call
	}
	return 1 // medium — no per-action gate; the launch escalation is the guard
}

// agentLaunchEnvironment returns the parent environment with PATH augmented to
// include the directories agent CLIs are commonly installed in. Under launchd the
// daemon's inherited PATH is minimal and would not find the vendor binaries; the
// user's own dirs are preserved first, missing standard/agent dirs appended.
func agentLaunchEnvironment() []string {
	extra := []string{"/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"}
	if home, err := os.UserHomeDir(); err == nil {
		extra = append(extra,
			filepath.Join(home, ".local", "bin"),
			filepath.Join(home, ".kimi-code", "bin"),
			filepath.Join(home, ".lancer", "bin"),
		)
	}
	env := os.Environ()
	result := make([]string, 0, len(env)+1)
	pathFound := false
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			pathFound = true
			seen := map[string]bool{}
			merged := []string{}
			for _, p := range strings.Split(strings.TrimPrefix(e, "PATH="), ":") {
				if p != "" && !seen[p] {
					seen[p] = true
					merged = append(merged, p)
				}
			}
			for _, d := range extra {
				if !seen[d] {
					seen[d] = true
					merged = append(merged, d)
				}
			}
			result = append(result, "PATH="+strings.Join(merged, ":"))
		} else {
			result = append(result, e)
		}
	}
	if !pathFound {
		result = append(result, "PATH="+strings.Join(extra, ":"))
	}
	// The vendor-CLI hooks resolve the gating binary as ${LANCERD:-$HOME/.lancer/bin/lancerd}.
	// Without an explicit LANCERD, runs dispatched by an isolated (LANCER_STATE_DIR)
	// daemon still gate through the PRODUCTION binary — version skew observed live
	// 2026-07-17 (docs/test-runs/2026-07-17-gap-reproof). Point hooks at the
	// dispatching daemon's own executable; a pre-set LANCERD wins.
	hasLancerd := false
	for _, e := range env {
		if strings.HasPrefix(e, "LANCERD=") {
			hasLancerd = true
			break
		}
	}
	if !hasLancerd {
		if exe, err := os.Executable(); err == nil && exe != "" {
			result = append(result, "LANCERD="+exe)
		}
	}
	return result
}

// lookPathIn resolves an executable name against the PATH carried in env (not the
// process's own PATH), returning the absolute path or "" if not found. Used so a
// launchd-spawned daemon with a minimal inherited PATH can still locate agent CLIs.
func lookPathIn(name string, env []string) string {
	return lookPathInExcluding(name, env, "")
}

// lookPathInExcluding is lookPathIn that skips any candidate whose directory
// equals excludeDir (used to ignore ~/.lancer/bin shim wrappers during auth
// preflight — those wrappers dial the daemon and must not run the probe).
func lookPathInExcluding(name string, env []string, excludeDir string) string {
	var pathValue string
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			pathValue = strings.TrimPrefix(e, "PATH=")
			break
		}
	}
	excludeDir = filepath.Clean(excludeDir)
	for _, dir := range strings.Split(pathValue, ":") {
		if dir == "" {
			continue
		}
		if excludeDir != "" && filepath.Clean(dir) == excludeDir {
			continue
		}
		candidate := filepath.Join(dir, name)
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return candidate
		}
	}
	return ""
}

// lancerGateEnvironment replaces any inherited value rather than appending a
// duplicate. That makes the dispatch contract deterministic on every platform.
func lancerGateEnvironment(environment []string) []string {
	result := make([]string, 0, len(environment)+1)
	for _, entry := range environment {
		if !strings.HasPrefix(entry, "LANCER_GATE=") {
			result = append(result, entry)
		}
	}
	return append(result, "LANCER_GATE=1")
}

// streamDrainGrace is how long a failed run waits for stdout/stderr readers
// before force-closing pipes. Detached MCP orphans can hold write-ends open
// indefinitely; this bound keeps failure terminal.
var streamDrainGrace = 250 * time.Millisecond

// streamOutputHold, when non-nil, blocks stream readers until the channel is
// closed. Tests use it to reproduce status-before-drain races; production leaves
// it nil.
var streamOutputHold <-chan struct{}

// boundedTail keeps a trailing byte window for zero-output failure surfacing.
type boundedTail struct {
	mu  sync.Mutex
	buf []byte
	max int
}

func (b *boundedTail) Write(p []byte) (int, error) {
	if b == nil || b.max <= 0 {
		return len(p), nil
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.buf = append(b.buf, p...)
	if len(b.buf) > b.max {
		b.buf = append([]byte(nil), b.buf[len(b.buf)-b.max:]...)
	}
	return len(p), nil
}

func (b *boundedTail) String() string {
	if b == nil {
		return ""
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return string(b.buf)
}

// surfaceZeroOutputFailure emits a resultError from the teed stderr (or last
// raw stdout) when stream readers produced no chunks — the fallback for the
// unclassified exit-1 / zero-output case.
func surfaceZeroOutputFailure(emit emitFunc, runID string, seq *int64, stderrTail, stdoutTail *boundedTail) {
	if emit == nil || atomic.LoadInt64(seq) > 0 {
		return
	}
	msg := strings.TrimSpace(stderrTail.String())
	if msg == "" {
		msg = strings.TrimSpace(stdoutTail.String())
	}
	if msg == "" {
		return
	}
	emitStreamJSONResultError(emit, runID, truncateRunErrorMessage(msg), seq)
}

func streamOutput(emit emitFunc, runID, stream string, r io.Reader, seq *int64, done *sync.WaitGroup, streamJSON bool) {
	if streamOutputHold != nil {
		<-streamOutputHold
	}
	if stream == "stdout" && streamJSON {
		streamJSONOutput(emit, runID, r, seq, done)
		return
	}
	defer done.Done()
	if emit == nil {
		_, _ = io.Copy(io.Discard, r)
		return
	}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		n := atomic.AddInt64(seq, 1)
		emit("agent.run.output", map[string]any{
			"runId":  runID,
			"stream": stream,
			"chunk":  sc.Text() + "\n",
			"seq":    int(n),
		})
	}
}

// emitToolArtifact keeps the existing live terminal event while emitting the
// normalized, durable event consumed by chat history and review surfaces.
func emitToolArtifact(emit emitFunc, runID, toolID, toolName, inputJSON string) {
	if emit == nil {
		return
	}
	emit("agent.tool.start", map[string]any{
		"runId": runID, "toolId": toolID, "toolName": toolName, "inputJSON": inputJSON,
	})
	emitLiveStatusTool(emit, runID, toolName, inputJSON)
	emit("agent.artifact", map[string]any{
		"artifactID":  toolID,
		"runID":       runID,
		"kind":        "tool",
		"title":       toolName,
		"payloadJSON": inputJSON,
		"status":      "running",
	})
}

// emitVendorSession reports the vendor CLI's exact session/thread id, once
// extracted from structured stdout, as an internal-only notification — it is
// never forwarded to the phone (see dispatcher.wrapEmitForRun, which
// intercepts this specific method name). A conversation-ledger-backed launch
// binds the id via conversationStore.bindVendorSession so a later follow-up
// can resume this EXACT session (resumeArgv) instead of falling back to
// "continue latest in cwd" — see the cross-device sync build handoff's Task 3.
func emitVendorSession(emit emitFunc, runID, vendorSessionID string) {
	if emit == nil || vendorSessionID == "" {
		return
	}
	emit("agent.run.vendorSession", map[string]any{"runId": runID, "vendorSessionId": vendorSessionID})
}

// extractStreamJSONResultError reads Claude's terminal stream-json `result`
// object when the run failed at the vendor/API layer (is_error or non-success
// subtype). Field priority matches live claude CLI output: result, error, then
// subtype + api_error_status.
func extractStreamJSONResultError(obj map[string]any) (string, bool) {
	typ, _ := obj["type"].(string)
	if typ != "result" {
		return "", false
	}
	subtype, _ := obj["subtype"].(string)
	isError, _ := obj["is_error"].(bool)
	if !isError && (subtype == "" || subtype == "success") {
		return "", false
	}
	if r, ok := obj["result"].(string); ok && strings.TrimSpace(r) != "" {
		return strings.TrimSpace(r), true
	}
	if e, ok := obj["error"].(string); ok && strings.TrimSpace(e) != "" {
		return strings.TrimSpace(e), true
	}
	apiStatus, _ := obj["api_error_status"].(string)
	if subtype != "" && apiStatus != "" {
		return subtype + ": " + apiStatus, true
	}
	if subtype != "" && subtype != "success" {
		return subtype, true
	}
	if strings.TrimSpace(apiStatus) != "" {
		return strings.TrimSpace(apiStatus), true
	}
	return "Run failed", true
}

// extractAssistantMessageText pulls concatenated text blocks from a vendor
// {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
// envelope (Cursor Agent stream-json; also Claude's whole-message form).
func extractAssistantMessageText(obj map[string]any) string {
	msg, _ := obj["message"].(map[string]any)
	if msg == nil {
		return ""
	}
	content, ok := msg["content"].([]any)
	if !ok {
		return ""
	}
	var b strings.Builder
	for _, raw := range content {
		block, _ := raw.(map[string]any)
		if block == nil {
			continue
		}
		if t, _ := block["type"].(string); t != "" && t != "text" {
			continue
		}
		if text, _ := block["text"].(string); text != "" {
			b.WriteString(text)
		}
	}
	return b.String()
}

// cursorToolCallNameAndInput maps Cursor Agent's nested tool_call object
// (shellToolCall / writeToolCall / …) into a display name + JSON input for
// emitToolArtifact. Unknown nested keys fall back to the wrapper description.
func cursorToolCallNameAndInput(tc map[string]any) (name, inputJSON string) {
	if shell, ok := tc["shellToolCall"].(map[string]any); ok {
		args, _ := shell["args"].(map[string]any)
		cmd, _ := args["command"].(string)
		b, _ := json.Marshal(map[string]string{"command": cmd})
		return "Bash", string(b)
	}
	for key, raw := range tc {
		if !strings.HasSuffix(key, "ToolCall") {
			continue
		}
		inner, _ := raw.(map[string]any)
		if inner == nil {
			continue
		}
		args, _ := inner["args"].(map[string]any)
		b, _ := json.Marshal(args)
		base := strings.TrimSuffix(key, "ToolCall")
		if base == "" {
			base = key
		}
		if len(base) > 0 {
			base = strings.ToUpper(base[:1]) + base[1:]
		}
		return base, string(b)
	}
	if desc, _ := tc["description"].(string); desc != "" {
		b, _ := json.Marshal(map[string]string{"description": desc})
		return "Tool", string(b)
	}
	return "", ""
}

func emitStreamJSONResultError(emit emitFunc, runID, errText string, seq *int64) {
	if emit == nil || errText == "" {
		return
	}
	n := atomic.AddInt64(seq, 1)
	emit("agent.run.output", map[string]any{
		"runId": runID, "stream": "stdout", "chunk": errText + "\n", "seq": int(n),
	})
	emit("agent.run.resultError", map[string]any{"runId": runID, "error": errText})
}

func streamJSONOutput(emit emitFunc, runID string, r io.Reader, seq *int64, done *sync.WaitGroup) {
	defer done.Done()
	if emit == nil {
		_, _ = io.Copy(io.Discard, r)
		return
	}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	// Accumulator for Claude tool_use content blocks (reset per block).
	type toolAccum struct {
		toolID   string
		toolName string
		inputBuf strings.Builder
	}
	var pending *toolAccum

	// sessionCaptured latches once the first vendor session/thread id is
	// found — "the FIRST available" id is all the ledger needs (see
	// conversation_store.bindVendorSession), and re-emitting on every
	// subsequent line would be redundant churn.
	var sessionCaptured bool
	var authErrorEmitted bool // once per run — avoid duplicate assistant+result auth errors
	// sawStreamTextDelta latches when Claude-style stream_event text deltas
	// appear. Cursor Agent emits whole assistant messages without deltas
	// (verified 2026-07-19); we only fall back to those when no deltas were
	// seen, so Claude runs that also emit a final assistant envelope don't
	// double-print.
	var sawStreamTextDelta bool

	for sc.Scan() {
		line := sc.Text()

		// A line that isn't a JSON object (plain text, a JSON array, a panic/stack
		// trace printed to stdout) falls back to raw so real output is never silently
		// dropped. Unknown JSON *object* types are suppressed below (vendor metadata).
		var obj map[string]any
		if err := json.Unmarshal([]byte(line), &obj); err != nil {
			n := atomic.AddInt64(seq, 1)
			emit("agent.run.output", map[string]any{
				"runId": runID, "stream": "stdout", "chunk": line + "\n", "seq": int(n),
			})
			continue
		}

		// OpenCode carries its session id as a top-level "sessionID" field on
		// EVERY event (step_start/text/tool/step_finish/...) — verified live
		// 2026-07-02 against opencode 1.17.11 ("run --format json"). Kimi's
		// exact prompt-mode stream-json shape could not be live-verified this
		// session (the installed kimi CLI hit an unrelated account/billing
		// check before emitting any stdout — see resumeArgv's doc comment for
		// the same caveat); "sessionId" is a best-effort guess consistent with
		// kimi's own camelCase convention elsewhere in this codebase
		// (session_index.jsonl's "sessionId" field) — re-verify against a live
		// run before relying on it in production.
		if !sessionCaptured {
			if sid, ok := obj["sessionID"].(string); ok && sid != "" {
				emitVendorSession(emit, runID, sid)
				sessionCaptured = true
			} else if sid, ok := obj["sessionId"].(string); ok && sid != "" {
				emitVendorSession(emit, runID, sid)
				sessionCaptured = true
			}
		}

		typ, _ := obj["type"].(string)
		switch typ {
		case "stream_event":
			event, _ := obj["event"].(map[string]any)
			if event == nil {
				continue
			}
			eTyp, _ := event["type"].(string)
			switch eTyp {
			case "content_block_start":
				cb, _ := event["content_block"].(map[string]any)
				if cb == nil {
					break
				}
				cbType, _ := cb["type"].(string)
				switch cbType {
				case "tool_use":
					pending = &toolAccum{
						toolID:   fmt.Sprintf("%v", cb["id"]),
						toolName: fmt.Sprintf("%v", cb["name"]),
					}
					// Tool start (name only; target fills in on content_block_stop).
					emitLiveStatusTool(emit, runID, pending.toolName, "")
				case "thinking":
					pending = nil
					emitLiveStatusThinking(emit, runID)
				default:
					pending = nil
				}
			case "content_block_delta":
				delta, _ := event["delta"].(map[string]any)
				if delta == nil {
					break
				}
				switch dTyp, _ := delta["type"].(string); dTyp {
				case "text_delta":
					text, _ := delta["text"].(string)
					if text == "" {
						break
					}
					sawStreamTextDelta = true
					emitLiveStatusStreaming(emit, runID)
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text, "seq": int(n),
					})
				case "thinking_delta":
					emitLiveStatusThinking(emit, runID)
				case "input_json_delta":
					if pending != nil {
						partial, _ := delta["partial_json"].(string)
						pending.inputBuf.WriteString(partial)
					}
				}
			case "content_block_stop":
				if pending != nil {
					emitToolArtifact(emit, runID, pending.toolID, pending.toolName, pending.inputBuf.String())
					if isQuestionToolName(pending.toolName) {
						// Internal-only notification, intercepted by
						// wrapEmitForRun (which has this run's Agent/CWD
						// context this free function doesn't) to build the
						// full QuestionEvent via extractQuestionEvent
						// (question.go) — same pattern as
						// "agent.run.vendorSession" below.
						emit("agent.question.raw", map[string]any{
							"runId": runID, "toolId": pending.toolID, "toolName": pending.toolName, "inputJSON": pending.inputBuf.String(),
						})
					}
					pending = nil
				}
			}
		case "system":
			// Claude: {"type":"system","subtype":"init","session_id":"..."} is
			// the session-establishment event — the exact id `--resume` takes
			// (verified live 2026-07-02 against claude 2.1.198). No text is
			// emitted from ANY system event (init or otherwise), same as
			// before this capture was added.
			if !sessionCaptured {
				if subtype, _ := obj["subtype"].(string); subtype == "init" {
					if sid, _ := obj["session_id"].(string); sid != "" {
						emitVendorSession(emit, runID, sid)
						sessionCaptured = true
					}
				}
			}
		case "assistant":
			// Whole-message fallback is normally suppressed when Claude-style
			// stream_event text deltas already arrived (deltas supersede).
			// Exception 1: structured auth-failure assistants
			// (error=authentication_failed, live 2026-07-14) — classify promptly
			// so the phone never waits out TTFO after vendor output arrived.
			// Exception 2: Cursor Agent (and similar) emit only whole assistant
			// messages — verified live 2026-07-19 against agent 2026.07.16-899851b.
			if msg, ok := extractClaudeAssistantAuthError(obj); ok && !authErrorEmitted {
				authErrorEmitted = true
				invalidateClaudeAuthCache()
				emitStreamJSONResultError(emit, runID, msg, seq)
			} else if !sawStreamTextDelta {
				if text := extractAssistantMessageText(obj); text != "" {
					emitLiveStatusStreaming(emit, runID)
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text + "\n", "seq": int(n),
					})
				}
			}
		case "thinking":
			// Cursor Agent: {"type":"thinking","subtype":"delta"|"completed",...}
			// — verified live 2026-07-19. No text forwarded (same as Claude
			// thinking_delta / opencode reasoning) — live-status only.
			emitLiveStatusThinking(emit, runID)
		case "tool_call":
			// Cursor Agent: {"type":"tool_call","subtype":"started"|"completed",
			// "call_id":"...","tool_call":{"shellToolCall":{"args":{"command":"..."}}}}
			// — verified live 2026-07-19. Announce on started only (completed
			// carries stdout under result.success; tool cards already cover it).
			if subtype, _ := obj["subtype"].(string); subtype != "" && subtype != "started" {
				break
			}
			callID, _ := obj["call_id"].(string)
			tc, _ := obj["tool_call"].(map[string]any)
			if tc == nil {
				break
			}
			toolName, inputJSON := cursorToolCallNameAndInput(tc)
			if toolName == "" {
				break
			}
			emitToolArtifact(emit, runID, callID, toolName, inputJSON)
		case "result":
			if errText, ok := extractStreamJSONResultError(obj); ok {
				if classifyClaudeResultAuthError(obj, errText) {
					invalidateClaudeAuthCache()
					errText = normalizeClaudeAuthErrorMessage(errText)
					if authErrorEmitted {
						// Already reported via assistant auth path — skip duplicate.
						errText = ""
					} else {
						authErrorEmitted = true
					}
				}
				if errText != "" {
					emitStreamJSONResultError(emit, runID, errText, seq)
				}
			}
			// A "result" line means this turn is done — but with
			// --input-format stream-json (claudeStdinPromptArgv) the CLI does
			// NOT exit on its own afterward; verified live 2026-07-10 it idles
			// waiting for another stdin message. Signal wrapEmitForRun to close
			// this run's stdin so the process actually exits. Harmless no-op
			// for every other run shape (dispatcher.handleControlClose
			// nil-checks the run's closeStdin).
			emit("agent.control.close", map[string]any{"runId": runID})
		case "control_request":
			// The live bidirectional control channel opened by
			// --permission-prompt-tool stdio + --input-format stream-json
			// (agentArgv's doc comment) — verified live 2026-07-10:
			// {"type":"control_request","request_id":"...","request":{
			//   "subtype":"can_use_tool","tool_name":"...","input":{...},
			//   "tool_use_id":"...","requires_user_interaction":true}}.
			// Only "can_use_tool" is a known subtype; anything else is
			// ignored (forward-compat with a future protocol addition rather
			// than misinterpreting it). dispatcher.handleControlRequest owns
			// the allow/deny decision and the actual stdin write.
			req, _ := obj["request"].(map[string]any)
			if req == nil {
				break
			}
			if subtype, _ := req["subtype"].(string); subtype != "can_use_tool" {
				break
			}
			requestID, _ := obj["request_id"].(string)
			toolName, _ := req["tool_name"].(string)
			toolUseID, _ := req["tool_use_id"].(string)
			input, _ := req["input"].(map[string]any)
			if requestID == "" {
				break
			}
			emit("agent.control.request", map[string]any{
				"runId": runID, "requestId": requestID, "toolName": toolName,
				"toolUseId": toolUseID, "input": input,
			})
		case "text":
			part, _ := obj["part"].(map[string]any)
			if part == nil {
				continue
			}
			text, _ := part["text"].(string)
			if text == "" {
				continue
			}
			emitLiveStatusStreaming(emit, runID)
			n := atomic.AddInt64(seq, 1)
			emit("agent.run.output", map[string]any{
				"runId": runID, "stream": "stdout", "chunk": text, "seq": int(n),
			})
		case "reasoning":
			// opencode: {"type":"reasoning","part":{"type":"reasoning","text":"..."}}
			// — only appears on the wire with --thinking on the argv (see
			// agentArgv's opencode case doc comment) — verified live
			// 2026-07-18 against opencode 1.17.18. No text is forwarded to
			// chat output (same as Claude's thinking_delta / codex's
			// reasoning item below) — only the live-status state changes.
			emitLiveStatusThinking(emit, runID)
		case "tool_use":
			// opencode: complete tool event (input already resolved, not streaming deltas).
			part, _ := obj["part"].(map[string]any)
			if part == nil {
				continue
			}
			toolName, _ := part["tool"].(string)
			callID, _ := part["callID"].(string)
			if toolName == "" || callID == "" {
				continue
			}
			state, _ := part["state"].(map[string]any)
			if state == nil {
				continue
			}
			inputObj, _ := state["input"].(map[string]any)
			inputBytes, _ := json.Marshal(inputObj)
			displayName := toolName
			if len(toolName) > 0 {
				displayName = strings.ToUpper(toolName[:1]) + toolName[1:]
			}
			emitToolArtifact(emit, runID, callID, displayName, string(inputBytes))
		case "item.started":
			// codex --json: command execution started → show as a Bash tool card.
			item, _ := obj["item"].(map[string]any)
			if item == nil {
				continue
			}
			if itemType, _ := item["type"].(string); itemType == "command_execution" {
				cmd, _ := item["command"].(string)
				id, _ := item["id"].(string)
				cmdBytes, _ := json.Marshal(map[string]string{"command": cmd})
				emitToolArtifact(emit, runID, id, "Bash", string(cmdBytes))
			}
		case "item.completed":
			// codex --json: emit agent prose; command output is suppressed (shown via tool card).
			item, _ := obj["item"].(map[string]any)
			if item == nil {
				continue
			}
			switch itemType, _ := item["type"].(string); itemType {
			case "agent_message":
				text, _ := item["text"].(string)
				if text != "" {
					emitLiveStatusStreaming(emit, runID)
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text + "\n", "seq": int(n),
					})
				}
			case "reasoning":
				// codex --json: {"item":{"type":"reasoning","text":"**...**"}}
				// — only appears on the wire with -c model_reasoning_summary=auto
				// on the argv (see agentArgv's codex case doc comment) —
				// verified live 2026-07-18 against codex-cli 0.144.6. No text
				// is forwarded to chat output (same as Claude's thinking_delta
				// / opencode's reasoning event above) — only the live-status
				// state changes.
				emitLiveStatusThinking(emit, runID)
			}
		case "thread.started":
			// Codex: {"type":"thread.started","thread_id":"..."} — the exact
			// id `codex exec resume <id>` takes (verified live 2026-07-02
			// against codex-cli 0.135.0). No text emitted (metadata only,
			// same suppression as before this capture was added).
			if !sessionCaptured {
				if tid, _ := obj["thread_id"].(string); tid != "" {
					emitVendorSession(emit, runID, tid)
					sessionCaptured = true
				}
			}
		case "turn.started", "turn.completed",
			"step_start", "step_finish", "tool", "tool_result",
			"session_event", "message_start", "message_stop":
			// lifecycle/metadata events (opencode + codex) — suppress
		case "session":
			// Pi: {"type":"session","version":3,"id":"...","timestamp":...,
			// "cwd":"..."} — ALWAYS the first line pi emits in --mode json
			// (verified live 2026-07-18 against pi 0.80.10,
			// scratchpad/pi-smoke/pi-stream.jsonl line 0). The exact id
			// `pi ... --session <id>` resumes (see resumeArgv's pi case,
			// Phase 3(c), and pi_session_reader.go's on-disk format proof).
			if !sessionCaptured {
				if sid, _ := obj["id"].(string); sid != "" {
					emitVendorSession(emit, runID, sid)
					sessionCaptured = true
				}
			}
		case "agent_start", "turn_start", "message_end", "turn_end", "agent_end", "agent_settled",
			"tool_execution_start", "tool_execution_update", "tool_execution_end":
			// Pi lifecycle/metadata events — verified live 2026-07-18 against
			// pi 0.80.10. tool_execution_* duplicate what toolcall_end (below)
			// already reports via emitToolArtifact (same toolCallId/toolName/
			// arguments, just re-announced once the tool actually runs), so no
			// separate live-status or artifact emission is needed here.
		case "message_update":
			// Pi: {"type":"message_update","assistantMessageEvent":{"type":
			// thinking_start|thinking_delta|thinking_end|toolcall_start|
			// toolcall_delta|toolcall_end|text_start|text_delta|text_end,...}}
			// — verified live 2026-07-18 against pi 0.80.10 with a
			// bash-tool-triggering prompt (scratchpad/pi-smoke/pi-tool-stream.jsonl).
			ame, _ := obj["assistantMessageEvent"].(map[string]any)
			if ame == nil {
				break
			}
			switch ameType, _ := ame["type"].(string); ameType {
			case "thinking_start", "thinking_delta":
				emitLiveStatusThinking(emit, runID)
			case "text_delta":
				delta, _ := ame["delta"].(string)
				if delta == "" {
					break
				}
				emitLiveStatusStreaming(emit, runID)
				n := atomic.AddInt64(seq, 1)
				emit("agent.run.output", map[string]any{
					"runId": runID, "stream": "stdout", "chunk": delta, "seq": int(n),
				})
			case "toolcall_end":
				// The complete, resolved tool call — {id,name,arguments} — no
				// need to accumulate toolcall_delta's partialArgs fragments
				// (unlike Claude's content_block_delta/input_json_delta path)
				// since pi hands back the fully-parsed arguments object here.
				tc, _ := ame["toolCall"].(map[string]any)
				if tc == nil {
					break
				}
				toolID, _ := tc["id"].(string)
				toolName, _ := tc["name"].(string)
				if toolName == "" {
					break
				}
				argsObj, _ := tc["arguments"].(map[string]any)
				argsBytes, _ := json.Marshal(argsObj)
				emitToolArtifact(emit, runID, toolID, toolName, string(argsBytes))
			case "toolcall_start", "toolcall_delta", "thinking_end", "text_start", "text_end":
				// No new information to forward: toolcall_end (above) carries
				// the complete args; thinking_end/text_end are stream-closing
				// markers only.
			default:
				// Unknown assistantMessageEvent type — suppress (forward-compat).
			}
		case "context.append_message":
			// Kimi: {"type":"context.append_message","message":{"role":...,
			// "content":[{"type":"text","text":"..."}],"toolCalls":[...]}} —
			// the SAME wrapped shape kimi_session_reader.go's
			// kimiMessagesFromLine already proves from real
			// ~/.kimi-code/sessions/**/wire.jsonl captures (see
			// TestKimiTranscriptToolCallInputJSON). Kimi's live
			// `--output-format stream-json` stdout shape could NOT be
			// live-verified this session — the installed kimi CLI (0.18.0)
			// hits `provider.api_error: 402` (membership) before emitting any
			// stdout, re-confirmed 2026-07-18 (see resumeArgv's doc comment
			// for the same caveat). This mapping is shape-from-prior-captures
			// only, NOT live-verified 2026-07-18 (402). No thinking/reasoning
			// content type has ever been observed for kimi anywhere in this
			// codebase (unlike codex's "reasoning" item or opencode's
			// "reasoning" event, both live-verified above), so — per the
			// "don't invent event types" constraint — no emitLiveStatusThinking
			// call is wired here; only streaming (assistant text) and tool
			// (toolCalls) are mapped, both grounded in kimiMessagesFromLine's
			// existing, tested parsing.
			for _, m := range kimiMessagesFromLine([]byte(line)) {
				switch m.Role {
				case "assistant":
					if m.Text != "" {
						emitLiveStatusStreaming(emit, runID)
						n := atomic.AddInt64(seq, 1)
						emit("agent.run.output", map[string]any{
							"runId": runID, "stream": "stdout", "chunk": m.Text + "\n", "seq": int(n),
						})
					}
				case "toolCall":
					emitToolArtifact(emit, runID, m.ToolUseID, m.ToolName, m.InputJSON)
				}
			}
		case "":
			// kimi stream-json uses {"role":"..."} instead of {"type":"..."}.
			// Flat shape kept alongside the "context.append_message" case
			// above (uncertain which one, if either, the live stream-json
			// output actually uses — see that case's doc comment on why kimi
			// could not be live-verified this session).
			role, _ := obj["role"].(string)
			if role == "assistant" {
				content, _ := obj["content"].(string)
				if content != "" {
					emitLiveStatusStreaming(emit, runID)
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": content, "seq": int(n),
					})
				}
			}
			// meta, user, tool etc. → suppress
		default:
			// Unknown event type — suppress to avoid emitting raw JSON into chat.
		}
	}
}

func emitRunStatus(emit emitFunc, runID, status string, code *int) {
	if emit == nil {
		return
	}
	params := map[string]any{"runId": runID, "status": status}
	if code != nil {
		params["exitCode"] = *code
	}
	emit("agent.run.status", params)
	// Call sites only pass "running" | "exited" | "failed" (see rg emitRunStatus).
	// cancelled / budget-exceeded are dispatcher Status values, never emitRunStatus args.
	if status == "exited" || status == "failed" {
		clearLiveStatus(runID)
	}
}

func exitCode(waitErr error) int {
	if waitErr == nil {
		return 0
	}
	var ee *exec.ExitError
	if errors.As(waitErr, &ee) {
		return ee.ExitCode()
	}
	return -1
}

type dispatchRun struct {
	ID           string
	Agent        string
	Prompt       string
	CWD          string // working dir of the original launch; reused for continues
	Model        string // model of the original launch; reused for continues
	Status       string // running | paused | cancelled | budget-exceeded
	BudgetUSD    float64
	Contract     *runContract
	SessionID    string // captured vendor session/thread id; bound to the conversation ledger via bindVendorSession for exact resume
	WorktreePath string // non-empty when launched in a daemon-managed per-run worktree
	RepoRoot     string // repo root for worktree cleanup
	handle       *procHandle
	// pendingControlAnswer stages a resolved AskUserQuestion outcome (allow
	// with the real answer, or a fail-closed deny on hold-timeout) keyed by
	// tool_use_id, staged by registerAndWaitForQuestion (question.go) the
	// instant it resolves — strictly before the stdout scanner can reach the
	// corresponding "control_request" line for the SAME tool_use_id, because
	// registerAndWaitForQuestion runs synchronously in that same scanning
	// goroutine and blocks it until answered (see its doc comment). Consumed
	// (and deleted) by dispatcher.handleControlRequest. Guarded by
	// dispatcher.mu like every other dispatchRun field.
	pendingControlAnswer map[string]controlAnswer
	// Attachment privacy for phone-facing tool/artifact events: absolute
	// paths under the attachment root (and known object paths) are redacted
	// in wrapEmitForRun before relay/ledger. Vendor stdin is not altered.
	attachmentRoot         string
	attachmentPlaceholders map[string]string
	// observedResumeKey is non-empty only for a run launched by
	// resumeObservedSession — the dispatcher.activeObservedResumes key
	// (observedResumeKey's doc comment) this run occupies, so the
	// agent.run.status terminal handler can release it. Empty for every
	// other launch path.
	observedResumeKey string
	// startedNotified is set the first time wrapEmitForRun sees
	// agent.run.status "running" for this run, so onRunStarted fires
	// exactly once even if a launcher (or a bug) re-emits "running".
	startedNotified bool
}

// runTerminalCallback fires once when a launched run reaches a terminal process
// status (exited/failed). Used by the server to apply per-run worktree retention.
type runTerminalCallback func(runID, status string, exitCode int)

// runStartedCallback fires once when a launched run first emits status
// "running" (process confirmed started). Used by the server to push-to-start
// a Live Activity via postRunStartPush.
type runStartedCallback func(runID, agent string)

// policyEvalFunc returns the policy effect ("allow"|"ask"|"deny"), the matched
// rule, and whether the effect came from the fail-closed default (no rule matched).
type policyEvalFunc func(ApprovalEvent) (effect string, rule string, fromDefault bool)

// providerSpend tracks per-provider spend with daily/monthly caps and burn rate.
type providerSpend struct {
	todayUSD            float64
	monthUSD            float64
	dailyCap            float64
	monthlyCap          float64
	burnRate            float64 // USD per hour
	projectedDailyTotal float64
	lastUpdate          time.Time
	// currentMonth is the calendar month (year*100+month) monthUSD accumulates
	// within; a sample from a different month resets monthUSD.
	currentMonth int
	// lastDailyUSD is the previous cumulative-daily sample, used to derive the
	// month-to-month delta since todayUSD itself resets at the day boundary.
	lastDailyUSD float64
	// burnSamples tracks (timestamp, cumulativeUSD) pairs for burn rate calculation.
	burnSamples []burnSample
}

type burnSample struct {
	at         time.Time
	cumulative float64
}

// QuotaAlert is the daemon-side counterpart of QuotaGuard.SpendAlert.
type QuotaAlert struct {
	ID        string  `json:"id"`
	Provider  string  `json:"provider"`
	Type      string  `json:"type"`
	Message   string  `json:"message"`
	Threshold float64 `json:"threshold"`
	Actual    float64 `json:"actual"`
	CreatedAt string  `json:"createdAt"`
}

// QuotaProviderResult is the daemon-side counterpart of QuotaGuard.ProviderQuota.
type QuotaProviderResult struct {
	ID                  string   `json:"id"`
	DailyCapUSD         *float64 `json:"dailyCapUSD"`
	MonthlyCapUSD       *float64 `json:"monthlyCapUSD"`
	SpentTodayUSD       float64  `json:"spentTodayUSD"`
	SpentThisMonthUSD   float64  `json:"spentThisMonthUSD"`
	BurnRateUSDPerHour  float64  `json:"burnRateUSDPerHour"`
	ProjectedDailyTotal float64  `json:"projectedDailyTotal"`
	QuotaRemainingUSD   *float64 `json:"quotaRemainingUSD"`
	LastUpdated         string   `json:"lastUpdated"`
}

// QuotaGuardResult is the daemon-side response for agent.quota.status.
type QuotaGuardResult struct {
	Providers []QuotaProviderResult `json:"providers"`
	Alerts    []QuotaAlert          `json:"alerts"`
}

type dispatcher struct {
	mu               sync.Mutex
	runs             map[string]*dispatchRun
	emergencyStopped bool
	spentUSD         float64 // accumulated daily spend; gate compares against per-run BudgetUSD cap
	providerSpend    map[string]*providerSpend
	// activeObservedResumes tracks, per exact vendor+sessionID target, the
	// runID of a Lancer-launched resumeObservedSession that hasn't reached a
	// terminal status yet. Keyed by observedResumeKey(vendor, sessionID).
	// Without this, two overlapping agent.observedSession.continue calls for
	// the SAME on-disk vendor session (e.g. a slow first reply plus an
	// impatient second follow-up tap, or a client-side race) each launch
	// their own `claude --resume <sessionId>` process — two OS processes
	// concurrently reading/appending the same session transcript file, which
	// the vendor CLI's resume mechanism was never designed to tolerate
	// (found 2026-07-18: resumeObservedSession had zero same-session
	// exclusion). This does NOT cover a session still busy in the
	// ORIGINAL terminal it was started in — the daemon has no handle on
	// that process; the iOS client's isObservedSessionWorking transcript-
	// activity heuristic (ShellLiveBridge.swift) is the only signal for
	// that half and queues locally instead of calling this RPC while busy.
	// Guarded by mu like every other dispatcher field. Lazily initialized.
	activeObservedResumes map[string]string
	launch                launchFunc
	audit                 func(AuditEntry) // run-control audit sink; no-op until wired by the server
	emit                  emitFunc         // run-output/status notifier; nil until wired by the server
	// hookWired reports whether a per-action PreToolUse hook is verifiably wired
	// for the given agent binary (argv[0]). Nil ⇒ treat as not wired (fail-closed:
	// launches escalate). Set by the server from the real install state.
	hookWired func(string) bool
	// bindVendorSession persists a run's extracted vendor session/thread id to
	// the conversation ledger (conversationStore.bindVendorSession). Nil when
	// no conversation store is available (e.g. it failed to open at startup) —
	// wrapEmitForRun checks for nil before calling it. Only invoked for
	// conversation-ledger-backed launches (launchConversationTurn); plain
	// dispatch/continueRun/resumeObservedSession runs have no ledger turn to
	// bind against.
	bindVendorSession func(runID, vendorSessionID string) error
	// onRunTerminal is invoked when a launched run emits exited/failed status.
	onRunTerminal runTerminalCallback
	// onRunStarted is invoked exactly once when a launched run first emits
	// status "running" (realLauncher's emitRunStatus after cmd.Start, or any
	// test launcher that mirrors that). Nil ⇒ no-op (same fail-safe as
	// onRunTerminal). Wired by the server to handleRunStarted → postRunStartPush.
	onRunStarted runStartedCallback
	// onQuestion is invoked when a question-tool tool_use completes in a run's
	// stream-json output (see wrapEmitForRun's "agent.question.raw" case and
	// question.go's extractQuestionEvent). Nil ⇒ question tool_use calls are
	// still emitted as ordinary tool artifacts (emitToolArtifact already ran)
	// but never become a first-class QuestionEvent — no server wired yet, same
	// fail-safe-no-op convention as bindVendorSession/onRunTerminal being nil.
	onQuestion func(event QuestionEvent)
	// deliverApproval routes a launch-time policy "ask" gate's ApprovalEvent
	// through the server's real delivery chokepoint (approvals store + durable
	// queue + E2E relay) so it actually reaches the phone as a decidable card,
	// instead of the event being constructed and then discarded. Nil ⇒ no
	// server wired yet (e.g. a dispatcher built directly in tests) — the
	// "ask" branch still returns dispatchResult{Status:"needsApproval"}, it
	// just can't deliver a card, same as before this field existed.
	deliverApproval func(ApprovalEvent) <-chan hookDecision
	// onConversationLaunchResolved fires once for every conversation-append
	// launch-gate "ask" whose async decision resolved to something other than
	// "started" — i.e. an approve that then failed to actually launch (denied
	// by a later step, an auth-preflight error, etc.) — so the caller can
	// persist that outcome onto the conversation ledger and clean up any
	// worktree it created, exactly like conversationsAppend's synchronous path
	// already does for an inline (non-"ask") result. A plain approve→launch
	// that starts successfully does NOT call this: the ordinary emit/ledger
	// plumbing (wrapEmitForRun → persistConversationEvent) already covers a
	// "started" run identically to any other dispatch. Nil ⇒ no server wired
	// (tests) — the resume goroutine still runs the launch, it just can't
	// report a non-started outcome back to the ledger.
	onConversationLaunchResolved func(runID string, result dispatchResult, worktreePath, worktreeRepoRoot string)
	// claudeAuthPreflight gates Claude Code launches. Nil ⇒ package default
	// (claudeAuthPreflight) unless tests disable it via
	// claudeAuthPreflightDisabledForTest. loggedIn:false and probe failures
	// both fail closed (see claude_auth.go).
	claudeAuthPreflight func() error
	// receiptAccum/receipts track per-run evidence for lancer.proof/v0 (A1).
	receiptMu    sync.Mutex
	receiptAccum map[string]*receiptAccumulator
	receipts     map[string]*runReceipt
	receiptGit   gitRunner
}

func newDispatcher() *dispatcher {
	d := &dispatcher{
		runs:          map[string]*dispatchRun{},
		providerSpend: map[string]*providerSpend{},
		launch:        realLauncher,
		audit:         func(AuditEntry) {},
	}
	if os.Getenv("LANCER_RELAY_E2E_FAKE_DISPATCH") == "1" {
		d.launch = e2eFakeRelayLaunch
	}
	return d
}

// e2eFakeRelayLaunch is used only by scripts/validation/relay-approval-e2e.sh to
// prove the receipt pipeline on a live, relay-paired resident daemon without
// invoking a real vendor CLI.
func e2eFakeRelayLaunch(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
	go func() {
		emit("agent.tool.start", map[string]any{
			"inputJSON": `{"command":"go test ./..."}`,
		})
		emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
	}()
	return &procHandle{kill: func() {}}, nil
}

// emitAudit forwards to the audit sink, tolerating a nil sink (a dispatcher built
// directly in tests has no sink wired).
func (d *dispatcher) emitAudit(e AuditEntry) {
	if d.audit != nil {
		d.audit(e)
	}
}

// deliverLaunchApproval routes a launch-time policy "ask" gate's constructed
// ApprovalEvent through deliverApproval (server.deliverApprovalEvent) so it
// actually reaches the phone as a decidable card, and returns the decision
// channel so a caller that can actually DO something once the human decides
// (see launchConversationTurn's "ask" branch / resumeConversationLaunch) can
// wait on it. Callers that have nothing to resume (dispatch/continueRun/
// resumeObservedSession's "ask" branches — no vendor process ever launches
// for those until a NEW dispatch call re-evaluates policy, so there is
// nothing to continue here) may simply ignore the returned channel; the
// decision is still recorded regardless of whether anything reads it
// (applyDecision/resolve() do that unconditionally). Nil-safe: a dispatcher
// with no server wired (tests) just skips delivery, matching pre-fix
// behavior, and returns a nil channel.
func (d *dispatcher) deliverLaunchApproval(event ApprovalEvent) <-chan hookDecision {
	if d.deliverApproval != nil {
		return d.deliverApproval(event)
	}
	return nil
}

// wrapEmitForRun wraps the dispatcher's shared emit sink for one launched
// run so the internal "agent.run.vendorSession" event (emitted at most once
// by streamJSONOutput, when it extracts a vendor CLI's session/thread id from
// structured stdout — see emitVendorSession) updates dispatchRun.SessionID
// for this run and — when ledgerBacked — also persists the id via
// d.bindVendorSession so a later agent.conversations.append follow-up on the
// same conversation gets resumeMode "exact" instead of "latestInCwdFallback"
// (see buildConversationArgv). Every other method name passes straight
// through to d.emit unchanged; the vendorSession event itself is NEVER
// forwarded further — it is an internal signal, not a phone-facing
// notification.
//
// ledgerBacked is false for plain dispatch/continueRun/resumeObservedSession
// launches (no conversation ledger row exists for their runID, so calling
// bindVendorSession would just fail with "no turn found" on every ordinary
// chat message) and true only for launchConversationTurn, whose runID always
// has a ledger turn already persisted by conversationStore.beginTurn before
// the process launches.
func (d *dispatcher) wrapEmitForRun(runID string, ledgerBacked bool) emitFunc {
	return func(method string, params any) {
		// Phone-event privacy first: redact verified attachment absolute paths
		// in tool/artifact/live-status/output/question JSON before receipt
		// accumulation, relay, and ledger. Vendor stdin is not altered
		// (redaction is emit-side only; replacement is bounded to this run's
		// resolved attachments — not a global filesystem scrub).
		if method == "agent.tool.start" || method == "agent.artifact" || method == liveStatusMethod ||
			method == "agent.run.output" || method == "agent.question.raw" {
			d.mu.Lock()
			run := d.runs[runID]
			var root string
			var placeholders map[string]string
			if run != nil {
				root = run.attachmentRoot
				placeholders = run.attachmentPlaceholders
			}
			d.mu.Unlock()
			params = redactAttachmentPathsInParams(method, params, root, placeholders)
		}
		d.observeReceiptEmit(runID, method, params)
		if method == "agent.run.vendorSession" {
			m, _ := params.(map[string]any)
			vendorSessionID, _ := m["vendorSessionId"].(string)
			if vendorSessionID == "" {
				return
			}
			d.mu.Lock()
			if run := d.runs[runID]; run != nil {
				run.SessionID = vendorSessionID
			}
			d.mu.Unlock()
			if ledgerBacked && d.bindVendorSession != nil {
				_ = d.bindVendorSession(runID, vendorSessionID)
			}
			return
		}
		if method == "agent.question.raw" {
			m, _ := params.(map[string]any)
			toolID, _ := m["toolId"].(string)
			toolName, _ := m["toolName"].(string)
			inputJSON, _ := m["inputJSON"].(string)
			d.mu.Lock()
			run := d.runs[runID]
			d.mu.Unlock()
			var agent, cwd string
			if run != nil {
				agent, cwd = run.Agent, run.CWD
			}
			if event, ok := extractQuestionEvent(agent, runID, cwd, toolID, toolName, inputJSON); ok && d.onQuestion != nil {
				d.onQuestion(event)
			}
			return
		}
		if method == "agent.control.request" {
			m, _ := params.(map[string]any)
			requestID, _ := m["requestId"].(string)
			toolName, _ := m["toolName"].(string)
			toolUseID, _ := m["toolUseId"].(string)
			input, _ := m["input"].(map[string]any)
			d.handleControlRequest(runID, requestID, toolName, toolUseID, input)
			return
		}
		if method == "agent.control.close" {
			d.mu.Lock()
			run := d.runs[runID]
			d.mu.Unlock()
			if run != nil && run.handle != nil && run.handle.closeStdin != nil {
				run.handle.closeStdin()
			}
			return
		}
		if method == "agent.run.status" {
			if m, ok := params.(map[string]any); ok {
				status, _ := m["status"].(string)
				exitCode := -1
				switch c := m["exitCode"].(type) {
				case int:
					exitCode = c
				case float64:
					exitCode = int(c)
				}
				if status == "running" {
					// Single chokepoint for Live Activity push-to-start: every
					// Lancer-dispatched launch path (dispatch/continueRun/
					// resumeObservedSession/launchConversationTurn) flows
					// through wrapEmitForRun, and realLauncher emits
					// "running" exactly once after cmd.Start succeeds.
					var agent string
					var fire bool
					d.mu.Lock()
					if run := d.runs[runID]; run != nil && !run.startedNotified {
						run.startedNotified = true
						agent = run.Agent
						fire = true
					}
					d.mu.Unlock()
					if fire && d.onRunStarted != nil {
						d.onRunStarted(runID, agent)
					}
				}
				if status == "exited" || status == "failed" {
					d.finalizeReceipt(runID, status, exitCode)
					// Release this run's activeObservedResumes reservation
					// (if any) now that it's reached a terminal state — the
					// same session can be resumed again. Every run has this
					// field checked (not just ones from resumeObservedSession):
					// it's empty for every other launch path, so the delete
					// is a safe no-op for them.
					d.mu.Lock()
					if run := d.runs[runID]; run != nil && run.observedResumeKey != "" {
						delete(d.activeObservedResumes, run.observedResumeKey)
						run.observedResumeKey = ""
					}
					d.mu.Unlock()
					if d.onRunTerminal != nil {
						d.onRunTerminal(runID, status, exitCode)
					}
				}
			}
		}
		if d.emit != nil {
			d.emit(method, params)
		}
	}
}

// controlAnswer is a resolved AskUserQuestion outcome staged by
// registerAndWaitForQuestion (question.go) for delivery as a
// control_response once the corresponding control_request's request_id is
// known — see dispatchRun.pendingControlAnswer's doc comment.
type controlAnswer struct {
	allow   bool
	answers map[string]any // Agent-SDK "answers" shape: question text -> label | []label | freeText
	message string         // deny message; empty for allow
}

// controlResponsePayload mirrors the exact wire shape verified live
// 2026-07-10 (see agentArgv's doc comment / docs/plans/
// 2026-07-10-in-thread-questions-Status.md's M3 probe evidence):
//
//	{"type":"control_response","response":{"subtype":"success",
//	 "request_id":"...","response":{"behavior":"allow"|"deny", ...}}}
type controlResponsePayload struct {
	Type     string                  `json:"type"`
	Response controlResponseEnvelope `json:"response"`
}

type controlResponseEnvelope struct {
	Subtype   string            `json:"subtype"`
	RequestID string            `json:"request_id"`
	Response  controlToolResult `json:"response"`
}

type controlToolResult struct {
	Behavior     string         `json:"behavior"` // "allow" | "deny"
	UpdatedInput map[string]any `json:"updatedInput,omitempty"`
	Message      string         `json:"message,omitempty"`
}

func allowControlResponse(requestID string, updatedInput map[string]any) controlResponsePayload {
	return controlResponsePayload{
		Type: "control_response",
		Response: controlResponseEnvelope{
			Subtype:   "success",
			RequestID: requestID,
			Response:  controlToolResult{Behavior: "allow", UpdatedInput: updatedInput},
		},
	}
}

func denyControlResponse(requestID, message string) controlResponsePayload {
	return controlResponsePayload{
		Type: "control_response",
		Response: controlResponseEnvelope{
			Subtype:   "success",
			RequestID: requestID,
			Response:  controlToolResult{Behavior: "deny", Message: message},
		},
	}
}

// buildControlAnswers converts a resolved QuestionAnswer into the Agent
// SDK's documented "answers" shape (question text -> selected label, an
// array of labels for multiSelect, or free text) — verified live 2026-07-10:
// a plain string works for single-select, a JSON array of strings for
// multiSelect. Items must already be aligned 1:1 with event.Questions by
// index (questionStore.resolve's own contract — see question.go).
func buildControlAnswers(event QuestionEvent, answer QuestionAnswer) map[string]any {
	out := make(map[string]any, len(event.Questions))
	for i, q := range event.Questions {
		if i >= len(answer.Items) {
			break
		}
		item := answer.Items[i]
		switch {
		case len(item.SelectedLabels) > 1:
			out[q.Question] = item.SelectedLabels
		case len(item.SelectedLabels) == 1:
			out[q.Question] = item.SelectedLabels[0]
		case item.FreeText != "":
			out[q.Question] = item.FreeText
		default:
			out[q.Question] = ""
		}
	}
	return out
}

// stashControlAnswer records a resolved AskUserQuestion outcome for runID's
// pending control_request to pick up — see dispatchRun.pendingControlAnswer.
// A no-op if the run is gone (e.g. cancelled/exited between the answer
// resolving and this call) or toolUseID is empty.
func (d *dispatcher) stashControlAnswer(runID, toolUseID string, ca controlAnswer) {
	if toolUseID == "" {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil {
		return
	}
	if run.pendingControlAnswer == nil {
		run.pendingControlAnswer = map[string]controlAnswer{}
	}
	run.pendingControlAnswer[toolUseID] = ca
}

// takeControlAnswer pops (retrieves and deletes) a staged control answer.
func (d *dispatcher) takeControlAnswer(runID, toolUseID string) (controlAnswer, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.pendingControlAnswer == nil {
		return controlAnswer{}, false
	}
	ca, ok := run.pendingControlAnswer[toolUseID]
	if ok {
		delete(run.pendingControlAnswer, toolUseID)
	}
	return ca, ok
}

// handleControlRequest answers a live control_request (streamJSONOutput's
// "control_request" case, forwarded here via wrapEmitForRun's
// "agent.control.request" internal event) on the run's actual child stdin.
//
// For a recognized question tool (isQuestionToolName), it answers with
// whatever registerAndWaitForQuestion already staged via stashControlAnswer:
// allow with the real structured answer, or a fail-closed deny if the
// 10-minute hold timed out with no answer. If nothing was staged at all (the
// question pipeline never registered this tool_use_id — e.g. onQuestion is
// nil, or extractQuestionEvent didn't recognize the input), this denies and
// audits rather than guessing.
//
// Any OTHER tool name is denied unconditionally, no exceptions: Lancer's
// PreToolUse hook already gates every ordinary tool call before canUseTool
// is ever consulted (docs/agent-contract.md; see launchRisk's hookWired
// convention) — ordinary tool approvals are NOT routed through this control
// protocol. A control_request for e.g. Bash arriving here means the hook did
// not resolve it, an unexpected and security-relevant state this must never
// silently allow. This is a deliberate scope boundary for M3, not an
// oversight — see docs/plans/2026-07-10-in-thread-questions-Status.md.
func (d *dispatcher) handleControlRequest(runID, requestID, toolName, toolUseID string, input map[string]any) {
	if requestID == "" {
		return
	}
	d.mu.Lock()
	run := d.runs[runID]
	d.mu.Unlock()
	if run == nil || run.handle == nil || run.handle.writeControlResponse == nil {
		return
	}

	var resp controlResponsePayload
	if isQuestionToolName(toolName) {
		if ca, ok := d.takeControlAnswer(runID, toolUseID); ok {
			if ca.allow {
				updated := make(map[string]any, len(input)+1)
				for k, v := range input {
					updated[k] = v
				}
				updated["answers"] = ca.answers
				resp = allowControlResponse(requestID, updated)
			} else {
				resp = denyControlResponse(requestID, ca.message)
			}
		} else {
			resp = denyControlResponse(requestID, "no answer available for this question")
			d.emitAudit(AuditEntry{Action: "control-request-unresolved", Agent: run.Agent, Kind: "question", Command: toolName, ApprovalID: toolUseID})
		}
	} else {
		resp = denyControlResponse(requestID, "tool approval must go through Lancer's PreToolUse hook, not an interactive prompt")
		d.emitAudit(AuditEntry{Action: "control-request-denied-unexpected-tool", Agent: run.Agent, Kind: "command", Command: toolName, ApprovalID: toolUseID})
	}

	payload, err := json.Marshal(resp)
	if err != nil {
		return
	}
	_ = run.handle.writeControlResponse(payload)
}

func (d *dispatcher) receiptStartFromDispatch(p dispatchParams) receiptStartParams {
	return receiptStartParams{
		agent:        p.Agent,
		model:        p.Model,
		cwd:          p.CWD,
		worktreePath: p.worktreePath,
		contract:     runContractToReceipt(p.Contract),
	}
}

// takeRunWorktree returns and clears the managed worktree metadata for a run.
func (d *dispatcher) takeRunWorktree(runID string) (path, repoRoot string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.WorktreePath == "" {
		return "", ""
	}
	path, repoRoot = run.WorktreePath, run.RepoRoot
	run.WorktreePath = ""
	run.RepoRoot = ""
	return path, repoRoot
}

// setSpentUSD updates the tracked daily spend and enforces per-run caps.
func (d *dispatcher) setSpentUSD(v float64) {
	d.mu.Lock()
	d.spentUSD = v
	d.mu.Unlock()
	d.enforceBudgets()
}

func (d *dispatcher) runStatus(runID string) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	if run := d.runs[runID]; run != nil {
		return run.Status
	}
	return ""
}

func emergencyStoppedResult() dispatchResult {
	return dispatchResult{Status: "emergencyStopped", Message: "emergency stop is active"}
}

// ensureClaudeAuth runs the Claude Code auth preflight when agent is claudeCode.
// Other vendors are untouched. See claude_auth.go for fail-closed contract.
func (d *dispatcher) ensureClaudeAuth(agent string) error {
	if normalizeAgentSource(agent) != "claudeCode" {
		return nil
	}
	if d.claudeAuthPreflight != nil {
		return d.claudeAuthPreflight()
	}
	if claudeAuthPreflightDisabledForTest {
		return nil
	}
	return claudeAuthPreflight()
}

func (d *dispatcher) emergencyStopActive() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.emergencyStopped
}

// setEmergencyStopped sets the in-memory latch directly, bypassing the
// process-killing/approval-denying side effects in emergencyStop(). Used only
// to (a) restore a persisted latch at daemon startup (server.newServer) and
// (b) lift it on an explicit clear (server.clearEmergencyStop) — never from
// the hot dispatch/hook paths themselves.
func (d *dispatcher) setEmergencyStopped(active bool) {
	d.mu.Lock()
	d.emergencyStopped = active
	d.mu.Unlock()
}

func (d *dispatcher) attachLaunchHandle(runID string, handle *procHandle) bool {
	kill := false
	d.mu.Lock()
	if run := d.runs[runID]; run != nil {
		if d.emergencyStopped || run.Status == "cancelled" {
			run.Status = "cancelled"
			kill = true
		} else {
			run.handle = handle
		}
	} else {
		kill = true
	}
	d.mu.Unlock()
	if kill && handle != nil {
		handle.kill()
		return false
	}
	return !kill
}

func (d *dispatcher) emergencyStop() int {
	type stoppedRun struct {
		id     string
		agent  string
		handle *procHandle
	}
	var stopped []stoppedRun
	d.mu.Lock()
	d.emergencyStopped = true
	for _, run := range d.runs {
		if run.Status != "running" && run.Status != "paused" {
			continue
		}
		run.Status = "cancelled"
		stopped = append(stopped, stoppedRun{id: run.ID, agent: run.Agent, handle: run.handle})
	}
	d.mu.Unlock()

	for _, run := range stopped {
		if run.handle != nil {
			run.handle.kill()
		}
		d.emitAudit(AuditEntry{Action: "run-stopped", Agent: run.agent, Kind: "run-control", ApprovalID: run.id})
	}
	return len(stopped)
}

// runForCWD returns the ID of an active (running) dispatched run whose cwd and
// agent match, so a hook-originated approval can be correlated back to the run
// that triggered it. Returns "" when no active run matches.
func (d *dispatcher) runForCWD(cwd, agent string) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	want := expandHome(cwd)
	wantAgent := normalizeAgentSource(agent)
	for id, run := range d.runs {
		if run.Status != "running" {
			continue
		}
		if expandHome(run.CWD) == want && normalizeAgentSource(run.Agent) == wantAgent {
			return id
		}
	}
	return ""
}

// setBudget updates a run's cap and enforces it immediately. usd <= 0 removes the
// cap (the run continues unconstrained).
func (d *dispatcher) setBudget(runID string, usd float64) bool {
	d.mu.Lock()
	run := d.runs[runID]
	if run == nil {
		d.mu.Unlock()
		return false
	}
	run.BudgetUSD = usd
	d.mu.Unlock()
	d.enforceBudgets()
	return true
}

// enforceBudgets kills any running/paused run whose accumulated spend meets its cap.
func (d *dispatcher) enforceBudgets() {
	type stoppedRun struct{ id, agent string }
	var stopped []stoppedRun
	d.mu.Lock()
	for _, run := range d.runs {
		if run.Status != "running" && run.Status != "paused" {
			continue
		}
		// spentUSD is a shared daily total; any run whose cap the total has reached is stopped.
		if run.BudgetUSD > 0 && d.spentUSD >= run.BudgetUSD {
			if run.handle != nil {
				run.handle.kill()
			}
			run.Status = "budget-exceeded"
			stopped = append(stopped, stoppedRun{run.ID, run.Agent})
		}
	}
	d.mu.Unlock()
	// Audit outside the lock so the file write never blocks the dispatcher mutex.
	for _, s := range stopped {
		d.emitAudit(AuditEntry{Action: "run-budget-exceeded", Agent: s.agent, Kind: "run-control", ApprovalID: s.id})
	}
}

// updateProviderSpend records cumulative spend for a provider and recomputes burn rate.
func (d *dispatcher) updateProviderSpend(provider string, usd float64) {
	d.mu.Lock()
	defer d.mu.Unlock()

	now := time.Now()
	ps, ok := d.providerSpend[provider]
	if !ok {
		ps = &providerSpend{lastUpdate: now}
		d.providerSpend[provider] = ps
	}

	ps.todayUSD = usd
	ps.lastUpdate = now

	// Monthly accumulation mirrors daily tracking: usd is the cumulative daily
	// spend, so add the delta since the last sample. On a month rollover, reset
	// the monthly total to the current sample's spend.
	month := now.Year()*100 + int(now.Month())
	if ps.currentMonth != month {
		ps.currentMonth = month
		ps.monthUSD = usd
		ps.lastDailyUSD = usd
	} else {
		delta := usd - ps.lastDailyUSD
		if delta < 0 {
			// usd reset (new day): the full sample is new monthly spend.
			delta = usd
		}
		ps.monthUSD += delta
		ps.lastDailyUSD = usd
	}

	// Append burn sample (keep last 60 minutes).
	ps.burnSamples = append(ps.burnSamples, burnSample{at: now, cumulative: usd})
	cutoff := now.Add(-60 * time.Minute)
	filtered := ps.burnSamples[:0]
	for _, s := range ps.burnSamples {
		if s.at.After(cutoff) {
			filtered = append(filtered, s)
		}
	}
	ps.burnSamples = filtered

	// Compute burn rate from oldest sample in window.
	if len(ps.burnSamples) >= 2 {
		oldest := ps.burnSamples[0]
		elapsed := now.Sub(oldest.at).Hours()
		if elapsed > 0 {
			ps.burnRate = (usd - oldest.cumulative) / elapsed
		}
	}

	// Project daily total: current spend + (burnRate * hours remaining today).
	hoursRemaining := 24.0 - float64(now.Hour()) - float64(now.Minute())/60.0
	if hoursRemaining < 0 {
		hoursRemaining = 0
	}
	ps.projectedDailyTotal = usd + ps.burnRate*hoursRemaining
}

// setProviderCap sets daily and/or monthly caps for a provider. Pass 0 to leave unchanged.
func (d *dispatcher) setProviderCap(provider string, dailyUSD, monthlyUSD float64) {
	d.mu.Lock()
	defer d.mu.Unlock()

	ps, ok := d.providerSpend[provider]
	if !ok {
		ps = &providerSpend{lastUpdate: time.Now()}
		d.providerSpend[provider] = ps
	}
	if dailyUSD > 0 {
		ps.dailyCap = dailyUSD
	}
	if monthlyUSD > 0 {
		ps.monthlyCap = monthlyUSD
	}
}

// checkProviderQuotasLocked is the lock-free body. The caller MUST already hold
// d.mu. Split out so getQuotaGuard (which holds the lock) can reuse it without
// re-locking the non-reentrant mutex — re-locking deadlocked the resident
// daemon's single-threaded attach loop, silently breaking every approval that
// arrived after the phone's connect-time agent.quota.status call.
func (d *dispatcher) checkProviderQuotasLocked() []QuotaAlert {
	var alerts []QuotaAlert
	now := time.Now()

	for name, ps := range d.providerSpend {
		if ps.dailyCap > 0 {
			pct := ps.todayUSD / ps.dailyCap
			if pct >= 1.0 {
				alerts = append(alerts, QuotaAlert{
					ID:        newUUID(),
					Provider:  name,
					Type:      "overLimit",
					Message:   name + " daily spend $" + fmt.Sprintf("%.2f", ps.todayUSD) + " exceeds cap $" + fmt.Sprintf("%.2f", ps.dailyCap),
					Threshold: ps.dailyCap,
					Actual:    ps.todayUSD,
					CreatedAt: now.UTC().Format(time.RFC3339),
				})
			} else if pct >= 0.8 {
				alerts = append(alerts, QuotaAlert{
					ID:        newUUID(),
					Provider:  name,
					Type:      "nearLimit",
					Message:   name + " daily spend at " + fmt.Sprintf("%.0f", pct*100) + "% of cap",
					Threshold: ps.dailyCap,
					Actual:    ps.todayUSD,
					CreatedAt: now.UTC().Format(time.RFC3339),
				})
			}
		}
		if ps.dailyCap > 0 && ps.projectedDailyTotal > ps.dailyCap {
			alerts = append(alerts, QuotaAlert{
				ID:        newUUID(),
				Provider:  name,
				Type:      "projectedExceed",
				Message:   name + " projected $" + fmt.Sprintf("%.2f", ps.projectedDailyTotal) + " exceeds daily cap",
				Threshold: ps.dailyCap,
				Actual:    ps.projectedDailyTotal,
				CreatedAt: now.UTC().Format(time.RFC3339),
			})
		}
		if ps.burnRate > 5.0 {
			alerts = append(alerts, QuotaAlert{
				ID:        newUUID(),
				Provider:  name,
				Type:      "burnRateHigh",
				Message:   name + " burn rate $" + fmt.Sprintf("%.2f", ps.burnRate) + "/hr",
				Threshold: 5.0,
				Actual:    ps.burnRate,
				CreatedAt: now.UTC().Format(time.RFC3339),
			})
		}
	}
	return alerts
}

// getQuotaGuard returns the full quota status for all tracked providers.
func (d *dispatcher) getQuotaGuard() QuotaGuardResult {
	d.mu.Lock()
	defer d.mu.Unlock()

	result := QuotaGuardResult{}
	now := time.Now()

	for name, ps := range d.providerSpend {
		p := QuotaProviderResult{
			ID:                  name,
			SpentTodayUSD:       ps.todayUSD,
			SpentThisMonthUSD:   ps.monthUSD,
			BurnRateUSDPerHour:  ps.burnRate,
			ProjectedDailyTotal: ps.projectedDailyTotal,
			LastUpdated:         ps.lastUpdate.UTC().Format(time.RFC3339),
		}
		if ps.dailyCap > 0 {
			p.DailyCapUSD = &ps.dailyCap
			remaining := ps.dailyCap - ps.todayUSD
			p.QuotaRemainingUSD = &remaining
		}
		if ps.monthlyCap > 0 {
			p.MonthlyCapUSD = &ps.monthlyCap
		}
		result.Providers = append(result.Providers, p)
	}
	result.Alerts = d.checkProviderQuotasLocked()
	_ = now
	return result
}

// dispatch applies the budget + policy gate, then launches. It NEVER launches a
// run that policy denies/escalates, and refuses once the budget cap is reached.
func (d *dispatcher) dispatch(p dispatchParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	argv, ok := agentArgv(p.Agent, p.Prompt, p.Model, p.FullTools)
	if !ok {
		return dispatchResult{Status: "error", Message: "unknown agent: " + p.Agent}
	}
	if contractTooLarge(p.Contract) {
		return dispatchResult{Status: "error", Message: "contract too large"}
	}
	p.Contract = cloneRunContract(p.Contract)

	// Budget gate (hard stop). BudgetUSD <= 0 means "no cap".
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if p.BudgetUSD > 0 && spent >= p.BudgetUSD {
		audit(AuditEntry{Action: "dispatch-budget-exceeded", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return dispatchResult{Status: "budgetExceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, p.BudgetUSD)}
	}

	// Policy gate. A dispatched run defaults to medium risk so the bundled policy
	// escalates it unless a rule explicitly allows — fail-closed by default.
	command := "[dispatch] " + strings.Join(argv, " ")
	event := ApprovalEvent{
		ApprovalID:  newUUID(),
		Agent:       normalizeAgentSource(p.Agent),
		Kind:        "command",
		Command:     command,
		CWD:         p.CWD,
		Risk:        d.launchRisk(argv),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		ContentHash: computeContentHash(command, "", p.CWD, ""),
	}
	effect, rule, fromDefault := evalFn(event)
	effect = relaxLaunchEscalation(effect, fromDefault, argv, d.hookWired)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "dispatch-denied", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "dispatch-needs-approval", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "ask", Rule: rule})
		d.deliverLaunchApproval(event)
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	// Auth preflight BEFORE inserting a "running" run — a 20s claude auth
	// probe must not leave a ghost run visible to status/list. Fast-exit race
	// protection (record before launch) is preserved below.
	if err := d.ensureClaudeAuth(p.Agent); err != nil {
		audit(AuditEntry{Action: "dispatch-auth-preflight", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}

	// Allocate the runId before launch so streamed output/status events can be
	// tagged with it from the first byte. The run record (including worktree
	// metadata) is created BEFORE launch runs — d.launch's emit callback can
	// fire synchronously/immediately for a fast-exiting process, and it must
	// find this record already in place or run-terminal handling (worktree
	// retention, status tracking) silently no-ops against a nil run.
	id := newUUID()
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "dispatch-emergency-stopped", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD, Contract: p.Contract, WorktreePath: p.worktreePath, RepoRoot: p.worktreeRepoRoot}
	d.mu.Unlock()
	d.startReceiptAccum(id, d.receiptStartFromDispatch(p))
	handle, err := d.launch(argv, p.CWD, id, d.wrapEmitForRun(id, false))
	if err != nil {
		d.mu.Lock()
		delete(d.runs, id)
		d.mu.Unlock()
		audit(AuditEntry{Action: "dispatch-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	if !d.attachLaunchHandle(id, handle) {
		audit(AuditEntry{Action: "dispatch-emergency-stopped", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, ApprovalID: id})
		res := emergencyStoppedResult()
		res.RunID = id
		return res
	}
	audit(AuditEntry{Action: "dispatch-launched", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule, CWD: expandHome(p.CWD)}
}

func (d *dispatcher) cancel(runID string) bool {
	d.mu.Lock()
	run := d.runs[runID]
	// Idempotent: a second cancel returns false and emits no duplicate audit entry.
	if run == nil || run.Status == "cancelled" {
		d.mu.Unlock()
		return false
	}
	if run.handle != nil {
		run.handle.kill()
	}
	run.Status = "cancelled"
	agent := run.Agent
	d.mu.Unlock()
	d.emitAudit(AuditEntry{Action: "run-stopped", Agent: agent, Kind: "run-control", ApprovalID: runID})
	return true
}

func (d *dispatcher) pause(runID string) bool {
	d.mu.Lock()
	run := d.runs[runID]
	if run == nil || run.Status != "running" {
		d.mu.Unlock()
		return false
	}
	if run.handle != nil {
		run.handle.pause()
	}
	run.Status = "paused"
	agent := run.Agent
	d.mu.Unlock()
	d.emitAudit(AuditEntry{Action: "run-paused", Agent: agent, Kind: "run-control", ApprovalID: runID})
	return true
}

func (d *dispatcher) resume(runID string) bool {
	d.mu.Lock()
	run := d.runs[runID]
	if run == nil || run.Status != "paused" {
		d.mu.Unlock()
		return false
	}
	if run.handle != nil {
		run.handle.resume()
	}
	run.Status = "running"
	agent := run.Agent
	d.mu.Unlock()
	d.emitAudit(AuditEntry{Action: "run-resumed", Agent: agent, Kind: "run-control", ApprovalID: runID})
	return true
}

// continueFallback carries enough context to continue a conversation when the
// daemon no longer holds the original run in memory (the process ended, or the
// daemon restarted). The phone has this from the persisted conversation, so a
// "continue" survives a daemon restart instead of dead-ending on "unknown run".
type continueFallback struct {
	Agent     string
	CWD       string
	Model     string
	BudgetUSD float64
}

// continueRun re-launches the vendor CLI to continue an existing run's conversation
// with a new prompt, as a FRESH process under a NEW runId (avoids the per-launch seq
// collision in the phone's RunOutputStore). It re-passes the budget + policy gates
// exactly like dispatch(); a follow-up prompt is new attacker-influenceable input.
// When the in-memory run is gone, it falls back to `fb` (agent/cwd/model from the
// phone's persisted conversation) — `<vendor> --continue` resumes the most recent
// session in that directory, so leaving a chat and returning still works.
func (d *dispatcher) continueRun(runID, prompt string, fb continueFallback, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	d.mu.Lock()
	run := d.runs[runID]
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "continue-emergency-stopped", Kind: "dispatch", Command: prompt})
		return emergencyStoppedResult()
	}
	d.mu.Unlock()

	var agent, cwd, model string
	var budget float64
	switch {
	case run != nil:
		agent, cwd, model, budget = run.Agent, run.CWD, run.Model, run.BudgetUSD
	case fb.Agent != "":
		agent, cwd, model, budget = fb.Agent, fb.CWD, fb.Model, fb.BudgetUSD
	default:
		return dispatchResult{Status: "error", Message: "unknown run: " + runID}
	}

	// agent.run.continue (this legacy in-memory-run path, distinct from the
	// conversation-ledger's launchConversationTurn) has no FullTools field on
	// the wire yet — out of scope for the composer's per-dispatch toggle, so
	// this always launches strict, same as before.
	argv, ok := continueArgv(agent, prompt, model, false)
	if !ok {
		return dispatchResult{Status: "error", Message: "continue not supported for agent: " + agent}
	}

	// Budget gate (shared daily total vs this run's cap).
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if budget > 0 && spent >= budget {
		audit(AuditEntry{Action: "continue-budget-exceeded", Agent: agent, Kind: "dispatch", Command: prompt})
		return dispatchResult{Status: "budgetExceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, budget)}
	}

	// Policy gate (same risk scoring as dispatch: low for a hook-wired agent whose
	// tools are gated per-action, medium otherwise).
	continueCommand := "[continue] " + strings.Join(argv, " ")
	event := ApprovalEvent{
		ApprovalID:  newUUID(),
		Agent:       normalizeAgentSource(agent),
		Kind:        "command",
		Command:     continueCommand,
		CWD:         cwd,
		Risk:        d.launchRisk(argv),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		RunID:       runID,
		ContentHash: computeContentHash(continueCommand, "", cwd, ""),
	}
	effect, rule, fromDefault := evalFn(event)
	effect = relaxLaunchEscalation(effect, fromDefault, argv, d.hookWired)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "continue-denied", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "continue-needs-approval", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "ask", Rule: rule})
		d.deliverLaunchApproval(event)
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	if err := d.ensureClaudeAuth(agent); err != nil {
		audit(AuditEntry{Action: "continue-auth-preflight", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}

	id := newUUID()
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "continue-emergency-stopped", Agent: agent, Kind: "dispatch", Command: prompt})
		return emergencyStoppedResult()
	}
	d.runs[id] = &dispatchRun{ID: id, Agent: agent, Prompt: prompt, CWD: cwd, Model: model, Status: "running", BudgetUSD: budget}
	d.mu.Unlock()
	d.startReceiptAccum(id, receiptStartParams{agent: agent, model: model, cwd: cwd})
	handle, err := d.launch(argv, cwd, id, d.wrapEmitForRun(id, false))
	if err != nil {
		d.mu.Lock()
		delete(d.runs, id)
		d.mu.Unlock()
		audit(AuditEntry{Action: "continue-error", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	if !d.attachLaunchHandle(id, handle) {
		audit(AuditEntry{Action: "continue-emergency-stopped", Agent: agent, Kind: "dispatch", Command: prompt, ApprovalID: id})
		res := emergencyStoppedResult()
		res.RunID = id
		return res
	}
	audit(AuditEntry{Action: "continue-launched", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule}
}

// observedSessionContinueParams targets one specific on-disk vendor session —
// discovered via session_index.go's scan (Source: "transcriptObserved" /
// "providerManaged") and reported to the phone by agent.sessions.list — for a
// phone-initiated follow-up prompt. Unlike continueRun's fallback (agent/cwd
// recovered from the phone's persisted conversation, "--continue" = most
// recent session in a directory), this always carries the EXACT sessionId +
// cwd the phone already has from the session list, because a user can have
// multiple terminal sessions open in the same project directory and "most
// recent" would silently target the wrong one.
type observedSessionContinueParams struct {
	Vendor    string  `json:"vendor"`
	SessionID string  `json:"sessionId"`
	CWD       string  `json:"cwd"`
	Prompt    string  `json:"prompt"`
	Model     string  `json:"model"`
	BudgetUSD float64 `json:"budgetUSD"`
}

// resumeObservedSession sends a follow-up prompt into a session that was
// started directly in a terminal on the host — never dispatched by Lancer, so
// the daemon has no in-memory dispatchRun for it — by its exact vendor session
// ID. It re-passes the same policy + budget gates dispatch/continueRun use (a
// phone-supplied follow-up prompt is new attacker-influenceable input) and,
// once allowed, launches as a FRESH process under a NEW runId. From that point
// the resumed turn is a normal Lancer-tracked run: output streams back under
// the new runId exactly like dispatch/continueRun, and it can itself be
// continued later via agent.run.continue.
// observedResumeKey identifies one exact on-disk vendor session for
// dispatcher.activeObservedResumes — see that field's doc comment. \x1f
// (unit separator) can't appear in a vendor name or a vendor-issued session
// id, so this can't collide across different (vendor, sessionID) pairs the
// way a plain "+" join could if either half ever contained one.
func observedResumeKey(vendor, sessionID string) string {
	return vendor + "\x1f" + sessionID
}

func (d *dispatcher) resumeObservedSession(p observedSessionContinueParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	// agent.observedSession.continue targets a terminal-started session, not
	// a composer-dispatched conversation turn — out of scope for the
	// composer's per-dispatch toggle, so this always launches strict.
	argv, ok := resumeArgv(p.Vendor, p.SessionID, p.Prompt, p.Model, false)
	if !ok {
		return dispatchResult{Status: "error", Message: "resume-by-id not supported for agent: " + p.Vendor}
	}
	resumeKey := observedResumeKey(p.Vendor, p.SessionID)
	if d.emergencyStopActive() {
		audit(AuditEntry{Action: "observed-continue-emergency-stopped", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}

	// Budget gate (shared daily total vs this run's cap).
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if p.BudgetUSD > 0 && spent >= p.BudgetUSD {
		audit(AuditEntry{Action: "observed-continue-budget-exceeded", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt})
		return dispatchResult{Status: "budgetExceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, p.BudgetUSD)}
	}

	// Policy gate (same risk scoring as dispatch/continueRun).
	resumeCommand := "[observed-continue] " + strings.Join(argv, " ")
	event := ApprovalEvent{
		ApprovalID:  newUUID(),
		Agent:       normalizeAgentSource(p.Vendor),
		Kind:        "command",
		Command:     resumeCommand,
		CWD:         p.CWD,
		Risk:        d.launchRisk(argv),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		ContentHash: computeContentHash(resumeCommand, "", p.CWD, ""),
	}
	effect, rule, fromDefault := evalFn(event)
	effect = relaxLaunchEscalation(effect, fromDefault, argv, d.hookWired)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "observed-continue-denied", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "observed-continue-needs-approval", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, Effect: "ask", Rule: rule})
		d.deliverLaunchApproval(event)
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	if err := d.ensureClaudeAuth(p.Vendor); err != nil {
		audit(AuditEntry{Action: "observed-continue-auth-preflight", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}

	id := newUUID()
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "observed-continue-emergency-stopped", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}
	// Same-session exclusion (activeObservedResumes's doc comment): check AND
	// reserve inside this one critical section so two RPC calls landing
	// concurrently can't both pass a separate check before either reserves —
	// the reservation itself is what a second concurrent caller must see.
	if d.activeObservedResumes == nil {
		d.activeObservedResumes = map[string]string{}
	}
	if existingRunID, busy := d.activeObservedResumes[resumeKey]; busy {
		d.mu.Unlock()
		audit(AuditEntry{Action: "observed-continue-busy", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, ApprovalID: existingRunID})
		return dispatchResult{Status: "busy", Message: "Already resuming this session (run " + existingRunID + ") — wait for it to finish before sending another follow-up."}
	}
	d.activeObservedResumes[resumeKey] = id
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Vendor, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD, observedResumeKey: resumeKey}
	d.mu.Unlock()
	d.startReceiptAccum(id, receiptStartParams{agent: p.Vendor, model: p.Model, cwd: p.CWD})
	handle, err := d.launch(argv, p.CWD, id, d.wrapEmitForRun(id, false))
	if err != nil {
		d.mu.Lock()
		delete(d.runs, id)
		delete(d.activeObservedResumes, resumeKey)
		d.mu.Unlock()
		audit(AuditEntry{Action: "observed-continue-error", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	if !d.attachLaunchHandle(id, handle) {
		audit(AuditEntry{Action: "observed-continue-emergency-stopped", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, ApprovalID: id})
		res := emergencyStoppedResult()
		res.RunID = id
		return res
	}
	audit(AuditEntry{Action: "observed-continue-launched", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule}
}

// launchConversationTurn is agent.conversations.append's dispatch integration
// (cross-device sync build handoff, Task 3): it selects new/exact/fallback
// argv via buildConversationArgv, re-passes the SAME budget + policy gates
// dispatch/continueRun/resumeObservedSession use, and — once allowed —
// launches under runID (the caller-assigned id of the ledger turn already
// persisted by conversationStore.beginTurn) rather than minting a new one, so
// streamed output/status and the vendor-session-id capture route back to the
// right ledger turn via conversationStore.appendRunOutput/appendRunStatus/
// bindVendorSession (all keyed by run_id). The caller (conversationsAppend)
// is responsible for never invoking this twice for the same ledger turn (an
// idempotent clientTurnId replay must not double-launch).
//
// Desired semantic order (do not reorder):
//  1. clean policy command + attachment identity digest → ContentHash
//  2. policy allow
//  3. canonical / content validation (receipt, root, re-hash)
//  4. Claude auth preflight (ensureClaudeAuth, from 85c14180)
//  5. ephemeral JSON attachment manifest
//  6. run insert / launch
func (d *dispatcher) launchConversationTurn(runID string, p conversationLaunchParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	// 1. Policy/audit argv uses the CLEAN user prompt only. hostPath must never
	// enter ApprovalEvent.Command, ContentHash command material, audit Command,
	// or the in-memory run.Prompt (phone-visible surfaces / receipts).
	policyParams := p
	policyParams.Prompt = p.Prompt
	policyArgv, _, ok := buildConversationArgv(policyParams)
	if !ok {
		return dispatchResult{Status: "error", Message: "unknown agent: " + p.Agent}
	}
	// Same cap + clone as dispatch()'s identical gate — a conversation-append
	// launch is just as attacker-influenceable (phone-supplied) as a plain
	// dispatch, so it gets the same contract validation, not a looser one.
	if contractTooLarge(p.Contract) {
		return dispatchResult{Status: "error", Message: "contract too large"}
	}
	p.Contract = cloneRunContract(p.Contract)

	// Budget gate (shared daily total vs this conversation's cap).
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if p.BudgetUSD > 0 && spent >= p.BudgetUSD {
		audit(AuditEntry{Action: "conversation-append-budget-exceeded", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return dispatchResult{Status: "budgetExceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, p.BudgetUSD)}
	}

	// ContentHash binds clean argv + attachment identity digest in toolInput
	// (computeContentHash's existing 4th field) — not mutable hostPath text.
	command := "[conversation-append] " + strings.Join(policyArgv, " ")
	attDigest := attachmentIdentityDigest(p.Attachments)
	event := ApprovalEvent{
		ApprovalID:  newUUID(),
		Agent:       normalizeAgentSource(p.Agent),
		Kind:        "command",
		Command:     command,
		CWD:         p.CWD,
		Risk:        d.launchRisk(policyArgv),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		RunID:       runID,
		ContentHash: computeContentHash(command, "", p.CWD, attDigest),
	}

	// 2. Policy gate.
	effect, rule, fromDefault := evalFn(event)
	effect = relaxLaunchEscalation(effect, fromDefault, policyArgv, d.hookWired)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "conversation-append-denied", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "conversation-append-needs-approval", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "ask", Rule: rule})
		ch := d.deliverLaunchApproval(event)
		// THE MISSING LINK (see LC2-report.md): a delivered+decided approval is
		// worthless if nothing ever resumes the launch it was gating. Every
		// other "ask" branch in this file (dispatch/continueRun/
		// resumeObservedSession) has the same shape, but only
		// launchConversationTurn's caller (conversationsAppend) has no
		// alternative path back in — a mid-run PreToolUse escalation's hook
		// HTTP connection blocks in place and resumes the ALREADY-RUNNING
		// process on decision, but here no process has been launched yet, so
		// there is nothing for a phone-side "Retry" tap to do except restart
		// this whole ask-gate from scratch (the observed infinite loop). Wait
		// for the decision in the background and, on approve, actually run
		// the launch this "ask" gated — using the exact same continuation
		// (completeConversationLaunch) the allow-path below falls through to,
		// so an approved conversation-append launches with identical
		// argv/attachment/auth handling to an auto-allowed one.
		if ch != nil {
			go d.resumeConversationLaunchOnApproval(runID, p, rule, ch, audit)
		}
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	return d.completeConversationLaunch(runID, p, rule, audit)
}

// resumeConversationLaunchOnApproval is the continuation half of
// launchConversationTurn's "ask" branch: it blocks (in its own goroutine, not
// the caller's) on the approval decision channel deliverLaunchApproval
// returned, and — only for an actual approve/approveAlways decision — runs
// the SAME completeConversationLaunch steps (attachment resolution, auth
// preflight, argv build, process launch) that an auto-allowed turn runs
// inline. A deny (or the phone never deciding at all — the channel simply
// never fires and this goroutine parks harmlessly until process exit,
// mirroring the mid-run hook path's own "block until an explicit human
// decision arrives, however long that takes" contract) does nothing further:
// applyDecision/resolve() already recorded a deny's audit entry.
//
// alreadyLaunched guards the one race this design introduces: if a phone
// gives up on this pending card and drives a brand-new
// agent.conversations.append call for the same turn instead (a fresh runID,
// per conversationsAppend's clientTurnId-replay contract), and only THEN taps
// approve on the original stale card, this goroutine must not launch a SECOND
// process for a runID nothing else is waiting on. d.runs is empty for this
// runID until a launch actually starts, so any non-empty entry here (from a
// previous decision already having resumed it, e.g. resolve() firing twice —
// resolve() itself is a single delete-under-lock chokepoint, so that cannot
// happen — or plain defense in depth) means skip.
func (d *dispatcher) resumeConversationLaunchOnApproval(runID string, p conversationLaunchParams, rule string, ch <-chan hookDecision, audit func(AuditEntry)) {
	dec := <-ch
	if dec.decision != "approve" && dec.decision != "approveAlways" {
		return
	}
	d.mu.Lock()
	_, alreadyLaunched := d.runs[runID]
	d.mu.Unlock()
	if alreadyLaunched {
		return
	}
	result := d.completeConversationLaunch(runID, p, rule, audit)
	if d.onConversationLaunchResolved != nil && result.Status != "started" {
		d.onConversationLaunchResolved(runID, result, p.worktreePath, p.worktreeRepoRoot)
	}
}

// completeConversationLaunch is launchConversationTurn's post-policy-gate
// continuation (steps 3-6 of that function's doc comment): attachment
// resolution, Claude auth preflight, the ephemeral vendor prompt/argv build,
// and the actual process launch. Split out so an "ask" gate's async approval
// (resumeConversationLaunchOnApproval) can run through the IDENTICAL launch
// path an inline "allow" falls through to — one implementation of "what does
// launching this conversation turn actually mean", not two that could drift.
func (d *dispatcher) completeConversationLaunch(runID string, p conversationLaunchParams, rule string, audit func(AuditEntry)) dispatchResult {
	// Adapter scope: path manifest only for audited Claude Code. Other agents
	// with attachments fail closed with a path-free unsupported error — no
	// launch and no path in argv/ps.
	if len(p.Attachments) > 0 && normalizeAgentSource(p.Agent) != "claudeCode" {
		audit(AuditEntry{Action: "conversation-append-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: "attachments are not supported for this agent yet"}
	}

	// 3. Canonical path + content validation (receipt lookup, root trust
	// boundary, re-hash). Errors name id/name only — never hostPath.
	resolved, err := resolveAndVerifyAttachments(p.Attachments)
	if err != nil {
		audit(AuditEntry{Action: "conversation-append-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}

	// 4. Claude auth preflight — fail promptly rather than launching into a
	// stalled auth prompt (see 85c14180).
	if err := d.ensureClaudeAuth(p.Agent); err != nil {
		audit(AuditEntry{Action: "conversation-append-auth-preflight", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}

	// 5. Ephemeral JSON attachment manifest (Claude only; empty → clean prompt).
	vendorPrompt, err := vendorAttachmentPrompt(p.Prompt, resolved)
	if err != nil {
		audit(AuditEntry{Action: "conversation-append-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	launchParams := p
	launchParams.Prompt = vendorPrompt
	launchArgv, _, ok := buildConversationArgv(launchParams)
	if !ok {
		return dispatchResult{Status: "error", Message: "unknown agent: " + p.Agent}
	}

	attRoot := ""
	placeholders := attachmentPathPlaceholders(resolved)
	if len(resolved) > 0 {
		if root, rerr := ensureAttachmentRoot(); rerr == nil {
			attRoot = root
		}
	}

	// 6. See dispatch()'s identical comment: the run record must exist before
	// launch runs, or a fast-exiting process's terminal-status event races
	// past a nil run and worktree cleanup silently no-ops.
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "conversation-append-emergency-stopped", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}
	// run.Prompt stays the clean user intent — never the vendor path prefix.
	d.runs[runID] = &dispatchRun{
		ID: runID, Agent: p.Agent, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model,
		Status: "running", BudgetUSD: p.BudgetUSD, Contract: p.Contract,
		WorktreePath: p.worktreePath, RepoRoot: p.worktreeRepoRoot,
		attachmentRoot: attRoot, attachmentPlaceholders: placeholders,
	}
	d.mu.Unlock()
	d.startReceiptAccum(runID, d.receiptStartFromDispatch(dispatchParams{
		Agent: p.Agent, CWD: p.CWD, Model: p.Model, Contract: p.Contract, worktreePath: p.worktreePath, worktreeRepoRoot: p.worktreeRepoRoot,
	}))
	handle, err := d.launch(launchArgv, p.CWD, runID, d.wrapEmitForRun(runID, true))
	if err != nil {
		d.mu.Lock()
		delete(d.runs, runID)
		d.mu.Unlock()
		audit(AuditEntry{Action: "conversation-append-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	if !d.attachLaunchHandle(runID, handle) {
		audit(AuditEntry{Action: "conversation-append-emergency-stopped", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, ApprovalID: runID})
		res := emergencyStoppedResult()
		res.RunID = runID
		return res
	}
	audit(AuditEntry{Action: "conversation-append-launched", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule, ApprovalID: runID})
	return dispatchResult{RunID: runID, Status: "started", Decision: "allow", Rule: rule, CWD: expandHome(p.CWD)}
}
