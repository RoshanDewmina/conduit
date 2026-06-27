package main

import (
	"encoding/json"
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
	// Non-message payloads yield nothing.
	if _, text := codexMessageText(mk(`{"type":"function_call","name":"shell"}`)); text != "" {
		t.Fatalf("function_call should not produce text, got %q", text)
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
