package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"lancer/lancerd/policy"
)

// --- test helpers ---------------------------------------------------------

// callSSHRPC drives one agent.conversations.* JSON-RPC call through
// s.handleMessage (the real SSH transport entrypoint) and returns the framed
// rpcMessage response, capturing it via the emitter seam the same way
// server_test.go's TestDeviceRegister/TestRunControlRPCs do.
func callSSHRPC(t *testing.T, s *server, method string, params any) rpcMessage {
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

	var raw json.RawMessage
	if params != nil {
		b, err := json.Marshal(params)
		if err != nil {
			t.Fatalf("marshal params: %v", err)
		}
		raw = b
	}
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: method, Params: raw})

	select {
	case m := <-resultCh:
		return m
	case <-time.After(2 * time.Second):
		t.Fatalf("%s: no RPC frame emitted", method)
	}
	return rpcMessage{}
}

// decodeInto round-trips v (typically an rpcMessage's Result, or a
// json.RawMessage) through JSON into out, failing the test on any error.
func decodeInto(t *testing.T, v any, out any) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := json.Unmarshal(data, out); err != nil {
		t.Fatalf("unmarshal into %T: %v (data=%s)", out, err, data)
	}
}

// relayEnvelope is the {"type":..., "payload":...} shape every relay result
// message uses (see e2e_router.go's conversationRelayPayload/sendMessage calls).
type relayEnvelope struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// callRelay drives one agentConversations* relay message through
// router.handleMessage and returns the decoded envelope.
func callRelay(t *testing.T, router *e2eRouter, client *fakeRelayClient, msgType string, payload any) relayEnvelope {
	t.Helper()
	var raw []byte
	if payload != nil {
		b, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("marshal payload: %v", err)
		}
		raw = b
	}
	router.handleMessage(msgType, raw)

	gotType, data := client.lastMessage()
	if gotType == "" {
		t.Fatalf("%s: no relay message sent", msgType)
	}
	var env relayEnvelope
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	return env
}

// --- tests -----------------------------------------------------------------

// TestServerInitializesConversationStore verifies newServer wires up the
// conversation ledger the same way it wires up policy/audit/secrets/scheduler:
// a real *conversationStore backed by <home>/.lancer/conversations.sqlite.
func TestServerInitializesConversationStore(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	if s.conversations == nil {
		t.Fatal("expected newServer to initialize s.conversations, got nil")
	}
	want := filepath.Join(home, ".lancer", "conversations.sqlite")
	if _, err := os.Stat(want); err != nil {
		t.Errorf("expected sqlite file at %s: %v", want, err)
	}
}

// TestConversationsListSSHAndRelayMatchShape proves the SSH JSON-RPC path
// (agent.conversations.list) and the relay path (agentConversationsList)
// return byte-for-byte identical payloads for the same underlying store
// state — required by the cross-device sync build handoff's Task 2 steps.
func TestConversationsListSSHAndRelayMatchShape(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	if _, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "Fix the failing auth test",
	}, "/Users/roshan/project", "run_1"); err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.list", map[string]interface{}{"limit": 50})
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.list error: %+v", sshMsg.Error)
	}
	var sshResult conversationListResult
	decodeInto(t, sshMsg.Result, &sshResult)

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsList", map[string]interface{}{"limit": 50})
	if env.Type != "agentConversationsListResult" {
		t.Fatalf("relay type = %q, want agentConversationsListResult", env.Type)
	}
	var relayResult conversationListResult
	decodeInto(t, env.Payload, &relayResult)

	if !reflect.DeepEqual(sshResult, relayResult) {
		t.Fatalf("SSH and relay list results differ:\nSSH:   %+v\nRelay: %+v", sshResult, relayResult)
	}
	if len(sshResult.Conversations) != 1 {
		t.Fatalf("expected 1 conversation, got %d", len(sshResult.Conversations))
	}
}

// TestConversationsFetchSSHAndRelayMatchShape mirrors the list test for
// agent.conversations.fetch / agentConversationsFetch.
func TestConversationsFetchSSHAndRelayMatchShape(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	begin, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first prompt",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	if err := s.conversations.appendRunOutput("run_1", "stdout", "hello", 2); err != nil {
		t.Fatalf("appendRunOutput: %v", err)
	}

	fetchReq := map[string]interface{}{"conversationId": begin.ConversationID, "sinceSeq": 0, "limit": 500}

	sshMsg := callSSHRPC(t, s, "agent.conversations.fetch", fetchReq)
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.fetch error: %+v", sshMsg.Error)
	}
	var sshResult conversationFetchResult
	decodeInto(t, sshMsg.Result, &sshResult)

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsFetch", fetchReq)
	if env.Type != "agentConversationsFetchResult" {
		t.Fatalf("relay type = %q, want agentConversationsFetchResult", env.Type)
	}
	var relayResult conversationFetchResult
	decodeInto(t, env.Payload, &relayResult)

	if !reflect.DeepEqual(sshResult, relayResult) {
		t.Fatalf("SSH and relay fetch results differ:\nSSH:   %+v\nRelay: %+v", sshResult, relayResult)
	}
	if len(sshResult.Turns) != 1 || len(sshResult.Events) != 2 {
		t.Fatalf("unexpected fetch shape: turns=%d events=%d", len(sshResult.Turns), len(sshResult.Events))
	}
}

// TestConversationsAppendSSHAndRelayMatchShape proves append's SSH and relay
// paths agree. It relies on beginTurn's idempotent clientTurnId behavior
// (conversation_store.go) so sending the exact same new-chat request twice —
// once over each transport — deterministically returns the identical
// underlying ledger row rather than two different conversations.
func TestConversationsAppendSSHAndRelayMatchShape(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	appendReq := map[string]interface{}{
		"clientTurnId": "device-1:1",
		"agent":        "claudeCode",
		"cwd":          "/Users/roshan/project",
		"prompt":       "Fix the failing auth test",
		"model":        "sonnet",
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.append", appendReq)
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.append error: %+v", sshMsg.Error)
	}
	var sshResult conversationAppendResponse
	decodeInto(t, sshMsg.Result, &sshResult)

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsAppend", appendReq)
	if env.Type != "agentConversationsAppendResult" {
		t.Fatalf("relay type = %q, want agentConversationsAppendResult", env.Type)
	}
	var relayResult conversationAppendResponse
	decodeInto(t, env.Payload, &relayResult)

	// Same clientTurnId ⇒ beginTurn's idempotent replay ⇒ identical row.
	if !reflect.DeepEqual(sshResult, relayResult) {
		t.Fatalf("SSH and relay append results differ:\nSSH:   %+v\nRelay: %+v", sshResult, relayResult)
	}
	// A fresh, unconfigured test server has no policy file, so the daemon's
	// fail-closed default ("ask" for any real command — see AGENTS.md/
	// go-daemon.md's "policy engine is fail-closed: default = ask") applies to
	// launchConversationTurn's real dispatch just like it would to the plain
	// agent.dispatch RPC. needsApproval is the CORRECT outcome here, not a
	// stub limitation — what actually matters is that both transports agree
	// (asserted above) and that the ledger row was genuinely created once.
	if sshResult.Status != "needsApproval" {
		t.Fatalf("status = %q, want needsApproval (fail-closed default policy on an unconfigured test server)", sshResult.Status)
	}
	if sshResult.ResumeMode != "new" {
		t.Fatalf("resumeMode = %q, want new (fresh conversation)", sshResult.ResumeMode)
	}

	listRes, err := s.conversations.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 1 {
		t.Fatalf("conversations = %d, want 1 (idempotent replay must not duplicate)", len(listRes.Conversations))
	}
}

// TestConversationsAppendFollowUpResumeModeNone verifies a follow-up append
// (existing conversationId) whose conversation has never had a vendor session
// bound to any turn reports resumeMode "latestInCwdFallback" — real dispatch
// runs (Task 3), but with no exact vendor session known yet, it must be
// honest about degraded resume confidence rather than silently claiming
// "exact". It also proves a follow-up correctly inherits the conversation's
// provider when the request omits "agent" (per the RPC contract).
func TestConversationsAppendFollowUpResumeModeNone(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	first, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	followUpReq := map[string]interface{}{
		"conversationId": first.ConversationID,
		"baseSeq":        first.NextSeq,
		"clientTurnId":   "device-1:2",
		"prompt":         "second prompt",
	}
	sshMsg := callSSHRPC(t, s, "agent.conversations.append", followUpReq)
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.append (follow-up) error: %+v", sshMsg.Error)
	}
	var result conversationAppendResponse
	decodeInto(t, sshMsg.Result, &result)

	// Same fail-closed-default reasoning as
	// TestConversationsAppendSSHAndRelayMatchShape — a real dispatch attempt
	// on an unconfigured test server needs approval; that's correct.
	if result.Status != "needsApproval" {
		t.Fatalf("status = %q, want needsApproval (fail-closed default policy on an unconfigured test server)", result.Status)
	}
	if result.ResumeMode != "latestInCwdFallback" {
		t.Fatalf("resumeMode = %q, want latestInCwdFallback (no vendor session bound on this conversation yet)", result.ResumeMode)
	}
	if result.VendorSessionID != "" {
		t.Fatalf("vendorSessionId = %q, want empty (no vendor session was ever bound)", result.VendorSessionID)
	}
}

// TestConversationsAppendConflictSameOnBothPaths proves a stale baseSeq
// produces an identical "conflict" response on both transports.
func TestConversationsAppendConflictSameOnBothPaths(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	first, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	// Bump the conversation to seq 2 out from under a stale baseSeq=1 append.
	if _, err := s.conversations.beginTurn(conversationAppendRequest{
		ConversationID: first.ConversationID,
		BaseSeq:        first.NextSeq,
		ClientTurnID:   "device-1:2",
		Prompt:         "second",
	}, "/proj", "run_2"); err != nil {
		t.Fatalf("beginTurn (second): %v", err)
	}

	staleReq := map[string]interface{}{
		"conversationId": first.ConversationID,
		"baseSeq":        first.NextSeq, // stale: conversation is now at seq 2
		"clientTurnId":   "device-2:1",
		"prompt":         "concurrent conflicting write",
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.append", staleReq)
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.append (conflict) error: %+v", sshMsg.Error)
	}
	var sshResult conversationAppendResponse
	decodeInto(t, sshMsg.Result, &sshResult)

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	// Use a distinct clientTurnId so the relay call is a genuinely separate
	// conflicting append, not an idempotent replay of the SSH one.
	staleReq["clientTurnId"] = "device-3:1"
	env := callRelay(t, router, client, "agentConversationsAppend", staleReq)
	var relayResult conversationAppendResponse
	decodeInto(t, env.Payload, &relayResult)

	if sshResult.Status != "conflict" || relayResult.Status != "conflict" {
		t.Fatalf("expected conflict on both paths, got SSH=%q relay=%q", sshResult.Status, relayResult.Status)
	}
	if sshResult.NextSeq != relayResult.NextSeq {
		t.Fatalf("conflict nextSeq differs: SSH=%d relay=%d", sshResult.NextSeq, relayResult.NextSeq)
	}
	if sshResult.ResumeMode != "" || relayResult.ResumeMode != "" {
		t.Fatalf("expected no resumeMode on a conflict, got SSH=%q relay=%q", sshResult.ResumeMode, relayResult.ResumeMode)
	}
}

// TestConversationsAppendNeedsApprovalUnderDefaultPolicyDoesNotDispatch
// proves the fail-closed path: on a fresh temp-dir server (no policy.yaml,
// and — critically — no PreToolUse hook actually installed for "claude" in
// this home dir), launchConversationTurn's policy gate treats the launch as
// not hook-wired and escalates to needsApproval, so the fake dispatcher.launch
// must never be called. This is NOT proof that agent.conversations.append is
// a dispatch stub — see TestConversationsAppendLaunchesAndBindsSessionUnderAllowPolicy
// for the positive case showing it DOES launch and bind a session once policy
// allows it (Task 3, already implemented in conversationsAppend).
func TestConversationsAppendNeedsApprovalUnderDefaultPolicyDoesNotDispatch(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	launched := false
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.append", map[string]interface{}{
		"clientTurnId": "device-1:1",
		"agent":        "claudeCode",
		"cwd":          "/proj",
		"prompt":       "do not actually run this",
	})
	if sshMsg.Error != nil {
		t.Fatalf("agent.conversations.append error: %+v", sshMsg.Error)
	}
	var result conversationAppendResponse
	decodeInto(t, sshMsg.Result, &result)

	if launched {
		t.Fatal("agent.conversations.append should have been gated to needsApproval under default fail-closed policy, but dispatcher.launch was called")
	}
	s.dispatcher.mu.Lock()
	_, dispatched := s.dispatcher.runs[result.RunID]
	s.dispatcher.mu.Unlock()
	if dispatched {
		t.Fatalf("runID %q must not appear in dispatcher.runs — no process was launched for it", result.RunID)
	}
	if result.RunID == "" {
		t.Fatal("expected a generated runID even though nothing was dispatched")
	}

	// The ledger row must still exist and be readable via fetch.
	fetchRes, err := s.conversations.fetch(result.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 || fetchRes.Turns[0].RunID != result.RunID {
		t.Fatalf("expected the ledger to record the stub runID: %+v", fetchRes.Turns)
	}
}

// TestConversationsAppendLaunchesAndBindsSessionUnderAllowPolicy is the RPC-
// level positive counterpart to the needsApproval test above: with an
// explicit allow policy rule in place, a real agent.conversations.append call
// (through s.handleMessage, exactly like a live SSH client) must launch the
// fake CLI process, capture its emitted vendor session id via
// wrapEmitForRun -> bindVendorSession, and expose it as resumeMode "new" on
// this turn — proving append's dispatch integration (Task 3) end-to-end
// through the actual RPC entrypoint, not just the lower-level dispatcher
// unit tests in dispatch_conversation_test.go.
func TestConversationsAppendLaunchesAndBindsSessionUnderAllowPolicy(t *testing.T) {
	home := t.TempDir()
	globalPath := policy.GlobalPolicyPath(home)
	doc := policy.Document{
		Default: string(policy.EffectAsk),
		Rules: []policy.Rule{
			{ID: "allow-all-commands", Effect: string(policy.EffectAllow), Kind: "command"},
		},
	}
	if err := policy.SaveFile(globalPath, doc); err != nil {
		t.Fatalf("SaveFile policy: %v", err)
	}

	s := newServer(home)
	defer s.poller.stopForTest()

	var launchedArgv []string
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchedArgv = argv
		// Simulate the vendor CLI announcing its session id on first output,
		// exactly like TestLaunchConversationTurnBindsVendorSessionForExactResume.
		emit("agent.run.vendorSession", map[string]any{"runId": runID, "vendorSessionId": "live-sess-rpc-1"})
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.append", map[string]interface{}{
		"clientTurnId": "device-1:1",
		"agent":        "claudeCode",
		"cwd":          "/proj",
		"prompt":       "actually run this",
	})
	if sshMsg.Error != nil {
		t.Fatalf("agent.conversations.append error: %+v", sshMsg.Error)
	}
	var result conversationAppendResponse
	decodeInto(t, sshMsg.Result, &result)

	if result.Status != "started" {
		t.Fatalf("status = %q, want started (%s)", result.Status, result.Message)
	}
	if launchedArgv == nil {
		t.Fatal("expected dispatcher.launch to be called under an allow policy, but it wasn't")
	}
	if result.ResumeMode != "new" {
		t.Fatalf("resumeMode = %q, want new (first turn of a brand-new conversation)", result.ResumeMode)
	}

	s.dispatcher.mu.Lock()
	run, dispatched := s.dispatcher.runs[result.RunID]
	s.dispatcher.mu.Unlock()
	if !dispatched {
		t.Fatalf("runID %q must appear in dispatcher.runs after a real launch", result.RunID)
	}
	if run.Status != "running" {
		t.Fatalf("run.Status = %q, want running", run.Status)
	}

	// The emitted vendor session id must have propagated through
	// wrapEmitForRun into the ledger, so a follow-up append on this same
	// conversation gets exact resume, not latest-in-cwd fallback.
	bound, err := s.conversations.latestVendorSessionID(result.ConversationID)
	if err != nil {
		t.Fatalf("latestVendorSessionID: %v", err)
	}
	if bound != "live-sess-rpc-1" {
		t.Fatalf("bound vendor session = %q, want live-sess-rpc-1", bound)
	}

	followUp := callSSHRPC(t, s, "agent.conversations.append", map[string]interface{}{
		"conversationId": result.ConversationID,
		"baseSeq":        result.NextSeq,
		"clientTurnId":   "device-1:2",
		"prompt":         "follow up",
	})
	if followUp.Error != nil {
		t.Fatalf("follow-up agent.conversations.append error: %+v", followUp.Error)
	}
	var followUpResult conversationAppendResponse
	decodeInto(t, followUp.Result, &followUpResult)
	if followUpResult.Status != "started" {
		t.Fatalf("follow-up status = %q, want started (%s)", followUpResult.Status, followUpResult.Message)
	}
	if followUpResult.ResumeMode != "exact" || followUpResult.VendorSessionID != "live-sess-rpc-1" {
		t.Fatalf("follow-up resumeMode=%q vendorSessionId=%q, want exact/live-sess-rpc-1", followUpResult.ResumeMode, followUpResult.VendorSessionID)
	}
}

// TestConversationsAppendDecodesAndThreadsContract is the RPC-level proof for
// PR #34 review finding P1: the iOS composer sends a `contract` field on
// agent.conversations.append (ConversationAppendRequest.contract,
// LancerDProtocol.swift:912) for both a brand-new conversation and a
// follow-up — this drives the wire path exactly like a live SSH client would
// (raw JSON through s.handleMessage, not a Go struct literal) to prove the
// daemon actually DECODES the "contract" key (conversationAppendRequest.Contract,
// conversation_store.go) and that launchConversationTurn's synthetic
// dispatchParams carries it into the terminal receipt — not just that the Go
// struct field exists.
func TestConversationsAppendDecodesAndThreadsContract(t *testing.T) {
	home := t.TempDir()
	globalPath := policy.GlobalPolicyPath(home)
	doc := policy.Document{
		Default: string(policy.EffectAsk),
		Rules: []policy.Rule{
			{ID: "allow-all-commands", Effect: string(policy.EffectAllow), Kind: "command"},
		},
	}
	if err := policy.SaveFile(globalPath, doc); err != nil {
		t.Fatalf("SaveFile policy: %v", err)
	}

	s := newServer(home)
	defer s.poller.stopForTest()

	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		go emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	// Raw map (not a conversationAppendRequest{} literal) — this round-trips
	// through encoding/json exactly the way the wire bytes from an iOS client
	// would, so a mistyped/missing json tag on the Go struct would fail this
	// test the same way it fails a real device.
	sshMsg := callSSHRPC(t, s, "agent.conversations.append", map[string]interface{}{
		"clientTurnId": "device-1:1",
		"agent":        "claudeCode",
		"cwd":          "/proj",
		"prompt":       "add the contract",
		"contract": map[string]interface{}{
			"goal":               "thread the contract end to end",
			"doneCriteria":       []string{"contract shows up on the receipt"},
			"validationCommands": []string{"go test ./..."},
		},
	})
	if sshMsg.Error != nil {
		t.Fatalf("agent.conversations.append error: %+v", sshMsg.Error)
	}
	var result conversationAppendResponse
	decodeInto(t, sshMsg.Result, &result)
	if result.Status != "started" {
		t.Fatalf("status = %q, want started (%s)", result.Status, result.Message)
	}

	deadline := time.After(2 * time.Second)
	var receipt *runReceipt
	for receipt == nil {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for receipt")
		default:
			receipt = s.dispatcher.getReceipt(result.RunID)
			if receipt == nil {
				time.Sleep(10 * time.Millisecond)
			}
		}
	}
	if receipt.Contract == nil {
		t.Fatal("expected the wire-decoded contract on the receipt")
	}
	if receipt.Contract.Goal != "thread the contract end to end" {
		t.Fatalf("receipt goal = %q, want %q", receipt.Contract.Goal, "thread the contract end to end")
	}
	if !reflect.DeepEqual(receipt.Contract.DoneCriteria, []string{"contract shows up on the receipt"}) {
		t.Fatalf("receipt doneCriteria = %v", receipt.Contract.DoneCriteria)
	}

	// Oversized contract on the SAME RPC path must be rejected before launch,
	// not truncated or silently dropped.
	launched := false
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	criteria := make([]string, contractMaxDoneCriteria+1)
	for i := range criteria {
		criteria[i] = "ok"
	}
	oversizedMsg := callSSHRPC(t, s, "agent.conversations.append", map[string]interface{}{
		"clientTurnId": "device-1:2",
		"agent":        "claudeCode",
		"cwd":          "/proj",
		"prompt":       "oversized contract",
		"contract": map[string]interface{}{
			"goal":         "x",
			"doneCriteria": criteria,
		},
	})
	if oversizedMsg.Error != nil {
		t.Fatalf("agent.conversations.append (oversized) error: %+v", oversizedMsg.Error)
	}
	var oversizedResult conversationAppendResponse
	decodeInto(t, oversizedMsg.Result, &oversizedResult)
	if oversizedResult.Status != "error" || oversizedResult.Message != "contract too large" {
		t.Fatalf("oversized contract result = %+v, want error/contract too large", oversizedResult)
	}
	if launched {
		t.Fatal("dispatcher.launch must not be called for an oversized contract")
	}
}

// TestConversationsArchiveSSHAndRelayMatchShape verifies the archive RPC on
// two structurally identical fresh conversations (one archived via SSH, one
// via relay) produce the same-shaped response modulo the (expectedly
// different) conversationId.
func TestConversationsArchiveSSHAndRelayMatchShape(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	convA, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1", Agent: "claudeCode", Prompt: "a",
	}, "/proj-a", "run_a")
	if err != nil {
		t.Fatalf("beginTurn a: %v", err)
	}
	convB, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:2", Agent: "claudeCode", Prompt: "b",
	}, "/proj-b", "run_b")
	if err != nil {
		t.Fatalf("beginTurn b: %v", err)
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.archive", map[string]interface{}{
		"conversationId": convA.ConversationID, "archived": true,
	})
	if sshMsg.Error != nil {
		t.Fatalf("SSH agent.conversations.archive error: %+v", sshMsg.Error)
	}
	var sshResult conversationArchiveResponse
	decodeInto(t, sshMsg.Result, &sshResult)

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsArchive", map[string]interface{}{
		"conversationId": convB.ConversationID, "archived": true,
	})
	var relayResult conversationArchiveResponse
	decodeInto(t, env.Payload, &relayResult)

	if sshResult.OK != true || relayResult.OK != true {
		t.Fatalf("expected ok=true on both paths, got SSH=%v relay=%v", sshResult.OK, relayResult.OK)
	}
	if sshResult.LastSeq != relayResult.LastSeq {
		t.Fatalf("lastSeq shape differs: SSH=%d relay=%d (both conversations started identical, should match)",
			sshResult.LastSeq, relayResult.LastSeq)
	}
	if sshResult.ConversationID != convA.ConversationID || relayResult.ConversationID != convB.ConversationID {
		t.Fatalf("archive responses did not echo the requested conversationId back: SSH=%+v relay=%+v", sshResult, relayResult)
	}

	// Verify persistence: fetch shows archivedAt set (via list includeArchived).
	listRes, err := s.conversations.list(50, "", true)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	found := false
	for _, c := range listRes.Conversations {
		if c.ID == convA.ConversationID {
			found = true
			if c.ArchivedAt == "" {
				t.Error("expected archivedAt to be set after archive")
			}
		}
	}
	if !found {
		t.Fatal("archived conversation missing from list(includeArchived=true)")
	}
}

// TestConversationsArchiveUnknownConversationErrorsSameOnBothPaths verifies
// an unknown conversationId surfaces as an error consistently on both
// transports (SSH JSON-RPC error vs. relay payload "error" field — the
// existing asymmetry already used by agentFsList/agentFsRead).
func TestConversationsArchiveUnknownConversationErrorsSameOnBothPaths(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	sshMsg := callSSHRPC(t, s, "agent.conversations.archive", map[string]interface{}{
		"conversationId": "conv_does_not_exist", "archived": true,
	})
	if sshMsg.Error == nil {
		t.Fatal("expected SSH error for unknown conversationId, got none")
	}

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsArchive", map[string]interface{}{
		"conversationId": "conv_does_not_exist", "archived": true,
	})
	var payloadMap map[string]interface{}
	if err := json.Unmarshal(env.Payload, &payloadMap); err != nil {
		t.Fatalf("unmarshal relay payload: %v", err)
	}
	if _, hasErr := payloadMap["error"]; !hasErr {
		t.Fatalf("expected relay payload to carry an error field, got %+v", payloadMap)
	}
}

// TestConversationsAttachObservedSessionUnknownSessionErrorsIdentically
// verifies agent.conversations.attachObservedSession surfaces an unknown
// on-disk session as a clear error — never a fabricated success — identically
// on both transports. (The RPC layer always re-reads the transcript from
// disk rather than trusting caller-supplied content — see
// conversation_rpc.go's Task 9 note — so an unfixtured sessionId in these
// process-wide ~/.claude/projects-rooted tests is exactly the "not found"
// path; conversation_store_test.go covers the real-import/idempotency
// behavior directly against the store, independent of on-disk transcripts.)
func TestConversationsAttachObservedSessionUnknownSessionErrorsIdentically(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	req := map[string]interface{}{
		"provider":  "claudeCode",
		"sessionId": "vendor-session-does-not-exist",
		"cwd":       "/Users/roshan/project",
	}

	sshMsg := callSSHRPC(t, s, "agent.conversations.attachObservedSession", req)
	if sshMsg.Error == nil {
		t.Fatal("expected SSH error for an unknown sessionId, got a success result")
	}

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, s)
	router.client = client
	env := callRelay(t, router, client, "agentConversationsAttachObservedSession", req)
	if env.Type != "agentConversationsAttachObservedSessionResult" {
		t.Fatalf("relay type = %q, want agentConversationsAttachObservedSessionResult", env.Type)
	}
	var payloadMap map[string]interface{}
	if err := json.Unmarshal(env.Payload, &payloadMap); err != nil {
		t.Fatalf("unmarshal relay payload: %v", err)
	}
	relayErr, hasErr := payloadMap["error"]
	if !hasErr {
		t.Fatalf("expected relay payload to carry an error field, got %+v", payloadMap)
	}

	if sshMsg.Error.Message != relayErr {
		t.Fatalf("SSH and relay error messages differ: SSH=%q relay=%q", sshMsg.Error.Message, relayErr)
	}
	if importedEvents, ok := payloadMap["importedEvents"]; ok {
		if importedEvents != float64(0) {
			t.Fatalf("expected importedEvents=0 in the error payload, got %v", importedEvents)
		}
	}

	// Missing required fields must also error, not silently succeed.
	if _, err := s.conversationsAttachObservedSession(conversationAttachObservedSessionRequest{}); err == nil {
		t.Fatal("expected an error for an empty attachObservedSession request")
	}
}

// TestConversationsRPCsErrorWhenStoreUnavailable verifies every conversation
// RPC method degrades to a clear error (not a panic) when s.conversations is
// nil — the openConversationStore-failed-at-startup path in newServer.
func TestConversationsRPCsErrorWhenStoreUnavailable(t *testing.T) {
	s := &server{}

	if _, err := s.conversationsList(conversationListRequest{}); err == nil {
		t.Error("conversationsList: expected error with nil store")
	}
	if _, err := s.conversationsFetch(conversationFetchRequest{ConversationID: "x"}); err == nil {
		t.Error("conversationsFetch: expected error with nil store")
	}
	if _, err := s.conversationsAppend(conversationAppendRequest{ClientTurnID: "x", Prompt: "x"}); err == nil {
		t.Error("conversationsAppend: expected error with nil store")
	}
	if _, err := s.conversationsArchive(conversationArchiveRequest{ConversationID: "x"}); err == nil {
		t.Error("conversationsArchive: expected error with nil store")
	}
}
