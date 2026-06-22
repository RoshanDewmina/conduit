package main

import "testing"

func TestNormalizeAgentSourceCodexAliases(t *testing.T) {
	t.Parallel()

	cases := []string{"codex", "openai-codex", "  codex  "}
	for _, input := range cases {
		if got := normalizeAgentSource(input); got != "codex" {
			t.Fatalf("normalizeAgentSource(%q) = %q, want codex", input, got)
		}
	}
}

func TestNormalizeAgentSourceClaudeAliases(t *testing.T) {
	t.Parallel()

	cases := []string{"claude", "claude-code", "claude_code", "claudecode"}
	for _, input := range cases {
		if got := normalizeAgentSource(input); got != "claudeCode" {
			t.Fatalf("normalizeAgentSource(%q) = %q, want claudeCode", input, got)
		}
	}
}

func TestNormalizeAgentSourceCursorPlaceholder(t *testing.T) {
	t.Parallel()

	cases := []string{"cursor", "cursor-agent", "cursor-cli"}
	for _, input := range cases {
		if got := normalizeAgentSource(input); got != "cursor" {
			t.Fatalf("normalizeAgentSource(%q) = %q, want cursor", input, got)
		}
	}
}
