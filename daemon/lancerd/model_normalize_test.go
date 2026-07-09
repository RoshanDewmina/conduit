package main

import (
	"slices"
	"testing"
)

func TestNormalizeClaudeModel(t *testing.T) {
	cases := map[string]string{
		"":                         "",
		"haiku":                    "haiku",
		"sonnet":                   "sonnet",
		"opus":                     "opus",
		"anthropic/claude-haiku-4": "haiku",
		"anthropic/claude-sonnet-4": "sonnet",
		"anthropic/claude-opus-4":  "opus",
		"claude-sonnet-5":          "sonnet",
		"some-future-model":        "some-future-model",
	}
	for in, want := range cases {
		if got := normalizeClaudeModel(in); got != want {
			t.Fatalf("normalizeClaudeModel(%q)=%q want %q", in, got, want)
		}
	}
}

func TestAgentArgvRemapsClaudeModel(t *testing.T) {
	argv, ok := agentArgv("claudeCode", "hi", "anthropic/claude-haiku-4")
	if !ok {
		t.Fatal("expected ok")
	}
	i := slices.Index(argv, "--model")
	if i < 0 || i+1 >= len(argv) {
		t.Fatalf("missing --model in %v", argv)
	}
	if argv[i+1] != "haiku" {
		t.Fatalf("--model=%q want haiku; argv=%v", argv[i+1], argv)
	}
}
