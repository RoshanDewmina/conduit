package main

import (
	"encoding/json"
	"testing"

	"conduit/conduitd/policy"
)

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
