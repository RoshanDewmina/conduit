package main

import (
	"strings"

	"conduit/conduitd/policy"
)

// policyRequest maps a hook event into the policy engine input.
func policyRequest(event ApprovalEvent) policy.Request {
	tool := event.ToolName
	if tool == "" {
		tool = event.Kind
	}
	risk := -1
	if event.Risk >= 0 {
		risk = event.Risk
	}
	return policy.Request{
		Agent:   event.Agent,
		Tool:    tool,
		Kind:    event.Kind,
		Command: event.Command,
		CWD:     event.CWD,
		Risk:    risk,
	}
}

// allowRuleFromEvent builds an allow rule persisted on approve-always (policy-always.yaml).
func allowRuleFromEvent(event ApprovalEvent) policy.Rule {
	tool := event.ToolName
	if tool == "" {
		tool = event.Kind
	}
	prefix := strings.TrimSpace(event.Command)
	if len(prefix) > 120 {
		prefix = prefix[:120]
	}
	return policy.AllowRuleFromPrefix(event.Agent, tool, prefix)
}
