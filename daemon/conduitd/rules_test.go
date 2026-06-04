package main

import (
	"testing"

	"conduit/conduitd/policy"
)

func TestPolicyRequestUsesToolName(t *testing.T) {
	event := ApprovalEvent{
		Agent:    "claudeCode",
		Kind:     "command",
		Command:  "npm test",
		ToolName: "Bash",
		CWD:      "/repo",
	}
	req := policyRequest(event)
	if req.Tool != "Bash" {
		t.Fatalf("tool = %q", req.Tool)
	}
}

func TestAllowRuleFromEvent(t *testing.T) {
	event := ApprovalEvent{
		Agent:    "codex",
		ToolName: "shell",
		Command:  "make test",
	}
	rule := allowRuleFromEvent(event)
	if rule.Effect != string(policy.EffectAllow) {
		t.Fatalf("effect = %q", rule.Effect)
	}
	if rule.Match != "make test*" {
		t.Fatalf("match = %q", rule.Match)
	}
}

func TestAllowRuleFromEventFallsBackToKind(t *testing.T) {
	event := ApprovalEvent{Agent: "claudeCode", Kind: "patch", Command: "apply diff"}
	rule := allowRuleFromEvent(event)
	if rule.Tool != "patch" {
		t.Fatalf("tool = %q", rule.Tool)
	}
}
