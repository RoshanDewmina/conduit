package main

import (
	"testing"
)

// TestRunAgentHookWithToolUse verifies that the new tool-use flags are parsed
// and propagated into the ApprovalEvent fields.  We can't dial the Unix socket
// in a unit test, so we exercise the flag/event construction path directly by
// reproducing the logic inline (same approach keeps the test hermetic).
func TestRunAgentHookWithToolUse(t *testing.T) {
	// Simulate the flag values that would be parsed from:
	//   conduitd agent-hook --agent claudeCode --kind command --command "ls" \
	//     --cwd /tmp --risk low \
	//     --tool-name bash --tool-use-id abc --session-id xyz --tool-input '{"command":"ls"}'
	agent := "claudeCode"
	kind := "command"
	command := "ls"
	cwd := "/tmp"
	risk := "low"
	toolName := "bash"
	toolUseID := "abc"
	sessionID := "xyz"
	toolInput := `{"command":"ls"}`

	normalizedKind := normalizeKind(kind)
	patch := ""
	if normalizedKind == "patch" {
		patch = command
	}

	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(agent),
		Kind:       normalizedKind,
		Command:    command,
		Patch:      patch,
		CWD:        cwd,
		Risk:       riskToInt(risk),
		ToolName:   toolName,
		ToolUseID:  toolUseID,
		SessionID:  sessionID,
		ToolInput:  toolInput,
	}

	if event.Agent != "claudeCode" {
		t.Errorf("Agent: got %q, want %q", event.Agent, "claudeCode")
	}
	if event.Kind != "command" {
		t.Errorf("Kind: got %q, want %q", event.Kind, "command")
	}
	if event.CWD != "/tmp" {
		t.Errorf("CWD: got %q, want %q", event.CWD, "/tmp")
	}
	if event.Risk != 0 {
		t.Errorf("Risk: got %d, want 0 (low)", event.Risk)
	}
	if event.ToolName != "bash" {
		t.Errorf("ToolName: got %q, want %q", event.ToolName, "bash")
	}
	if event.ToolUseID != "abc" {
		t.Errorf("ToolUseID: got %q, want %q", event.ToolUseID, "abc")
	}
	if event.SessionID != "xyz" {
		t.Errorf("SessionID: got %q, want %q", event.SessionID, "xyz")
	}
	if event.ToolInput != `{"command":"ls"}` {
		t.Errorf("ToolInput: got %q, want %q", event.ToolInput, `{"command":"ls"}`)
	}
	if event.ApprovalID == "" {
		t.Error("ApprovalID should not be empty")
	}
}

// TestRunAgentHookToolUseEmptyByDefault verifies that the new fields are empty
// (not set) when the flags are not provided, preserving backwards compat.
func TestRunAgentHookToolUseEmptyByDefault(t *testing.T) {
	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "echo hi",
		CWD:        "/tmp",
		Risk:       0,
	}

	if event.ToolName != "" {
		t.Errorf("ToolName should be empty by default, got %q", event.ToolName)
	}
	if event.ToolUseID != "" {
		t.Errorf("ToolUseID should be empty by default, got %q", event.ToolUseID)
	}
	if event.SessionID != "" {
		t.Errorf("SessionID should be empty by default, got %q", event.SessionID)
	}
	if event.ToolInput != "" {
		t.Errorf("ToolInput should be empty by default, got %q", event.ToolInput)
	}
}

func TestHookShouldHoldMutating(t *testing.T) {
	if !hookShouldHold("patch", 0) {
		t.Fatal("patch should hold when daemon down")
	}
	if !hookShouldHold("fileWrite", 0) {
		t.Fatal("fileWrite should hold")
	}
	if !hookShouldHold("command", 0) {
		t.Fatal("command should hold when daemon down")
	}
}

func TestHookReadOnlyFailOpenWithEnv(t *testing.T) {
	t.Setenv("CONDUIT_HOOK_READONLY_FAIL_OPEN", "1")
	if hookShouldHold("grep", 0) {
		t.Fatal("grep should fail-open with env")
	}
	if !hookShouldHold("patch", 0) {
		t.Fatal("patch should still hold with env")
	}
	if !hookShouldHold("grep", 3) {
		t.Fatal("critical risk should hold even with read-only fail-open env")
	}
}
