package main

import (
	"strings"
	"sync"
	"testing"
)

func TestStreamJSONOutputEmitsTextDeltas(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `{"type":"system","subtype":"init","session_id":"sess_abc"}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"!"}}}
{"type":"result","subtype":"success","result":"done","total_cost_usd":0.01,"is_error":false}
`
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 3 {
		t.Fatalf("want 3 delta chunks, got %d: %+v", len(chunks), chunks)
	}
	if chunks[0]["chunk"] != "Hello" {
		t.Fatalf("chunk[0] want 'Hello', got %q", chunks[0]["chunk"])
	}
	if chunks[1]["chunk"] != " world" {
		t.Fatalf("chunk[1] want ' world', got %q", chunks[1]["chunk"])
	}
	if chunks[2]["chunk"] != "!" {
		t.Fatalf("chunk[2] want '!', got %q", chunks[2]["chunk"])
	}
	if s1, s2 := chunks[0]["seq"].(int), chunks[1]["seq"].(int); s2 != s1+1 {
		t.Fatalf("seq not monotonic: %d then %d", s1, s2)
	}
}

func TestStreamJSONOutputEmitsNormalizedToolArtifact(t *testing.T) {
	var methods []string
	var artifact map[string]any
	emit := func(method string, params any) {
		methods = append(methods, method)
		if method == "agent.artifact" {
			artifact = params.(map[string]any)
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"item.started","item":{"type":"command_execution","id":"cmd-1","command":"git status"}}
`
	streamJSONOutput(emit, "run-1", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	if artifact == nil {
		t.Fatalf("expected normalized artifact, methods: %v", methods)
	}
	if artifact["artifactID"] != "cmd-1" || artifact["runID"] != "run-1" {
		t.Fatalf("unexpected artifact identity: %+v", artifact)
	}
	if artifact["kind"] != "tool" || artifact["status"] != "running" {
		t.Fatalf("unexpected artifact lifecycle: %+v", artifact)
	}
}

func TestStreamJSONNonJSONLineFallsBackToRaw(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := "some plain text line\n"
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 1 {
		t.Fatalf("want 1 raw chunk, got %d", len(chunks))
	}
	if chunks[0]["chunk"] != "some plain text line\n" {
		t.Fatalf("want raw chunk with newline, got %q", chunks[0]["chunk"])
	}
	if chunks[0]["runId"] != "run-1" {
		t.Fatalf("want runId 'run-1', got %q", chunks[0]["runId"])
	}
	if chunks[0]["stream"] != "stdout" {
		t.Fatalf("want stream 'stdout', got %q", chunks[0]["stream"])
	}
}

// An unknown JSON *object* type is suppressed (not dumped raw): in multi-vendor
// structured mode the agents emit many metadata object types that should never
// reach chat. (Non-object/non-JSON lines DO fall back to raw — see the tests
// below — so genuine plain-text output is never silently lost.)
func TestStreamJSONUnknownObjectTypeSuppressed(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `{"type":"unknown_event","data":"value"}
`
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 0 {
		t.Fatalf("want unknown object type suppressed (0 chunks), got %d: %+v", len(chunks), chunks)
	}
}

func TestStreamJSONNonObjectJSONFallsBackToRaw(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `[1,2,3]
`
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 1 {
		t.Fatalf("want 1 raw chunk for JSON array, got %d", len(chunks))
	}
}

func TestStreamJSONMixedContent(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `non-JSON preamble
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"delta1"}}}
{"type":"assistant","message":{"content":[{"type":"text","text":"whole"}]}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"delta2"}}}
`
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 3 {
		t.Fatalf("want 3 chunks (raw + delta1 + delta2), got %d: %+v", len(chunks), chunks)
	}
	if chunks[0]["chunk"] != "non-JSON preamble\n" {
		t.Fatalf("chunk[0] should be raw preamble, got %q", chunks[0]["chunk"])
	}
	if chunks[1]["chunk"] != "delta1" {
		t.Fatalf("chunk[1] should be 'delta1', got %q", chunks[1]["chunk"])
	}
	if chunks[2]["chunk"] != "delta2" {
		t.Fatalf("chunk[2] should be 'delta2', got %q", chunks[2]["chunk"])
	}
}

func TestStreamJSONEmptyDeltaSkipped(t *testing.T) {
	var mu sync.Mutex
	var chunks []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		if method == "agent.run.output" {
			chunks = append(chunks, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":""}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"real"}}}
`
	r := strings.NewReader(input)
	streamJSONOutput(emit, "run-1", r, &seq, &wg)
	wg.Wait()

	if len(chunks) != 1 {
		t.Fatalf("want 1 chunk (empty delta skipped), got %d", len(chunks))
	}
	if chunks[0]["chunk"] != "real" {
		t.Fatalf("want 'real', got %q", chunks[0]["chunk"])
	}
}

func TestStreamJSONResultErrorEmitsOutputAndResultError(t *testing.T) {
	var mu sync.Mutex
	var outputs []map[string]any
	var resultErrors []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.output":
			outputs = append(outputs, p)
		case "agent.run.resultError":
			resultErrors = append(resultErrors, p)
		}
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)

	input := `{"type":"result","subtype":"error","is_error":true,"result":"Credit balance is too low"}
`
	streamJSONOutput(emit, "run-err", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(outputs) != 1 {
		t.Fatalf("want 1 output event, got %d: %+v", len(outputs), outputs)
	}
	if !strings.Contains(outputs[0]["chunk"].(string), "Credit balance is too low") {
		t.Fatalf("output chunk = %q, want vendor error text", outputs[0]["chunk"])
	}
	if len(resultErrors) != 1 {
		t.Fatalf("want 1 resultError event, got %d: %+v", len(resultErrors), resultErrors)
	}
	if resultErrors[0]["error"] != "Credit balance is too low" {
		t.Fatalf("resultError = %q", resultErrors[0]["error"])
	}
}

func TestStreamJSONSuccessResultSuppressed(t *testing.T) {
	var mu sync.Mutex
	var outputs []map[string]any
	emit := func(method string, params any) {
		if method != "agent.run.output" {
			return
		}
		p := params.(map[string]any)
		mu.Lock()
		outputs = append(outputs, p)
		mu.Unlock()
	}

	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"result","subtype":"success","result":"done","is_error":false}
`
	streamJSONOutput(emit, "run-ok", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(outputs) != 0 {
		t.Fatalf("success result should not emit output, got %d", len(outputs))
	}
}
