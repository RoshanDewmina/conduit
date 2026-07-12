package main

import (
	"strings"
	"sync"
	"testing"
	"unicode/utf8"
)

func TestLiveStatusToolTargetPriorityAndCap(t *testing.T) {
	got := liveStatusToolTarget(`{"query":"q","path":"/p","command":"ls","file_path":"/Users/me/ChatUI.swift"}`)
	if got != "/Users/me/ChatUI.swift" {
		t.Fatalf("file_path should win, got %q", got)
	}
	got = liveStatusToolTarget(`{"command":"go test ./...","query":"x"}`)
	if got != "go test ./..." {
		t.Fatalf("command should win over query, got %q", got)
	}
	got = liveStatusToolTarget(`{"path":"/a/b","query":"x"}`)
	if got != "/a/b" {
		t.Fatalf("path should win over query, got %q", got)
	}
	got = liveStatusToolTarget(`{"query":"hello"}`)
	if got != "hello" {
		t.Fatalf("query alone, got %q", got)
	}

	long := strings.Repeat("a", 120)
	got = liveStatusToolTarget(`{"file_path":"` + long + `"}`)
	if utf8.RuneCountInString(got) != liveStatusTargetCap {
		t.Fatalf("cap = %d, got %d (%q)", liveStatusTargetCap, utf8.RuneCountInString(got), got)
	}
}

func TestEmitLiveStatusDedupeAndClear(t *testing.T) {
	tracker := newLiveStatusTracker()
	var events []map[string]any
	emit := func(method string, params any) {
		if method != liveStatusMethod {
			t.Fatalf("unexpected method %q", method)
		}
		m, _ := params.(map[string]any)
		events = append(events, m)
	}

	tracker.emit(emit, "run-1", liveStatusStarting, "", "")
	tracker.emit(emit, "run-1", liveStatusStarting, "", "") // dedupe
	tracker.emit(emit, "run-1", liveStatusThinking, "", "")
	tracker.emit(emit, "run-1", liveStatusTool, "Edit", "/Users/me/ChatUI.swift")
	tracker.emit(emit, "run-1", liveStatusTool, "Edit", "/Users/me/ChatUI.swift") // dedupe
	tracker.emit(emit, "run-1", liveStatusTool, "Bash", "go test")
	tracker.emit(emit, "run-1", liveStatusStreaming, "", "")

	if len(events) != 5 {
		t.Fatalf("want 5 emissions after dedupe, got %d: %+v", len(events), events)
	}
	wantStates := []string{
		liveStatusStarting, liveStatusThinking, liveStatusTool, liveStatusTool, liveStatusStreaming,
	}
	for i, want := range wantStates {
		if events[i]["state"] != want {
			t.Fatalf("event[%d].state = %v, want %q", i, events[i]["state"], want)
		}
		if events[i]["runId"] != "run-1" {
			t.Fatalf("event[%d].runId = %v", i, events[i]["runId"])
		}
		if _, ok := events[i]["at"].(string); !ok || events[i]["at"] == "" {
			t.Fatalf("event[%d] missing at", i)
		}
	}
	if events[2]["toolName"] != "Edit" || events[2]["target"] != "/Users/me/ChatUI.swift" {
		t.Fatalf("tool event = %+v", events[2])
	}
	if events[3]["toolName"] != "Bash" || events[3]["target"] != "go test" {
		t.Fatalf("bash event = %+v", events[3])
	}

	tracker.clear("run-1")
	tracker.emit(emit, "run-1", liveStatusStarting, "", "")
	if len(events) != 6 {
		t.Fatalf("after clear, starting should emit again; got %d", len(events))
	}
}

func TestEmitLiveStatusNilSafe(t *testing.T) {
	emitLiveStatus(nil, "r", liveStatusStarting, "", "")
	emitLiveStatusStarting(nil, "r")
	emitLiveStatusThinking(nil, "r")
	emitLiveStatusStreaming(nil, "r")
	emitLiveStatusTool(nil, "r", "Edit", `{"file_path":"a.swift"}`)
}

func TestEmitLiveStatusToolFromInputJSON(t *testing.T) {
	tracker := newLiveStatusTracker()
	var events []map[string]any
	emit := func(method string, params any) {
		m, _ := params.(map[string]any)
		events = append(events, m)
	}
	tracker.emit(emit, "r2", liveStatusTool, "XcodeBuildMCP", liveStatusToolTarget(`{"command":"build"}`))
	if len(events) != 1 || events[0]["toolName"] != "XcodeBuildMCP" || events[0]["target"] != "build" {
		t.Fatalf("got %+v", events)
	}
}

func TestStreamJSONEmitsLiveStatusTransitions(t *testing.T) {
	clearLiveStatus("run-live")
	var liveStates []string
	var toolTargets []string
	emit := func(method string, params any) {
		if method != liveStatusMethod {
			return
		}
		m, _ := params.(map[string]any)
		liveStates = append(liveStates, m["state"].(string))
		if t, ok := m["target"].(string); ok {
			toolTargets = append(toolTargets, t)
		}
	}

	input := `{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"thinking"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"plan"}}}
{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"t1","name":"Edit"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"file_path\":\"ChatUI.swift\"}"}}}
{"type":"stream_event","event":{"type":"content_block_stop"}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}}
`
	var seq int64
	var done sync.WaitGroup
	done.Add(1)
	streamJSONOutput(emit, "run-live", strings.NewReader(input), &seq, &done)
	done.Wait()

	if len(liveStates) < 3 {
		t.Fatalf("liveStates = %v", liveStates)
	}
	if liveStates[0] != liveStatusThinking {
		t.Fatalf("first live = %q, want thinking", liveStates[0])
	}
	foundTool, foundStreaming := false, false
	for _, s := range liveStates {
		if s == liveStatusTool {
			foundTool = true
		}
		if s == liveStatusStreaming {
			foundStreaming = true
		}
	}
	if !foundTool || !foundStreaming {
		t.Fatalf("expected tool+streaming in %v", liveStates)
	}
	foundTarget := false
	for _, tgt := range toolTargets {
		if tgt == "ChatUI.swift" {
			foundTarget = true
		}
	}
	if !foundTarget {
		t.Fatalf("expected ChatUI.swift target in %v", toolTargets)
	}
	clearLiveStatus("run-live")
}

func TestPersistConversationEventSkipsLiveStatus(t *testing.T) {
	// Guard: live status must remain ephemeral. The persist switch only
	// accepts output/status/artifact/receipt — liveStatus falls through.
	s := &server{}
	s.persistConversationEvent(liveStatusMethod, map[string]any{
		"runId": "r", "state": liveStatusThinking, "at": "2026-07-12T00:00:00Z",
	})
	// No panic / no store required — nil conversations is a silent no-op.
}
