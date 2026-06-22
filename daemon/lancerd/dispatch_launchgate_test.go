package main

import "testing"

// askDefaultEval forces the fail-closed default ("ask", fromDefault=true) so we
// exercise the launch escalation. askRuleEval is an EXPLICIT ask rule
// (fromDefault=false) which must never be relaxed.
func askDefaultEval(ApprovalEvent) (string, string, bool) { return "ask", "default", true }
func askRuleEval(ApprovalEvent) (string, string, bool)    { return "ask", "explicit-rule", false }

// claudeWired is the hook-wired predicate the server installs for a host where
// the Claude PreToolUse hook is actually registered.
func claudeWired(bin string) bool { return bin == "claude" }

func newTestDispatcher() *dispatcher {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	d.hookWired = claudeWired
	return d
}

func TestRelaxLaunchEscalation(t *testing.T) {
	// Default ask + hook verifiably wired → relaxed to allow (only for that agent).
	if got := relaxLaunchEscalation("ask", true, []string{"claude", "-p", "hi"}, claudeWired); got != "allow" {
		t.Errorf("claude default-ask + wired → %q, want allow", got)
	}
	// Hook NOT wired (e.g. OpenCode TODO, or Claude not installed) → stays ask.
	if got := relaxLaunchEscalation("ask", true, []string{"opencode", "run"}, claudeWired); got != "ask" {
		t.Errorf("opencode default-ask (hook not wired) → %q, want ask", got)
	}
	if got := relaxLaunchEscalation("ask", true, []string{"claude", "-p", "hi"}, nil); got != "ask" {
		t.Errorf("claude with nil hookWired → %q, want ask (fail-closed)", got)
	}
	// Explicit ask RULE (fromDefault=false) is never relaxed, even for a wired agent.
	if got := relaxLaunchEscalation("ask", false, []string{"claude", "-p", "hi"}, claudeWired); got != "ask" {
		t.Errorf("claude explicit-ask rule → %q, want ask (no silent downgrade)", got)
	}
	// Non-hook agents keep their launch escalation.
	if got := relaxLaunchEscalation("ask", true, []string{"codex", "exec"}, claudeWired); got != "ask" {
		t.Errorf("codex default-ask → %q, want ask", got)
	}
	// An explicit deny is never relaxed.
	if got := relaxLaunchEscalation("deny", true, []string{"claude", "-p", "hi"}, claudeWired); got != "deny" {
		t.Errorf("claude deny → %q, want deny", got)
	}
}

// The owner's bug: with the fail-closed default, a Claude dispatch + every
// follow-up returned needsApproval. With the hook wired, the launch now starts.
func TestDispatchClaudeUnderAskDefaultStarts(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askDefaultEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("claude dispatch (hook wired) → %q (%s), want started", res.Status, res.Message)
	}
}

func TestContinueClaudeUnderAskDefaultStarts(t *testing.T) {
	d := newTestDispatcher()
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askDefaultEval, noAudit)
	if first.Status != "started" {
		t.Fatalf("setup dispatch → %q, want started", first.Status)
	}
	cont := d.continueRun(first.RunID, "again", askDefaultEval, noAudit)
	if cont.Status != "started" {
		t.Fatalf("claude continue (hook wired) → %q (%s), want started", cont.Status, cont.Message)
	}
	if cont.RunID == first.RunID || cont.RunID == "" {
		t.Fatalf("continue must allocate a new runId, got %q", cont.RunID)
	}
}

// Fail-closed: when the Claude hook is NOT wired, the launch must still escalate
// (the per-action gate the relaxation relies on isn't there).
func TestDispatchClaudeWithoutWiredHookEscalates(t *testing.T) {
	d := newDispatcher()
	d.launch = func([]string, string, string, emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	d.hookWired = func(string) bool { return false } // hook not installed
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askDefaultEval, noAudit)
	if res.Status != "needsApproval" {
		t.Fatalf("claude dispatch (hook NOT wired) → %q, want needsApproval", res.Status)
	}
}

// An EXPLICIT ask rule is authoritative and must not be silently downgraded,
// even for a hook-wired agent.
func TestDispatchClaudeExplicitAskRuleEscalates(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askRuleEval, noAudit)
	if res.Status != "needsApproval" {
		t.Fatalf("claude dispatch (explicit ask rule) → %q, want needsApproval", res.Status)
	}
}

// Non-hook agents (Codex/Kimi) have no per-action gate, so the launch escalation
// is their only guard and must be preserved under the ask default.
func TestDispatchCodexUnderAskDefaultNeedsApproval(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "codex", CWD: "/repo", Prompt: "hi"}, askDefaultEval, noAudit)
	if res.Status != "needsApproval" {
		t.Fatalf("codex dispatch under ask-default → %q, want needsApproval", res.Status)
	}
}

// A deny rule still blocks a hook-gated agent.
func TestDispatchClaudeDenyStillDenied(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, denyEval, noAudit)
	if res.Status != "denied" {
		t.Fatalf("claude dispatch with deny rule → %q, want denied", res.Status)
	}
}
