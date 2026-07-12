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

// agentArgv builds an explicit, shell-free argv for launching an agent with a
// prompt. Explicit argv (never `sh -c "<interpolated>"`) avoids command injection.
func agentArgv(agent, prompt, model string) ([]string, bool) {
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
		argv := []string{"codex", "exec", "--json"}
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
		argv := []string{"opencode", "run", "--format", "json"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	default:
		return nil, false
	}
}

// continueArgv builds an explicit, shell-free argv that continues the most-recent
// vendor session in the run's cwd with a new prompt. It mirrors agentArgv (same
// streaming flags + per-vendor gating) so a continued run streams identically to
// the original. ok=false means the agent is unknown.
func continueArgv(agent, prompt, model string) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		// --permission-prompt-tool stdio + --input-format stream-json: see
		// agentArgv's doc comment — same live-verified same-turn-continuation
		// protocol applies to a continued turn; realLauncher strips the
		// trailing "-p", prompt pair and delivers it over stdin the same way.
		argv := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--continue"}
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
		argv := []string{"codex", "exec", "resume", "--last", "--json"}
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
		argv := []string{"opencode", "run", "--continue", "--format", "json"}
		if model != "" {
			argv = append(argv, "--model", model)
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
//     not live-smoke-tested — re-verify before relying on it in production)
func resumeArgv(agent, sessionID, prompt, model string) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		// --permission-prompt-tool stdio + --input-format stream-json: see
		// agentArgv's doc comment — same live-verified same-turn-continuation
		// protocol applies to a resumed turn; realLauncher strips the trailing
		// "-p", prompt pair and delivers it over stdin the same way.
		argv := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--resume", sessionID}
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
		argv := []string{"codex", "exec", "resume", sessionID, "--json"}
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
		argv := []string{"opencode", "run", "--session", sessionID, "--format", "json"}
		if model != "" {
			argv = append(argv, "--model", model)
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
		argv, ok = agentArgv(p.Agent, p.Prompt, p.Model)
		return argv, "new", ok
	case p.VendorSessionID != "":
		argv, ok = resumeArgv(p.Agent, p.VendorSessionID, p.Prompt, p.Model)
		return argv, "exact", ok
	default:
		argv, ok = continueArgv(p.Agent, p.Prompt, p.Model)
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
	Agent       string  `json:"agent"`
	CWD         string  `json:"cwd"`
	Prompt      string  `json:"prompt"`
	BudgetUSD   float64 `json:"budgetUSD"`
	Model       string  `json:"model"`
	UseWorktree bool    `json:"useWorktree,omitempty"`
	Contract    *runContract `json:"contract,omitempty"`

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

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}

	var stdinCtl *controlStdin
	if useControlStdin {
		stdinPipe, err := cmd.StdinPipe()
		if err != nil {
			return nil, err
		}
		stdinCtl = &controlStdin{w: stdinPipe}
	}

	if err := cmd.Start(); err != nil {
		return nil, err
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
	var streams sync.WaitGroup
	streams.Add(2)
	go streamOutput(emit, runID, "stdout", stdout, &seq, &streams, streamJSON)
	go streamOutput(emit, runID, "stderr", stderr, &seq, &streams, false)

	go func() {
		// Report completion the instant the AGENT process exits — never gate it on
		// the stdout/stderr pipes hitting EOF. Claude Code spawns MCP server
		// subprocesses that detach (setsid) into their own session, so they escape
		// the agent's process group AND keep the pipe write-ends open after the
		// agent exits. Waiting on those pipes (streams.Wait) would hang the run in
		// "running" forever — the exact bug that broke every fresh dispatch.
		code := exitCode(cmd.Wait())
		if code == 0 {
			emitRunStatus(emit, runID, "exited", &code)
		} else {
			emitRunStatus(emit, runID, "failed", &code)
		}
		// Best-effort cleanup AFTER status is sent: kill the agent's group (reaps
		// any MCP children that didn't detach) and close our pipe ends so the
		// reader goroutines unblock instead of leaking.
		if proc := cmd.Process; proc != nil {
			_ = syscall.Kill(-proc.Pid, syscall.SIGKILL)
		}
		_ = stdout.Close()
		_ = stderr.Close()
		if stdinCtl != nil {
			stdinCtl.close()
		}
		streams.Wait()
	}()

	proc := cmd.Process
	return &procHandle{
		kill: func() {
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
	return argv[0] == "claude" || argv[0] == "opencode"
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
	return result
}

// lookPathIn resolves an executable name against the PATH carried in env (not the
// process's own PATH), returning the absolute path or "" if not found. Used so a
// launchd-spawned daemon with a minimal inherited PATH can still locate agent CLIs.
func lookPathIn(name string, env []string) string {
	var pathValue string
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			pathValue = strings.TrimPrefix(e, "PATH=")
			break
		}
	}
	for _, dir := range strings.Split(pathValue, ":") {
		if dir == "" {
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

func streamOutput(emit emitFunc, runID, stream string, r io.Reader, seq *int64, done *sync.WaitGroup, streamJSON bool) {
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
			// Whole-message fallback (superseded by deltas) — suppress.
		case "result":
			if errText, ok := extractStreamJSONResultError(obj); ok {
				emitStreamJSONResultError(emit, runID, errText, seq)
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
			if itemType, _ := item["type"].(string); itemType == "agent_message" {
				text, _ := item["text"].(string)
				if text != "" {
					emitLiveStatusStreaming(emit, runID)
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text + "\n", "seq": int(n),
					})
				}
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
		case "":
			// kimi stream-json uses {"role":"..."} instead of {"type":"..."}.
			role, _ := obj["role"].(string)
			if role == "assistant" {
				content, _ := obj["content"].(string)
				if content != "" {
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
}

// runTerminalCallback fires once when a launched run reaches a terminal process
// status (exited/failed). Used by the server to apply per-run worktree retention.
type runTerminalCallback func(runID, status string, exitCode int)

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
	launch           launchFunc
	audit            func(AuditEntry) // run-control audit sink; no-op until wired by the server
	emit             emitFunc         // run-output/status notifier; nil until wired by the server
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
	// onQuestion is invoked when a question-tool tool_use completes in a run's
	// stream-json output (see wrapEmitForRun's "agent.question.raw" case and
	// question.go's extractQuestionEvent). Nil ⇒ question tool_use calls are
	// still emitted as ordinary tool artifacts (emitToolArtifact already ran)
	// but never become a first-class QuestionEvent — no server wired yet, same
	// fail-safe-no-op convention as bindVendorSession/onRunTerminal being nil.
	onQuestion func(event QuestionEvent)
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
				if status == "exited" || status == "failed" {
					d.finalizeReceipt(runID, status, exitCode)
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

func (d *dispatcher) emergencyStopActive() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.emergencyStopped
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
	argv, ok := agentArgv(p.Agent, p.Prompt, p.Model)
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
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
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

	argv, ok := continueArgv(agent, prompt, model)
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
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
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
func (d *dispatcher) resumeObservedSession(p observedSessionContinueParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	argv, ok := resumeArgv(p.Vendor, p.SessionID, p.Prompt, p.Model)
	if !ok {
		return dispatchResult{Status: "error", Message: "resume-by-id not supported for agent: " + p.Vendor}
	}
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
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	id := newUUID()
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "observed-continue-emergency-stopped", Agent: p.Vendor, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Vendor, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD}
	d.mu.Unlock()
	d.startReceiptAccum(id, receiptStartParams{agent: p.Vendor, model: p.Model, cwd: p.CWD})
	handle, err := d.launch(argv, p.CWD, id, d.wrapEmitForRun(id, false))
	if err != nil {
		d.mu.Lock()
		delete(d.runs, id)
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
func (d *dispatcher) launchConversationTurn(runID string, p conversationLaunchParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	argv, _, ok := buildConversationArgv(p)
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

	// Policy gate (same risk scoring as dispatch/continueRun/resumeObservedSession).
	command := "[conversation-append] " + strings.Join(argv, " ")
	event := ApprovalEvent{
		ApprovalID:  newUUID(),
		Agent:       normalizeAgentSource(p.Agent),
		Kind:        "command",
		Command:     command,
		CWD:         p.CWD,
		Risk:        d.launchRisk(argv),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		RunID:       runID,
		ContentHash: computeContentHash(command, "", p.CWD, ""),
	}
	effect, rule, fromDefault := evalFn(event)
	effect = relaxLaunchEscalation(effect, fromDefault, argv, d.hookWired)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "conversation-append-denied", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "conversation-append-needs-approval", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "ask", Rule: rule})
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	// See dispatch()'s identical comment: the run record must exist before
	// launch runs, or a fast-exiting process's terminal-status event races
	// past a nil run and worktree cleanup silently no-ops.
	d.mu.Lock()
	if d.emergencyStopped {
		d.mu.Unlock()
		audit(AuditEntry{Action: "conversation-append-emergency-stopped", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return emergencyStoppedResult()
	}
	d.runs[runID] = &dispatchRun{ID: runID, Agent: p.Agent, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD, Contract: p.Contract, WorktreePath: p.worktreePath, RepoRoot: p.worktreeRepoRoot}
	d.mu.Unlock()
	d.startReceiptAccum(runID, d.receiptStartFromDispatch(dispatchParams{
		Agent: p.Agent, CWD: p.CWD, Model: p.Model, Contract: p.Contract, worktreePath: p.worktreePath, worktreeRepoRoot: p.worktreeRepoRoot,
	}))
	handle, err := d.launch(argv, p.CWD, runID, d.wrapEmitForRun(runID, true))
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
