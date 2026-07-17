package main

import (
	"encoding/json"
	"testing"
	"time"
)

// TestEmergencyStopDeniesPendingApprovalsAndUnblocksWaiters is the live-gap
// regression (2026-07-17): Emergency Stop stopped runs / wrote run-stopped but
// left PreToolUse hook gates blocked on pending escalations. After estop every
// pending approval must resolve deny (unblocking waiters) and audit both the
// deny (escalation approvalId) and run-stopped.
func TestEmergencyStopDeniesPendingApprovalsAndUnblocksWaiters(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	run := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})
	if run.RunID == "" {
		t.Fatalf("dispatch did not start a run: %+v", run)
	}

	event := ApprovalEvent{
		ApprovalID:  "6c8d949e-escalation-1",
		Agent:       "claudeCode",
		Kind:        "command",
		Command:     "sleep 120",
		CWD:         home,
		ContentHash: computeContentHash("sleep 120", "", home, ""),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
	}
	decisionCh := s.approvals.add(event)

	waiterDone := make(chan hookDecision, 1)
	go func() { waiterDone <- <-decisionCh }()

	stopped, denied := s.applyEmergencyStop()
	if stopped != 1 {
		t.Fatalf("stoppedRuns = %d, want 1", stopped)
	}
	if denied != 1 {
		t.Fatalf("deniedApprovals = %d, want 1", denied)
	}

	if pending := s.approvals.pendingEvents(); len(pending) != 0 {
		t.Fatalf("pending approvals after emergency stop = %+v, want none", pending)
	}

	select {
	case d := <-waiterDone:
		if d.decision != "deny" {
			t.Fatalf("hook waiter decision = %q, want deny", d.decision)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("hook decision-channel consumer was not unblocked by emergency stop")
	}

	entries, err := s.audit.tail(50)
	if err != nil {
		t.Fatal(err)
	}
	var sawDeny, sawStopped bool
	for _, e := range entries {
		if e.ApprovalID == event.ApprovalID && (e.Action == "deny" || e.Action == "deny-emergency-stop") {
			sawDeny = true
		}
		if e.Action == "run-stopped" && e.ApprovalID == run.RunID {
			sawStopped = true
		}
	}
	if !sawDeny {
		t.Fatalf("audit missing deny entry for escalation %s; entries=%+v", event.ApprovalID, entries)
	}
	if !sawStopped {
		t.Fatalf("audit missing run-stopped for run %s; entries=%+v", run.RunID, entries)
	}
}

// TestEmergencyStopWithZeroPendingSucceeds is the negative case: no pending
// approvals → success with deniedApprovals=0 (and stoppedRuns=0 when idle).
func TestEmergencyStopWithZeroPendingSucceeds(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	stopped, denied := s.applyEmergencyStop()
	if stopped != 0 {
		t.Fatalf("stoppedRuns = %d, want 0", stopped)
	}
	if denied != 0 {
		t.Fatalf("deniedApprovals = %d, want 0", denied)
	}
	if pending := s.approvals.pendingEvents(); len(pending) != 0 {
		t.Fatalf("pending = %+v, want none", pending)
	}
}

// TestEmergencyStopRPCIncludesDeniedApprovalsCount keeps the iOS-visible
// result shape backward compatible while surfacing the new denied count.
func TestEmergencyStopRPCIncludesDeniedApprovalsCount(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	event := ApprovalEvent{
		ApprovalID:  "estop-rpc-1",
		Agent:       "claudeCode",
		Kind:        "command",
		Command:     "rm -rf /",
		CWD:         "/tmp",
		ContentHash: computeContentHash("rm -rf /", "", "/tmp", ""),
	}
	_ = s.approvals.add(event)

	resultCh := make(chan rpcMessage, 1)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		_ = json.Unmarshal(data, &m)
		select {
		case resultCh <- m:
		default:
		}
		return nil
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.emergencyStop"})

	select {
	case res := <-resultCh:
		m, ok := res.Result.(map[string]interface{})
		if !ok {
			t.Fatalf("result = %#v, want object", res.Result)
		}
		if m["emergencyStopped"] != true {
			t.Fatalf("result = %#v, want emergencyStopped=true", res.Result)
		}
		if m["stoppedRuns"] != float64(0) {
			t.Fatalf("result = %#v, want stoppedRuns=0", res.Result)
		}
		if m["deniedApprovals"] != float64(1) {
			t.Fatalf("result = %#v, want deniedApprovals=1", res.Result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("agent.emergencyStop: no result emitted")
	}
}
