package main

import (
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"conduit/conduitd/policy"
)

func withStateDir(t *testing.T) string {
	t.Helper()
	dir := filepath.Join("/tmp", "conduit-ws-a-"+newUUID()[:8])
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	t.Setenv("CONDUIT_STATE_DIR", dir)
	return dir
}

func startResident(t *testing.T) *resident {
	t.Helper()
	r, err := newResident()
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		if err := r.listen(); err != nil {
			t.Logf("resident listen ended: %v", err)
		}
	}()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		path, err := socketPath()
		if err == nil {
			if _, err := os.Stat(path); err == nil {
				return r
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("resident daemon did not start")
	return nil
}

func dialResident(t *testing.T) net.Conn {
	t.Helper()
	path, err := socketPath()
	if err != nil {
		t.Fatal(err)
	}
	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	return conn
}

func TestQueuePersistsAcrossRestart(t *testing.T) {
	dir := withStateDir(t)
	event := ApprovalEvent{
		ApprovalID: "q-1",
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "rm -rf /",
		CWD:        dir,
		Risk:       2,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	q := newDiskQueue(filepath.Join(dir, queueFileName))
	if err := q.add(event); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(dir, queueFileName))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Errorf("queue mode = %o, want 0600", info.Mode().Perm())
	}

	r := &resident{core: newServer(serverHome()), queue: q}
	if err := r.restoreQueue(); err != nil {
		t.Fatal(err)
	}
	pending := r.core.approvals.pendingEvents()
	if len(pending) != 1 || pending[0].ApprovalID != "q-1" {
		t.Fatalf("pending after restore = %+v", pending)
	}
}

func installTestPolicy(t *testing.T) {
	t.Helper()
	doc := policy.Document{
		Default: string(policy.EffectAsk),
		Rules: []policy.Rule{
			{ID: "ask-file-write", Effect: string(policy.EffectAsk), Kind: "fileWrite"},
		},
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(serverHome()), doc); err != nil {
		t.Fatal(err)
	}
}

func TestHookQueuesWithoutAttachDrainsOnAttach(t *testing.T) {
	withStateDir(t)
	installTestPolicy(t)
	startResident(t)

	event := ApprovalEvent{
		ApprovalID: "hook-1",
		Agent:      "claudeCode",
		Kind:       "fileWrite",
		Command:    "notes.txt",
		CWD:        "/tmp",
		Risk:       0,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}

	var wg sync.WaitGroup
	wg.Add(1)
	var hookDecision ApprovalDecision
	go func() {
		defer wg.Done()
		conn := dialResident(t)
		defer conn.Close()
		_ = json.NewEncoder(conn).Encode(event)
		_ = json.NewDecoder(conn).Decode(&hookDecision)
	}()

	time.Sleep(100 * time.Millisecond)

	qPath, _ := queuePath()
	data, err := os.ReadFile(qPath)
	if err != nil {
		t.Fatalf("queue file: %v", err)
	}
	if !strings.Contains(string(data), "hook-1") {
		t.Fatalf("expected queued event, got %s", data)
	}

	attach := dialResident(t)
	defer attach.Close()
	hello, _ := json.Marshal(attachHello{Op: "attach"})
	if err := writeFrame(attach, hello); err != nil {
		t.Fatal(err)
	}

	var notified bool
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		frame, err := readFrame(attach)
		if err != nil {
			break
		}
		var msg rpcMessage
		if json.Unmarshal(frame, &msg) == nil && msg.Method == "agent.approval.pending" {
			notified = true
			break
		}
	}
	if !notified {
		t.Fatal("attach client did not receive agent.approval.pending")
	}

	params, _ := json.Marshal(ApprovalDecision{ApprovalID: "hook-1", Decision: "approve"})
	resp, _ := json.Marshal(rpcMessage{
		JSONRPC: "2.0",
		ID:      1,
		Method:  "agent.approval.response",
		Params:  params,
	})
	if err := writeFrame(attach, resp); err != nil {
		t.Fatal(err)
	}

	wg.Wait()
	if hookDecision.Decision != "approve" {
		t.Fatalf("hook decision = %+v", hookDecision)
	}
}

// TestHookFastAutoApprovesWithNoClient is the Finding #10 regression: when the
// daemon is up but NO client can answer (no attach + no registered push device),
// an escalated approval must fast-auto-approve after the short grace, NOT block
// the full 120s. If the grace ever regresses to the 120s window this test's
// deadline (noClientGrace + slack, well under 120s) trips.
func TestHookFastAutoApprovesWithNoClient(t *testing.T) {
	withStateDir(t)
	installTestPolicy(t) // fileWrite → ask (escalate)

	s := newServer(serverHome())
	srv, cli := net.Pipe()

	event := ApprovalEvent{
		ApprovalID: "noclient-1",
		Agent:      "claudeCode",
		Kind:       "fileWrite",
		Command:    "notes.txt",
		CWD:        "/tmp",
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	first, _ := json.Marshal(event)

	done := make(chan struct{})
	go func() {
		// clientReachable=false → no attach client and no registered push device.
		s.handleHookWithNotify(srv, first, nil, func() bool { return false })
		close(done)
	}()

	var decision ApprovalDecision
	_ = cli.SetReadDeadline(time.Now().Add(noClientGrace + 5*time.Second))
	if err := json.NewDecoder(cli).Decode(&decision); err != nil {
		t.Fatalf("decode decision: %v", err)
	}
	if decision.Decision != "approve" {
		t.Fatalf("no-client escalation should fast-auto-approve, got %q", decision.Decision)
	}
	cli.Close()
	<-done

	// The fast-approve must be audited distinctly so it is auditable after the fact.
	entries, err := s.audit.tail(10)
	if err != nil {
		t.Fatalf("audit tail: %v", err)
	}
	var sawAutoAllow bool
	for _, e := range entries {
		if e.Action == "auto-allow-no-client" && e.ApprovalID == "noclient-1" {
			sawAutoAllow = true
		}
	}
	if !sawAutoAllow {
		t.Fatalf("expected auto-allow-no-client audit entry, got %+v", entries)
	}
}

// TestHookWaitsWhenClientReachable confirms the fast-approve does NOT fire when a
// client is reachable: with clientReachable=true the hook takes the full 120s
// human-decision path, so a phone decision delivered after the grace window still
// wins. We deliver an approve shortly AFTER noClientGrace to prove the short
// window was not used.
func TestHookWaitsWhenClientReachable(t *testing.T) {
	withStateDir(t)
	installTestPolicy(t)

	s := newServer(serverHome())
	srv, cli := net.Pipe()

	event := ApprovalEvent{
		ApprovalID: "reachable-1",
		Agent:      "claudeCode",
		Kind:       "fileWrite",
		Command:    "notes.txt",
		CWD:        "/tmp",
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	first, _ := json.Marshal(event)

	go s.handleHookWithNotify(srv, first, nil, func() bool { return true })

	// Resolve via the RPC path slightly after the grace would have expired; if the
	// hook had wrongly used the short grace it would already have auto-approved and
	// removed the pending, so this resolve would be a no-op and the decode below
	// would read a fast-approve instead of our explicit deny.
	time.Sleep(noClientGrace + 500*time.Millisecond)
	if _, ok := s.applyDecision("reachable-1", "deny", ""); !ok {
		t.Fatal("pending approval missing — hook did not keep waiting past the grace window")
	}

	var decision ApprovalDecision
	_ = cli.SetReadDeadline(time.Now().Add(5 * time.Second))
	if err := json.NewDecoder(cli).Decode(&decision); err != nil {
		t.Fatalf("decode decision: %v", err)
	}
	if decision.Decision != "deny" {
		t.Fatalf("reachable-client decision should honor the user's deny, got %q", decision.Decision)
	}
	cli.Close()
}

func TestServeAttachRelaysPing(t *testing.T) {
	withStateDir(t)
	startResident(t)

	sockPath, _ := socketPath()
	client, err := net.Dial("unix", sockPath)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	hello, _ := json.Marshal(attachHello{Op: "attach"})
	if err := writeFrame(client, hello); err != nil {
		t.Fatal(err)
	}

	ping, _ := json.Marshal(rpcMessage{JSONRPC: "2.0", ID: 1, Method: "ping"})
	if err := writeFrame(client, ping); err != nil {
		t.Fatal(err)
	}

	frame, err := readFrame(client)
	if err != nil {
		t.Fatal(err)
	}
	var msg rpcMessage
	if err := json.Unmarshal(frame, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.Result != "pong" {
		t.Fatalf("ping result = %v", msg.Result)
	}
}

func TestResidentRejectsSecondAttach(t *testing.T) {
	withStateDir(t)
	startResident(t)

	a := dialResident(t)
	defer a.Close()
	hello, _ := json.Marshal(attachHello{Op: "attach"})
	_ = writeFrame(a, hello)
	time.Sleep(50 * time.Millisecond)

	b := dialResident(t)
	defer b.Close()
	_ = writeFrame(b, hello)
	_ = b.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	_, err := readFrame(b)
	if err == nil {
		t.Fatal("expected second attach to close without frame")
	}
	if err != io.EOF && !isClosedNetErr(err) {
		// connection closed is acceptable
	}
}

func isClosedNetErr(err error) bool {
	if err == nil {
		return false
	}
	return err.Error() == "read: connection reset by peer" ||
		err.Error() == "EOF"
}
