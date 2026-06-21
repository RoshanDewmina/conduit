package main

import "testing"

// askEvalLocal forces the fail-closed default ("ask") so we exercise the launch
// escalation. Named distinctly to avoid clashing with any shared stub.
func askEvalLocal(ApprovalEvent) (string, string) { return "ask", "default" }

func newTestDispatcher() *dispatcher {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	return d
}

func TestRelaxLaunchEscalation(t *testing.T) {
	// Hook-gated agents: an "ask" on the launch is relaxed to "allow".
	if got := relaxLaunchEscalation("ask", []string{"claude", "-p", "hi"}); got != "allow" {
		t.Errorf("claude ask → %q, want allow", got)
	}
	if got := relaxLaunchEscalation("ask", []string{"opencode", "run", "x"}); got != "allow" {
		t.Errorf("opencode ask → %q, want allow", got)
	}
	// Non-hook agents keep their launch escalation.
	if got := relaxLaunchEscalation("ask", []string{"codex", "exec"}); got != "ask" {
		t.Errorf("codex ask → %q, want ask", got)
	}
	if got := relaxLaunchEscalation("ask", []string{"kimi", "x"}); got != "ask" {
		t.Errorf("kimi ask → %q, want ask", got)
	}
	// An explicit deny is never relaxed.
	if got := relaxLaunchEscalation("deny", []string{"claude", "-p", "hi"}); got != "deny" {
		t.Errorf("claude deny → %q, want deny", got)
	}
}

// The owner's bug: with the fail-closed default ("ask"), a Claude dispatch and
// every follow-up returned needsApproval, so only the first message could be
// sent. Hook-gated agents must now launch (the PreToolUse hook still gates the
// agent's actual tool actions).
func TestDispatchClaudeUnderAskDefaultStarts(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askEvalLocal, noAudit)
	if res.Status != "started" {
		t.Fatalf("claude dispatch under ask-default → %q (%s), want started", res.Status, res.Message)
	}
}

func TestContinueClaudeUnderAskDefaultStarts(t *testing.T) {
	d := newTestDispatcher()
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "hi"}, askEvalLocal, noAudit)
	if first.Status != "started" {
		t.Fatalf("setup dispatch → %q, want started", first.Status)
	}
	cont := d.continueRun(first.RunID, "again", askEvalLocal, noAudit)
	if cont.Status != "started" {
		t.Fatalf("claude continue under ask-default → %q (%s), want started", cont.Status, cont.Message)
	}
	if cont.RunID == first.RunID || cont.RunID == "" {
		t.Fatalf("continue must allocate a new runId, got %q", cont.RunID)
	}
}

// Non-hook agents (Codex/Kimi) have no per-action gate, so the launch escalation
// is their only guard and must be preserved under the ask default.
func TestDispatchCodexUnderAskDefaultNeedsApproval(t *testing.T) {
	d := newTestDispatcher()
	res := d.dispatch(dispatchParams{Agent: "codex", CWD: "/repo", Prompt: "hi"}, askEvalLocal, noAudit)
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
