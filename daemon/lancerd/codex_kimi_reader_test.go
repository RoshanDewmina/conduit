package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCodexMessageText(t *testing.T) {
	mk := func(s string) json.RawMessage { return json.RawMessage(s) }

	role, text := codexMessageText(mk(`{"type":"message","role":"user","content":[{"type":"input_text","text":"fix the bug"}]}`))
	if role != "user" || text != "fix the bug" {
		t.Fatalf("user msg → (%q,%q)", role, text)
	}
	role, text = codexMessageText(mk(`{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}`))
	if role != "assistant" || text != "done" {
		t.Fatalf("assistant msg → (%q,%q)", role, text)
	}
	// Non-message payloads yield nothing from the text helper.
	if _, text := codexMessageText(mk(`{"type":"function_call","name":"shell"}`)); text != "" {
		t.Fatalf("function_call should not produce text, got %q", text)
	}
}

func TestCodexResponseItemFunctionCall(t *testing.T) {
	mk := func(s string) json.RawMessage { return json.RawMessage(s) }

	msgs := codexResponseItem(mk(`{"type":"function_call","name":"shell","arguments":"{\"command\":\"ls\"}","call_id":"call_abc"}`))
	if len(msgs) != 1 {
		t.Fatalf("got %d msgs, want 1: %+v", len(msgs), msgs)
	}
	m := msgs[0]
	if m.Role != "toolCall" || m.ToolName != "shell" || m.ToolUseID != "call_abc" {
		t.Fatalf("function_call → %+v", m)
	}
	if !strings.Contains(m.InputJSON, `"command"`) || !strings.Contains(m.InputJSON, `ls`) {
		t.Fatalf("InputJSON = %q", m.InputJSON)
	}

	out := codexResponseItem(mk(`{"type":"function_call_output","call_id":"call_abc","output":"file.txt"}`))
	if len(out) != 1 || out[0].Role != "toolResult" || out[0].ToolUseID != "call_abc" || out[0].Text != "file.txt" {
		t.Fatalf("function_call_output → %+v", out)
	}
}

func TestIsCodexInjectedText(t *testing.T) {
	for _, s := range []string{"<environment_context>", "<system-reminder>", "# AGENTS.md instructions for /x", "<permissions>"} {
		if !isCodexInjectedText(s) {
			t.Fatalf("%q should be flagged as injected", s)
		}
	}
	if isCodexInjectedText("fix the auth bug") {
		t.Fatal("a real prompt must not be flagged as injected")
	}
}

func TestKimiMessage(t *testing.T) {
	role, text, tool := kimiMessage([]byte(`{"type":"context.append_message","message":{"role":"user","content":[{"type":"text","text":"hello kimi"}],"toolCalls":[]}}`))
	if role != "user" || text != "hello kimi" || tool != "" {
		t.Fatalf("user → (%q,%q,%q)", role, text, tool)
	}
	role, _, tool = kimiMessage([]byte(`{"type":"context.append_message","message":{"role":"assistant","content":[{"type":"text","text":"on it"}],"toolCalls":[{"name":"bash"}]}}`))
	if role != "assistant" || tool != "bash" {
		t.Fatalf("assistant+tool → (%q,tool=%q)", role, tool)
	}
	// Non-message wire events yield nothing.
	if role, _, _ := kimiMessage([]byte(`{"type":"config.update","modelAlias":"x"}`)); role != "" {
		t.Fatalf("config.update should not be a message, got role %q", role)
	}
}

func TestKimiTranscriptToolCallInputJSON(t *testing.T) {
	msgs := kimiMessagesFromLine([]byte(`{"type":"context.append_message","message":{"role":"assistant","content":[{"type":"text","text":"running"}],"toolCalls":[{"id":"tc1","function":{"name":"bash","arguments":"{\"command\":\"pwd\"}"}}]}}`))
	var tc *SessionMessage
	for i := range msgs {
		if msgs[i].Role == "toolCall" {
			tc = &msgs[i]
			break
		}
	}
	if tc == nil {
		t.Fatalf("expected toolCall in %+v", msgs)
	}
	if tc.ToolName != "bash" || tc.ToolUseID != "tc1" {
		t.Fatalf("toolCall = %+v", tc)
	}
	if !strings.Contains(tc.InputJSON, `"command"`) || !strings.Contains(tc.InputJSON, `pwd`) {
		t.Fatalf("InputJSON = %q", tc.InputJSON)
	}
}

func TestTruncateTitle(t *testing.T) {
	if got := truncateTitle("  hello   world  "); got != "hello world" {
		t.Fatalf("whitespace collapse → %q", got)
	}
	long := make([]byte, 200)
	for i := range long {
		long[i] = 'a'
	}
	if len(truncateTitle(string(long))) != 80 {
		t.Fatal("title should cap at 80 chars")
	}
}
