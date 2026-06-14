package main

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

// allowEval / denyEval / askEval are policy stubs for dispatch tests.
func allowEval(ApprovalEvent) (string, string) { return "allow", "test-allow" }
func denyEval(ApprovalEvent) (string, string)  { return "deny", "deny-network" }

func noAudit(AuditEntry) {}

func TestProcHandlePauseResumeRecorded(t *testing.T) {
	var events []string
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{
			kill:   func() { events = append(events, "kill") },
			pause:  func() { events = append(events, "pause") },
			resume: func() { events = append(events, "resume") },
		}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi"},
		func(ApprovalEvent) (string, string) { return "allow", "test-allow" },
		func(AuditEntry) {})
	if res.Status != "started" {
		t.Fatalf("want started, got %q (%s)", res.Status, res.Message)
	}
	if !d.pause(res.RunID) || !d.resume(res.RunID) {
		t.Fatal("pause/resume returned false for a live run")
	}
	if got := strings.Join(events, ","); got != "pause,resume" {
		t.Fatalf("want pause,resume; got %q", got)
	}
}

func TestDispatchDeniedByPolicyDoesNotLaunch(t *testing.T) {
	launched := false
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string, string, emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "do x"}, denyEval, noAudit)
	if res.Status != "denied" {
		t.Fatalf("want denied, got %q", res.Status)
	}
	if launched {
		t.Fatal("a denied dispatch must NOT launch a process")
	}
}

func TestDispatchBudgetExceededDoesNotLaunch(t *testing.T) {
	launched := false
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string, string, emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}}
	d.setSpentUSD(10)
	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "do x", BudgetUSD: 5}, allowEval, noAudit)
	if res.Status != "budgetExceeded" {
		t.Fatalf("want budgetExceeded, got %q", res.Status)
	}
	if launched {
		t.Fatal("an over-budget dispatch must NOT launch")
	}
}

func TestDispatchAllowLaunchesAndCancels(t *testing.T) {
	cancelled := false
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string, string, emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() { cancelled = true }, pause: func() {}, resume: func() {}}, nil
	}}
	res := d.dispatch(dispatchParams{Agent: "codex", Prompt: "run tests"}, allowEval, noAudit)
	if res.Status != "started" || res.RunID == "" {
		t.Fatalf("want started with runID, got %+v", res)
	}
	if !d.cancel(res.RunID) {
		t.Fatal("cancel should find the run")
	}
	if !cancelled {
		t.Fatal("cancel must invoke the launch cancel func")
	}
}

func TestDispatchUnknownAgent(t *testing.T) {
	d := newDispatcher()
	res := d.dispatch(dispatchParams{Agent: "nope", Prompt: "x"}, allowEval, noAudit)
	if res.Status != "error" {
		t.Fatalf("want error for unknown agent, got %q", res.Status)
	}
}

func TestScheduleDueTickAndPersistence(t *testing.T) {
	home := t.TempDir()
	s := newScheduler(home)
	sc := s.add(schedule{Agent: "claudeCode", CWD: "/tmp", Prompt: "nightly", EverySeconds: 60})
	if sc.ID == "" {
		t.Fatal("add should assign an ID")
	}

	// Reload from disk → persisted.
	if got := newScheduler(home).list(); len(got) != 1 || got[0].ID != sc.ID {
		t.Fatalf("schedule did not persist/reload: %+v", got)
	}

	now := time.Unix(100, 0) // LastRunUnix=0, interval=60 → due
	fired := 0
	n := s.tick(now, func(dispatchParams) dispatchResult { fired++; return dispatchResult{Status: "running"} })
	if n != 1 || fired != 1 {
		t.Fatalf("want 1 fire, got tick=%d fired=%d", n, fired)
	}
	// Immediately after firing, not due again.
	if got := s.due(now); len(got) != 0 {
		t.Fatalf("should not be due right after firing, got %d", len(got))
	}
	// After another interval, due again.
	if got := s.due(time.Unix(170, 0)); len(got) != 1 {
		t.Fatalf("should be due after another interval, got %d", len(got))
	}

	if !s.remove(sc.ID) || len(s.list()) != 0 {
		t.Fatal("remove should delete the schedule")
	}
}

func TestSetBudgetKillsRunOverCap(t *testing.T) {
	var killed bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() { killed = true }, pause: func() {}, resume: func() {}}, nil
	}
	// dispatch with no cap so it always admits; the cap is set after spend accrues.
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi"},
		func(ApprovalEvent) (string, string) { return "allow", "test-allow" },
		func(AuditEntry) {})

	// Lowering the cap below current spend must kill the run immediately.
	d.setSpentUSD(4.00)
	if !d.setBudget(res.RunID, 2.00) {
		t.Fatal("setBudget returned false for a live run")
	}
	if !killed {
		t.Fatal("run over its new cap was not killed")
	}
	if st := d.runStatus(res.RunID); st != "budget-exceeded" {
		t.Fatalf("want budget-exceeded, got %q", st)
	}
}

func TestSpendUpdateEnforcesPerRunCap(t *testing.T) {
	var killed bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() { killed = true }, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", BudgetUSD: 5.00},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})
	d.setSpentUSD(4.99) // under cap — still running
	if killed {
		t.Fatal("killed under cap")
	}
	d.setSpentUSD(5.00) // exactly at cap — the >= boundary must enforce
	if !killed || d.runStatus(res.RunID) != "budget-exceeded" {
		t.Fatal("spend reaching the cap did not stop the run")
	}
}

func TestSetBudgetAbsentRunReturnsFalse(t *testing.T) {
	d := newDispatcher()
	if d.setBudget("no-such-id", 5.00) {
		t.Fatal("setBudget on absent run should return false")
	}
}

func TestRunControlActionsAreAudited(t *testing.T) {
	var actions []string
	d := newDispatcher()
	d.audit = func(e AuditEntry) { actions = append(actions, e.Action) }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})

	d.pause(res.RunID)
	d.resume(res.RunID)
	d.cancel(res.RunID)

	// Exact-order assertion: each control action audits once, in sequence. Also
	// guards against a duplicate "run-stopped" if cancel ever loses idempotency.
	want := []string{"run-paused", "run-resumed", "run-stopped"}
	if !reflect.DeepEqual(actions, want) {
		t.Fatalf("want %v; got %v", want, actions)
	}
}

func TestBudgetExceededIsAudited(t *testing.T) {
	var actions []string
	d := newDispatcher()
	d.audit = func(e AuditEntry) { actions = append(actions, e.Action) }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x", BudgetUSD: 5.00},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})
	d.setSpentUSD(5.00) // hits the cap → enforceBudgets stops the run

	found := false
	for _, a := range actions {
		if a == "run-budget-exceeded" {
			found = true
		}
	}
	if !found {
		t.Fatalf("budget-exceeded stop was not audited; got %v (run %s)", actions, res.RunID)
	}
}
