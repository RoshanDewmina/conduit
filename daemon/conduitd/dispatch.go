package main

import (
	"bufio"
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
		argv := []string{"claude", "-p", prompt}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return argv, true
	case "codex":
		argv := []string{"codex", "exec"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	case "opencode":
		argv := []string{"opencode", "run"}
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
	cmd := exec.Command(argv[0], argv[1:]...) // explicit argv, no shell
	cmd.Dir = expandHome(cwd)
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

	var seq int64
	var streams sync.WaitGroup
	streams.Add(2)
	go streamOutput(emit, runID, "stdout", stdout, &seq, &streams)
	go streamOutput(emit, runID, "stderr", stderr, &seq, &streams)

	go func() {
		// Drain both pipes before reaping so no chunk is dropped (cmd.Wait closes
		// the pipes after exit, ending the readers), then report final status.
		streams.Wait()
		code := exitCode(cmd.Wait())
		if code == 0 {
			emitRunStatus(emit, runID, "exited", &code)
		} else {
			emitRunStatus(emit, runID, "failed", &code)
		}
	}()

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

func streamOutput(emit emitFunc, runID, stream string, r io.Reader, seq *int64, done *sync.WaitGroup) {
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
	Status    string // running | paused | cancelled | budget-exceeded
	BudgetUSD float64
	handle    *procHandle
}

// policyEvalFunc returns the policy effect ("allow"|"ask"|"deny") and matched rule.
type policyEvalFunc func(ApprovalEvent) (effect string, rule string)

// providerSpend tracks per-provider spend with daily/monthly caps and burn rate.
type providerSpend struct {
	todayUSD           float64
	monthUSD           float64
	dailyCap           float64
	monthlyCap         float64
	burnRate           float64 // USD per hour
	projectedDailyTotal float64
	lastUpdate         time.Time
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
	mu             sync.Mutex
	runs           map[string]*dispatchRun
	spentUSD       float64 // accumulated daily spend; gate compares against per-run BudgetUSD cap
	providerSpend  map[string]*providerSpend
	launch         launchFunc
	audit          func(AuditEntry) // run-control audit sink; no-op until wired by the server
	emit           emitFunc         // run-output/status notifier; nil until wired by the server
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
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}
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
