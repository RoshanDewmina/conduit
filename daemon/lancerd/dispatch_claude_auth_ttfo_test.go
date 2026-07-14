package main

import (
	"errors"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// RED→GREEN: Claude auth preflight + TTFO (time-to-first-output).

func TestDispatchClaudeNotLoggedInStartsNoVendor(t *testing.T) {
	d := newDispatcher()
	var launches atomic.Int64
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	d.claudeAuthPreflight = func() error { return errClaudeNotLoggedIn }

	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "hi", CWD: t.TempDir()}, allowEval, noAudit)
	if res.Status != "error" {
		t.Fatalf("status=%q want error (%s)", res.Status, res.Message)
	}
	if !strings.Contains(res.Message, "Not logged in") {
		t.Fatalf("message=%q", res.Message)
	}
	if launches.Load() != 0 {
		t.Fatalf("vendor must not start, launches=%d", launches.Load())
	}
}

func TestDispatchClaudeAuthUnavailableStartsNoVendor(t *testing.T) {
	d := newDispatcher()
	var launches atomic.Int64
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	d.claudeAuthPreflight = func() error { return errClaudeAuthUnavailable }

	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "hi", CWD: t.TempDir()}, allowEval, noAudit)
	if res.Status != "error" {
		t.Fatalf("status=%q want error (%s)", res.Status, res.Message)
	}
	if !strings.Contains(res.Message, "auth status unavailable — retry") {
		t.Fatalf("message=%q", res.Message)
	}
	if launches.Load() != 0 {
		t.Fatalf("unavailable must fail closed (no 75s vendor launch), launches=%d", launches.Load())
	}
}

func TestDispatchClaudeLoggedInLaunches(t *testing.T) {
	d := newDispatcher()
	var launches atomic.Int64
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	d.claudeAuthPreflight = func() error { return nil }

	res := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "hi", CWD: t.TempDir()}, allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("status=%q (%s)", res.Status, res.Message)
	}
	if launches.Load() != 1 {
		t.Fatalf("launches=%d", launches.Load())
	}
}

func TestDispatchCodexSkipsClaudeAuthPreflight(t *testing.T) {
	d := newDispatcher()
	var preflightCalls atomic.Int64
	d.claudeAuthPreflight = func() error {
		preflightCalls.Add(1)
		return errClaudeNotLoggedIn
	}
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "codex", Prompt: "hi", CWD: t.TempDir()}, allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("codex must not be blocked by claude preflight: %q %s", res.Status, res.Message)
	}
	if preflightCalls.Load() != 0 {
		t.Fatalf("preflight must not run for codex")
	}
}

func TestStreamJSONAssistantAuthenticationFailedClassifies(t *testing.T) {
	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"assistant","error":"authentication_failed","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]}}
`
	streamJSONOutput(emit, "run-auth", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) != 1 {
		t.Fatalf("want 1 resultError, got %v", resultErrors)
	}
	if resultErrors[0] != claudeNotLoggedInMessage {
		t.Fatalf("got %q", resultErrors[0])
	}
}

func TestStreamJSONBenignLoginMentionDoesNotClassify(t *testing.T) {
	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"assistant","message":{"content":[{"type":"text","text":"Docs say run /login on the host for setup"}]}}
`
	streamJSONOutput(emit, "run-benign", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) != 0 {
		t.Fatalf("benign /login must not classify, got %v", resultErrors)
	}
}

func TestStreamJSONResultAuthenticationFailedClassifies(t *testing.T) {
	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"result","subtype":"error","is_error":true,"result":"Not logged in · Please run /login","error":"authentication_failed"}
`
	streamJSONOutput(emit, "run-auth2", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) != 1 || resultErrors[0] != claudeNotLoggedInMessage {
		t.Fatalf("got %v", resultErrors)
	}
}

func TestStreamJSONAuthErrorDedupeAssistantThenResult(t *testing.T) {
	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"assistant","error":"authentication_failed","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]}}
{"type":"result","subtype":"error","is_error":true,"result":"Not logged in · Please run /login","error":"authentication_failed"}
`
	streamJSONOutput(emit, "run-auth-dedupe", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) != 1 {
		t.Fatalf("want exactly one auth resultError per run, got %v", resultErrors)
	}
}

func TestStreamJSONResultContentHeuristicOnlyWhenIsError(t *testing.T) {
	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	// is_error result with /login text but no structured authentication_failed —
	// content heuristic allowed because already marked is_error.
	input := `{"type":"result","subtype":"error","is_error":true,"result":"Please run /login"}
`
	streamJSONOutput(emit, "run-content-heur", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) != 1 || resultErrors[0] != claudeNotLoggedInMessage {
		t.Fatalf("is_error content heuristic: got %v", resultErrors)
	}
}

func TestClaudeTTFOKillsSilentChild(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 80 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var statuses []map[string]any
	var resultErrors []string
	emit := func(method string, params any) {
		p, _ := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.status":
			statuses = append(statuses, p)
		case "agent.run.resultError":
			resultErrors = append(resultErrors, p["error"].(string))
		}
	}

	h, err := realLauncher([]string{"sleep", "30"}, "", "run-ttfo-silent", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		done := len(resultErrors) > 0
		for _, s := range statuses {
			if s["status"] == "failed" || s["status"] == "exited" {
				done = true
			}
		}
		mu.Unlock()
		if done || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) == 0 || !strings.Contains(resultErrors[0], "cold-start timeout") {
		t.Fatalf("want cold-start timeout resultError, got %v", resultErrors)
	}
	var failed bool
	for _, s := range statuses {
		if s["status"] == "failed" {
			failed = true
		}
	}
	if !failed {
		t.Fatalf("want failed status, got %+v", statuses)
	}
}

func TestClaudeTTFONotCancelledByStderr(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 120 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}

	// stderr spam only — must NOT cancel TTFO; cold-start should still fire.
	h, err := realLauncher([]string{"sh", "-c", "echo noise >&2; sleep 5"}, "", "run-ttfo-stderr", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		n := len(resultErrors)
		mu.Unlock()
		if n > 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) == 0 || !strings.Contains(resultErrors[0], "cold-start timeout") {
		t.Fatalf("stderr must not cancel TTFO; want cold-start, got %v", resultErrors)
	}
}

func TestClaudeTTFONotCancelledByInitOrThinking(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 150 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}

	// Init vendorSession + thinking liveStatus only, then hang — TTFO must fire.
	script := `
printf '%s\n' '{"type":"system","subtype":"init","session_id":"sess-hang"}'
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"thinking"}}}'
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"..."}}}'
sleep 5
`
	argv := []string{"sh", "-c", script, "x", "--output-format", "stream-json"}
	h, err := realLauncher(argv, "", "run-ttfo-init-think", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		n := len(resultErrors)
		mu.Unlock()
		if n > 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) == 0 || !strings.Contains(resultErrors[0], "cold-start timeout") {
		t.Fatalf("init/thinking must not cancel TTFO; want cold-start, got %v", resultErrors)
	}
}

func TestClaudeTTFOCancelledByTextDelta(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 500 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var resultErrors []string
	var statuses []string
	emit := func(method string, params any) {
		p, _ := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.resultError":
			resultErrors = append(resultErrors, p["error"].(string))
		case "agent.run.status":
			statuses = append(statuses, p["status"].(string))
		}
	}

	script := `
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}}'
exit 0
`
	argv := []string{"sh", "-c", script, "x", "--output-format", "stream-json"}
	h, err := realLauncher(argv, "", "run-ttfo-text", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(2 * time.Second)
	for {
		mu.Lock()
		done := false
		for _, s := range statuses {
			if s == "exited" || s == "failed" {
				done = true
			}
		}
		mu.Unlock()
		if done || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(80 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()
	for _, e := range resultErrors {
		if strings.Contains(e, "cold-start timeout") {
			t.Fatalf("text_delta must cancel TTFO: %v", resultErrors)
		}
	}
}

func TestClaudeTTFOCancelledByToolStart(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 500 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var resultErrors []string
	var statuses []string
	emit := func(method string, params any) {
		p, _ := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.resultError":
			resultErrors = append(resultErrors, p["error"].(string))
		case "agent.run.status":
			statuses = append(statuses, p["status"].(string))
		}
	}

	script := `
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"t1","name":"Bash"}}}'
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"command\":\"true\"}"}}}'
printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_stop"}}'
exit 0
`
	argv := []string{"sh", "-c", script, "x", "--output-format", "stream-json"}
	h, err := realLauncher(argv, "", "run-ttfo-tool", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(2 * time.Second)
	for {
		mu.Lock()
		done := false
		for _, s := range statuses {
			if s == "exited" || s == "failed" {
				done = true
			}
		}
		mu.Unlock()
		if done || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(80 * time.Millisecond)
	mu.Lock()
	defer mu.Unlock()
	for _, e := range resultErrors {
		if strings.Contains(e, "cold-start timeout") {
			t.Fatalf("tool start must cancel TTFO: %v", resultErrors)
		}
	}
}

func TestClaudeAuthStreamWinsOverTTFO(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 2 * time.Second
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var resultErrors []string
	emit := func(method string, params any) {
		if method != "agent.run.resultError" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		resultErrors = append(resultErrors, p["error"].(string))
		mu.Unlock()
	}

	// Extra argv flags after the script enable stream-json parsing without
	// changing sh -c behavior (they become $0/$1). Never used for production
	// Claude launches (those use explicit claude argv).
	script := `echo '{"type":"assistant","error":"authentication_failed","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]}}'; exit 1`
	argv := []string{"sh", "-c", script, "x", "--output-format", "stream-json"}
	h, err := realLauncher(argv, "", "run-auth-vs-ttfo", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		n := len(resultErrors)
		mu.Unlock()
		if n > 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(50 * time.Millisecond) // allow any late TTFO

	mu.Lock()
	defer mu.Unlock()
	if len(resultErrors) == 0 {
		t.Fatal("want auth resultError")
	}
	for _, e := range resultErrors {
		if strings.Contains(e, "cold-start timeout") {
			t.Fatalf("auth must win over TTFO: %v", resultErrors)
		}
		if !strings.Contains(e, "Not logged in") {
			t.Fatalf("want auth message, got %q", e)
		}
	}
}

func TestClaudeTTFOCompletionRaceOneTerminal(t *testing.T) {
	prev := claudeFirstOutputTimeout
	prevApply := ttfoAppliesTo
	claudeFirstOutputTimeout = 30 * time.Millisecond
	ttfoAppliesTo = func([]string) bool { return true }
	t.Cleanup(func() { claudeFirstOutputTimeout = prev; ttfoAppliesTo = prevApply })

	var mu sync.Mutex
	var terminals []string
	emit := func(method string, params any) {
		if method != "agent.run.status" {
			return
		}
		p := params.(map[string]any)
		st, _ := p["status"].(string)
		if st == "exited" || st == "failed" {
			mu.Lock()
			terminals = append(terminals, st)
			mu.Unlock()
		}
	}

	h, err := realLauncher([]string{"sleep", "5"}, "", "run-ttfo-race", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	defer h.kill()

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		n := len(terminals)
		mu.Unlock()
		if n >= 1 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()
	if len(terminals) != 1 {
		t.Fatalf("want exactly one terminal status, got %v", terminals)
	}
}

func TestClaudeAuthPreflightErrorIsTyped(t *testing.T) {
	if !errors.Is(errClaudeNotLoggedIn, errClaudeNotLoggedIn) {
		t.Fatal()
	}
	if errors.Is(errors.New("other"), errClaudeNotLoggedIn) {
		t.Fatal()
	}
	if !errors.Is(errClaudeAuthUnavailable, errClaudeAuthUnavailable) {
		t.Fatal()
	}
	if errors.Is(errClaudeNotLoggedIn, errClaudeAuthUnavailable) {
		t.Fatal()
	}
}

// --- Preflight ordering: policy → ensureClaudeAuth → insert d.runs → launch ---

func TestDispatchClaudeAuthPreflightBeforeRunInsert(t *testing.T) {
	d := newDispatcher()
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	d.claudeAuthPreflight = func() error {
		entered.Done()
		release.Wait()
		return errClaudeNotLoggedIn
	}
	var launches atomic.Int64
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}

	var res dispatchResult
	var done sync.WaitGroup
	done.Add(1)
	go func() {
		defer done.Done()
		res = d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "hi", CWD: t.TempDir()}, allowEval, noAudit)
	}()
	entered.Wait()
	// While blocked in preflight there must be no ghost "running" run.
	d.mu.Lock()
	ghost := 0
	for _, run := range d.runs {
		if run.Status == "running" {
			ghost++
		}
	}
	d.mu.Unlock()
	if ghost != 0 {
		release.Done()
		done.Wait()
		t.Fatalf("ghost running runs during preflight: %d", ghost)
	}
	release.Done()
	done.Wait()
	if res.Status != "error" || launches.Load() != 0 {
		t.Fatalf("status=%q launches=%d msg=%q", res.Status, launches.Load(), res.Message)
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.runs) != 0 {
		t.Fatalf("failed preflight must leave no run: %+v", d.runs)
	}
}

func TestContinueClaudeNotLoggedInStartsNoVendor(t *testing.T) {
	d := newDispatcher()
	d.claudeAuthPreflight = func() error { return nil }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", Prompt: "start", CWD: t.TempDir()}, allowEval, noAudit)
	if first.Status != "started" {
		t.Fatalf("setup dispatch: %q %s", first.Status, first.Message)
	}

	var launches atomic.Int64
	d.claudeAuthPreflight = func() error { return errClaudeNotLoggedIn }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	res := d.continueRun(first.RunID, "next", continueFallback{}, allowEval, noAudit)
	if res.Status != "error" || !strings.Contains(res.Message, "Not logged in") {
		t.Fatalf("got %+v", res)
	}
	if launches.Load() != 0 {
		t.Fatalf("continue must not launch, launches=%d", launches.Load())
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	for id, run := range d.runs {
		if id != first.RunID && run.Status == "running" {
			t.Fatalf("ghost continue run %s status=%s", id, run.Status)
		}
	}
}

func TestResumeClaudeNotLoggedInStartsNoVendor(t *testing.T) {
	d := newDispatcher()
	var launches atomic.Int64
	d.claudeAuthPreflight = func() error { return errClaudeNotLoggedIn }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	res := d.resumeObservedSession(observedSessionContinueParams{
		Vendor: "claudeCode", SessionID: "sess-1", CWD: t.TempDir(), Prompt: "go",
	}, allowEval, noAudit)
	if res.Status != "error" || !strings.Contains(res.Message, "Not logged in") {
		t.Fatalf("got %+v", res)
	}
	if launches.Load() != 0 {
		t.Fatalf("resume must not launch")
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.runs) != 0 {
		t.Fatalf("failed resume must leave no run: %+v", d.runs)
	}
}

func TestConversationLaunchClaudeNotLoggedInStartsNoVendor(t *testing.T) {
	d := newDispatcher()
	var launches atomic.Int64
	d.claudeAuthPreflight = func() error { return errClaudeNotLoggedIn }
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches.Add(1)
		return &procHandle{kill: func() {}}, nil
	}
	res := d.launchConversationTurn("conv-run-1", conversationLaunchParams{
		Agent: "claudeCode", Prompt: "hi", CWD: t.TempDir(), IsNew: true,
	}, allowEval, noAudit)
	if res.Status != "error" || !strings.Contains(res.Message, "Not logged in") {
		t.Fatalf("got %+v", res)
	}
	if launches.Load() != 0 {
		t.Fatalf("conversation launch must not start vendor")
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if _, ok := d.runs["conv-run-1"]; ok {
		t.Fatal("failed conversation preflight must not leave running run")
	}
}
