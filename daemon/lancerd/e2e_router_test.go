package main

import (
	"encoding/json"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"lancer/lancerd/policy"
)

// fakeRelayClient is a minimal e2eRelayClient stub that records sent messages.
type fakeRelayClient struct {
	mu       sync.Mutex
	messages []struct {
		msgType string
		data    []byte
	}
	paired bool
}

func (f *fakeRelayClient) isPaired() bool { return f.paired }

func (f *fakeRelayClient) stop() {}

func (f *fakeRelayClient) sendMessage(msgType string, data []byte) error {
	f.mu.Lock()
	f.messages = append(f.messages, struct {
		msgType string
		data    []byte
	}{msgType, data})
	f.mu.Unlock()
	return nil
}

func (f *fakeRelayClient) lastMessage() (string, []byte) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.messages) == 0 {
		return "", nil
	}
	m := f.messages[len(f.messages)-1]
	return m.msgType, m.data
}

// TestE2ERouterDispatch verifies that an inbound agentDispatch message through
// the E2E router calls server.runDispatch and sends the result back.
func TestE2ERouterDispatch(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	// Use a non-hook agent (codex): its launch escalation is preserved under the
	// fail-closed default, so this still exercises the router's escalation path.
	// (Hook-gated agents like claude/opencode now launch and rely on the
	// per-action PreToolUse hook — see relaxLaunchEscalation + dispatch_launchgate_test.)
	dispatchPayload, _ := json.Marshal(map[string]interface{}{
		"agent":  "codex",
		"cwd":    "/tmp",
		"prompt": "test task",
	})
	router.handleMessage("agentDispatch", dispatchPayload)

	msgType, data := client.lastMessage()
	if msgType != "dispatchResult" {
		t.Fatalf("expected dispatchResult, got %q", msgType)
	}
	var env struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	var result dispatchResult
	if err := json.Unmarshal(env.Payload, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result.Status != "needsApproval" {
		t.Fatalf("expected needsApproval (default policy escalates a non-hook agent), got %q", result.Status)
	}
}

// TestE2ERouterDispatchStarted verifies a dispatch that passes policy starts
// the run and returns a runId.
func TestE2ERouterDispatchStarted(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	// Install a permissive policy so dispatch proceeds.
	doc := policy.Document{
		Default: string(policy.EffectAllow),
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), doc); err != nil {
		t.Fatal(err)
	}
	srv.policy.reload("")

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	dispatchPayload, _ := json.Marshal(map[string]interface{}{
		"agent":  "opencode",
		"cwd":    "/tmp",
		"prompt": "test task",
	})
	router.handleMessage("agentDispatch", dispatchPayload)

	msgType, data := client.lastMessage()
	if msgType != "dispatchResult" {
		t.Fatalf("expected dispatchResult, got %q", msgType)
	}
	var env struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	var result dispatchResult
	if err := json.Unmarshal(env.Payload, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result.Status != "started" {
		t.Fatalf("expected started, got %q", result.Status)
	}
	if result.RunID == "" {
		t.Fatal("expected non-empty runId")
	}
}

// TestE2ERouterContinue verifies that an inbound agentRunContinue message reaches
// server.runContinue, re-passes the gate, and replies with runContinueResult
// carrying a NEW runId.
func TestE2ERouterContinue(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()
	srv.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), policy.Document{Default: string(policy.EffectAllow)}); err != nil {
		t.Fatal(err)
	}
	srv.policy.reload("")

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	first := srv.runDispatch(dispatchParams{Agent: "opencode", CWD: "/tmp", Prompt: "start"})
	if first.Status != "started" {
		t.Fatalf("dispatch: want started, got %q", first.Status)
	}

	payload, _ := json.Marshal(map[string]string{"runId": first.RunID, "prompt": "next"})
	router.handleMessage("agentRunContinue", payload)

	msgType, data := client.lastMessage()
	if msgType != "runContinueResult" {
		t.Fatalf("expected runContinueResult, got %q", msgType)
	}
	var env struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	var result dispatchResult
	if err := json.Unmarshal(env.Payload, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result.Status != "started" || result.RunID == "" || result.RunID == first.RunID {
		t.Fatalf("continue: want started + new runId, got %+v", result)
	}
}

// TestE2ERouterSessionContinue verifies that an inbound agentSessionContinue
// message reaches server.runObservedSessionContinue (the same core logic the
// SSH transport's agent.observedSession.continue uses) and replies with
// sessionContinueResult carrying a new runId.
func TestE2ERouterSessionContinue(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()
	srv.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), policy.Document{Default: string(policy.EffectAllow)}); err != nil {
		t.Fatal(err)
	}
	srv.policy.reload("")

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{
		"vendor":    "claudeCode",
		"sessionId": "sess-abc",
		"cwd":       "/repo/observed",
		"prompt":    "keep going",
	})
	router.handleMessage("agentSessionContinue", payload)

	msgType, data := client.lastMessage()
	if msgType != "sessionContinueResult" {
		t.Fatalf("expected sessionContinueResult, got %q", msgType)
	}
	var env struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	var result dispatchResult
	if err := json.Unmarshal(env.Payload, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result.Status != "started" || result.RunID == "" {
		t.Fatalf("want started + runId, got %+v", result)
	}
}

// TestE2ERouterSessionContinueDenied verifies a policy-denied
// agentSessionContinue does not launch and replies with a denied result.
func TestE2ERouterSessionContinueDenied(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()
	launched := false
	srv.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), policy.Document{Default: string(policy.EffectDeny)}); err != nil {
		t.Fatal(err)
	}
	srv.policy.reload("")

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{
		"vendor":    "claudeCode",
		"sessionId": "sess-abc",
		"cwd":       "/repo/observed",
		"prompt":    "keep going",
	})
	router.handleMessage("agentSessionContinue", payload)

	if launched {
		t.Fatal("a policy-denied agentSessionContinue must NOT launch")
	}
	msgType, data := client.lastMessage()
	if msgType != "sessionContinueResult" {
		t.Fatalf("expected sessionContinueResult, got %q", msgType)
	}
	var env struct {
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	var result dispatchResult
	if err := json.Unmarshal(env.Payload, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result.Status != "denied" {
		t.Fatalf("want denied, got %+v", result)
	}
}

// TestE2ERouterFsList verifies that an inbound agentFsList message reaches
// server.fsList and replies with fsListResult carrying the home-folded path and
// directory-first entries.
func TestE2ERouterFsList(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	mustMkdir(t, filepath.Join(home, "projects"))
	mustWrite(t, filepath.Join(home, "notes.txt"))

	srv := newServer(t.TempDir())
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{"path": "~"})
	router.handleMessage("agentFsList", payload)

	msgType, data := client.lastMessage()
	if msgType != "fsListResult" {
		t.Fatalf("expected fsListResult, got %q", msgType)
	}
	var env struct {
		Type    string `json:"type"`
		Payload struct {
			Path    string    `json:"path"`
			Parent  string    `json:"parent"`
			Entries []fsEntry `json:"entries"`
			Error   string    `json:"error"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if env.Payload.Error != "" {
		t.Fatalf("unexpected error: %q", env.Payload.Error)
	}
	if env.Payload.Path != "~" {
		t.Errorf("path = %q, want ~", env.Payload.Path)
	}
	want := []fsEntry{{Name: "projects", IsDir: true}, {Name: "notes.txt", IsDir: false}}
	if len(env.Payload.Entries) != len(want) {
		t.Fatalf("entries = %+v, want %+v", env.Payload.Entries, want)
	}
	for i, w := range want {
		if env.Payload.Entries[i] != w {
			t.Errorf("entries[%d] = %+v, want %+v", i, env.Payload.Entries[i], w)
		}
	}
}

// TestE2ERouterFsListRejectsEscape verifies a path outside the home directory
// comes back as an error field (fail-closed) with an empty (non-null) entries list.
func TestE2ERouterFsListRejectsEscape(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	srv := newServer(t.TempDir())
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{"path": "/etc"})
	router.handleMessage("agentFsList", payload)

	_, data := client.lastMessage()
	var env struct {
		Payload struct {
			Entries []fsEntry `json:"entries"`
			Error   string    `json:"error"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if env.Payload.Error == "" {
		t.Fatal("expected an error for a path outside home")
	}
	if env.Payload.Entries == nil {
		t.Fatal("expected entries to be [] not null")
	}
}

// TestE2ERouterSendRelayNotification verifies that sendRelayNotification sends
// a correctly typed message only when paired.
func TestE2ERouterSendRelayNotification(t *testing.T) {
	t.Run("sends when paired", func(t *testing.T) {
		client := &fakeRelayClient{paired: true}
		router := &e2eRouter{client: client}

		params := map[string]interface{}{"runId": "r-1", "stream": "stdout", "chunk": "hello", "seq": 1}
		router.sendRelayNotification("agent.run.output", params)

		msgType, data := client.lastMessage()
		if msgType != "agentRunOutput" {
			t.Fatalf("expected agentRunOutput, got %q", msgType)
		}
		var env struct {
			Type    string                 `json:"type"`
			Payload map[string]interface{} `json:"payload"`
		}
		if err := json.Unmarshal(data, &env); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		if env.Payload["runId"] != "r-1" {
			t.Fatalf("payload.runId = %v", env.Payload["runId"])
		}
	})

	t.Run("noop when not paired", func(t *testing.T) {
		client := &fakeRelayClient{paired: false}
		router := &e2eRouter{client: client}
		router.sendRelayNotification("agent.run.output", nil)

		_, data := client.lastMessage()
		if data != nil {
			t.Fatal("expected no message when not paired")
		}
	})

	t.Run("noop for unmapped method", func(t *testing.T) {
		client := &fakeRelayClient{paired: true}
		router := &e2eRouter{client: client}
		router.sendRelayNotification("agent.ping", nil)

		_, data := client.lastMessage()
		if data != nil {
			t.Fatal("expected no message for unmapped method")
		}
	})
}

// TestRelayPairPersistence tests writing and reading relay-pairing.json in an
// isolated LANCER_STATE_DIR.
func TestRelayPairPersistence(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	cfg := &relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "123456",
		PrivateKey: "test-priv-key-b64",
		PublicKey:  "test-pub-key-b64",
	}
	if err := writeRelayPairing(cfg); err != nil {
		t.Fatalf("writeRelayPairing: %v", err)
	}

	read, err := readRelayPairing()
	if err != nil {
		t.Fatalf("readRelayPairing: %v", err)
	}
	if read.RelayURL != cfg.RelayURL {
		t.Errorf("RelayURL = %q, want %q", read.RelayURL, cfg.RelayURL)
	}
	if read.Code != cfg.Code {
		t.Errorf("Code = %q, want %q", read.Code, cfg.Code)
	}
	if read.PrivateKey != cfg.PrivateKey {
		t.Errorf("PrivateKey = %q, want %q", read.PrivateKey, cfg.PrivateKey)
	}
	if read.PublicKey != cfg.PublicKey {
		t.Errorf("PublicKey = %q, want %q", read.PublicKey, cfg.PublicKey)
	}
}

// TestRelayPairWatcher verifies the file watcher detects changes when the
// file is updated after the watcher starts.
func TestRelayPairWatcher(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	changed := make(chan *relayPairConfig, 1)
	w := newRelayPairWatcher(func(cfg *relayPairConfig) {
		changed <- cfg
	})

	w.start()
	defer w.stop()

	// Wait for poll loop to be in its ticker wait, then write.
	time.Sleep(100 * time.Millisecond)

	cfg := &relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "123456",
		PrivateKey: base64URLEncode(make([]byte, 32)),
		PublicKey:  base64URLEncode(make([]byte, 32)),
	}
	if err := writeRelayPairing(cfg); err != nil {
		t.Fatal(err)
	}

	select {
	case c := <-changed:
		if c.Code != "123456" {
			t.Fatalf("got code %q", c.Code)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("watcher never detected file change")
	}
}

// TestE2ERouterHandleApprovalResponse verifies the existing approvalResponse path.
func TestE2ERouterHandleApprovalResponse(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	// Register a pending approval.
	ch := srv.approvals.add(ApprovalEvent{ApprovalID: "appr-2", Command: "test"})

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{
		"approvalID": "appr-2",
		"decision":   "approve",
	})
	router.handleMessage("approvalResponse", payload)

	select {
	case d := <-ch:
		if d.decision != "approve" {
			t.Fatalf("decision = %q, want approve", d.decision)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("approval never resolved")
	}
}

// TestE2ERouterHandleApprovalResponseSendsAck verifies a successful decision
// gets an explicit approvalResponseAck{ok:true} reply — the phone previously
// had no way to distinguish "the daemon processed this" from "the frame went
// nowhere," which was the root cause of decisions silently vanishing.
func TestE2ERouterHandleApprovalResponseSendsAck(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	srv.approvals.add(ApprovalEvent{ApprovalID: "appr-ack-ok", Command: "test"})

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{
		"approvalID": "appr-ack-ok",
		"decision":   "approve",
	})
	router.handleMessage("approvalResponse", payload)

	msgType, data := client.lastMessage()
	if msgType != "approvalResponseAck" {
		t.Fatalf("expected approvalResponseAck, got %q", msgType)
	}
	var ack struct {
		Payload struct {
			ApprovalID string `json:"approvalID"`
			OK         bool   `json:"ok"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &ack); err != nil {
		t.Fatalf("unmarshal ack: %v", err)
	}
	if ack.Payload.ApprovalID != "appr-ack-ok" || !ack.Payload.OK {
		t.Fatalf("ack payload = %+v, want approvalID=appr-ack-ok ok=true", ack.Payload)
	}
}

// TestE2ERouterHandleApprovalResponseAckFailure verifies a decision for an
// unknown/already-resolved approval gets ok:false rather than being silently
// dropped or (worse) implicitly treated as success.
func TestE2ERouterHandleApprovalResponseAckFailure(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()
	// Note: no approvals.add — "appr-missing" was never pending (or already
	// resolved by the timeout path, which behaves identically from here).

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	payload, _ := json.Marshal(map[string]string{
		"approvalID": "appr-missing",
		"decision":   "approve",
	})
	router.handleMessage("approvalResponse", payload)

	msgType, data := client.lastMessage()
	if msgType != "approvalResponseAck" {
		t.Fatalf("expected approvalResponseAck, got %q", msgType)
	}
	var ack struct {
		Payload struct {
			ApprovalID string `json:"approvalID"`
			OK         bool   `json:"ok"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &ack); err != nil {
		t.Fatalf("unmarshal ack: %v", err)
	}
	if ack.Payload.OK {
		t.Fatalf("expected ok=false for a decision on a never-pending approval, got %+v", ack.Payload)
	}
}

// TestE2ERouterSendApprovalResolved verifies the resolved-notification sender
// respects pairing state (no-op when unpaired) and emits the right shape when
// paired.
func TestE2ERouterSendApprovalResolved(t *testing.T) {
	t.Run("unpaired is a no-op", func(t *testing.T) {
		client := &fakeRelayClient{paired: false}
		router := &e2eRouter{client: client}
		router.sendApprovalResolved("appr-x", "deny")
		if msgType, _ := client.lastMessage(); msgType != "" {
			t.Fatalf("expected no message sent while unpaired, got %q", msgType)
		}
	})

	t.Run("paired sends the resolved notice", func(t *testing.T) {
		client := &fakeRelayClient{paired: true}
		router := &e2eRouter{client: client}
		router.sendApprovalResolved("appr-y", "deny")
		msgType, data := client.lastMessage()
		if msgType != "approvalResolved" {
			t.Fatalf("expected approvalResolved, got %q", msgType)
		}
		var msg struct {
			Payload struct {
				ApprovalID string `json:"approvalID"`
				Decision   string `json:"decision"`
			} `json:"payload"`
		}
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		if msg.Payload.ApprovalID != "appr-y" || msg.Payload.Decision != "deny" {
			t.Fatalf("payload = %+v, want approvalID=appr-y decision=deny", msg.Payload)
		}
	})
}

// TestMethodToRelayType verifies the JSON-RPC method → relay type mapping.
func TestMethodToRelayType(t *testing.T) {
	cases := []struct {
		method string
		want   string
	}{
		{"agent.run.output", "agentRunOutput"},
		{"agent.run.status", "agentRunStatus"},
		{"agent.approval.pending", ""},
		{"", ""},
	}
	for _, tc := range cases {
		got := methodToRelayType(tc.method)
		if got != tc.want {
			t.Errorf("methodToRelayType(%q) = %q, want %q", tc.method, got, tc.want)
		}
	}
}

// TestResidentRelayWiringNotPanicking verifies that runDaemon does not panic
// when relay-pairing.json is absent (the common case — no pairing configured).
func TestResidentRelayWiringNoPanicWithoutPairing(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	// wireRelayFromPairing should be a no-op (no file).
	r.wireRelayFromPairing()
	if r.core.e2e != nil {
		t.Fatal("expected no e2e router when no pairing file")
	}
}

// TestResidentRelayWiring verifies that when relay-pairing.json exists,
// wireRelayFromPairing creates the E2E router and client.
func TestResidentRelayWiring(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	priv, pub, err := generateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	cfg := &relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "654321",
		PrivateKey: base64URLEncode(priv[:]),
		PublicKey:  base64URLEncode(pub[:]),
	}
	if err := writeRelayPairing(cfg); err != nil {
		t.Fatal(err)
	}

	r, err := newResident()
	if err != nil {
		t.Fatalf("newResident: %v", err)
	}
	r.wireRelayFromPairing()

	if r.core.e2e == nil {
		t.Fatal("expected e2e router to be wired")
	}
	if r.core.e2e.client == nil {
		t.Fatal("expected e2e client to be created")
	}
}
