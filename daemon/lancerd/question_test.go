package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// claudeAskUserQuestionFixture is a realistic Claude Code AskUserQuestion
// tool_use input, matching the documented Claude Agent SDK schema (see
// question.go's claudeAskUserQuestionInput doc comment / the "Handle
// approvals and user input" docs): 1-4 questions, 2-4 options each.
const claudeAskUserQuestionFixture = `{"questions":[{"question":"How should I format the output?","header":"Format","multiSelect":false,"options":[{"label":"Summary","description":"Brief overview"},{"label":"Detailed","description":"Full explanation"}]}]}`

// --- extractQuestionEvent -------------------------------------------------

func TestQuestionExtractClaudeFixtureIsComplete(t *testing.T) {
	event, ok := extractQuestionEvent("claude", "run-1", "/tmp/proj", "toolu_01", "AskUserQuestion", claudeAskUserQuestionFixture)
	if !ok {
		t.Fatalf("expected AskUserQuestion to be recognized as a question tool")
	}
	if event.Confidence != "complete" {
		t.Fatalf("confidence = %q, want complete for a verified Claude fixture", event.Confidence)
	}
	if event.Agent != "claudeCode" {
		t.Fatalf("agent = %q, want normalized claudeCode", event.Agent)
	}
	if !event.AllowFreeText {
		t.Fatalf("AllowFreeText must be true — Claude always offers an implicit Other option")
	}
	if len(event.Questions) != 1 {
		t.Fatalf("want 1 question, got %d: %+v", len(event.Questions), event.Questions)
	}
	q := event.Questions[0]
	if q.Question != "How should I format the output?" || q.Header != "Format" {
		t.Fatalf("unexpected question text/header: %+v", q)
	}
	if len(q.Options) != 2 {
		t.Fatalf("want 2 Ladder options, got %d: %+v", len(q.Options), q.Options)
	}
	if q.Options[0].Label != "Summary" || q.Options[0].Description != "Brief overview" {
		t.Fatalf("Ladder option[0] = %+v, want Summary/Brief overview", q.Options[0])
	}
	if q.Options[1].Label != "Detailed" {
		t.Fatalf("Ladder option[1] = %+v, want Detailed", q.Options[1])
	}
	if event.QuestionID == "" || event.RunID != "run-1" || event.CWD != "/tmp/proj" || event.ToolUseID != "toolu_01" {
		t.Fatalf("unexpected event identity fields: %+v", event)
	}
}

func TestQuestionExtractIgnoresOrdinaryTool(t *testing.T) {
	if _, ok := extractQuestionEvent("claude", "run-1", "/tmp", "toolu_02", "Bash", `{"command":"ls"}`); ok {
		t.Fatalf("an ordinary tool (Bash) must never be treated as a question")
	}
}

// A recognized question-tool name whose input doesn't parse into the known
// structured schema must still produce a QuestionEvent (degrade visibly),
// never silently drop it.
func TestQuestionExtractDegradesOnMalformedStructuredInput(t *testing.T) {
	malformed := `{"question":"Pick a color","notTheRightShapeAtAll":true}`
	event, ok := extractQuestionEvent("claude", "run-1", "/tmp", "toolu_03", "AskUserQuestion", malformed)
	if !ok {
		t.Fatalf("a recognized question tool with unparseable input must still produce an event")
	}
	if event.Confidence != "bestEffort" {
		t.Fatalf("confidence = %q, want bestEffort for malformed structured input", event.Confidence)
	}
	if len(event.Questions) != 1 || len(event.Questions[0].Options) != 0 {
		t.Fatalf("degraded event should carry free-text-only questions, got %+v", event.Questions)
	}
	if event.Questions[0].Question != "Pick a color" {
		t.Fatalf("degraded event should recover readable question text, got %q", event.Questions[0].Question)
	}
	if !event.AllowFreeText {
		t.Fatalf("a degraded event must allow free text — it's the only way to answer it")
	}
}

// A vendor never verified to support the structured schema must never be
// reported as "complete" confidence, even if its tool call happens to be
// named exactly "AskUserQuestion" and happens to parse cleanly — confidence
// is a per-vendor trust axis (same convention as receipt.go's
// commandsConfidence), not just a per-payload shape check.
func TestQuestionExtractNeverClaimsCompleteForUnverifiedVendor(t *testing.T) {
	event, ok := extractQuestionEvent("codex", "run-1", "/tmp", "toolu_04", "AskUserQuestion", claudeAskUserQuestionFixture)
	if !ok {
		t.Fatalf("expected a question event even for an unverified vendor")
	}
	if event.Confidence != "bestEffort" {
		t.Fatalf("confidence = %q, want bestEffort — codex is not verified for structured questions", event.Confidence)
	}
}

// A future/unknown vendor tool with an obviously question-shaped name must
// still surface as a degraded event rather than being silently dropped as an
// ordinary, uninspected tool artifact.
func TestQuestionExtractRecognizesUnknownQuestionShapedToolName(t *testing.T) {
	event, ok := extractQuestionEvent("opencode", "run-1", "/tmp", "toolu_05", "ask_question", `{"prompt":"Continue?"}`)
	if !ok {
		t.Fatalf("a tool name containing 'question' should be recognized, even if unverified")
	}
	if event.Confidence != "bestEffort" {
		t.Fatalf("confidence = %q, want bestEffort", event.Confidence)
	}
	if event.Questions[0].Question != "Continue?" {
		t.Fatalf("expected to recover 'prompt' field text, got %q", event.Questions[0].Question)
	}
}

// --- questionStore / waitForAnswer ----------------------------------------

// TestQuestionAnswerRPCUnblocksWaitingRun proves the store half of "answer RPC
// unblocks the waiting run": a goroutine blocked in waitForAnswer (standing in
// for registerAndWaitForQuestion blocking a run's stream-scanning goroutine —
// see question.go) is released the moment resolve() is called, with the exact
// answer it was given.
func TestQuestionAnswerRPCUnblocksWaitingRun(t *testing.T) {
	store := newQuestionStore()
	event := QuestionEvent{
		QuestionID: "q-1",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Proceed?", Options: []QuestionOption{{Label: "Yes"}, {Label: "No"}}}},
		Confidence: "complete",
	}
	ch := store.add(event)

	type result struct {
		answer QuestionAnswer
		ok     bool
	}
	resultCh := make(chan result, 1)
	go func() {
		a, ok := waitForAnswer(ch, 5*time.Second)
		resultCh <- result{a, ok}
	}()

	// Give the goroutine a moment to actually be blocked in waitForAnswer
	// before resolving, so this test exercises the "unblocks a waiting
	// caller" path rather than a buffered-channel technicality.
	time.Sleep(20 * time.Millisecond)

	answer := QuestionAnswer{QuestionID: "q-1", Items: []QuestionItemAnswer{{SelectedLabels: []string{"Yes"}}}}
	resolved, ok := store.resolve("q-1", answer)
	if !ok {
		t.Fatalf("resolve should succeed for a pending question")
	}
	if resolved.QuestionID != "q-1" {
		t.Fatalf("resolved event id = %q, want q-1", resolved.QuestionID)
	}

	select {
	case r := <-resultCh:
		if !r.ok {
			t.Fatalf("waiting goroutine should have received the answer, not timed out")
		}
		if len(r.answer.Items) != 1 || r.answer.Items[0].SelectedLabels[0] != "Yes" {
			t.Fatalf("unexpected answer delivered to waiter: %+v", r.answer)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("waiting goroutine was never unblocked by resolve()")
	}

	if pending := store.pendingEvents(); len(pending) != 0 {
		t.Fatalf("resolved question should no longer be pending, got %+v", pending)
	}
}

// TestQuestionResolveRejectsItemCountMismatch guards resolve()'s only
// validation: an answer whose Items don't align 1:1 with the event's
// Questions must never partially resolve.
func TestQuestionResolveRejectsItemCountMismatch(t *testing.T) {
	store := newQuestionStore()
	event := QuestionEvent{
		QuestionID: "q-2",
		Questions:  []QuestionItem{{Question: "A"}, {Question: "B"}},
	}
	store.add(event)

	_, ok := store.resolve("q-2", QuestionAnswer{QuestionID: "q-2", Items: []QuestionItemAnswer{{FreeText: "only one"}}})
	if ok {
		t.Fatalf("resolve must reject an item-count mismatch (1 answer for 2 questions)")
	}
	if pending := store.pendingEvents(); len(pending) != 1 {
		t.Fatalf("a rejected resolve must leave the question pending, got %+v", pending)
	}
}

// TestQuestionResolveCaseInsensitive mirrors
// TestApprovalResolveCaseInsensitive (approval_case_test.go): the phone sends
// Swift's uppercase UUID.uuidString while the daemon stores ids lowercase.
func TestQuestionResolveCaseInsensitive(t *testing.T) {
	store := newQuestionStore()
	lower := "cace8588-685d-4c34-8081-231fef1f974d"
	store.add(QuestionEvent{QuestionID: lower, Questions: []QuestionItem{{Question: "Q"}}})

	_, ok := store.resolve(strings.ToUpper(lower), QuestionAnswer{QuestionID: lower, Items: []QuestionItemAnswer{{FreeText: "ok"}}})
	if !ok {
		t.Fatalf("resolve with UPPERCASE id must match the lowercase-stored pending")
	}
}

// TestQuestionTimeoutHoldsInsteadOfDenying is the "fail-closed hold" case the
// task spec calls for, in explicit contrast to approval.go's waitWithTimeout
// (whose timeout synthesizes a "deny" AND the caller evicts the pending
// approval). A question's timeout must do neither: waitForAnswer reports
// ok=false with a zero-value answer that must not be treated as real, AND —
// unlike approvals — the pending question must still be there afterward, so
// a late answer can still resolve it.
func TestQuestionTimeoutHoldsInsteadOfDenying(t *testing.T) {
	store := newQuestionStore()
	event := QuestionEvent{QuestionID: "q-3", Questions: []QuestionItem{{Question: "Still there?"}}}
	ch := store.add(event)

	answer, ok := waitForAnswer(ch, 30*time.Millisecond)
	if ok {
		t.Fatalf("expected timeout (ok=false), got an answer: %+v", answer)
	}
	if len(answer.Items) != 0 {
		t.Fatalf("timeout must return a zero-value answer, got %+v", answer)
	}

	pending := store.pendingEvents()
	if len(pending) != 1 || pending[0].QuestionID != "q-3" {
		t.Fatalf("a timed-out question must remain pending (hold, not auto-resolve), got %+v", pending)
	}

	// A late answer, arriving after the timeout gave up waiting, must still
	// be honored — nothing evicted the pending entry on timeout.
	late, ok := store.resolve("q-3", QuestionAnswer{QuestionID: "q-3", Items: []QuestionItemAnswer{{FreeText: "yes, still there"}}})
	if !ok {
		t.Fatalf("a late answer after a hold-timeout must still resolve successfully")
	}
	if late.QuestionID != "q-3" {
		t.Fatalf("late-resolved event id = %q, want q-3", late.QuestionID)
	}
}

// --- agent.question.answer RPC (server.go wiring) --------------------------

func TestQuestionAnswerRPCResolvesPendingQuestion(t *testing.T) {
	withStateDir(t)
	s := newServer(serverHome())
	event := QuestionEvent{
		QuestionID: "rpc-q-1",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Ready?", Options: []QuestionOption{{Label: "Yes"}, {Label: "No"}}}},
		Confidence: "complete",
	}
	ch := s.questions.add(event)

	params, _ := json.Marshal(QuestionAnswer{QuestionID: "rpc-q-1", Items: []QuestionItemAnswer{{SelectedLabels: []string{"Yes"}}}})
	msg := &rpcMessage{JSONRPC: "2.0", ID: float64(1), Method: "agent.question.answer", Params: params}
	s.handleMessage(msg)

	select {
	case a := <-ch:
		if len(a.Items) != 1 || a.Items[0].SelectedLabels[0] != "Yes" {
			t.Fatalf("unexpected answer delivered via RPC: %+v", a)
		}
	default:
		t.Fatalf("agent.question.answer RPC should have resolved and signaled the pending channel")
	}
}

func TestQuestionAnswerRPCErrorsOnUnknownQuestion(t *testing.T) {
	withStateDir(t)
	s := newServer(serverHome())
	params, _ := json.Marshal(QuestionAnswer{QuestionID: "does-not-exist", Items: []QuestionItemAnswer{{FreeText: "x"}}})
	msg := &rpcMessage{JSONRPC: "2.0", ID: float64(1), Method: "agent.question.answer", Params: params}
	// Should not panic; applyQuestionAnswer must report ok=false internally.
	// (handleMessage writes the JSON-RPC error via s.writeFramed, which is a
	// no-op with no emitter/stdout wired in this test — we only need to prove
	// no panic and that the store stays empty.)
	s.handleMessage(msg)
	if pending := s.questions.pendingEvents(); len(pending) != 0 {
		t.Fatalf("unknown-question answer must not create a pending entry, got %+v", pending)
	}
}

// --- end-to-end: registerAndWaitForQuestion + applyQuestionAnswer ----------

// TestQuestionRegisterAndWaitUnblocksOnAnswer exercises the actual
// production hook wired in newServer (s.dispatcher.onQuestion =
// s.registerAndWaitForQuestion): registering a question blocks the calling
// goroutine (standing in for the run's stream-scanning goroutine) until
// applyQuestionAnswer (the RPC handler's logic) resolves it.
func TestQuestionRegisterAndWaitUnblocksOnAnswer(t *testing.T) {
	withStateDir(t)
	s := newServer(serverHome())
	event := QuestionEvent{
		QuestionID: "hold-1",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Continue with the risky path?", Options: []QuestionOption{{Label: "Yes"}, {Label: "No"}}}},
		Confidence: "complete",
	}

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		s.registerAndWaitForQuestion(event) // blocks until answered (10-minute hold ceiling)
	}()

	// Give registerAndWaitForQuestion time to register + start waiting.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(s.questions.pendingEvents()) == 1 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if len(s.questions.pendingEvents()) != 1 {
		t.Fatalf("question was never registered as pending")
	}

	if _, ok := s.applyQuestionAnswer(QuestionAnswer{QuestionID: "hold-1", Items: []QuestionItemAnswer{{SelectedLabels: []string{"Yes"}}}}); !ok {
		t.Fatalf("applyQuestionAnswer should resolve the pending question")
	}

	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("registerAndWaitForQuestion did not unblock after applyQuestionAnswer")
	}
}

// --- stream-json extraction wiring (dispatch.go) ----------------------------

// TestQuestionStreamJSONEmitsRawForAskUserQuestion proves the
// extraction hooks into the SAME stream-json parsing path as ordinary tool
// artifacts (dispatch.go's content_block_stop handling): a Claude
// AskUserQuestion tool_use, split across content_block_start/delta/stop lines
// exactly as the real CLI streams it, produces both the normal tool artifact
// AND the internal-only "agent.question.raw" notification wrapEmitForRun
// intercepts.
func TestQuestionStreamJSONEmitsRawForAskUserQuestion(t *testing.T) {
	var mu sync.Mutex
	var methods []string
	var raw map[string]any
	emit := func(method string, params any) {
		mu.Lock()
		defer mu.Unlock()
		methods = append(methods, method)
		if method == "agent.question.raw" {
			raw = params.(map[string]any)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_01","name":"AskUserQuestion"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"questions\":[{\"question\":\"How should I format the output?\",\"header\":\"Format\",\"options\":[{\"label\":\"Summary\",\"description\":\"Brief overview\"},{\"label\":\"Detailed\",\"description\":\"Full explanation\"}],\"multiSelect\":false}]}"}}}
{"type":"stream_event","event":{"type":"content_block_stop"}}
`
	streamJSONOutput(emit, "run-1", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	var sawArtifact, sawRaw bool
	for _, m := range methods {
		if m == "agent.artifact" {
			sawArtifact = true
		}
		if m == "agent.question.raw" {
			sawRaw = true
		}
	}
	if !sawArtifact {
		t.Fatalf("AskUserQuestion should still emit the ordinary tool artifact, methods: %v", methods)
	}
	if !sawRaw {
		t.Fatalf("AskUserQuestion should also emit agent.question.raw, methods: %v", methods)
	}
	if raw["toolName"] != "AskUserQuestion" || raw["runId"] != "run-1" {
		t.Fatalf("unexpected agent.question.raw payload: %+v", raw)
	}
	var parsed claudeAskUserQuestionInput
	if err := json.Unmarshal([]byte(raw["inputJSON"].(string)), &parsed); err != nil || len(parsed.Questions) != 1 {
		t.Fatalf("agent.question.raw inputJSON did not round-trip the assembled tool_use input: %v (%q)", err, raw["inputJSON"])
	}
}

// TestQuestionStreamJSONOrdinaryToolDoesNotEmitRaw guards against any
// regression that starts treating every tool_use as a question.
func TestQuestionStreamJSONOrdinaryToolDoesNotEmitRaw(t *testing.T) {
	var methods []string
	emit := func(method string, params any) { methods = append(methods, method) }

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_02","name":"Bash"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"command\":\"ls\"}"}}}
{"type":"stream_event","event":{"type":"content_block_stop"}}
`
	streamJSONOutput(emit, "run-1", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	for _, m := range methods {
		if m == "agent.question.raw" {
			t.Fatalf("an ordinary Bash tool_use must never emit agent.question.raw, methods: %v", methods)
		}
	}
}

// --- wrapEmitForRun wiring (dispatch.go) ------------------------------------

// TestQuestionWrapEmitForRunBuildsEventAndInvokesOnQuestion proves the full
// hook/stream-json wiring end to end: an "agent.question.raw" notification —
// as emitted by streamJSONOutput above — carries through wrapEmitForRun (using
// the run's registered Agent/CWD) into a real QuestionEvent delivered to
// d.onQuestion, and is NOT forwarded further as a raw notification to the
// phone.
func TestQuestionWrapEmitForRunBuildsEventAndInvokesOnQuestion(t *testing.T) {
	d := newDispatcher()
	d.runs["run-1"] = &dispatchRun{ID: "run-1", Agent: "claude", CWD: "/tmp/proj", Status: "running"}

	var got QuestionEvent
	var gotOK bool
	d.onQuestion = func(event QuestionEvent) {
		got = event
		gotOK = true
	}

	var forwarded []string
	d.emit = func(method string, params any) { forwarded = append(forwarded, method) }

	wrapped := d.wrapEmitForRun("run-1", false)
	wrapped("agent.question.raw", map[string]any{
		"runId": "run-1", "toolId": "toolu_01", "toolName": "AskUserQuestion", "inputJSON": claudeAskUserQuestionFixture,
	})

	if !gotOK {
		t.Fatalf("wrapEmitForRun should have invoked d.onQuestion for a recognized question tool_use")
	}
	if got.Agent != "claudeCode" || got.CWD != "/tmp/proj" || got.RunID != "run-1" {
		t.Fatalf("onQuestion event missing run context: %+v", got)
	}
	if got.Confidence != "complete" {
		t.Fatalf("confidence = %q, want complete", got.Confidence)
	}
	for _, m := range forwarded {
		if m == "agent.question.raw" {
			t.Fatalf("agent.question.raw is internal-only and must not be forwarded to d.emit, forwarded: %v", forwarded)
		}
	}
}

// TestQuestionWrapEmitForRunSkipsOrdinaryTool guards the "return"
// early-exit in wrapEmitForRun's agent.question.raw case: an ordinary tool
// name must never reach d.onQuestion (extractQuestionEvent returns ok=false).
func TestQuestionWrapEmitForRunSkipsOrdinaryTool(t *testing.T) {
	d := newDispatcher()
	d.runs["run-1"] = &dispatchRun{ID: "run-1", Agent: "claude", CWD: "/tmp", Status: "running"}
	var invoked bool
	d.onQuestion = func(event QuestionEvent) { invoked = true }

	wrapped := d.wrapEmitForRun("run-1", false)
	wrapped("agent.question.raw", map[string]any{
		"runId": "run-1", "toolId": "toolu_02", "toolName": "Bash", "inputJSON": `{"command":"ls"}`,
	})

	if invoked {
		t.Fatalf("d.onQuestion must not fire for a non-question tool")
	}
}

// --- push-backend delivery (GAP 2: closes the app-backgrounded/killed hole) -

// TestPostQuestionPush verifies postQuestionPush POSTs to /question with the
// session-scoped payload and, crucially, never includes the question text or
// option labels anywhere in the wire body — mirrors TestPostApprovalPush
// (server_test.go).
func TestPostQuestionPush(t *testing.T) {
	var received []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/question" || r.Method != http.MethodPost {
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
		SessionID:      "device-session-q1",
	}

	event := QuestionEvent{
		QuestionID: "question-abc",
		Agent:      "claudeCode",
		Confidence: "complete",
		Questions: []QuestionItem{{
			Question: "Do you want to deploy to prod with the rotated database credentials?",
			Options:  []QuestionOption{{Label: "Yes"}, {Label: "No"}},
		}},
	}

	s.postQuestionPush(dev, event)

	var payload map[string]interface{}
	if err := json.Unmarshal(received, &payload); err != nil {
		t.Fatalf("could not decode payload: %v (raw: %s)", err, received)
	}
	if payload["sessionId"] != "device-session-q1" {
		t.Errorf("sessionId = %v, want device-session-q1", payload["sessionId"])
	}
	if payload["id"] != "question-abc" {
		t.Errorf("id = %v, want question-abc", payload["id"])
	}
	if !strings.Contains(string(received), "\"confidence\":\"complete\"") {
		t.Errorf("expected confidence in payload, got %s", received)
	}
	if strings.Contains(string(received), "deploy to prod") || strings.Contains(string(received), "rotated database credentials") {
		t.Fatalf("postQuestionPush must never include question text on the wire: %s", received)
	}
}

// TestNotifyQuestionPendingPostsPushWhenDeviceRegistered verifies
// notifyQuestionPending fires postQuestionPush whenever a push-registered
// device is present — the actual production wiring this gap closes, since
// registerAndWaitForQuestion (question.go) is the only production caller of
// notifyQuestionPending and previously only ever hit writeFramed/e2e.
func TestNotifyQuestionPendingPostsPushWhenDeviceRegistered(t *testing.T) {
	withStateDir(t)
	pushed := make(chan string, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case pushed <- r.URL.Path:
		default:
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	s := newServer(serverHome())
	s.deviceMu.Lock()
	s.device = &registeredDevice{PushBackendURL: srv.URL, SessionID: "sess-notify"}
	s.deviceMu.Unlock()

	s.notifyQuestionPending(QuestionEvent{
		QuestionID: "notify-q-1",
		Agent:      "claudeCode",
		Questions:  []QuestionItem{{Question: "Proceed?"}},
	})

	select {
	case path := <-pushed:
		if path != "/question" {
			t.Fatalf("pushed to %q, want /question", path)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("notifyQuestionPending did not POST to the push backend within 2s")
	}
}
