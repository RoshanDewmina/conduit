package main

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

// allowEval / denyEval / askEval are policy stubs for dispatch tests.
func allowEval(ApprovalEvent) (string, string, bool) { return "allow", "test-allow", false }
func denyEval(ApprovalEvent) (string, string, bool)  { return "deny", "deny-network", false }

func noAudit(AuditEntry) {}

func TestResolveDispatchCWDRejectsMissingRelative(t *testing.T) {
	if _, err := resolveDispatchCWD("command-center"); err == nil {
		t.Fatal("expected error for bare relative cwd")
	}
	abs := t.TempDir()
	got, err := resolveDispatchCWD(abs)
	if err != nil {
		t.Fatalf("absolute existing cwd: %v", err)
	}
	if got != abs {
		t.Fatalf("got %q want %q", got, abs)
	}
}

func TestDispatchStoresCWDAndModel(t *testing.T) {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Model: "sonnet", Prompt: "hi"},
		allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("want started, got %q (%s)", res.Status, res.Message)
	}
	run := d.runs[res.RunID]
	if run == nil || run.CWD != "/repo" || run.Model != "sonnet" {
		t.Fatalf("want CWD=/repo Model=sonnet, got %+v", run)
	}
}

func TestAgentArgv(t *testing.T) {
	claude, ok := agentArgv("claudeCode", "start", "", false)
	if !ok {
		t.Fatal("claude should be supported")
	}
	want := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`, "-p", "start"}
	if !reflect.DeepEqual(claude, want) {
		t.Fatalf("claude argv mismatch:\n got %v\nwant %v", claude, want)
	}
	if _, ok := agentArgv("bogus", "x", "", false); ok {
		t.Fatal("unknown agent must be unsupported")
	}
}

func TestContinueArgv(t *testing.T) {
	claude, ok := continueArgv("claudeCode", "next step", "", false)
	if !ok {
		t.Fatal("claude continue should be supported")
	}
	want := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--continue", "--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`, "-p", "next step"}
	if !reflect.DeepEqual(claude, want) {
		t.Fatalf("claude argv mismatch:\n got %v\nwant %v", claude, want)
	}
	oc, ok := continueArgv("opencode", "next step", "gpt-5", false)
	if !ok || !reflect.DeepEqual(oc, []string{"opencode", "run", "--continue", "--format", "json", "--thinking", "--model", "gpt-5", "next step"}) {
		t.Fatalf("opencode argv mismatch: %v ok=%v", oc, ok)
	}
	if _, ok := continueArgv("codex", "x", "", false); !ok {
		t.Fatal("codex continue should be supported (gated by LANCER_CODEX_UNSAFE at runtime)")
	}
	if _, ok := continueArgv("kimi", "x", "", false); !ok {
		t.Fatal("kimi continue should be supported")
	}
	if _, ok := continueArgv("bogus", "x", "", false); ok {
		t.Fatal("unknown agent must be unsupported")
	}
}

func TestContinueRunNewRunIDAndGate(t *testing.T) {
	var launches int
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches++
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"}, allowEval, noAudit)
	cont := d.continueRun(first.RunID, "next", continueFallback{}, allowEval, noAudit)
	if cont.Status != "started" {
		t.Fatalf("want started, got %q (%s)", cont.Status, cont.Message)
	}
	if cont.RunID == "" || cont.RunID == first.RunID {
		t.Fatalf("continue must allocate a NEW runId, got %q (first %q)", cont.RunID, first.RunID)
	}
	if launches != 2 {
		t.Fatalf("want 2 launches, got %d", launches)
	}
}

func TestContinueRunDeniedDoesNotLaunch(t *testing.T) {
	var contLaunched bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"}, allowEval, noAudit)
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		contLaunched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.continueRun(first.RunID, "next", continueFallback{}, denyEval, noAudit)
	if res.Status != "denied" {
		t.Fatalf("want denied, got %q", res.Status)
	}
	if contLaunched {
		t.Fatal("a policy-denied continue must NOT launch")
	}
}

func TestResumeArgv(t *testing.T) {
	claude, ok := resumeArgv("claudeCode", "sess-123", "next step", "", false)
	want := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--resume", "sess-123", "--strict-mcp-config", "--mcp-config", `{"mcpServers":{}}`, "-p", "next step"}
	if !ok || !reflect.DeepEqual(claude, want) {
		t.Fatalf("claude resume argv mismatch:\n got %v (ok=%v)\nwant %v", claude, ok, want)
	}
	codex, ok := resumeArgv("codex", "sess-123", "next step", "", false)
	wantCodex := []string{"codex", "exec", "resume", "sess-123", "--json", "-c", "model_reasoning_summary=auto", "next step"}
	if !ok || !reflect.DeepEqual(codex, wantCodex) {
		t.Fatalf("codex resume argv mismatch:\n got %v (ok=%v)\nwant %v", codex, ok, wantCodex)
	}
	oc, ok := resumeArgv("opencode", "sess-123", "next step", "gpt-5", false)
	wantOC := []string{"opencode", "run", "--session", "sess-123", "--format", "json", "--thinking", "--model", "gpt-5", "next step"}
	if !ok || !reflect.DeepEqual(oc, wantOC) {
		t.Fatalf("opencode resume argv mismatch:\n got %v (ok=%v)\nwant %v", oc, ok, wantOC)
	}
	kimi, ok := resumeArgv("kimi", "sess-123", "next step", "", false)
	wantKimi := []string{"kimi", "--session", "sess-123", "--prompt", "next step", "--output-format", "stream-json"}
	if !ok || !reflect.DeepEqual(kimi, wantKimi) {
		t.Fatalf("kimi resume argv mismatch:\n got %v (ok=%v)\nwant %v", kimi, ok, wantKimi)
	}
	if _, ok := resumeArgv("bogus", "sess-123", "x", "", false); ok {
		t.Fatal("unknown agent must be unsupported")
	}
}

func TestResumeObservedSessionLaunchesNewRun(t *testing.T) {
	var launchedArgv []string
	var launchedCWD string
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchedArgv = argv
		launchedCWD = cwd
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.resumeObservedSession(observedSessionContinueParams{
		Vendor:    "claudeCode",
		SessionID: "sess-abc",
		CWD:       "/repo/observed",
		Prompt:    "keep going",
	}, allowEval, noAudit)
	if res.Status != "started" || res.RunID == "" {
		t.Fatalf("want started with a runId, got %+v", res)
	}
	if launchedCWD != "/repo/observed" {
		t.Fatalf("want launch cwd /repo/observed, got %q", launchedCWD)
	}
	if len(launchedArgv) == 0 || launchedArgv[0] != "claude" {
		t.Fatalf("want claude argv, got %v", launchedArgv)
	}
	found := false
	for i, a := range launchedArgv {
		if a == "--resume" && i+1 < len(launchedArgv) && launchedArgv[i+1] == "sess-abc" {
			found = true
		}
	}
	if !found {
		t.Fatalf("want --resume sess-abc in argv, got %v", launchedArgv)
	}
	run := d.runs[res.RunID]
	if run == nil || run.CWD != "/repo/observed" {
		t.Fatalf("want a tracked run with CWD=/repo/observed, got %+v", run)
	}
}

// TestResumeObservedSessionSameSessionBusyRejectsSecondLaunch proves the
// 2026-07-18 fix: two overlapping agent.observedSession.continue calls
// targeting the EXACT SAME vendor+sessionID (e.g. a slow first reply plus an
// impatient second follow-up tap) must not both launch a
// `claude --resume <sessionId>` process — two OS processes concurrently
// appending to the same on-disk session transcript is a real corruption
// risk the vendor CLI's resume mechanism was never designed to tolerate.
// The first run is left deliberately non-terminal (launch stub never emits
// agent.run.status) so the second call finds the reservation still held.
func TestResumeObservedSessionSameSessionBusyRejectsSecondLaunch(t *testing.T) {
	launchCount := 0
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchCount++
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-busy", CWD: "/repo", Prompt: "first follow-up",
	}, allowEval, noAudit)
	if first.Status != "started" || first.RunID == "" {
		t.Fatalf("want first call started, got %+v", first)
	}

	second := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-busy", CWD: "/repo", Prompt: "second follow-up",
	}, allowEval, noAudit)
	if second.Status != "busy" {
		t.Fatalf("want second concurrent call for the same session rejected as busy, got %+v", second)
	}
	if launchCount != 1 {
		t.Fatalf("want exactly 1 process launched for the same session while the first is still running, got %d", launchCount)
	}

	// A different session is NOT blocked by the first one's reservation.
	other := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-other", CWD: "/repo", Prompt: "unrelated session",
	}, allowEval, noAudit)
	if other.Status != "started" {
		t.Fatalf("want an unrelated session unaffected by another session's reservation, got %+v", other)
	}
	if launchCount != 2 {
		t.Fatalf("want the unrelated session's launch to go through, got launchCount=%d", launchCount)
	}
}

// TestResumeObservedSessionReservationReleasedOnTerminal proves the
// reservation set by resumeObservedSession is released once that run
// reaches a terminal agent.run.status ("exited"/"failed"), so a LATER
// follow-up to the same session (after the first one actually finished) is
// not permanently blocked.
func TestResumeObservedSessionReservationReleasedOnTerminal(t *testing.T) {
	d := newDispatcher()
	launchCount := 0
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchCount++
		// Emit synchronously (not `go emit(...)`) so the terminal status —
		// and this test's release-the-reservation code path — has
		// definitely run before resumeObservedSession returns.
		emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-done", CWD: "/repo", Prompt: "first follow-up",
	}, allowEval, noAudit)
	if first.Status != "started" {
		t.Fatalf("want first call started, got %+v", first)
	}
	if run := d.runs[first.RunID]; run == nil || run.observedResumeKey != "" {
		t.Fatalf("want the reservation cleared on the run record once terminal, got %+v", run)
	}

	second := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-done", CWD: "/repo", Prompt: "second follow-up, after the first finished",
	}, allowEval, noAudit)
	if second.Status != "started" {
		t.Fatalf("want a follow-up AFTER the prior run finished to launch normally, got %+v", second)
	}
	if launchCount != 2 {
		t.Fatalf("want both calls to launch (sequential, not overlapping), got launchCount=%d", launchCount)
	}
}

func TestResumeObservedSessionDeniedDoesNotLaunch(t *testing.T) {
	launched := false
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-abc", CWD: "/repo", Prompt: "next",
	}, denyEval, noAudit)
	if res.Status != "denied" {
		t.Fatalf("want denied, got %q", res.Status)
	}
	if launched {
		t.Fatal("a policy-denied observed-session continue must NOT launch")
	}
}

func TestResumeObservedSessionUnknownVendor(t *testing.T) {
	d := newDispatcher()
	res := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "bogus", SessionID: "sess-abc", CWD: "/repo", Prompt: "next",
	}, allowEval, noAudit)
	if res.Status != "error" {
		t.Fatalf("want error for unsupported vendor, got %q (%s)", res.Status, res.Message)
	}
}

// TestOnRunStartedFiresOnceOnDispatchedLaunch proves the Live Activity
// push-to-start hook: a successful dispatch whose launcher emits
// agent.run.status "running" (mirroring realLauncher after cmd.Start) invokes
// onRunStarted exactly once with the run's agent — and a duplicate "running"
// emit does not fire again. A launcher that never emits "running" must not
// invoke the callback (failed Start / stub that skips the status event).
func TestOnRunStartedFiresOnceOnDispatchedLaunch(t *testing.T) {
	var started []struct{ runID, agent string }
	d := newDispatcher()
	d.onRunStarted = func(runID, agent string) {
		started = append(started, struct{ runID, agent string }{runID, agent})
	}
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		// Mirror realLauncher: emit "running" once the process is confirmed started.
		emit("agent.run.status", map[string]any{"runId": runID, "status": "running"})
		// A second "running" must not double-fire (startedNotified guard).
		emit("agent.run.status", map[string]any{"runId": runID, "status": "running"})
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"},
		allowEval, noAudit)
	if res.Status != "started" || res.RunID == "" {
		t.Fatalf("want started with a runId, got %+v", res)
	}
	if len(started) != 1 {
		t.Fatalf("want onRunStarted exactly once, got %d calls: %+v", len(started), started)
	}
	if started[0].runID != res.RunID {
		t.Fatalf("onRunStarted runID = %q, want %q", started[0].runID, res.RunID)
	}
	if started[0].agent != "claudeCode" {
		t.Fatalf("onRunStarted agent = %q, want claudeCode", started[0].agent)
	}

	// Launch path that never emits "running" must not invoke the callback.
	started = nil
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res2 := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "again"},
		allowEval, noAudit)
	if res2.Status != "started" {
		t.Fatalf("want second dispatch started, got %+v", res2)
	}
	if len(started) != 0 {
		t.Fatalf("want no onRunStarted when launcher skips running status, got %+v", started)
	}
}

func TestContinueRunUnknownRun(t *testing.T) {
	d := newDispatcher()
	if res := d.continueRun("nope", "x", continueFallback{}, allowEval, noAudit); res.Status != "error" {
		t.Fatalf("want error for unknown run, got %q", res.Status)
	}
}

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
		func(ApprovalEvent) (string, string, bool) { return "allow", "test-allow", false },
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
		func(ApprovalEvent) (string, string, bool) { return "allow", "test-allow", false },
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
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})
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
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})

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
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})
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

func TestEmergencyStopStopsRunsAndBlocksLaunches(t *testing.T) {
	var killed int
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() { killed++ }, pause: func() {}, resume: func() {}}, nil
	}

	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "one"}, allowEval, noAudit)
	second := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "two"}, allowEval, noAudit)
	if first.Status != "started" || second.Status != "started" {
		t.Fatalf("setup dispatches failed: first=%+v second=%+v", first, second)
	}
	if !d.pause(second.RunID) {
		t.Fatal("setup pause failed")
	}

	if stopped := d.emergencyStop(); stopped != 2 {
		t.Fatalf("emergencyStop stopped %d runs, want 2", stopped)
	}
	if killed != 2 {
		t.Fatalf("emergencyStop killed %d handles, want 2", killed)
	}
	if d.runStatus(first.RunID) != "cancelled" || d.runStatus(second.RunID) != "cancelled" {
		t.Fatalf("runs not marked cancelled: first=%q second=%q", d.runStatus(first.RunID), d.runStatus(second.RunID))
	}

	blocked := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "after stop"}, allowEval, noAudit)
	if blocked.Status != "emergencyStopped" {
		t.Fatalf("dispatch after emergency stop = %q, want emergencyStopped", blocked.Status)
	}
}

func TestEmergencyStopDuringLaunchKillsLateHandle(t *testing.T) {
	var killed int
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		if stopped := d.emergencyStop(); stopped != 1 {
			t.Fatalf("emergencyStop during launch stopped %d runs, want 1", stopped)
		}
		return &procHandle{kill: func() { killed++ }, pause: func() {}, resume: func() {}}, nil
	}

	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "race"}, allowEval, noAudit)
	if res.Status != "emergencyStopped" {
		t.Fatalf("dispatch racing emergency stop = %q, want emergencyStopped", res.Status)
	}
	if killed != 1 {
		t.Fatalf("late launch handle killed %d times, want 1", killed)
	}
	if d.runStatus(res.RunID) != "cancelled" {
		t.Fatalf("racing run status = %q, want cancelled", d.runStatus(res.RunID))
	}
}

func TestEmergencyStopBlocksSessionLaunches(t *testing.T) {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "start"}, allowEval, noAudit)
	if first.Status != "started" {
		t.Fatalf("setup dispatch = %q, want started", first.Status)
	}
	d.emergencyStop()

	if res := d.continueRun(first.RunID, "continue", continueFallback{}, allowEval, noAudit); res.Status != "emergencyStopped" {
		t.Fatalf("continue after emergency stop = %q, want emergencyStopped", res.Status)
	}
	if res := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "session-1", CWD: "/tmp", Prompt: "resume",
	}, allowEval, noAudit); res.Status != "emergencyStopped" {
		t.Fatalf("observed resume after emergency stop = %q, want emergencyStopped", res.Status)
	}
	if res := d.launchConversationTurn("conversation-run-1", conversationLaunchParams{
		Agent: "claudeCode", CWD: "/tmp", Prompt: "conversation",
	}, allowEval, noAudit); res.Status != "emergencyStopped" {
		t.Fatalf("conversation launch after emergency stop = %q, want emergencyStopped", res.Status)
	}
}

func TestDispatchContract(t *testing.T) {
	valid := &runContract{
		Goal:               "add receipt contract",
		DoneCriteria:       []string{"contract echoes in receipt"},
		ValidationCommands: []string{"go test ./..."},
	}

	t.Run("echoes in receipt and run record", func(t *testing.T) {
		d := newDispatcher()
		d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
			go emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
			return &procHandle{kill: func() {}}, nil
		}
		res := d.dispatch(dispatchParams{
			Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", Model: "sonnet", Contract: valid,
		}, allowEval, noAudit)
		if res.Status != "started" {
			t.Fatalf("dispatch status = %q, want started", res.Status)
		}
		run := d.runs[res.RunID]
		if run == nil || run.Contract == nil {
			t.Fatal("expected contract on run record")
		}
		if run.Contract.Goal != valid.Goal {
			t.Fatalf("run contract goal = %q, want %q", run.Contract.Goal, valid.Goal)
		}
		if !reflect.DeepEqual(run.Contract.DoneCriteria, valid.DoneCriteria) {
			t.Fatalf("run doneCriteria = %v, want %v", run.Contract.DoneCriteria, valid.DoneCriteria)
		}

		deadline := time.After(2 * time.Second)
		var receipt *runReceipt
		for receipt == nil {
			select {
			case <-deadline:
				t.Fatal("timed out waiting for receipt")
			default:
				receipt = d.getReceipt(res.RunID)
				if receipt == nil {
					time.Sleep(10 * time.Millisecond)
				}
			}
		}
		if receipt.Contract == nil {
			t.Fatal("expected contract on receipt")
		}
		if receipt.Contract.Goal != valid.Goal {
			t.Fatalf("receipt goal = %q, want %q", receipt.Contract.Goal, valid.Goal)
		}
		if !reflect.DeepEqual(receipt.Contract.DoneCriteria, valid.DoneCriteria) {
			t.Fatalf("receipt doneCriteria = %v, want %v", receipt.Contract.DoneCriteria, valid.DoneCriteria)
		}
		if !reflect.DeepEqual(receipt.Contract.ValidationCommands, valid.ValidationCommands) {
			t.Fatalf("receipt validationCommands = %v, want %v", receipt.Contract.ValidationCommands, valid.ValidationCommands)
		}
	})

	t.Run("too many done criteria", func(t *testing.T) {
		d := newDispatcher()
		criteria := make([]string, contractMaxDoneCriteria+1)
		for i := range criteria {
			criteria[i] = "ok"
		}
		res := d.dispatch(dispatchParams{
			Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", Contract: &runContract{Goal: "x", DoneCriteria: criteria},
		}, allowEval, noAudit)
		if res.Status != "error" || res.Message != "contract too large" {
			t.Fatalf("dispatch = %+v, want error contract too large", res)
		}
	})

	t.Run("done criterion too long", func(t *testing.T) {
		d := newDispatcher()
		long := strings.Repeat("a", contractMaxDoneCriterionChars+1)
		res := d.dispatch(dispatchParams{
			Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", Contract: &runContract{Goal: "x", DoneCriteria: []string{long}},
		}, allowEval, noAudit)
		if res.Status != "error" || res.Message != "contract too large" {
			t.Fatalf("dispatch = %+v, want error contract too large", res)
		}
	})

	t.Run("too many validation commands", func(t *testing.T) {
		d := newDispatcher()
		cmds := make([]string, contractMaxValidationCommands+1)
		for i := range cmds {
			cmds[i] = "go test ./..."
		}
		res := d.dispatch(dispatchParams{
			Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", Contract: &runContract{Goal: "x", ValidationCommands: cmds},
		}, allowEval, noAudit)
		if res.Status != "error" || res.Message != "contract too large" {
			t.Fatalf("dispatch = %+v, want error contract too large", res)
		}
	})
}
