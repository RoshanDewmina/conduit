package main

import (
	"encoding/json"
	"os"
	"testing"
	"time"

	"conduit/conduitd/policy"
)

// The poll-delivered path (poller → applyDecision) must persist an approveAlways
// decision to the always-policy AND write an audit entry — IDENTICALLY to the
// live-SSH agent.approval.response path, which now routes through the same
// applyDecision. This closes the conduitd poll-path governance gap.
func TestApplyDecisionApproveAlwaysPersistsPolicyAndAudit(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)

	event := ApprovalEvent{
		ApprovalID: "appr-poll-1",
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "echo hi",
		CWD:        home,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	_ = s.approvals.add(event)

	if _, ok := s.applyDecision("appr-poll-1", "approveAlways", ""); !ok {
		t.Fatal("applyDecision did not resolve a pending approval")
	}

	// Audit: a human-decision entry with the approveAlways action + approvalId.
	entries, err := s.audit.tail(20)
	if err != nil {
		t.Fatal(err)
	}
	var audited bool
	for _, e := range entries {
		if e.ApprovalID == "appr-poll-1" && e.Action == "approveAlways" {
			audited = true
		}
	}
	if !audited {
		t.Fatalf("approveAlways not audited; entries=%+v", entries)
	}

	// Policy: the always-policy file now exists and carries an allow rule.
	if _, err := os.Stat(policy.AlwaysPolicyPath(home)); err != nil {
		t.Fatalf("always-policy not written: %v", err)
	}
	doc, err := policy.LoadFile(policy.AlwaysPolicyPath(home))
	if err != nil {
		t.Fatalf("load always-policy: %v", err)
	}
	if len(doc.Rules) == 0 {
		t.Fatal("always-policy has no rules after approveAlways")
	}
}

// A poll-delivered plain approve is audited but writes no always-rule.
func TestApplyDecisionApproveAuditedNoPolicy(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	event := ApprovalEvent{ApprovalID: "appr-poll-2", Agent: "codex", Kind: "command", Command: "ls", CWD: home}
	_ = s.approvals.add(event)

	if _, ok := s.applyDecision("appr-poll-2", "approve", ""); !ok {
		t.Fatal("applyDecision did not resolve")
	}
	if _, err := os.Stat(policy.AlwaysPolicyPath(home)); !os.IsNotExist(err) {
		t.Fatalf("plain approve must not write always-policy (err=%v)", err)
	}
	entries, _ := s.audit.tail(20)
	var audited bool
	for _, e := range entries {
		if e.ApprovalID == "appr-poll-2" && e.Action == "approve" {
			audited = true
		}
	}
	if !audited {
		t.Fatal("approve not audited")
	}
}

func TestPolicyEngineFileWriteEscalates(t *testing.T) {
	home := t.TempDir()
	globalPath := policy.GlobalPolicyPath(home)
	doc := policy.Document{
		Default: string(policy.EffectAsk),
		Rules: []policy.Rule{
			{ID: "ask-file-write", Effect: string(policy.EffectAsk), Kind: "fileWrite"},
		},
	}
	if err := policy.SaveFile(globalPath, doc); err != nil {
		t.Fatal(err)
	}
	e := newPolicyEngine(home)
	event := ApprovalEvent{
		ApprovalID: "id-1",
		Agent:      "claudeCode",
		Kind:       "fileWrite",
		Command:    "notes.txt",
		CWD:        "/tmp",
		Risk:       0,
	}
	res := e.evaluate(event)
	if res.Effect != policy.EffectAsk {
		t.Fatalf("expected ask for fileWrite, got %v (%s)", res.Effect, res.MatchedRule)
	}
}

func TestPolicyEngineAutoAllow(t *testing.T) {
	home := t.TempDir()
	globalPath := policy.GlobalPolicyPath(home)
	doc := policy.Document{
		Default: string(policy.EffectAsk),
		Rules: []policy.Rule{
			{Effect: string(policy.EffectAllow), Match: "echo*"},
		},
	}
	if err := policy.SaveFile(globalPath, doc); err != nil {
		t.Fatal(err)
	}

	e := newPolicyEngine(home)
	event := ApprovalEvent{
		ApprovalID: "id-1",
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "echo hello",
		CWD:        t.TempDir(),
	}
	res := e.evaluate(event)
	if res.Effect != policy.EffectAllow {
		t.Fatalf("expected allow, got %v (%s)", res.Effect, res.MatchedRule)
	}
}

func TestAuditTailRPC(t *testing.T) {
	home := t.TempDir()
	s := &server{
		approvals: newApprovalStore(),
		audit:     newAuditLog(home),
	}
	_ = s.audit.append(AuditEntry{Action: "policy", Effect: "allow", Agent: "codex"})

	params, _ := json.Marshal(map[string]int{"limit": 5})
	msg := &rpcMessage{JSONRPC: "2.0", ID: 9, Method: "agent.audit.tail", Params: params}
	s.handleMessage(msg)
}
