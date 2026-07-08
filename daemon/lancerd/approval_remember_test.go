package main

import (
	"testing"
	"time"

	"lancer/lancerd/policy"
)

// approve with a valid, scoped, expiring rule persists it — and the next
// identical hook event auto-allows without prompting.
func TestApproveAndRememberValidRulePersistsAndAutoAllows(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)

	event := ApprovalEvent{
		ApprovalID: "remember-1",
		Agent:      "claudeCode",
		Kind:       "command",
		ToolName:   "bash",
		Command:    "npm test",
		CWD:        home,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	ch := s.approvals.add(event)
	_ = ch

	rule := &policy.Rule{
		ID:        "remember-1-rule",
		Effect:    string(policy.EffectAllow),
		Agent:     "claudeCode",
		Tool:      "bash",
		ExpiresAt: time.Now().UTC().Add(7 * 24 * time.Hour).Format(time.RFC3339),
	}

	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve the pending approval")
	}
	s.applyAllowRule(resolved, rule)

	doc, err := policy.LoadFile(policy.AlwaysPolicyPath(home))
	if err != nil {
		t.Fatalf("load always-policy: %v", err)
	}
	if len(doc.Rules) != 1 {
		t.Fatalf("expected 1 remembered rule, got %d (%+v)", len(doc.Rules), doc.Rules)
	}

	// The next identical hook event (same agent/tool) now auto-allows.
	next := ApprovalEvent{
		ApprovalID: "remember-2",
		Agent:      "claudeCode",
		Kind:       "command",
		ToolName:   "bash",
		Command:    "npm test",
		CWD:        home,
	}
	res := s.policy.evaluate(next)
	if res.Effect != policy.EffectAllow {
		t.Fatalf("expected auto-allow from remembered rule, got %v (%s)", res.Effect, res.MatchedRule)
	}
}

// A rule with no ExpiresAt must be rejected — not persisted.
func TestApproveAndRememberRejectsMissingExpiry(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "remember-noexp", Agent: "codex", Kind: "command", Command: "ls", CWD: home}
	s.approvals.add(event)

	rule := &policy.Rule{Effect: string(policy.EffectAllow), Tool: "bash"}
	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve")
	}
	s.applyAllowRule(resolved, rule)

	if err := policy.ValidateAllowRule(*rule); err == nil {
		t.Fatal("expected ValidateAllowRule to reject a rule with no ExpiresAt")
	}
	assertNoAlwaysPolicy(t, home)
}

// A rule expiring more than 30 days out must be rejected — not persisted.
func TestApproveAndRememberRejectsExpiryBeyond30Days(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "remember-toolong", Agent: "codex", Kind: "command", Command: "ls", CWD: home}
	s.approvals.add(event)

	rule := &policy.Rule{
		Effect:    string(policy.EffectAllow),
		Tool:      "bash",
		ExpiresAt: time.Now().UTC().Add(31 * 24 * time.Hour).Format(time.RFC3339),
	}
	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve")
	}
	s.applyAllowRule(resolved, rule)

	if err := policy.ValidateAllowRule(*rule); err == nil {
		t.Fatal("expected ValidateAllowRule to reject a rule expiring beyond 30 days")
	}
	assertNoAlwaysPolicy(t, home)
}

// An unscoped rule (no Repo/PathPattern/Tool) must be rejected — not persisted.
func TestApproveAndRememberRejectsUnscopedRule(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "remember-unscoped", Agent: "codex", Kind: "command", Command: "ls", CWD: home}
	s.approvals.add(event)

	rule := &policy.Rule{
		Effect:    string(policy.EffectAllow),
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour).Format(time.RFC3339),
	}
	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve")
	}
	s.applyAllowRule(resolved, rule)

	if err := policy.ValidateAllowRule(*rule); err == nil {
		t.Fatal("expected ValidateAllowRule to reject an unscoped rule")
	}
	assertNoAlwaysPolicy(t, home)
}

// A rule with effect != allow must be rejected — not persisted.
func TestApproveAndRememberRejectsNonAllowEffect(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "remember-denyeffect", Agent: "codex", Kind: "command", Command: "ls", CWD: home}
	s.approvals.add(event)

	rule := &policy.Rule{
		Effect:    string(policy.EffectAsk),
		Tool:      "bash",
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour).Format(time.RFC3339),
	}
	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve")
	}
	s.applyAllowRule(resolved, rule)

	if err := policy.ValidateAllowRule(*rule); err == nil {
		t.Fatal("expected ValidateAllowRule to reject a non-allow effect")
	}
	assertNoAlwaysPolicy(t, home)
}

// A valid remembered rule's creation is written into the hash-chained audit log.
func TestApproveAndRememberAuditsRuleCreation(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "remember-audit", Agent: "claudeCode", Kind: "command", Command: "npm test", CWD: home}
	s.approvals.add(event)

	rule := &policy.Rule{
		Effect:    string(policy.EffectAllow),
		Tool:      "bash",
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour).Format(time.RFC3339),
	}
	resolved, ok := s.applyDecision(event.ApprovalID, "approve", "", "")
	if !ok {
		t.Fatal("applyDecision did not resolve")
	}
	s.applyAllowRule(resolved, rule)

	entries, err := s.audit.tail(20)
	if err != nil {
		t.Fatal(err)
	}
	var found bool
	for _, e := range entries {
		if e.ApprovalID == "remember-audit" && e.Action == "remember-rule" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected a remember-rule audit entry; entries=%+v", entries)
	}

	verify := s.audit.Verify()
	if !verify.Valid {
		t.Fatalf("audit chain broken at %d after remember-rule entry", verify.BrokenAt)
	}
}

func assertNoAlwaysPolicy(t *testing.T, home string) {
	t.Helper()
	doc, err := policy.LoadFile(policy.AlwaysPolicyPath(home))
	if err == nil && len(doc.Rules) != 0 {
		t.Fatalf("rejected rule must not be persisted; found rules=%+v", doc.Rules)
	}
}
