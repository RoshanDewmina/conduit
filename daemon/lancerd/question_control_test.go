// Package main tests for M3 (2026-07-10): the live bidirectional
// control_request/control_response protocol that lets an AskUserQuestion
// answer resume the SAME claudeCode run — see agentArgv's doc comment
// (dispatch.go) and registerAndWaitForQuestion's doc comment (question.go).
//
// Named question_control_test.go (not control_test.go) deliberately —
// control_test.go/control.go already own an unrelated domain (the
// LancerMac local IPC control socket: hello handshake, peer-uid auth).
package main

import (
	"encoding/json"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

// --- claudeStdinPromptArgv --------------------------------------------------

func TestClaudeStdinPromptArgvSplitsTrailingPrompt(t *testing.T) {
	argv, _ := agentArgv("claudeCode", "hello there", "")
	execArgv, prompt, ok := claudeStdinPromptArgv(argv)
	if !ok {
		t.Fatalf("claudeStdinPromptArgv should recognize a claudeCode agentArgv build, got ok=false for %v", argv)
	}
	if prompt != "hello there" {
		t.Fatalf("prompt = %q, want %q", prompt, "hello there")
	}
	wantExec := []string{"claude", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "-p"}
	if !reflect.DeepEqual(execArgv, wantExec) {
		t.Fatalf("execArgv mismatch:\n got %v\nwant %v", execArgv, wantExec)
	}
	// The original argv (with the prompt still positional) must be untouched —
	// dispatch()/continueRun()/resumeRun() build their audit "command" string
	// from it.
	if argv[len(argv)-1] != "hello there" {
		t.Fatalf("claudeStdinPromptArgv must not mutate its input argv, got %v", argv)
	}
}

func TestClaudeStdinPromptArgvAppliesToContinueAndResume(t *testing.T) {
	cont, _ := continueArgv("claudeCode", "next", "")
	if _, _, ok := claudeStdinPromptArgv(cont); !ok {
		t.Fatalf("claudeStdinPromptArgv should recognize continueArgv's claudeCode build: %v", cont)
	}
	res, _ := resumeArgv("claudeCode", "sess-1", "next", "")
	if _, _, ok := claudeStdinPromptArgv(res); !ok {
		t.Fatalf("claudeStdinPromptArgv should recognize resumeArgv's claudeCode build: %v", res)
	}
}

func TestClaudeStdinPromptArgvRejectsOtherVendors(t *testing.T) {
	for _, agent := range []string{"codex", "kimi", "opencode"} {
		argv, ok := agentArgv(agent, "hello", "")
		if !ok {
			t.Fatalf("agentArgv(%q) should be supported", agent)
		}
		if _, _, ok := claudeStdinPromptArgv(argv); ok {
			t.Fatalf("claudeStdinPromptArgv must reject a non-claudeCode argv, got ok=true for %v", argv)
		}
	}
}

func TestClaudeStdinPromptArgvRejectsWithoutStreamInputOrEmptyPrompt(t *testing.T) {
	noStreamInput := []string{"claude", "--output-format", "stream-json", "--verbose", "-p", "hi"}
	if _, _, ok := claudeStdinPromptArgv(noStreamInput); ok {
		t.Fatalf("must reject an argv without --input-format stream-json: %v", noStreamInput)
	}
	emptyPrompt := []string{"claude", "--input-format", "stream-json", "--output-format", "stream-json", "-p", ""}
	if _, _, ok := claudeStdinPromptArgv(emptyPrompt); ok {
		t.Fatalf("must reject an empty positional prompt: %v", emptyPrompt)
	}
	tooShort := []string{"claude", "-p"}
	if _, _, ok := claudeStdinPromptArgv(tooShort); ok {
		t.Fatalf("must reject a too-short argv: %v", tooShort)
	}
}

// --- buildControlAnswers ----------------------------------------------------

func TestBuildControlAnswersSingleSelect(t *testing.T) {
	event := QuestionEvent{Questions: []QuestionItem{{Question: "Pick a color"}}}
	answer := QuestionAnswer{Items: []QuestionItemAnswer{{SelectedLabels: []string{"Red"}}}}
	got := buildControlAnswers(event, answer)
	want := map[string]any{"Pick a color": "Red"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("single-select answers = %+v, want %+v", got, want)
	}
}

func TestBuildControlAnswersMultiSelect(t *testing.T) {
	event := QuestionEvent{Questions: []QuestionItem{{Question: "Toppings?", MultiSelect: true}}}
	answer := QuestionAnswer{Items: []QuestionItemAnswer{{SelectedLabels: []string{"Cheese", "Mushroom"}}}}
	got := buildControlAnswers(event, answer)
	want := map[string]any{"Toppings?": []string{"Cheese", "Mushroom"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("multi-select answers = %+v, want %+v", got, want)
	}
}

func TestBuildControlAnswersFreeText(t *testing.T) {
	event := QuestionEvent{Questions: []QuestionItem{{Question: "Anything else?"}}}
	answer := QuestionAnswer{Items: []QuestionItemAnswer{{FreeText: "yes, use dark mode"}}}
	got := buildControlAnswers(event, answer)
	want := map[string]any{"Anything else?": "yes, use dark mode"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("free-text answers = %+v, want %+v", got, want)
	}
}

func TestBuildControlAnswersMultiQuestionAlignsByIndex(t *testing.T) {
	event := QuestionEvent{Questions: []QuestionItem{{Question: "Q1"}, {Question: "Q2"}}}
	answer := QuestionAnswer{Items: []QuestionItemAnswer{
		{SelectedLabels: []string{"A"}},
		{FreeText: "B"},
	}}
	got := buildControlAnswers(event, answer)
	want := map[string]any{"Q1": "A", "Q2": "B"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("multi-question answers = %+v, want %+v", got, want)
	}
}

// --- control_response wire shape (verified live 2026-07-10) ----------------

func TestAllowControlResponseWireShape(t *testing.T) {
	payload := allowControlResponse("req-1", map[string]any{
		"questions": []any{"orig"},
		"answers":   map[string]any{"Q": "A"},
	})
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if decoded["type"] != "control_response" {
		t.Fatalf("type = %v, want control_response", decoded["type"])
	}
	resp, _ := decoded["response"].(map[string]any)
	if resp == nil || resp["subtype"] != "success" || resp["request_id"] != "req-1" {
		t.Fatalf("response envelope mismatch: %+v", resp)
	}
	inner, _ := resp["response"].(map[string]any)
	if inner == nil || inner["behavior"] != "allow" {
		t.Fatalf("inner response mismatch: %+v", inner)
	}
	if _, hasMessage := inner["message"]; hasMessage {
		t.Fatalf("allow response must omit an empty message field, got %+v", inner)
	}
	updated, _ := inner["updatedInput"].(map[string]any)
	if updated == nil || updated["answers"] == nil {
		t.Fatalf("updatedInput.answers missing: %+v", inner)
	}
}

func TestDenyControlResponseWireShape(t *testing.T) {
	payload := denyControlResponse("req-2", "user declined")
	raw, _ := json.Marshal(payload)
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	resp := decoded["response"].(map[string]any)
	inner := resp["response"].(map[string]any)
	if inner["behavior"] != "deny" || inner["message"] != "user declined" {
		t.Fatalf("deny response mismatch: %+v", inner)
	}
	if _, hasUpdatedInput := inner["updatedInput"]; hasUpdatedInput {
		t.Fatalf("deny response must omit updatedInput, got %+v", inner)
	}
}

// --- dispatcher.handleControlRequest ---------------------------------------

// fakeControlWriter captures every payload handleControlRequest writes so
// tests can assert on the exact bytes without a real process.
type fakeControlWriter struct {
	mu       sync.Mutex
	payloads [][]byte
}

func (f *fakeControlWriter) write(payload []byte) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.payloads = append(f.payloads, payload)
	return nil
}

func (f *fakeControlWriter) last(t *testing.T) map[string]any {
	t.Helper()
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.payloads) == 0 {
		t.Fatalf("no control_response was written")
	}
	var decoded map[string]any
	if err := json.Unmarshal(f.payloads[len(f.payloads)-1], &decoded); err != nil {
		t.Fatalf("unmarshal written payload: %v", err)
	}
	return decoded
}

func newRunWithFakeControlWriter(d *dispatcher, runID string) *fakeControlWriter {
	w := &fakeControlWriter{}
	d.runs[runID] = &dispatchRun{
		ID:    runID,
		Agent: "claudeCode",
		handle: &procHandle{
			writeControlResponse: w.write,
		},
	}
	return w
}

func behaviorOf(t *testing.T, decoded map[string]any) (behavior string, inner map[string]any) {
	t.Helper()
	resp, _ := decoded["response"].(map[string]any)
	inner, _ = resp["response"].(map[string]any)
	if inner == nil {
		t.Fatalf("malformed control_response: %+v", decoded)
	}
	behavior, _ = inner["behavior"].(string)
	return behavior, inner
}

func TestHandleControlRequestAllowsWithStagedAnswer(t *testing.T) {
	d := newDispatcher()
	w := newRunWithFakeControlWriter(d, "run-1")
	d.stashControlAnswer("run-1", "toolu_1", controlAnswer{
		allow:   true,
		answers: map[string]any{"Pick a color": "Red"},
	})

	d.handleControlRequest("run-1", "req-1", "AskUserQuestion", "toolu_1", map[string]any{
		"questions": []any{map[string]any{"question": "Pick a color"}},
	})

	behavior, inner := behaviorOf(t, w.last(t))
	if behavior != "allow" {
		t.Fatalf("behavior = %q, want allow", behavior)
	}
	updated, _ := inner["updatedInput"].(map[string]any)
	if updated == nil {
		t.Fatalf("updatedInput missing: %+v", inner)
	}
	if _, hasQuestions := updated["questions"]; !hasQuestions {
		t.Fatalf("updatedInput must echo the original questions field, got %+v", updated)
	}
	answers, _ := updated["answers"].(map[string]any)
	if answers["Pick a color"] != "Red" {
		t.Fatalf("updatedInput.answers mismatch: %+v", updated)
	}

	// The staged answer is consumed exactly once.
	if _, ok := d.takeControlAnswer("run-1", "toolu_1"); ok {
		t.Fatalf("handleControlRequest must consume (delete) the staged answer")
	}
}

func TestHandleControlRequestDeniesOnTimeoutStash(t *testing.T) {
	d := newDispatcher()
	w := newRunWithFakeControlWriter(d, "run-2")
	d.stashControlAnswer("run-2", "toolu_2", controlAnswer{
		allow:   false,
		message: "No human answer arrived within the wait window.",
	})

	d.handleControlRequest("run-2", "req-2", "AskUserQuestion", "toolu_2", map[string]any{})

	behavior, inner := behaviorOf(t, w.last(t))
	if behavior != "deny" {
		t.Fatalf("behavior = %q, want deny", behavior)
	}
	if inner["message"] != "No human answer arrived within the wait window." {
		t.Fatalf("deny message mismatch: %+v", inner)
	}
}

func TestHandleControlRequestDeniesWhenNoAnswerStaged(t *testing.T) {
	d := newDispatcher()
	var audited []AuditEntry
	d.audit = func(e AuditEntry) { audited = append(audited, e) }
	w := newRunWithFakeControlWriter(d, "run-3")

	d.handleControlRequest("run-3", "req-3", "AskUserQuestion", "toolu-never-staged", map[string]any{})

	behavior, _ := behaviorOf(t, w.last(t))
	if behavior != "deny" {
		t.Fatalf("behavior = %q, want deny when nothing was staged", behavior)
	}
	if len(audited) != 1 || audited[0].Action != "control-request-unresolved" {
		t.Fatalf("expected a control-request-unresolved audit entry, got %+v", audited)
	}
}

// TestHandleControlRequestDeniesNonQuestionToolAlways proves the fail-closed
// scope boundary: ANY tool name other than a recognized question tool is
// denied unconditionally, even if (implausibly) something staged an
// "allow" answer under that tool_use_id — ordinary tool approvals must go
// through Lancer's PreToolUse hook, never through this control channel.
func TestHandleControlRequestDeniesNonQuestionToolAlways(t *testing.T) {
	d := newDispatcher()
	var audited []AuditEntry
	d.audit = func(e AuditEntry) { audited = append(audited, e) }
	w := newRunWithFakeControlWriter(d, "run-4")
	d.stashControlAnswer("run-4", "toolu_bash", controlAnswer{allow: true, answers: map[string]any{"x": "y"}})

	d.handleControlRequest("run-4", "req-4", "Bash", "toolu_bash", map[string]any{"command": "rm -rf /"})

	behavior, _ := behaviorOf(t, w.last(t))
	if behavior != "deny" {
		t.Fatalf("behavior = %q, want deny for a non-question tool", behavior)
	}
	if len(audited) != 1 || audited[0].Action != "control-request-denied-unexpected-tool" {
		t.Fatalf("expected a control-request-denied-unexpected-tool audit entry, got %+v", audited)
	}
	// The stashed (misdirected) answer must be left untouched, not silently consumed.
	if _, ok := d.takeControlAnswer("run-4", "toolu_bash"); !ok {
		t.Fatalf("a non-question control_request must not consume an unrelated staged answer")
	}
}

func TestHandleControlRequestNoOpWithoutLiveWriter(t *testing.T) {
	d := newDispatcher()
	d.runs["run-5"] = &dispatchRun{ID: "run-5", Agent: "claudeCode"} // no handle at all
	// Must not panic when the run has no procHandle (e.g. a test double
	// launcher, or e2eFakeRelayLaunch, that never sets writeControlResponse).
	d.handleControlRequest("run-5", "req-5", "AskUserQuestion", "toolu_5", map[string]any{})
}

// --- registerAndWaitForQuestion staging (question.go) -----------------------

func TestRegisterAndWaitForQuestionStashesControlAnswerOnAnswer(t *testing.T) {
	withStateDir(t)
	s := newServer(serverHome())
	s.dispatcher.runs["run-stash-1"] = &dispatchRun{ID: "run-stash-1", Agent: "claudeCode"}
	event := QuestionEvent{
		QuestionID: "q-stash-1",
		RunID:      "run-stash-1",
		ToolUseID:  "toolu_stash_1",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Continue?", Options: []QuestionOption{{Label: "Yes"}, {Label: "No"}}}},
		Confidence: "complete",
	}

	done := make(chan struct{})
	go func() {
		s.registerAndWaitForQuestion(event)
		close(done)
	}()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(s.questions.pendingEvents()) != 1 {
		time.Sleep(5 * time.Millisecond)
	}
	if _, ok := s.applyQuestionAnswer(QuestionAnswer{QuestionID: "q-stash-1", Items: []QuestionItemAnswer{{SelectedLabels: []string{"Yes"}}}}); !ok {
		t.Fatalf("applyQuestionAnswer should resolve the pending question")
	}
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("registerAndWaitForQuestion did not unblock")
	}

	ca, ok := s.dispatcher.takeControlAnswer("run-stash-1", "toolu_stash_1")
	if !ok {
		t.Fatalf("registerAndWaitForQuestion must stash a control answer on success")
	}
	if !ca.allow {
		t.Fatalf("stashed answer should allow, got %+v", ca)
	}
	if ca.answers["Continue?"] != "Yes" {
		t.Fatalf("stashed answers mismatch: %+v", ca.answers)
	}
}

func TestRegisterAndWaitForQuestionStashesDenyOnTimeout(t *testing.T) {
	withStateDir(t)
	orig := questionAnswerHoldTimeout
	questionAnswerHoldTimeout = 30 * time.Millisecond
	defer func() { questionAnswerHoldTimeout = orig }()

	s := newServer(serverHome())
	s.dispatcher.runs["run-stash-2"] = &dispatchRun{ID: "run-stash-2", Agent: "claudeCode"}
	event := QuestionEvent{
		QuestionID: "q-stash-2",
		RunID:      "run-stash-2",
		ToolUseID:  "toolu_stash_2",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Still there?"}},
		Confidence: "bestEffort",
	}

	s.registerAndWaitForQuestion(event) // returns quickly given the shortened timeout above

	ca, ok := s.dispatcher.takeControlAnswer("run-stash-2", "toolu_stash_2")
	if !ok {
		t.Fatalf("a hold-timeout must still stash a fail-closed deny control answer")
	}
	if ca.allow {
		t.Fatalf("hold-timeout stash must deny, got allow=%v", ca.allow)
	}
	if ca.message == "" {
		t.Fatalf("deny stash should carry an explanatory message")
	}
}

// --- streamJSONOutput: control_request line parsing -------------------------

func TestStreamJSONOutputEmitsControlRequestForAskUserQuestion(t *testing.T) {
	var mu sync.Mutex
	var got map[string]any
	emit := func(method string, params any) {
		if method == "agent.control.request" {
			mu.Lock()
			got = params.(map[string]any)
			mu.Unlock()
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	line := `{"type":"control_request","request_id":"req-abc","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Pick a color"}]},"tool_use_id":"toolu_abc","requires_user_interaction":true}}` + "\n"
	streamJSONOutput(emit, "run-x", strings.NewReader(line), &seq, &wg)
	wg.Wait()

	mu.Lock()
	defer mu.Unlock()
	if got == nil {
		t.Fatalf("expected agent.control.request to be emitted")
	}
	if got["requestId"] != "req-abc" || got["toolName"] != "AskUserQuestion" || got["toolUseId"] != "toolu_abc" {
		t.Fatalf("unexpected agent.control.request payload: %+v", got)
	}
}

func TestStreamJSONOutputEmitsControlCloseOnResult(t *testing.T) {
	var mu sync.Mutex
	var sawClose bool
	emit := func(method string, params any) {
		if method == "agent.control.close" {
			mu.Lock()
			sawClose = true
			mu.Unlock()
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	line := `{"type":"result","subtype":"success","is_error":false,"result":"done"}` + "\n"
	streamJSONOutput(emit, "run-y", strings.NewReader(line), &seq, &wg)
	wg.Wait()

	mu.Lock()
	defer mu.Unlock()
	if !sawClose {
		t.Fatalf("a result line must emit agent.control.close so a stream-json-input run's stdin gets closed")
	}
}
