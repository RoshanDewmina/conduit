package main

import (
	"reflect"
	"strings"
	"sync"
	"testing"
)

// --- argv: pi launch ---------------------------------------------------------
//
// argv shape mirrors the live-verified invocation: `pi --provider openrouter
// --model deepseek/deepseek-v4-flash --mode json -p "<prompt>"` — verified
// live 2026-07-18 against pi 0.80.10 (scratchpad/pi-smoke/pi-stream.jsonl,
// pi-tool-stream.jsonl). No `-e <path>` extension flag yet — that lands in
// Phase 3(d) alongside the installer.

func TestAgentArgvPiWithProviderModel(t *testing.T) {
	argv, ok := agentArgv("pi", "do the thing", "openrouter/deepseek/deepseek-v4-flash", false)
	want := []string{"pi", "--mode", "json", "--provider", "openrouter", "--model", "deepseek/deepseek-v4-flash", "-p", "do the thing"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("pi agentArgv mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

func TestAgentArgvPiNoModel(t *testing.T) {
	argv, ok := agentArgv("pi", "do the thing", "", false)
	want := []string{"pi", "--mode", "json", "-p", "do the thing"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("pi agentArgv (no model) mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

func TestAgentArgvPiBareModelNoProviderPrefix(t *testing.T) {
	// A model with no "/" is passed through as --model with no --provider
	// override (pi falls back to its own default provider in that case).
	argv, ok := agentArgv("pi", "do the thing", "gemini-pro", false)
	want := []string{"pi", "--mode", "json", "--model", "gemini-pro", "-p", "do the thing"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("pi agentArgv (bare model) mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

func TestSplitPiModel(t *testing.T) {
	cases := []struct {
		model, wantProvider, wantModelID string
	}{
		{"openrouter/deepseek/deepseek-v4-flash", "openrouter", "deepseek/deepseek-v4-flash"},
		{"gemini-pro", "", "gemini-pro"},
		{"", "", ""},
		{"anthropic/claude-sonnet-5", "anthropic", "claude-sonnet-5"},
	}
	for _, c := range cases {
		provider, modelID := splitPiModel(c.model)
		if provider != c.wantProvider || modelID != c.wantModelID {
			t.Errorf("splitPiModel(%q) = (%q,%q), want (%q,%q)", c.model, provider, modelID, c.wantProvider, c.wantModelID)
		}
	}
}

// --- stream parsing: pi session id capture -----------------------------------
//
// Real captured first line from a live `pi --provider openrouter --model
// deepseek/deepseek-v4-flash --mode json -p "..."` run this session
// (scratchpad/pi-smoke/pi-stream.jsonl line 0).
func TestStreamJSONPiCapturesSessionID(t *testing.T) {
	clearLiveStatus("run-pi-session")
	var vendorSessionID string
	emit := func(method string, params any) {
		if method != "agent.run.vendorSession" {
			return
		}
		m, _ := params.(map[string]any)
		vendorSessionID, _ = m["vendorSessionId"].(string)
	}

	input := `{"type":"session","version":3,"id":"019f773d-faf4-7c6b-80f0-aba6c7d05745","timestamp":"2026-07-18T21:59:38.484Z","cwd":"/private/tmp/pi-smoke"}
{"type":"agent_start"}
{"type":"turn_start"}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-pi-session", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if vendorSessionID != "019f773d-faf4-7c6b-80f0-aba6c7d05745" {
		t.Fatalf("vendorSessionID = %q, want the session line's id", vendorSessionID)
	}
	clearLiveStatus("run-pi-session")
}

// --- stream parsing: pi thinking + text streaming ----------------------------
//
// Real captured lines from a live `pi --mode json` run (no tool call) this
// session (scratchpad/pi-smoke/pi-stream.jsonl lines 6-7, 31 abbreviated).
func TestStreamJSONPiThinkingAndTextStreaming(t *testing.T) {
	clearLiveStatus("run-pi-text")
	var liveStates []string
	var outputChunks []string
	emit := func(method string, params any) {
		m, _ := params.(map[string]any)
		switch method {
		case liveStatusMethod:
			liveStates = append(liveStates, m["state"].(string))
		case "agent.run.output":
			outputChunks = append(outputChunks, m["chunk"].(string))
		}
	}

	input := `{"type":"message_update","assistantMessageEvent":{"type":"thinking_start","contentIndex":0,"partial":{"role":"assistant","content":[{"type":"thinking","thinking":"The","thinkingSignature":"reasoning"}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"The","partial":{"role":"assistant","content":[{"type":"thinking","thinking":"The","thinkingSignature":"reasoning"}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"text_start","contentIndex":0,"partial":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"ok","partial":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"ok","partial":{"role":"assistant","content":[{"type":"text","text":"okok"}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"thinking_end","contentIndex":0}}
{"type":"message_update","assistantMessageEvent":{"type":"text_end","contentIndex":0}}
{"type":"turn_end","message":{"role":"assistant"},"toolResults":[]}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-pi-text", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(liveStates) == 0 || liveStates[0] != liveStatusThinking {
		t.Fatalf("want first live status = thinking, got %v", liveStates)
	}
	foundStreaming := false
	for _, s := range liveStates {
		if s == liveStatusStreaming {
			foundStreaming = true
		}
	}
	if !foundStreaming {
		t.Fatalf("want streaming after text_delta, got %v", liveStates)
	}
	if strings.Join(outputChunks, "") != "okok" {
		t.Fatalf("output chunks = %v, want the two text_delta fragments concatenated to \"okok\"", outputChunks)
	}
	clearLiveStatus("run-pi-text")
}

// --- stream parsing: pi tool call (toolcall_start/end + tool_execution_*) ----
//
// Real captured lines from a live `pi --mode json -p "Run 'echo
// hello-pi-tool-test' using your bash tool..."` run this session
// (scratchpad/pi-smoke/pi-tool-stream.jsonl lines 17, 26, 28-31 — the
// toolcall_start/toolcall_end message_update pair plus the tool_execution_*
// trio, trimmed to the fields under test).
func TestStreamJSONPiToolCallEmitsToolArtifact(t *testing.T) {
	clearLiveStatus("run-pi-tool")
	var liveTools []string
	var toolStarts []map[string]any
	emit := func(method string, params any) {
		m, _ := params.(map[string]any)
		switch method {
		case liveStatusMethod:
			if m["state"] == liveStatusTool {
				liveTools = append(liveTools, m["toolName"].(string))
			}
		case "agent.tool.start":
			toolStarts = append(toolStarts, m)
		}
	}

	input := `{"type":"message_update","assistantMessageEvent":{"type":"toolcall_start","contentIndex":1,"partial":{"role":"assistant","content":[{"type":"toolCall","id":"call_00913be689ae4450a70a89f8","name":"bash","arguments":{}}]}}}
{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","contentIndex":1,"delta":"{\"command\":"}}
{"type":"message_update","assistantMessageEvent":{"type":"toolcall_end","contentIndex":1,"toolCall":{"type":"toolCall","id":"call_00913be689ae4450a70a89f8","name":"bash","arguments":{"command":"echo hello-pi-tool-test"}}}}
{"type":"tool_execution_start","toolCallId":"call_00913be689ae4450a70a89f8","toolName":"bash","args":{"command":"echo hello-pi-tool-test"}}
{"type":"tool_execution_update","toolCallId":"call_00913be689ae4450a70a89f8","toolName":"bash","partialResult":{"content":[]}}
{"type":"tool_execution_end","toolCallId":"call_00913be689ae4450a70a89f8","toolName":"bash","result":{"content":[{"type":"text","text":"hello-pi-tool-test\n"}]},"isError":false}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-pi-tool", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(liveTools) != 1 || liveTools[0] != "bash" {
		t.Fatalf("want exactly one 'bash' tool live-status, got %v", liveTools)
	}
	if len(toolStarts) != 1 {
		t.Fatalf("want exactly one tool.start (from toolcall_end only, not tool_execution_start), got %d: %+v", len(toolStarts), toolStarts)
	}
	ts := toolStarts[0]
	if ts["toolId"] != "call_00913be689ae4450a70a89f8" || ts["toolName"] != "bash" {
		t.Fatalf("tool.start = %+v", ts)
	}
	inputJSON, _ := ts["inputJSON"].(string)
	if !strings.Contains(inputJSON, `"command"`) || !strings.Contains(inputJSON, "echo hello-pi-tool-test") {
		t.Fatalf("tool.start inputJSON = %q", inputJSON)
	}
	clearLiveStatus("run-pi-tool")
}

// TestStreamJSONPiUnknownEventTypeDoesNotError is the spec's required
// negative test: an unknown top-level event type, and an unknown
// assistantMessageEvent.type, must parse without error and without emitting
// any live-status or output.
func TestStreamJSONPiUnknownEventTypeDoesNotError(t *testing.T) {
	clearLiveStatus("run-pi-unknown")
	var events []string
	emit := func(method string, params any) {
		events = append(events, method)
	}

	input := `{"type":"session","id":"019f773d-faf4-7c6b-80f0-aba6c7d05745"}
{"type":"some_future_pi_event","payload":{"anything":"goes"}}
{"type":"message_update","assistantMessageEvent":{"type":"some_future_assistant_event","contentIndex":0}}
{"type":"agent_settled"}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-pi-unknown", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	// Only the session id capture should have emitted anything.
	if len(events) != 1 || events[0] != "agent.run.vendorSession" {
		t.Fatalf("unknown event types should be silently suppressed, got emits: %v", events)
	}
	clearLiveStatus("run-pi-unknown")
}
