package main

import (
	"testing"
	"time"
)

// TestConversationAppendApprovalResumesLaunch reproduces the bug found live by
// Lane C2 (docs/test-runs/2026-07-16-untested-feature-sweep/LC2-report.md,
// this repo's .worktrees/untested-sweep-2026-07-16 copy): the
// first-send-approval-race fix (commit 065481d9) made launchConversationTurn's
// "ask" branch actually DELIVER its ApprovalEvent as a decidable card over the
// relay (fixed) — but resolving that card (applyDecision → approvals.resolve)
// never resumed the launch it was gating. deliverLaunchApproval's returned
// decision channel was constructed and then unconditionally discarded
// (dispatch.go's pre-fix comment: "Fire-and-forget ... the decision channel is
// intentionally not awaited here"), so an "approve" decision was recorded in
// the audit log and nowhere else — no claude process ever spawned, the target
// repo's git log never changed, and the phone was stuck on "Couldn't get a
// reply" forever. This test proves the actual, observable signal a real user
// cares about: the daemon's launch func gets invoked with the real argv after
// approve, not just that an audit line was written.
//
// This was verified failing pre-fix (before resumeConversationLaunchOnApproval
// existed and deliverLaunchApproval's return value was discarded): the test
// below timed out waiting on launchedCh because approvals.resolve() had
// nothing downstream reading its decision channel. Confirmed by temporarily
// reverting dispatch.go to the pre-fix shape (git stash) and re-running this
// exact test — see PR description / session notes for the captured
// `--- FAIL ... timed out waiting for launch to resume after approve` output.
func TestConversationAppendApprovalResumesLaunch(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	launchedCh := make(chan []string, 1)
	srv.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchedCh <- argv
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	cwd := t.TempDir()
	runID := "run-conv-append-resume"
	res := srv.dispatcher.launchConversationTurn(runID, conversationLaunchParams{
		Agent: "claudeCode", CWD: cwd, Prompt: "run `pwd`, then git commit", IsNew: true,
	}, askEval, noAudit)

	if res.Status != "needsApproval" {
		t.Fatalf("launchConversationTurn status = %q, want needsApproval", res.Status)
	}

	// Nothing should have launched yet — the ask gate must not run the process
	// until a decision arrives.
	select {
	case argv := <-launchedCh:
		t.Fatalf("launch invoked BEFORE any approval decision was made (argv=%v)", argv)
	case <-time.After(50 * time.Millisecond):
	}

	pending := srv.approvals.pendingEvents()
	if len(pending) != 1 {
		t.Fatalf("s.approvals.pendingEvents() = %d, want 1 pending launch-gate approval", len(pending))
	}
	event := pending[0]
	if event.RunID != runID {
		t.Fatalf("pending approval RunID = %q, want %q", event.RunID, runID)
	}

	// Simulate the phone tapping Approve — the exact call applyDecision makes
	// for a live agent.approval.response RPC or relay decision.
	if _, ok := srv.applyDecision(event.ApprovalID, "approve", "", event.ContentHash); !ok {
		t.Fatalf("applyDecision(%q, approve) failed to resolve the pending approval", event.ApprovalID)
	}

	select {
	case argv := <-launchedCh:
		if len(argv) == 0 {
			t.Fatal("resumed launch invoked with empty argv")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for launch to resume after approve — approving a conversation-append's ask gate must actually launch the CLI, not silently do nothing (the LC2 bug)")
	}

	// The run must now be tracked as running, exactly like an auto-allowed
	// launch — proving the resumed path went through the SAME launch
	// bookkeeping (d.runs registration), not a shortcut.
	srv.dispatcher.mu.Lock()
	run, tracked := srv.dispatcher.runs[runID]
	srv.dispatcher.mu.Unlock()
	if !tracked {
		t.Fatalf("runID %q not present in dispatcher.runs after resumed launch", runID)
	}
	if run.Status != "running" {
		t.Fatalf("run.Status = %q, want running", run.Status)
	}
}

// TestConversationAppendApprovalDenyDoesNotLaunch is the negative counterpart:
// a deny decision on the same pending launch-gate approval must never resume
// the launch.
func TestConversationAppendApprovalDenyDoesNotLaunch(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	launchedCh := make(chan []string, 1)
	srv.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launchedCh <- argv
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}

	cwd := t.TempDir()
	runID := "run-conv-append-deny"
	res := srv.dispatcher.launchConversationTurn(runID, conversationLaunchParams{
		Agent: "claudeCode", CWD: cwd, Prompt: "run `pwd`, then git commit", IsNew: true,
	}, askEval, noAudit)
	if res.Status != "needsApproval" {
		t.Fatalf("launchConversationTurn status = %q, want needsApproval", res.Status)
	}

	pending := srv.approvals.pendingEvents()
	if len(pending) != 1 {
		t.Fatalf("s.approvals.pendingEvents() = %d, want 1", len(pending))
	}
	event := pending[0]

	if _, ok := srv.applyDecision(event.ApprovalID, "deny", "", event.ContentHash); !ok {
		t.Fatalf("applyDecision(%q, deny) failed to resolve", event.ApprovalID)
	}

	select {
	case argv := <-launchedCh:
		t.Fatalf("launch invoked after a DENY decision (argv=%v)", argv)
	case <-time.After(200 * time.Millisecond):
	}

	srv.dispatcher.mu.Lock()
	_, tracked := srv.dispatcher.runs[runID]
	srv.dispatcher.mu.Unlock()
	if tracked {
		t.Fatalf("runID %q should not be tracked in dispatcher.runs after a deny", runID)
	}
}
