package main

import (
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

// --- buildConversationArgv -------------------------------------------------

func TestBuildConversationArgvNewUsesAgentArgv(t *testing.T) {
	argv, resumeMode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "hi", IsNew: true,
	})
	if !ok {
		t.Fatal("ok = false, want true")
	}
	if resumeMode != "new" {
		t.Fatalf("resumeMode = %q, want new", resumeMode)
	}
	want, _ := agentArgv("claudeCode", "hi", "")
	if strings.Join(argv, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %v, want %v (agentArgv)", argv, want)
	}
}

func TestBuildConversationArgvFollowUpWithVendorSessionUsesResumeArgvExact(t *testing.T) {
	argv, resumeMode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", VendorSessionID: "sess-abc-123", IsNew: false,
	})
	if !ok {
		t.Fatal("ok = false, want true")
	}
	if resumeMode != "exact" {
		t.Fatalf("resumeMode = %q, want exact", resumeMode)
	}
	want, _ := resumeArgv("claudeCode", "sess-abc-123", "next", "")
	if strings.Join(argv, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %v, want %v (resumeArgv with exact session)", argv, want)
	}
	found := false
	for _, a := range argv {
		if a == "sess-abc-123" {
			found = true
		}
	}
	if !found {
		t.Fatalf("argv %v does not contain the exact vendor session id", argv)
	}
}

func TestBuildConversationArgvFollowUpWithNoVendorSessionFallsBackToContinueArgv(t *testing.T) {
	argv, resumeMode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", VendorSessionID: "", IsNew: false,
	})
	if !ok {
		t.Fatal("ok = false, want true")
	}
	if resumeMode != "latestInCwdFallback" {
		t.Fatalf("resumeMode = %q, want latestInCwdFallback", resumeMode)
	}
	want, _ := continueArgv("claudeCode", "next", "")
	if strings.Join(argv, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %v, want %v (continueArgv fallback)", argv, want)
	}
}

func TestBuildConversationArgvUnknownAgentReturnsNotOK(t *testing.T) {
	_, _, ok := buildConversationArgv(conversationLaunchParams{Agent: "not-a-real-agent", Prompt: "hi", IsNew: true})
	if ok {
		t.Fatal("ok = true, want false for an unknown agent")
	}
}

// --- vendor session capture from structured stdout (streamJSONOutput) -----

// captureVendorSession runs streamJSONOutput over a single JSON line and
// returns the vendorSessionId argument of the "agent.run.vendorSession" call
// it made, or "" if it never fired one. This exercises the SAME parsing path
// dispatch.go uses on real vendor CLI stdout — the fixture lines below are
// copies of shapes verified live during this task against each vendor's
// installed CLI (see the per-vendor comments in streamJSONOutput itself).
func captureVendorSession(t *testing.T, line string) string {
	t.Helper()
	var captured string
	emit := func(method string, params any) {
		if method != "agent.run.vendorSession" {
			return
		}
		if m, ok := params.(map[string]any); ok {
			if v, ok := m["vendorSessionId"].(string); ok {
				captured = v
			}
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-1", strings.NewReader(line+"\n"), &seq, &wg)
	wg.Wait()
	return captured
}

func TestStreamJSONOutputCapturesClaudeSessionID(t *testing.T) {
	// Claude: {"type":"system","subtype":"init","session_id":"..."} — verified
	// live 2026-07-02 against claude 2.1.198 (see streamJSONOutput's "system" case).
	got := captureVendorSession(t, `{"type":"system","subtype":"init","session_id":"claude-sess-xyz"}`)
	if got != "claude-sess-xyz" {
		t.Fatalf("captured vendor session = %q, want claude-sess-xyz", got)
	}
}

func TestStreamJSONOutputCapturesCodexThreadID(t *testing.T) {
	// Codex: {"type":"thread.started","thread_id":"..."} — verified live
	// 2026-07-02 against codex-cli 0.135.0.
	got := captureVendorSession(t, `{"type":"thread.started","thread_id":"codex-thread-789"}`)
	if got != "codex-thread-789" {
		t.Fatalf("captured vendor session = %q, want codex-thread-789", got)
	}
}

func TestStreamJSONOutputCapturesOpenCodeSessionID(t *testing.T) {
	// OpenCode: top-level "sessionID" on every event — verified live
	// 2026-07-02 against opencode 1.17.11.
	got := captureVendorSession(t, `{"type":"step_start","sessionID":"oc-session-456"}`)
	if got != "oc-session-456" {
		t.Fatalf("captured vendor session = %q, want oc-session-456", got)
	}
}

func TestStreamJSONOutputCapturesOnlyFirstSessionIDPerRun(t *testing.T) {
	// sessionCaptured latches after the first hit — a later line with a
	// DIFFERENT id must not override the first one already emitted.
	var calls []string
	emit := func(method string, params any) {
		if method != "agent.run.vendorSession" {
			return
		}
		if m, ok := params.(map[string]any); ok {
			if v, ok := m["vendorSessionId"].(string); ok {
				calls = append(calls, v)
			}
		}
	}
	lines := strings.Join([]string{
		`{"type":"system","subtype":"init","session_id":"first-id"}`,
		`{"type":"system","subtype":"init","session_id":"second-id"}`,
	}, "\n")
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-1", strings.NewReader(lines+"\n"), &seq, &wg)
	wg.Wait()
	if len(calls) != 1 {
		t.Fatalf("vendorSession emitted %d times, want exactly 1 (calls=%v)", len(calls), calls)
	}
	if calls[0] != "first-id" {
		t.Fatalf("captured %q, want first-id (first-available wins)", calls[0])
	}
}

// --- end-to-end: launchConversationTurn binds a session, next turn resumes exact ---

// TestLaunchConversationTurnBindsVendorSessionForExactResume proves the full
// loop this task exists for: turn 1's fake CLI process emits a vendor session
// id, wrapEmitForRun persists it via conversationStore.bindVendorSession, and
// a SECOND append on the same conversation — reading that bound id back via
// conversationStore.latestVendorSessionID, exactly like conversationsAppend
// does — selects resumeArgv with that EXACT session id, not continueArgv.
func TestLaunchConversationTurnBindsVendorSessionForExactResume(t *testing.T) {
	home := t.TempDir()
	store, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}

	d := newDispatcher()
	d.bindVendorSession = store.bindVendorSession

	var lastArgv []string
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		lastArgv = argv
		// Simulate the vendor CLI's first structured stdout line announcing
		// its session id — exactly what streamJSONOutput would extract and
		// forward via emitVendorSession in a real launch.
		emit("agent.run.vendorSession", map[string]any{"runId": runID, "vendorSessionId": "live-sess-1"})
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	// Turn 1: new conversation.
	first, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1", Agent: "claudeCode", Prompt: "first", CWD: "/proj",
	}, "/proj", "run-1")
	if err != nil {
		t.Fatalf("beginTurn (first): %v", err)
	}
	res1 := d.launchConversationTurn("run-1", conversationLaunchParams{
		Agent: "claudeCode", CWD: "/proj", Prompt: "first", IsNew: true,
	}, allowEval, noAudit)
	if res1.Status != "started" {
		t.Fatalf("turn 1 status = %q, want started (%s)", res1.Status, res1.Message)
	}

	// The fake launch's emit call must have propagated through wrapEmitForRun
	// into the ledger via bindVendorSession.
	bound, err := store.latestVendorSessionID(first.ConversationID)
	if err != nil {
		t.Fatalf("latestVendorSessionID: %v", err)
	}
	if bound != "live-sess-1" {
		t.Fatalf("bound vendor session = %q, want live-sess-1 (wrapEmitForRun -> bindVendorSession did not persist it)", bound)
	}

	// Turn 2: follow-up on the SAME conversation. Reading the bound session
	// (as conversationsAppend does) and passing it in must select resumeArgv
	// with that EXACT id, not continueArgv.
	second, err := store.beginTurn(conversationAppendRequest{
		ConversationID: first.ConversationID, BaseSeq: first.NextSeq,
		ClientTurnID: "device-1:2", Prompt: "second",
	}, "/proj", "run-2")
	if err != nil {
		t.Fatalf("beginTurn (second): %v", err)
	}
	res2 := d.launchConversationTurn("run-2", conversationLaunchParams{
		Agent: "claudeCode", CWD: "/proj", Prompt: "second", VendorSessionID: bound, IsNew: false,
	}, allowEval, noAudit)
	if res2.Status != "started" {
		t.Fatalf("turn 2 status = %q, want started (%s)", res2.Status, res2.Message)
	}
	if second.Status != "started" {
		t.Fatalf("beginTurn (second) status = %q, want started", second.Status)
	}

	want, _ := resumeArgv("claudeCode", "live-sess-1", "second", "")
	if strings.Join(lastArgv, " ") != strings.Join(want, " ") {
		t.Fatalf("turn 2 argv = %v, want %v (exact resume with the bound session id)", lastArgv, want)
	}
}

// --- contract threading (PR #34 review finding P1) -------------------------
//
// TestLaunchConversationTurnThreadsContract proves launchConversationTurn no
// longer drops conversationLaunchParams.Contract on the floor: it must land
// on both the in-memory run record (mirroring dispatch()'s own
// d.runs[id].Contract assignment — see TestDispatchContract) and, more
// importantly, on the accumulated receipt startReceiptAccum feeds — the
// symptom the review finding actually cared about, since a lost contract
// meant every agent.conversations.append-dispatched run's receipt card could
// never evaluate doneCriteria.
func TestLaunchConversationTurnThreadsContract(t *testing.T) {
	valid := &runContract{
		Goal:               "thread the contract through conversation append",
		DoneCriteria:       []string{"receipt echoes the contract verbatim"},
		ValidationCommands: []string{"go test ./..."},
	}

	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		go emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
		return &procHandle{kill: func() {}}, nil
	}

	res := d.launchConversationTurn("conversation-run-contract", conversationLaunchParams{
		Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", Model: "sonnet", IsNew: true, Contract: valid,
	}, allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("launchConversationTurn status = %q, want started (%s)", res.Status, res.Message)
	}

	run := d.runs[res.RunID]
	if run == nil || run.Contract == nil {
		t.Fatal("expected contract on conversation-launched run record")
	}
	if run.Contract.Goal != valid.Goal {
		t.Fatalf("run contract goal = %q, want %q", run.Contract.Goal, valid.Goal)
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
		t.Fatal("expected contract on conversation-launched run's receipt")
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
}

// TestLaunchConversationTurnRejectsOversizedContract proves
// launchConversationTurn rejects an oversized contract BEFORE launch — same
// cap, same error shape, same contractTooLarge/cloneRunContract helpers
// dispatch() itself uses (see TestDispatchContract's "too many done criteria"
// case) — rather than silently truncating or launching anyway.
func TestLaunchConversationTurnRejectsOversizedContract(t *testing.T) {
	criteria := make([]string, contractMaxDoneCriteria+1)
	for i := range criteria {
		criteria[i] = "ok"
	}

	d := newDispatcher()
	launched := false
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launched = true
		return &procHandle{kill: func() {}}, nil
	}

	res := d.launchConversationTurn("conversation-run-oversized", conversationLaunchParams{
		Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", IsNew: true,
		Contract: &runContract{Goal: "x", DoneCriteria: criteria},
	}, allowEval, noAudit)

	if res.Status != "error" || res.Message != "contract too large" {
		t.Fatalf("launchConversationTurn = %+v, want error contract too large", res)
	}
	if launched {
		t.Fatal("dispatcher.launch must not be called for an oversized contract")
	}
	if _, ok := d.runs["conversation-run-oversized"]; ok {
		t.Fatal("no run record should be created for a rejected oversized contract")
	}
}
