package main

import (
	"reflect"
	"strings"
	"sync"
	"testing"
)

// --- argv: codex reasoning-summary flag + opencode --thinking flag ---------
//
// Both flags were verified live 2026-07-18: without them, no reasoning event
// appears on the CLI's stdout stream; with them, one does. See agentArgv's
// codex/opencode case doc comments for the live-verification note, and
// TestStreamJSONCodexReasoningItemEmitsThinking /
// TestStreamJSONOpenCodeReasoningEventEmitsThinking below for the captured
// stream lines.

func TestAgentArgvCodexIncludesReasoningSummaryFlag(t *testing.T) {
	argv, ok := agentArgv("codex", "do the thing", "", false)
	want := []string{"codex", "exec", "--json", "-c", "model_reasoning_summary=auto", "do the thing"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("codex agentArgv mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

func TestAgentArgvOpenCodeIncludesThinkingFlag(t *testing.T) {
	argv, ok := agentArgv("opencode", "do the thing", "", false)
	want := []string{"opencode", "run", "--format", "json", "--thinking", "do the thing"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("opencode agentArgv mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

func TestContinueArgvCodexIncludesReasoningSummaryFlag(t *testing.T) {
	argv, ok := continueArgv("codex", "next step", "", false)
	want := []string{"codex", "exec", "resume", "--last", "--json", "-c", "model_reasoning_summary=auto", "next step"}
	if !ok || !reflect.DeepEqual(argv, want) {
		t.Fatalf("codex continueArgv mismatch:\n got %v (ok=%v)\nwant %v", argv, ok, want)
	}
}

// --- stream parsing: codex reasoning items ----------------------------------
//
// Fixture is a real captured line from a live headless smoke run this
// session: `codex exec --json -c model_reasoning_summary=auto "Reply with
// only the word ok. Do not edit any files." < /dev/null` in a git-inited temp
// dir, codex-cli 0.144.6 — the exact argv agentArgv now builds. Raw line:
//
//	{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Planning skill usage protocol**"}}
//
// (full stream also contained a command_execution item and a final
// agent_message "ok" — this fixture isolates the reasoning line under test).
func TestStreamJSONCodexReasoningItemEmitsThinking(t *testing.T) {
	clearLiveStatus("run-codex-reasoning")
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

	input := `{"type":"thread.started","thread_id":"019f775a-fc4c-7421-898e-e381f3fedb44"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Planning skill usage protocol**"}}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":42272,"output_tokens":171}}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-codex-reasoning", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(liveStates) == 0 || liveStates[0] != liveStatusThinking {
		t.Fatalf("want first live status = thinking, got %v", liveStates)
	}
	// The reasoning item's own text must NOT be forwarded to chat output —
	// only the agent_message text should be (same suppression as Claude's
	// thinking_delta / opencode's reasoning event).
	for _, c := range outputChunks {
		if strings.Contains(c, "Planning skill") {
			t.Fatalf("reasoning text leaked into chat output: %q", c)
		}
	}
	if len(outputChunks) != 1 || outputChunks[0] != "ok\n" {
		t.Fatalf("want only the agent_message chunk, got %v", outputChunks)
	}
	clearLiveStatus("run-codex-reasoning")
}

// --- stream parsing: opencode reasoning events ------------------------------
//
// Fixture is a real captured line from a live headless smoke run this
// session: `opencode run --format json --thinking "Reply with only the word
// ok. Do not edit any files." < /dev/null`, opencode 1.17.18 — the exact
// argv agentArgv now builds. Raw line (trimmed of the "time" sub-object,
// irrelevant to parsing):
//
//	{"type":"reasoning","timestamp":1784413932048,"sessionID":"ses_088a45be9ffennC9V2R6WPiSUB","part":{"id":"prt_...","messageID":"msg_...","sessionID":"ses_...","type":"reasoning","text":"The user wants me to reply with only the word \"ok\" and not edit any files."}}
func TestStreamJSONOpenCodeReasoningEventEmitsThinking(t *testing.T) {
	clearLiveStatus("run-oc-reasoning")
	var liveStates []string
	emit := func(method string, params any) {
		if method != liveStatusMethod {
			return
		}
		m, _ := params.(map[string]any)
		liveStates = append(liveStates, m["state"].(string))
	}

	input := `{"type":"step_start","timestamp":1784413930740,"sessionID":"ses_088a45be9ffennC9V2R6WPiSUB","part":{"type":"step-start"}}
{"type":"reasoning","timestamp":1784413932048,"sessionID":"ses_088a45be9ffennC9V2R6WPiSUB","part":{"id":"prt_f775bc8fb001pmhCVjstpbO3a8","type":"reasoning","text":"The user wants me to reply with only the word \"ok\" and not edit any files."}}
{"type":"text","timestamp":1784413932048,"sessionID":"ses_088a45be9ffennC9V2R6WPiSUB","part":{"type":"text","text":"ok"}}
{"type":"step_finish","timestamp":1784413932048,"sessionID":"ses_088a45be9ffennC9V2R6WPiSUB","part":{"type":"step-finish"}}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-oc-reasoning", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(liveStates) < 2 {
		t.Fatalf("want thinking + streaming, got %v", liveStates)
	}
	if liveStates[0] != liveStatusThinking {
		t.Fatalf("first live status = %q, want thinking", liveStates[0])
	}
	foundStreaming := false
	for _, s := range liveStates {
		if s == liveStatusStreaming {
			foundStreaming = true
		}
	}
	if !foundStreaming {
		t.Fatalf("want streaming after the text part, got %v", liveStates)
	}
	clearLiveStatus("run-oc-reasoning")
}

// Negative test (acceptance clause): a stream that never contains a
// "reasoning" event (i.e. what opencode emits WITHOUT --thinking on the
// argv — confirmed live: same prompt, same opencode 1.17.18 binary, only
// difference is the missing flag, and no reasoning line appeared) must
// produce no thinking live-status transition.
func TestStreamJSONOpenCodeWithoutThinkingFlagProducesNoThinking(t *testing.T) {
	clearLiveStatus("run-oc-nothink")
	var liveStates []string
	emit := func(method string, params any) {
		if method != liveStatusMethod {
			return
		}
		m, _ := params.(map[string]any)
		liveStates = append(liveStates, m["state"].(string))
	}

	// Real captured shape of `opencode run --format json` (no --thinking)
	// for the same prompt: step_start, text, step_finish — no reasoning line.
	input := `{"type":"step_start","timestamp":1784413944025,"sessionID":"ses_088a41e67ffeg7kPvd629Lfh5w","part":{"type":"step-start"}}
{"type":"text","timestamp":1784413944259,"sessionID":"ses_088a41e67ffeg7kPvd629Lfh5w","part":{"type":"text","text":"ok"}}
{"type":"step_finish","timestamp":1784413944260,"sessionID":"ses_088a41e67ffeg7kPvd629Lfh5w","part":{"type":"step-finish"}}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-oc-nothink", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	for _, s := range liveStates {
		if s == liveStatusThinking {
			t.Fatalf("no reasoning event in the stream — thinking must never fire, got %v", liveStates)
		}
	}
	clearLiveStatus("run-oc-nothink")
}

// --- stream parsing: kimi ----------------------------------------------------
//
// Kimi's live `--output-format stream-json` stdout shape could not be
// live-verified this session (provider.api_error: 402 membership,
// re-confirmed 2026-07-18 — see resumeArgv's doc comment and the
// "context.append_message" case's doc comment in streamJSONOutput). These
// fixtures instead exercise the shape kimi_session_reader.go's
// kimiMessagesFromLine already proves from real wire.jsonl captures (see
// TestKimiMessage / TestKimiTranscriptToolCallInputJSON in
// codex_kimi_reader_test.go) — the only kimi message shape this codebase has
// concrete evidence for.

func TestStreamJSONKimiWireFormatEmitsStreamingAndTool(t *testing.T) {
	clearLiveStatus("run-kimi-wire")
	var liveStates []string
	var toolNames []string
	var outputChunks []string
	emit := func(method string, params any) {
		m, _ := params.(map[string]any)
		switch method {
		case liveStatusMethod:
			liveStates = append(liveStates, m["state"].(string))
			if tn, ok := m["toolName"].(string); ok && tn != "" {
				toolNames = append(toolNames, tn)
			}
		case "agent.run.output":
			outputChunks = append(outputChunks, m["chunk"].(string))
		}
	}

	input := `{"type":"context.append_message","message":{"role":"assistant","content":[{"type":"text","text":"on it"}],"toolCalls":[{"id":"tc1","function":{"name":"bash","arguments":"{\"command\":\"pwd\"}"}}]}}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-kimi-wire", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	foundStreaming, foundTool := false, false
	for _, s := range liveStates {
		if s == liveStatusStreaming {
			foundStreaming = true
		}
		if s == liveStatusTool {
			foundTool = true
		}
	}
	if !foundStreaming {
		t.Fatalf("want streaming live status for assistant text, got %v", liveStates)
	}
	if !foundTool {
		t.Fatalf("want tool live status for the toolCall, got %v", liveStates)
	}
	if len(toolNames) != 1 || toolNames[0] != "bash" {
		t.Fatalf("want tool name 'bash', got %v", toolNames)
	}
	if len(outputChunks) != 1 || outputChunks[0] != "on it\n" {
		t.Fatalf("want assistant text forwarded to chat output, got %v", outputChunks)
	}
	// No thinking transition — kimi has no proven reasoning content type,
	// so none must be invented.
	for _, s := range liveStates {
		if s == liveStatusThinking {
			t.Fatalf("kimi mapping must never emit thinking (no evidence for it), got %v", liveStates)
		}
	}
	clearLiveStatus("run-kimi-wire")
}

func TestStreamJSONKimiFlatRoleEmitsStreaming(t *testing.T) {
	clearLiveStatus("run-kimi-flat")
	var liveStates []string
	emit := func(method string, params any) {
		if method != liveStatusMethod {
			return
		}
		m, _ := params.(map[string]any)
		liveStates = append(liveStates, m["state"].(string))
	}

	input := `{"role":"assistant","content":"hello from kimi"}
`
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	streamJSONOutput(emit, "run-kimi-flat", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if len(liveStates) != 1 || liveStates[0] != liveStatusStreaming {
		t.Fatalf("want a single streaming transition (closing the pre-Phase-2 gap), got %v", liveStates)
	}
	clearLiveStatus("run-kimi-flat")
}
