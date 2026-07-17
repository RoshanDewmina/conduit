package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"lancer/lancerd/policy"
)

// TestPerCWDPermissionModeEscalateDiffers proves the acceptance gate: set
// allow for /tmp/repoA and ask for /tmp/repoB → evaluate differs; global
// default untouched; override survives a new policyEngine (restart).
func TestPerCWDPermissionModeEscalateDiffers(t *testing.T) {
	home := t.TempDir()
	repoA := filepath.Join(home, "repoA")
	repoB := filepath.Join(home, "repoB")

	// Global default stays ask (bundled / explicit).
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), policy.Document{
		Default: string(policy.EffectAsk),
		Rules:   nil, // unmatched → default only, so override is observable
	}); err != nil {
		t.Fatal(err)
	}

	eng := newPolicyEngine(home)
	if err := eng.setPermissionMode("allow", repoA); err != nil {
		t.Fatal(err)
	}
	if err := eng.setPermissionMode("ask", repoB); err != nil {
		t.Fatal(err)
	}

	// Global document default must be untouched.
	doc, err := policy.LoadFile(policy.GlobalPolicyPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if doc.Default != "ask" {
		t.Fatalf("global Default = %q, want ask (untouched)", doc.Default)
	}
	if eng.getPermissionMode("~") != "ask" {
		t.Fatalf("global getPermissionMode = %q, want ask", eng.getPermissionMode("~"))
	}
	if eng.getPermissionMode(repoA) != "allow" {
		t.Fatalf("repoA mode = %q, want allow", eng.getPermissionMode(repoA))
	}
	if eng.getPermissionMode(repoB) != "ask" {
		t.Fatalf("repoB mode = %q, want ask", eng.getPermissionMode(repoB))
	}

	// Same action, different cwd → different escalate decision.
	eventA := ApprovalEvent{Agent: "claudeCode", Kind: "command", Command: "echo hi", CWD: repoA}
	eventB := ApprovalEvent{Agent: "claudeCode", Kind: "command", Command: "echo hi", CWD: repoB}
	resA := eng.evaluate(eventA)
	resB := eng.evaluate(eventB)
	if resA.Effect != policy.EffectAllow || resA.ShouldEscalate {
		t.Fatalf("repoA evaluate = %+v, want allow / no escalate", resA)
	}
	if resA.Scope == "" {
		t.Fatal("repoA result must set Scope for audit")
	}
	if resB.Effect != policy.EffectAsk || !resB.ShouldEscalate {
		t.Fatalf("repoB evaluate = %+v, want ask / escalate", resB)
	}
	if resB.Scope == "" {
		t.Fatal("repoB result must set Scope for audit")
	}

	// Restart: new engine instance against same home.
	eng2 := newPolicyEngine(home)
	resA2 := eng2.evaluate(eventA)
	resB2 := eng2.evaluate(eventB)
	if resA2.Effect != policy.EffectAllow {
		t.Fatalf("after restart repoA = %v, want allow", resA2.Effect)
	}
	if resB2.Effect != policy.EffectAsk {
		t.Fatalf("after restart repoB = %v, want ask", resB2.Effect)
	}
	doc2, err := policy.LoadFile(policy.GlobalPolicyPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if doc2.Default != "ask" {
		t.Fatalf("after restart global Default = %q, want ask", doc2.Default)
	}
}

func TestPerCWDPermissionModeCorruptFallsBackToDocumentDefault(t *testing.T) {
	home := t.TempDir()
	repo := filepath.Join(home, "repo")
	if err := policy.SaveFile(policy.GlobalPolicyPath(home), policy.Document{
		Default: string(policy.EffectDeny),
	}); err != nil {
		t.Fatal(err)
	}
	path := policy.CWDOverridePath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("not: [valid yaml"), 0600); err != nil {
		t.Fatal(err)
	}

	eng := newPolicyEngine(home)
	res := eng.evaluate(ApprovalEvent{
		Agent: "claudeCode", Kind: "command", Command: "echo hi", CWD: repo,
	})
	if res.Effect != policy.EffectDeny {
		t.Fatalf("corrupt override must fall back to document default deny, got %v", res.Effect)
	}
	if res.Scope != "" {
		t.Fatalf("corrupt override must not set Scope, got %q", res.Scope)
	}
	if eng.getPermissionMode(repo) != "deny" {
		t.Fatalf("getPermissionMode with corrupt file = %q, want document deny", eng.getPermissionMode(repo))
	}
}

func TestSetPermissionModeAuditedIncludesScope(t *testing.T) {
	home := t.TempDir()
	repo := filepath.Join(home, "scoped-repo")
	s := newServer(home)
	defer s.poller.stopForTest()

	if err := s.setPermissionModeAudited("allow", "relay-phone", repo); err != nil {
		t.Fatal(err)
	}
	entries, err := s.audit.tail(10)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	wantScope := "scope=" + policy.NormalizeCWD(repo)
	for _, e := range entries {
		if e.Action == "policy-mode-set" && e.Effect == "allow" && strings.Contains(e.Rule, wantScope) {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected policy-mode-set with %q in Rule, got %+v", wantScope, entries)
	}
}
