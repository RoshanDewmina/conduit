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

// agentArgv builds an explicit, shell-free argv for launching an agent with a
// prompt. Explicit argv (never `sh -c "<interpolated>"`) avoids command injection.
func agentArgv(agent, prompt, model string) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		argv := []string{"claude", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "-p", prompt}
		if model != "" {
			argv = append(argv, "--model", model)
		}
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
		argv := []string{"claude", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--continue", "-p", prompt}
		if model != "" {
			argv = append(argv, "--model", model)
		}
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

type dispatchParams struct {
	Agent     string  `json:"agent"`
	CWD       string  `json:"cwd"`
	Prompt    string  `json:"prompt"`
	BudgetUSD float64 `json:"budgetUSD"`
	Model     string  `json:"model"`
}

type dispatchResult struct {
	RunID    string `json:"runId,omitempty"`
	Status   string `json:"status"`             // started | needsApproval | denied | budgetExceeded | error
	Decision string `json:"decision,omitempty"` // allow | ask | deny
	Rule     string `json:"rule,omitempty"`
	Message  string `json:"message,omitempty"`
}

// procHandle controls a launched agent process. Injectable for tests.
type procHandle struct {
	kill   func()
	pause  func()
	resume func()
}

// emitFunc sends a JSON-RPC notification (method + params) to the attached phone.
type emitFunc func(method string, params any)

// launchFunc starts an agent process, streaming its stdout/stderr + status to
// emit (tagged with runID), and returns its control handle. Injectable for tests.
type launchFunc func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error)

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

	// Resolve the binary against the AUGMENTED PATH ourselves and pass an absolute
	// path. exec.Command resolves a bare name using the daemon's own (minimal)
	// PATH at call time — cmd.Env does NOT affect that lookup — so without this the
	// run fails "executable file not found in $PATH" under launchd.
	bin := argv[0]
	if !strings.Contains(bin, "/") {
		if resolved := lookPathIn(bin, env); resolved != "" {
			bin = resolved
		}
	}
	cmd := exec.Command(bin, argv[1:]...) // explicit argv, no shell
	cmd.Dir = expandHome(cwd)
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
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	emitRunStatus(emit, runID, "running", nil)

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
	emit("agent.artifact", map[string]any{
		"artifactID":  toolID,
		"runID":       runID,
		"kind":        "tool",
		"title":       toolName,
		"payloadJSON": inputJSON,
		"status":      "running",
	})
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
				if cbType, _ := cb["type"].(string); cbType == "tool_use" {
					pending = &toolAccum{
						toolID:   fmt.Sprintf("%v", cb["id"]),
						toolName: fmt.Sprintf("%v", cb["name"]),
					}
				} else {
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
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text, "seq": int(n),
					})
				case "input_json_delta":
					if pending != nil {
						partial, _ := delta["partial_json"].(string)
						pending.inputBuf.WriteString(partial)
					}
				}
			case "content_block_stop":
				if pending != nil {
					emitToolArtifact(emit, runID, pending.toolID, pending.toolName, pending.inputBuf.String())
					pending = nil
				}
			}
		case "system", "assistant", "result":
			// Recognised types we do not emit text from:
			//   system   – session init (reserved for future resume).
			//   assistant – whole-message fallback (superseded by deltas).
			//   result   – run completion metadata.
		case "text":
			part, _ := obj["part"].(map[string]any)
			if part == nil {
				continue
			}
			text, _ := part["text"].(string)
			if text == "" {
				continue
			}
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
					n := atomic.AddInt64(seq, 1)
					emit("agent.run.output", map[string]any{
						"runId": runID, "stream": "stdout", "chunk": text + "\n", "seq": int(n),
					})
				}
			}
		case "thread.started", "turn.started", "turn.completed",
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
	ID        string
	Agent     string
	Prompt    string
	CWD       string // working dir of the original launch; reused for continues
	Model     string // model of the original launch; reused for continues
	Status    string // running | paused | cancelled | budget-exceeded
	BudgetUSD float64
	SessionID string // reserved for future resume-by-id
	handle    *procHandle
}

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
	mu            sync.Mutex
	runs          map[string]*dispatchRun
	spentUSD      float64 // accumulated daily spend; gate compares against per-run BudgetUSD cap
	providerSpend map[string]*providerSpend
	launch        launchFunc
	audit         func(AuditEntry) // run-control audit sink; no-op until wired by the server
	emit          emitFunc         // run-output/status notifier; nil until wired by the server
	// hookWired reports whether a per-action PreToolUse hook is verifiably wired
	// for the given agent binary (argv[0]). Nil ⇒ treat as not wired (fail-closed:
	// launches escalate). Set by the server from the real install state.
	hookWired func(string) bool
}

func newDispatcher() *dispatcher {
	return &dispatcher{
		runs:          map[string]*dispatchRun{},
		providerSpend: map[string]*providerSpend{},
		launch:        realLauncher,
		audit:         func(AuditEntry) {},
	}
}

// emitAudit forwards to the audit sink, tolerating a nil sink (a dispatcher built
// directly in tests has no sink wired).
func (d *dispatcher) emitAudit(e AuditEntry) {
	if d.audit != nil {
		d.audit(e)
	}
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

// checkProviderQuotas scans all providers and returns alerts for caps/thresholds.
func (d *dispatcher) checkProviderQuotas() []QuotaAlert {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.checkProviderQuotasLocked()
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
	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(p.Agent),
		Kind:       "command",
		Command:    "[dispatch] " + strings.Join(argv, " "),
		CWD:        p.CWD,
		Risk:       d.launchRisk(argv),
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
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
	// tagged with it from the first byte.
	id := newUUID()
	handle, err := d.launch(argv, p.CWD, id, d.emit)
	if err != nil {
		audit(AuditEntry{Action: "dispatch-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	d.mu.Lock()
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}
	d.mu.Unlock()
	audit(AuditEntry{Action: "dispatch-launched", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule}
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
	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(agent),
		Kind:       "command",
		Command:    "[continue] " + strings.Join(argv, " "),
		CWD:        cwd,
		Risk:       d.launchRisk(argv),
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		RunID:      runID,
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
	handle, err := d.launch(argv, cwd, id, d.emit)
	if err != nil {
		audit(AuditEntry{Action: "continue-error", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	d.mu.Lock()
	d.runs[id] = &dispatchRun{ID: id, Agent: agent, Prompt: prompt, CWD: cwd, Model: model, Status: "running", BudgetUSD: budget, handle: handle}
	d.mu.Unlock()
	audit(AuditEntry{Action: "continue-launched", Agent: agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule}
}
