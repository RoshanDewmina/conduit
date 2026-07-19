package main

import (
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"
)

func TestAgentArgvCursor(t *testing.T) {
	t.Setenv("LANCER_CURSOR_FORCE", "")
	argv, ok := agentArgv("cursor", "do the thing", "gpt-5", false)
	if !ok {
		t.Fatal("cursor should be supported")
	}
	want := []string{"agent", "-p", "--output-format", "stream-json", "--trust", "--model", "gpt-5", "do the thing"}
	if !reflect.DeepEqual(argv, want) {
		t.Fatalf("cursor argv mismatch:\n got %v\nwant %v", argv, want)
	}
	if strings.Contains(strings.Join(argv, " "), "sh -c") {
		t.Fatal("must never shell-interpolate prompts")
	}
}

func TestAgentArgvCursorForceOptIn(t *testing.T) {
	t.Setenv("LANCER_CURSOR_FORCE", "1")
	argv, ok := agentArgv("cursor", "hi", "", false)
	if !ok {
		t.Fatal("cursor should be supported")
	}
	want := []string{"agent", "-p", "--output-format", "stream-json", "--trust", "--force", "hi"}
	if !reflect.DeepEqual(argv, want) {
		t.Fatalf("force argv mismatch:\n got %v\nwant %v", argv, want)
	}
}

func TestContinueAndResumeArgvCursor(t *testing.T) {
	t.Setenv("LANCER_CURSOR_FORCE", "")
	cont, ok := continueArgv("cursor", "next", "auto", false)
	if !ok {
		t.Fatal("cursor continue should be supported")
	}
	wantCont := []string{"agent", "-p", "--continue", "--output-format", "stream-json", "--trust", "--model", "auto", "next"}
	if !reflect.DeepEqual(cont, wantCont) {
		t.Fatalf("continue argv mismatch:\n got %v\nwant %v", cont, wantCont)
	}
	res, ok := resumeArgv("cursor", "chat-abc", "follow up", "", false)
	if !ok {
		t.Fatal("cursor resume should be supported")
	}
	wantRes := []string{"agent", "-p", "--resume", "chat-abc", "--output-format", "stream-json", "--trust", "follow up"}
	if !reflect.DeepEqual(res, wantRes) {
		t.Fatalf("resume argv mismatch:\n got %v\nwant %v", res, wantRes)
	}
}

func TestNormalizeAgentSourceCursorAliases(t *testing.T) {
	for _, in := range []string{"cursor", "Cursor", "cursor-agent", "cursor_cli", "agent"} {
		if got := normalizeAgentSource(in); got != "cursor" {
			t.Fatalf("normalizeAgentSource(%q) = %q, want cursor", in, got)
		}
	}
}

func TestStreamJSONOutputCursorAssistantAndToolCall(t *testing.T) {
	var mu sync.Mutex
	var chunks []string
	var artifacts []map[string]any
	var thinking int
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.output":
			if c, _ := p["chunk"].(string); c != "" {
				chunks = append(chunks, c)
			}
		case "agent.artifact":
			artifacts = append(artifacts, p)
	case liveStatusMethod:
			if state, _ := p["state"].(string); state == liveStatusThinking {
				thinking++
			}
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"system","subtype":"init","session_id":"sess-cursor-1"}
{"type":"thinking","subtype":"delta","text":"..."}
{"type":"tool_call","subtype":"started","call_id":"call-1","tool_call":{"shellToolCall":{"args":{"command":"echo hi"}}}}
{"type":"tool_call","subtype":"completed","call_id":"call-1","tool_call":{"shellToolCall":{"args":{"command":"echo hi"},"result":{"success":{"stdout":"hi\n","exitCode":0}}}}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"session_id":"sess-cursor-1"}
{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"sess-cursor-1"}
`
	streamJSONOutput(emit, "run-c", strings.NewReader(input), &seq, &wg)
	wg.Wait()

	if thinking == 0 {
		t.Fatal("expected thinking live-status from Cursor thinking event")
	}
	if len(artifacts) != 1 {
		t.Fatalf("want 1 tool artifact on started (not completed), got %d: %+v", len(artifacts), artifacts)
	}
	if artifacts[0]["artifactID"] != "call-1" {
		t.Fatalf("artifact id = %v, want call-1", artifacts[0]["artifactID"])
	}
	joined := strings.Join(chunks, "")
	if !strings.Contains(joined, "done") {
		t.Fatalf("assistant text missing from chunks: %v", chunks)
	}
}

func TestStreamJSONOutputClaudeDeltasSuppressWholeAssistant(t *testing.T) {
	var chunks []string
	emit := func(method string, params any) {
		if method != "agent.run.output" {
			return
		}
		p := params.(map[string]any)
		if c, _ := p["chunk"].(string); c != "" {
			chunks = append(chunks, c)
		}
	}
	var seq int64
	var wg sync.WaitGroup
	wg.Add(1)
	input := `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello whole duplicate"}]}}
`
	streamJSONOutput(emit, "run-1", strings.NewReader(input), &seq, &wg)
	wg.Wait()
	joined := strings.Join(chunks, "")
	if joined != "Hello" {
		t.Fatalf("want only delta text, got %q", joined)
	}
}

func TestInstalledAgentsDetectsCursorAgentBinary(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(dir+"/agent", []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	t.Setenv("HOME", t.TempDir())
	got := installedAgents(nil)
	has := false
	for _, v := range got {
		if v == "cursor" {
			has = true
		}
	}
	if !has {
		t.Fatalf("expected cursor detected from agent binary, got %v", got)
	}
}
