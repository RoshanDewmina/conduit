package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestDeviceRegister verifies that lancer.device.register stores the device
// info, mints a per-session relayToken, returns it to the app in the handshake
// result, and registers sessionId → relayToken with the backend.
func TestDeviceRegister(t *testing.T) {
	gotReg := make(chan map[string]string, 1)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/register" {
			var body map[string]string
			_ = json.NewDecoder(r.Body).Decode(&body)
			select {
			case gotReg <- body:
			default:
			}
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer backend.Close()

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	// Capture the RPC result frame via the emitter seam.
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

	params, _ := json.Marshal(map[string]string{
		"pushBackendURL": backend.URL,
		"sessionID":      "test-session-id",
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "lancer.device.register", Params: params})

	s.deviceMu.RLock()
	dev := s.device
	storedToken := s.relayToken
	s.deviceMu.RUnlock()
	if dev == nil {
		t.Fatal("device not registered")
	}
	if dev.PushBackendURL != backend.URL {
		t.Errorf("pushBackendURL = %q, want %q", dev.PushBackendURL, backend.URL)
	}
	if dev.SessionID != "test-session-id" {
		t.Errorf("sessionID = %q, want %q", dev.SessionID, "test-session-id")
	}
	if storedToken == "" {
		t.Fatal("relayToken not minted")
	}

	// The handshake result must carry the relayToken under the exact field name.
	var res rpcMessage
	select {
	case res = <-resultCh:
	case <-time.After(2 * time.Second):
		t.Fatal("no RPC result emitted")
	}
	resMap, ok := res.Result.(map[string]interface{})
	if !ok {
		t.Fatalf("result is %T, want object with relayToken", res.Result)
	}
	if resMap["relayToken"] != storedToken {
		t.Fatalf("handshake relayToken = %v, want %q", resMap["relayToken"], storedToken)
	}

	// lancerd must register sessionId → relayToken with the backend.
	select {
	case body := <-gotReg:
		if body["sessionId"] != "test-session-id" {
			t.Errorf("registration sessionId = %q", body["sessionId"])
		}
		if body["relayToken"] != storedToken {
			t.Errorf("registration relayToken = %q, want %q", body["relayToken"], storedToken)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("lancerd did not register relayToken with backend")
	}
}

// TestRunControlRPCs verifies agent.pause, agent.resume, and agent.budget.set RPCs.
func TestRunControlRPCs(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	run := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})
	if run.RunID == "" {
		t.Fatalf("dispatch did not start a run: %+v", run)
	}

	// call drives one RPC and asserts the boolean it returns under `key`.
	call := func(method, key, runID string, want bool) {
		t.Helper()
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
		params, _ := json.Marshal(map[string]interface{}{"runId": runID, "budgetUSD": 1.0})
		s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: method, Params: params})
		select {
		case res := <-resultCh:
			m, ok := res.Result.(map[string]interface{})
			if !ok || m[key] != want {
				t.Fatalf("%s: result = %#v, want %s=%v", method, res.Result, key, want)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("%s: no result emitted", method)
		}
	}

	// Ordering matters: pause must precede resume (the dispatcher state machine
	// only resumes a paused run). budgetUSD is ignored by pause/resume.
	call("agent.pause", "paused", run.RunID, true)
	call("agent.resume", "resumed", run.RunID, true)
	call("agent.budget.set", "ok", run.RunID, true)

	// An absent runId returns false through the RPC layer (not an error frame).
	call("agent.pause", "paused", "no-such-run", false)
}

func TestEmergencyStopRPCStopsRunsAndReturnsCount(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	run := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string, bool) { return "allow", "ok", false }, func(AuditEntry) {})
	if run.RunID == "" {
		t.Fatalf("dispatch did not start a run: %+v", run)
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
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.emergencyStop"})

	select {
	case res := <-resultCh:
		m, ok := res.Result.(map[string]interface{})
		if !ok {
			t.Fatalf("result = %#v, want object", res.Result)
		}
		if m["emergencyStopped"] != true || m["stoppedRuns"] != float64(1) {
			t.Fatalf("result = %#v, want emergencyStopped=true stoppedRuns=1", res.Result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("agent.emergencyStop: no result emitted")
	}
	if status := s.dispatcher.runStatus(run.RunID); status != "cancelled" {
		t.Fatalf("run status = %q, want cancelled", status)
	}
}

// TestPostApprovalPush verifies that postApprovalPush POSTs to /approval with the correct payload.
func TestPostApprovalPush(t *testing.T) {
	var received []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/approval" || r.Method != http.MethodPost {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		received = make([]byte, r.ContentLength)
		r.Body.Read(received)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	s := newServer(t.TempDir())
	dev := &registeredDevice{
		PushBackendURL: srv.URL,
		SessionID:      "device-session-123",
	}

	event := ApprovalEvent{
		ApprovalID: "approval-abc",
		Command:    "ls /tmp",
		Risk:       1, // medium
	}

	s.postApprovalPush(dev, event)

	var payload map[string]interface{}
	if err := json.Unmarshal(received, &payload); err != nil {
		t.Fatalf("could not decode payload: %v (raw: %s)", err, received)
	}
	if payload["sessionId"] != "device-session-123" {
		t.Errorf("sessionId = %v, want device-session-123", payload["sessionId"])
	}
	if payload["id"] != "approval-abc" {
		t.Errorf("id = %v, want approval-abc", payload["id"])
	}
	if payload["risk"] != "medium" {
		t.Errorf("risk = %v, want medium", payload["risk"])
	}
}

// TestHandleRunStartedPostsRunStart proves handleRunStarted POSTs /run-start
// with the phone's persistent device SessionID (not the agent run ID) — the
// exact ID space push-backend's liveActivityRegistry keys on. A wrong ID here
// silently no-ops forever with zero errors.
func TestHandleRunStartedPostsRunStart(t *testing.T) {
	got := make(chan map[string]interface{}, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/run-start" || r.Method != http.MethodPost {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		var body map[string]interface{}
		_ = json.NewDecoder(r.Body).Decode(&body)
		got <- body
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.deviceMu.Lock()
	s.device = &registeredDevice{
		PushBackendURL: srv.URL,
		SessionID:      "phone-session-xyz",
	}
	s.deviceMu.Unlock()

	s.handleRunStarted("agent-run-should-NOT-be-sessionId", "claudeCode")

	select {
	case payload := <-got:
		if payload["sessionId"] != "phone-session-xyz" {
			t.Fatalf("sessionId = %v, want phone-session-xyz (dev.SessionID, not the run ID)", payload["sessionId"])
		}
		if payload["agent"] != "claudeCode" {
			t.Fatalf("agent = %v, want claudeCode", payload["agent"])
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for /run-start POST")
	}
}
