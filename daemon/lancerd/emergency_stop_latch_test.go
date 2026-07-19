package main

import (
	"encoding/json"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// readPidsForTest parses whitespace-separated integer pids out of a file
// written by the test's own shell script; a missing file (not yet written)
// or a stray non-numeric line just yields fewer pids, which the poll loop
// treats as "not ready yet".
func readPidsForTest(t *testing.T, path string) []int {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var pids []int
	for _, line := range strings.Fields(string(data)) {
		if pid, err := strconv.Atoi(line); err == nil {
			pids = append(pids, pid)
		}
	}
	return pids
}

// TestEmergencyStopLatchPersistsAcrossRestart is the B2 restart regression:
// Emergency Stop must survive a daemon restart. It simulates a restart by
// constructing a second *server on the SAME home dir (newServer reloads the
// on-disk latch at startup) and proves both that the in-memory flag comes
// back active AND that a hook request arriving on the "new" process — the
// late-poller scenario from a hook process that outlived the old one — gets
// denied immediately rather than queued/waited-on.
func TestEmergencyStopLatchPersistsAcrossRestart(t *testing.T) {
	home := t.TempDir()

	s1 := newServer(home)
	defer s1.poller.stopForTest()
	s1.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	run := s1.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"}, allowEval, noAudit)
	if run.Status != "started" {
		t.Fatalf("setup dispatch = %+v, want started", run)
	}
	if _, _ = s1.applyEmergencyStop(); !s1.dispatcher.emergencyStopActive() {
		t.Fatal("emergencyStop did not set the in-memory flag before restart")
	}

	// "Restart": a fresh server value over the same home dir, exactly what
	// happens when the OS or launchd relaunches lancerd after a stop.
	s2 := newServer(home)
	defer s2.poller.stopForTest()
	if !s2.dispatcher.emergencyStopActive() {
		t.Fatal("emergency-stop latch did not survive daemon restart — dispatcher.emergencyStopped reset to false")
	}

	// A hook process that started before the restart and is only now getting
	// around to asking (or a brand-new one launched right after) must be
	// denied immediately — no queueing, no wait for a human.
	srv, cli := net.Pipe()
	event := ApprovalEvent{
		ApprovalID: "late-poll-after-restart-1",
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "sleep 120",
		CWD:        home,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	first, _ := json.Marshal(event)

	done := make(chan struct{})
	go func() {
		s2.handleHookWithNotify(srv, first, nil, func() bool { return true })
		close(done)
	}()

	var decision ApprovalDecision
	_ = cli.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := json.NewDecoder(cli).Decode(&decision); err != nil {
		t.Fatalf("decode decision: %v (hook did not respond promptly — it must not queue/wait once the latch is active)", err)
	}
	if decision.Decision != "deny" {
		t.Fatalf("decision = %q, want deny", decision.Decision)
	}
	cli.Close()
	<-done

	if pending := s2.approvals.pendingEvents(); len(pending) != 0 {
		t.Fatalf("late-arriving escalation was queued as pending = %+v, want denied outright", pending)
	}
}

// TestHookDeniesNewEscalationRaisedWhileEmergencyStopped covers the other half
// of the fail-closed requirement: a brand-new PreToolUse escalation raised
// AFTER a stop (no restart involved) must also be denied immediately, not
// just already-pending ones at the moment of the stop (that half is covered
// by TestEmergencyStopDeniesPendingApprovalsAndUnblocksWaiters).
func TestHookDeniesNewEscalationRaisedWhileEmergencyStopped(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	if _, _ = s.applyEmergencyStop(); !s.dispatcher.emergencyStopActive() {
		t.Fatal("applyEmergencyStop did not activate the latch")
	}

	srv, cli := net.Pipe()
	event := ApprovalEvent{
		ApprovalID: "new-escalation-post-stop-1",
		Agent:      "claudeCode",
		Kind:       "fileWrite",
		Command:    "notes.txt",
		CWD:        home,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	first, _ := json.Marshal(event)

	done := make(chan struct{})
	go func() {
		s.handleHookWithNotify(srv, first, nil, func() bool { return true })
		close(done)
	}()

	var decision ApprovalDecision
	_ = cli.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := json.NewDecoder(cli).Decode(&decision); err != nil {
		t.Fatalf("decode decision: %v", err)
	}
	if decision.Decision != "deny" {
		t.Fatalf("decision = %q, want deny", decision.Decision)
	}
	cli.Close()
	<-done

	entries, err := s.audit.tail(50)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, e := range entries {
		if e.ApprovalID == event.ApprovalID && e.Action == "auto-deny-emergency-stop" {
			found = true
		}
	}
	if !found {
		t.Fatalf("audit missing auto-deny-emergency-stop entry for %s; entries=%+v", event.ApprovalID, entries)
	}
}

// TestEmergencyStopClearRPCLiftsLatch proves the documented, sole way the
// latch clears: an explicit agent.emergencyStop.clear RPC — dispatch is
// blocked before it, allowed after, and the on-disk latch itself flips back
// to inactive (so a subsequent restart doesn't resurrect the stop).
func TestEmergencyStopClearRPCLiftsLatch(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	if _, _ = s.applyEmergencyStop(); !s.dispatcher.emergencyStopActive() {
		t.Fatal("applyEmergencyStop did not activate the latch")
	}

	blocked := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "blocked"}, allowEval, noAudit)
	if blocked.Status != "emergencyStopped" {
		t.Fatalf("dispatch while stopped = %q, want emergencyStopped", blocked.Status)
	}

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
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.emergencyStop.clear"})
	select {
	case res := <-resultCh:
		m, ok := res.Result.(map[string]interface{})
		if !ok || m["emergencyStopped"] != false {
			t.Fatalf("clear result = %#v, want emergencyStopped=false", res.Result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("agent.emergencyStop.clear: no result emitted")
	}

	if s.dispatcher.emergencyStopActive() {
		t.Fatal("latch still active in-memory after clear")
	}

	resumed := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "resumed"}, allowEval, noAudit)
	if resumed.Status != "started" {
		t.Fatalf("dispatch after clear = %+v, want started", resumed)
	}

	// A "restart" after the clear must NOT come back stopped.
	s2 := newServer(home)
	defer s2.poller.stopForTest()
	if s2.dispatcher.emergencyStopActive() {
		t.Fatal("latch resurrected on restart after an explicit clear — clear did not persist to disk")
	}
}

// TestEmergencyStopWorksWithNoRelayClientConnected is the B2 "no phone
// connectivity" requirement: applyEmergencyStop must fully do its job (kill
// runs, deny pending approvals) purely through the local call path, with no
// E2E relay wired up at all — proving the stop path does not depend on a
// connected relay client.
func TestEmergencyStopWorksWithNoRelayClientConnected(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()
	if s.e2e != nil {
		t.Fatal("test setup: server has an e2e router wired — this test needs none, to prove the stop path is relay-independent")
	}
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	run := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"}, allowEval, noAudit)
	event := ApprovalEvent{
		ApprovalID:  "no-relay-escalation-1",
		Agent:       "claudeCode",
		Kind:        "command",
		Command:     "sleep 120",
		CWD:         home,
		ContentHash: computeContentHash("sleep 120", "", home, ""),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
	}
	decisionCh := s.approvals.add(event)

	stopped, denied := s.applyEmergencyStop()
	if stopped != 1 {
		t.Fatalf("stoppedRuns = %d, want 1 (run %s)", stopped, run.RunID)
	}
	if denied != 1 {
		t.Fatalf("deniedApprovals = %d, want 1", denied)
	}
	select {
	case d := <-decisionCh:
		if d.decision != "deny" {
			t.Fatalf("decision = %q, want deny", d.decision)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("pending escalation was not resolved without a relay client connected")
	}
}

// TestEmergencyStopKillsWholeProcessGroup proves item (d): a real OS process
// tree (a shell with a backgrounded child, both in the same process group via
// Setpgid) is fully killed — parent AND child — by the same handle.kill() that
// dispatcher.emergencyStop() invokes for every stopped run (see
// TestEmergencyStopStopsRunsAndBlocksLaunches, which proves emergencyStop
// calls handle.kill(); this test proves what that kill actually does at the
// OS level via realLauncher).
func TestEmergencyStopKillsWholeProcessGroup(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("sh not available")
	}
	pidFile := filepath.Join(t.TempDir(), "pids")
	// Write the shell's own pid, then a backgrounded child's pid, before
	// waiting on the child — giving us two distinct real pids in one
	// process group to check after the kill.
	script := "echo $$ > " + pidFile + "; (sleep 30 & echo $! >> " + pidFile + "; wait)"

	emit := func(method string, params any) {}
	h, err := realLauncher([]string{"sh", "-c", script}, "", "run-killgroup-1", emit)
	if err != nil {
		t.Fatalf("realLauncher: %v", err)
	}

	var pids []int
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		pids = readPidsForTest(t, pidFile)
		if len(pids) == 2 {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if len(pids) != 2 {
		t.Fatalf("did not observe 2 pids in %s within deadline, got %v", pidFile, pids)
	}
	for _, pid := range pids {
		if err := syscall.Kill(pid, 0); err != nil {
			t.Fatalf("pid %d not alive before kill (test setup broken): %v", pid, err)
		}
	}

	h.kill()

	deadline = time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		allDead := true
		for _, pid := range pids {
			if err := syscall.Kill(pid, 0); err == nil {
				allDead = false
			}
		}
		if allDead {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	for _, pid := range pids {
		if err := syscall.Kill(pid, 0); err == nil {
			t.Fatalf("pid %d still alive after handle.kill() — process group was not fully killed", pid)
		}
	}
}
