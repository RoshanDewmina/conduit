package main

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func seedQueuedApproval(t *testing.T, r *resident, id, contentHash string) ApprovalEvent {
	t.Helper()
	event := ApprovalEvent{
		ApprovalID:  id,
		Agent:       "claudeCode",
		Kind:        "command",
		Command:     "printf queue-resolution-proof",
		CWD:         t.TempDir(),
		Risk:        1,
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		ContentHash: contentHash,
	}
	r.core.approvals.add(event)
	if err := r.queue.add(event); err != nil {
		t.Fatalf("queue.add: %v", err)
	}
	return event
}

func approvalResponseMessage(t *testing.T, id, contentHash string) *rpcMessage {
	t.Helper()
	params, err := json.Marshal(ApprovalDecision{
		ApprovalID:  id,
		Decision:    "approve",
		ContentHash: contentHash,
	})
	if err != nil {
		t.Fatal(err)
	}
	return &rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.approval.response", Params: params}
}

func assertQueueIDs(t *testing.T, r *resident, want ...string) {
	t.Helper()
	events, err := r.queue.readAll()
	if err != nil {
		t.Fatalf("queue.readAll: %v", err)
	}
	if len(events) != len(want) {
		t.Fatalf("queue contains %d event(s), want %d: %+v", len(events), len(want), events)
	}
	for i := range want {
		if events[i].ApprovalID != want[i] {
			t.Fatalf("queue[%d].ApprovalID = %q, want %q", i, events[i].ApprovalID, want[i])
		}
	}
}

func TestApprovalResolutionSyncsPersistentQueueForEveryIngress(t *testing.T) {
	tests := []struct {
		name    string
		resolve func(t *testing.T, r *resident, id string)
	}{
		{
			name: "e2e relay",
			resolve: func(t *testing.T, r *resident, id string) {
				client := &fakeRelayClient{paired: true}
				router := &e2eRouter{client: client, server: r.core}
				payload, err := json.Marshal(map[string]string{
					"approvalID": id,
					"decision":   "approve",
				})
				if err != nil {
					t.Fatal(err)
				}
				router.handleMessage("approvalResponse", payload)
			},
		},
		{
			name: "attach",
			resolve: func(t *testing.T, r *resident, id string) {
				r.handleAttachMessage(approvalResponseMessage(t, id, ""))
			},
		},
		{
			name: "control",
			resolve: func(t *testing.T, r *resident, id string) {
				serverConn, clientConn := net.Pipe()
				defer serverConn.Close()
				defer clientConn.Close()
				done := make(chan struct{})
				go func() {
					r.handleControlMessage(serverConn, approvalResponseMessage(t, id, ""))
					close(done)
				}()
				if _, err := readFrame(clientConn); err != nil {
					t.Fatalf("read control response: %v", err)
				}
				<-done
			},
		},
		{
			name: "canonical resolver",
			resolve: func(t *testing.T, r *resident, id string) {
				if _, ok := r.core.applyDecision(id, "approve", "", ""); !ok {
					t.Fatal("applyDecision did not resolve pending approval")
				}
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			withStateDir(t)
			r, err := newResident()
			if err != nil {
				t.Fatalf("newResident: %v", err)
			}
			defer r.core.poller.stopForTest()
			seedQueuedApproval(t, r, "approval-"+tc.name, "")

			tc.resolve(t, r, "approval-"+tc.name)

			assertQueueIDs(t, r)
		})
	}
}

func TestDecisionPollerResolutionSyncsPersistentQueue(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-poll", "")

	var requests atomic.Int32
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if requests.Add(1) == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"decisions": []map[string]string{{"approvalId": "approval-poll", "decision": "approve"}},
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"decisions": []any{}})
	}))
	defer backend.Close()

	r.core.poller.pollIntervalForTest = 20 * time.Millisecond
	r.core.poller.ensureRunning(backend.URL, "session", "token")
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		queued, err := r.queue.readAll()
		if err != nil {
			t.Fatalf("queue.readAll: %v", err)
		}
		if len(r.core.approvals.pendingEvents()) == 0 && len(queued) == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("poller did not resolve approval")
}

func TestRejectedApprovalResponsePreservesPersistentQueue(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-hash-mismatch", "expected-hash")

	r.handleAttachMessage(approvalResponseMessage(t, "approval-hash-mismatch", "wrong-hash"))

	assertQueueIDs(t, r, "approval-hash-mismatch")
	if len(r.core.approvals.pendingEvents()) != 1 {
		t.Fatal("hash-mismatched decision removed the in-memory approval")
	}
}

func TestCaseInsensitiveResolutionRemovesCanonicalQueueID(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-mixed-case", "")

	if _, ok := r.core.applyDecision("APPROVAL-MIXED-CASE", "approve", "", ""); !ok {
		t.Fatal("case-insensitive applyDecision did not resolve pending approval")
	}

	assertQueueIDs(t, r)
}

func TestResolvedApprovalDoesNotReturnAfterRestart(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-restart", "")

	client := &fakeRelayClient{paired: true}
	router := &e2eRouter{client: client, server: r.core}
	payload := []byte(`{"approvalID":"approval-restart","decision":"approve"}`)
	router.handleMessage("approvalResponse", payload)

	restarted := &resident{core: newServer(serverHome()), queue: r.queue}
	defer restarted.core.poller.stopForTest()
	if err := restarted.restoreQueue(); err != nil {
		t.Fatalf("restoreQueue: %v", err)
	}
	if got := restarted.core.approvals.pendingEvents(); len(got) != 0 {
		t.Fatalf("resolved approval returned after restart: %+v", got)
	}
}

func TestDeliveringPendingApprovalDoesNotEraseRestartState(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-delivered-not-resolved", "")

	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()
	r.attach = serverConn
	done := make(chan error, 1)
	go func() { done <- r.drainToAttach() }()
	if _, err := readFrame(clientConn); err != nil {
		t.Fatalf("read pending notification: %v", err)
	}
	if err := <-done; err != nil {
		t.Fatalf("drainToAttach: %v", err)
	}

	assertQueueIDs(t, r, "approval-delivered-not-resolved")
}

func TestConcurrentResolutionsCannotResurrectQueueEntries(t *testing.T) {
	withStateDir(t)
	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	defer r.core.poller.stopForTest()
	seedQueuedApproval(t, r, "approval-concurrent-a", "")
	seedQueuedApproval(t, r, "approval-concurrent-b", "")

	start := make(chan struct{})
	done := make(chan bool, 2)
	for _, id := range []string{"approval-concurrent-a", "approval-concurrent-b"} {
		go func(id string) {
			<-start
			_, ok := r.core.applyDecision(id, "approve", "", "")
			done <- ok
		}(id)
	}
	close(start)
	if !<-done || !<-done {
		t.Fatal("concurrent decision did not resolve")
	}

	assertQueueIDs(t, r)
}
