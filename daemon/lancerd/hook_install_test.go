package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestClaudeHookIsScopedToLancerDispatches(t *testing.T) {
	for _, script := range []string{claudeHookScript} {
		if !strings.Contains(script, `[[ "${LANCER_GATE:-}" != "1" ]]`) {
			t.Fatal("Claude hook must exit unless LANCER_GATE=1")
		}
	}
}

func readSettings(t *testing.T, path string) map[string]json.RawMessage {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("parse settings %q: %v", data, err)
	}
	return m
}

// ensureClaudeHookWiredOnBoot is what lets a plain dispatch launch immediately
// instead of escalating. It must wire the hook on a fresh install AND repair a
// stale/mismatched command (the real-world rebrand bug, where settings.json had a
// non-matching hook entry so claudeHookWired read false and every send blocked).
func TestEnsureClaudeHookWiredOnBoot(t *testing.T) {
	state := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", state)
	home := serverHome()
	path := claudeSettingsPath(home)

	if claudeHookWired(path) {
		t.Fatal("precondition: a fresh state dir should not have the hook wired")
	}
	ensureClaudeHookWiredOnBoot()
	if !claudeHookWired(path) {
		t.Fatal("boot wire should leave the Claude hook wired on a fresh install")
	}

	// Now simulate a stale/mismatched PreToolUse entry and confirm boot repairs it.
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	stale := `{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash ~/.conduit/hooks/conduit-hook.sh"}]}]}}`
	if err := os.WriteFile(path, []byte(stale), 0644); err != nil {
		t.Fatal(err)
	}
	if claudeHookWired(path) {
		t.Fatal("a stale conduit-only entry should read as not wired")
	}
	ensureClaudeHookWiredOnBoot()
	if !claudeHookWired(path) {
		t.Fatal("boot wire should repair a stale/mismatched hook command")
	}
}

func TestWireClaudeHookCreatesMissingSettings(t *testing.T) {
	home := t.TempDir()
	changed, err := wireClaudeHookSettings(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true on first wire")
	}
	if !claudeHookWired(claudeSettingsPath(home)) {
		t.Fatal("hook not wired after install into missing settings.json")
	}
}

func TestWireClaudeHookIsIdempotent(t *testing.T) {
	home := t.TempDir()
	if _, err := wireClaudeHookSettings(home); err != nil {
		t.Fatal(err)
	}
	first := readSettings(t, claudeSettingsPath(home))

	changed, err := wireClaudeHookSettings(home)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("second wire should be a no-op (changed=false)")
	}
	second := readSettings(t, claudeSettingsPath(home))

	// Exactly one PreToolUse matcher block — the merge must not duplicate it.
	pre := decodePreToolUse(t, second)
	if len(pre) != 1 {
		t.Fatalf("expected 1 PreToolUse matcher after re-wire, got %d", len(pre))
	}
	if string(first["hooks"]) != string(second["hooks"]) {
		t.Fatalf("idempotent re-wire changed hooks block: %s -> %s", first["hooks"], second["hooks"])
	}
}

func TestWireClaudeHookPreservesExistingKeys(t *testing.T) {
	home := t.TempDir()
	path := claudeSettingsPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	existing := `{
  "model": "claude-opus-4",
  "permissions": {"defaultMode": "bypassPermissions"},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo custom"}]}
    ]
  }
}`
	if err := os.WriteFile(path, []byte(existing), 0644); err != nil {
		t.Fatal(err)
	}

	changed, err := wireClaudeHookSettings(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true when lancer hook not yet present")
	}

	merged := readSettings(t, path)
	if _, ok := merged["model"]; !ok {
		t.Error("model key dropped")
	}
	if _, ok := merged["permissions"]; !ok {
		t.Error("permissions key dropped")
	}
	pre := decodePreToolUse(t, merged)
	if len(pre) != 2 {
		t.Fatalf("expected 2 PreToolUse matchers (user's + lancer's), got %d", len(pre))
	}
	if !claudeHookWired(path) {
		t.Fatal("lancer hook not registered after merge")
	}
	// The user's pre-existing custom hook must survive.
	if !preHasCommand(pre, "echo custom") {
		t.Fatal("user's existing PreToolUse hook was lost in the merge")
	}
}

func TestWireClaudeHookHandlesEmptyFile(t *testing.T) {
	home := t.TempDir()
	path := claudeSettingsPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(""), 0644); err != nil {
		t.Fatal(err)
	}
	changed, err := wireClaudeHookSettings(home)
	if err != nil {
		t.Fatalf("empty settings.json should be handled gracefully: %v", err)
	}
	if !changed {
		t.Fatal("expected changed=true wiring into empty file")
	}
	if !claudeHookWired(path) {
		t.Fatal("hook not wired into previously-empty settings.json")
	}
}

func TestWireClaudeHookRejectsMalformedJSON(t *testing.T) {
	home := t.TempDir()
	path := claudeSettingsPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{ not json"), 0644); err != nil {
		t.Fatal(err)
	}
	// A malformed settings.json must not be silently overwritten — surface an error.
	if _, err := wireClaudeHookSettings(home); err == nil {
		t.Fatal("expected error on malformed settings.json, got nil")
	}
}

func decodePreToolUse(t *testing.T, settings map[string]json.RawMessage) []json.RawMessage {
	t.Helper()
	var hooks map[string]json.RawMessage
	if err := json.Unmarshal(settings["hooks"], &hooks); err != nil {
		t.Fatalf("decode hooks: %v", err)
	}
	var pre []json.RawMessage
	if err := json.Unmarshal(hooks["PreToolUse"], &pre); err != nil {
		t.Fatalf("decode PreToolUse: %v", err)
	}
	return pre
}

func preHasCommand(matchers []json.RawMessage, cmd string) bool {
	for _, m := range matchers {
		var block struct {
			Hooks []struct {
				Command string `json:"command"`
			} `json:"hooks"`
		}
		if json.Unmarshal(m, &block) != nil {
			continue
		}
		for _, h := range block.Hooks {
			if h.Command == cmd {
				return true
			}
		}
	}
	return false
}
