package main

import "testing"

// Each vendor's hook invokes `lancerd agent-hook` with the same flags; this
// asserts the agent name normalization + structured fields survive into an
// ApprovalEvent for all three vendors.
func TestAgentHookBuildsStructuredEventPerVendor(t *testing.T) {
	cases := []struct {
		agentFlag string
		wantAgent string
	}{
		{"claudeCode", "claudeCode"},
		{"codex", "codex"},
		{"opencode", "opencode"},
	}
	for _, tc := range cases {
		ev := buildApprovalEventForTest(
			tc.agentFlag, "command", "rm -rf build/", "/repo",
			"high", "Bash", "tool-use-123", "sess-9", `{"command":"rm -rf build/"}`,
		)
		if ev.Agent != tc.wantAgent {
			t.Fatalf("%s: agent = %q, want %q", tc.agentFlag, ev.Agent, tc.wantAgent)
		}
		if ev.ToolName != "Bash" || ev.ToolUseID != "tool-use-123" ||
			ev.SessionID != "sess-9" || ev.ToolInput == "" {
			t.Fatalf("%s: structured fields not carried: %+v", tc.agentFlag, ev)
		}
		if ev.Kind != "command" || ev.Risk != 2 {
			t.Fatalf("%s: kind/risk wrong: kind=%s risk=%d", tc.agentFlag, ev.Kind, ev.Risk)
		}
		if ev.ApprovalID == "" || ev.Timestamp == "" {
			t.Fatalf("%s: missing id/timestamp", tc.agentFlag)
		}
	}
}
