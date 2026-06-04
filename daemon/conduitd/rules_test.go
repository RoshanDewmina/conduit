package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAlwaysRuleStoreMatches(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "always-rules.json")
	s := &alwaysRuleStore{path: path}
	s.add(alwaysRule{Agent: "claudeCode", Tool: "Bash", Prefix: "npm test"})

	event := ApprovalEvent{
		Agent:     "claudeCode",
		ToolName:  "Bash",
		Command:   "npm test -- --filter foo",
		Kind:      "command",
	}
	if !s.matches(event) {
		t.Fatal("expected rule to match prefixed command")
	}

	other := ApprovalEvent{
		Agent:    "claudeCode",
		ToolName: "Bash",
		Command:  "rm -rf /",
		Kind:     "command",
	}
	if s.matches(other) {
		t.Fatal("did not expect unrelated command to match")
	}
}

func TestAlwaysRuleStorePersists(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "always-rules.json")
	s := &alwaysRuleStore{path: path}
	s.add(alwaysRule{Agent: "codex", Tool: "shell", Prefix: "make"})

	reloaded := &alwaysRuleStore{path: path}
	reloaded.load()
	if len(reloaded.rules) != 1 {
		t.Fatalf("expected 1 persisted rule, got %d", len(reloaded.rules))
	}
	if reloaded.rules[0].Prefix != "make" {
		t.Fatalf("unexpected prefix %q", reloaded.rules[0].Prefix)
	}
	_ = os.Remove(path)
}
