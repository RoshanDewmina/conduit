package main

import (
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
	d.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{
			kill:   func() { events = append(events, "kill") },
			pause:  func() { events = append(events, "pause") },
			resume: func() { events = append(events, "resume") },
		}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi"},
		func(ApprovalEvent) (string, string) { return "allow", "test-allow" },
		func(AuditEntry) {})
	if res.Status != "running" {
		t.Fatalf("want running, got %q (%s)", res.Status, res.Message)
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
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string) (*procHandle, error) {
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
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}}
	d.setSpentUSD(10)
	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "do x", BudgetUSD: 5}, allowEval, noAudit)
	if res.Status != "budget-exceeded" {
		t.Fatalf("want budget-exceeded, got %q", res.Status)
	}
	if launched {
		t.Fatal("an over-budget dispatch must NOT launch")
	}
}

func TestDispatchAllowLaunchesAndCancels(t *testing.T) {
	cancelled := false
	d := &dispatcher{runs: map[string]*dispatchRun{}, launch: func([]string, string) (*procHandle, error) {
		return &procHandle{kill: func() { cancelled = true }, pause: func() {}, resume: func() {}}, nil
	}}
	res := d.dispatch(dispatchParams{Agent: "codex", Prompt: "run tests"}, allowEval, noAudit)
	if res.Status != "running" || res.RunID == "" {
		t.Fatalf("want running with runID, got %+v", res)
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
