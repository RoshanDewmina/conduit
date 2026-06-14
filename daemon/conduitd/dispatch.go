package main

import (
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// agentArgv builds an explicit, shell-free argv for launching an agent with a
// prompt. Explicit argv (never `sh -c "<interpolated>"`) avoids command injection.
func agentArgv(agent, prompt string) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		return []string{"claude", "-p", prompt}, true
	case "codex":
		return []string{"codex", "exec", prompt}, true
	case "opencode":
		return []string{"opencode", "run", prompt}, true
	default:
		return nil, false
	}
}

type dispatchParams struct {
	Agent     string  `json:"agent"`
	CWD       string  `json:"cwd"`
	Prompt    string  `json:"prompt"`
	BudgetUSD float64 `json:"budgetUSD"`
}

type dispatchResult struct {
	RunID    string `json:"runId,omitempty"`
	Status   string `json:"status"`             // running | needs-approval | denied | budget-exceeded | error
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

// launchFunc starts an agent process and returns its control handle.
type launchFunc func(argv []string, cwd string) (*procHandle, error)

func realLauncher(argv []string, cwd string) (*procHandle, error) {
	cmd := exec.Command(argv[0], argv[1:]...) // explicit argv, no shell
	cmd.Dir = cwd
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	go func() { _ = cmd.Wait() }()
	proc := cmd.Process
	return &procHandle{
		kill: func() {
			if proc != nil {
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

type dispatchRun struct {
	ID        string
	Agent     string
	Prompt    string
	Status    string // running | paused | cancelled | budget-exceeded
	BudgetUSD float64
	handle    *procHandle
}

// policyEvalFunc returns the policy effect ("allow"|"ask"|"deny") and matched rule.
type policyEvalFunc func(ApprovalEvent) (effect string, rule string)

type dispatcher struct {
	mu       sync.Mutex
	runs     map[string]*dispatchRun
	spentUSD float64 // accumulated daily spend; gate compares against per-run BudgetUSD cap
	launch   launchFunc
}

func newDispatcher() *dispatcher {
	return &dispatcher{runs: map[string]*dispatchRun{}, launch: realLauncher}
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
	d.mu.Lock()
	defer d.mu.Unlock()
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
		}
	}
}

// dispatch applies the budget + policy gate, then launches. It NEVER launches a
// run that policy denies/escalates, and refuses once the budget cap is reached.
func (d *dispatcher) dispatch(p dispatchParams, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	argv, ok := agentArgv(p.Agent, p.Prompt)
	if !ok {
		return dispatchResult{Status: "error", Message: "unknown agent: " + p.Agent}
	}

	// Budget gate (hard stop). BudgetUSD <= 0 means "no cap".
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if p.BudgetUSD > 0 && spent >= p.BudgetUSD {
		audit(AuditEntry{Action: "dispatch-budget-exceeded", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt})
		return dispatchResult{Status: "budget-exceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, p.BudgetUSD)}
	}

	// Policy gate. A dispatched run defaults to medium risk so the bundled policy
	// escalates it unless a rule explicitly allows — fail-closed by default.
	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(p.Agent),
		Kind:       "command",
		Command:    "[dispatch] " + strings.Join(argv, " "),
		CWD:        p.CWD,
		Risk:       1,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	effect, rule := evalFn(event)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "dispatch-denied", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "dispatch-needs-approval", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "ask", Rule: rule})
		return dispatchResult{Status: "needs-approval", Decision: "ask", Rule: rule}
	}

	handle, err := d.launch(argv, p.CWD)
	if err != nil {
		audit(AuditEntry{Action: "dispatch-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	id := newUUID()
	d.mu.Lock()
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}
	d.mu.Unlock()
	audit(AuditEntry{Action: "dispatch-launched", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "running", Decision: "allow", Rule: rule}
}

func (d *dispatcher) cancel(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil {
		return false
	}
	if run.handle != nil && run.Status != "cancelled" {
		run.handle.kill()
	}
	run.Status = "cancelled"
	return true
}

func (d *dispatcher) pause(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.Status != "running" {
		return false
	}
	if run.handle != nil {
		run.handle.pause()
	}
	run.Status = "paused"
	return true
}

func (d *dispatcher) resume(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.Status != "paused" {
		return false
	}
	if run.handle != nil {
		run.handle.resume()
	}
	run.Status = "running"
	return true
}
