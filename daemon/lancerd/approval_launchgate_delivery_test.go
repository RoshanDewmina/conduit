package main

import (
	"encoding/json"
	"testing"
)

// askEval is a policy stub that always escalates — mirrors allowEval/denyEval
// in dispatch_test.go (which doesn't define an "ask" variant despite its
// comment claiming to).
func askEval(ApprovalEvent) (string, string, bool) { return "ask", "test-ask", false }

// approvalPendingMessage decodes a fakeRelayClient-captured "approval" send
// into its inner {type, payload} envelope, as e2eRouter.sendApproval writes it.
func approvalPendingMessage(t *testing.T, msgType string, data []byte) (innerType string, approvalID string) {
	t.Helper()
	if msgType != "approval" {
		t.Fatalf("expected relay msgType %q, got %q", "approval", msgType)
	}
	var env struct {
		Type    string `json:"type"`
		Payload struct {
			ApprovalID string `json:"approvalID"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		t.Fatalf("unmarshal approval envelope: %v", err)
	}
	return env.Type, env.Payload.ApprovalID
}

// TestLaunchConversationTurnAskDeliversApprovalOverRelay reproduces the
// 2026-07-16 Lane C bug: a conversation-append launch whose policy gate
// escalates to "ask" must actually deliver a decidable approvalPending card
// over the E2E relay (and register in s.approvals so a later peer_joined's
// resendPendingApprovals can also find it), not just return a synchronous
// dispatchResult{Status:"needsApproval"} and silently discard the event.
//
// Root cause (see docs/test-runs/2026-07-16-untested-feature-sweep/LC-report.md):
// launchConversationTurn's "ask" branch constructed a real ApprovalEvent (with
// its own ApprovalID/ContentHash) but never routed it through
// s.approvals.add/notify/e2e.sendApproval — dispatch.go:2627-2629 (pre-fix)
// just returned. This was NOT a pairing-timing race: it dropped the event on
// every "ask" launch outcome, paired or not, immediately or hours later.
func TestLaunchConversationTurnAskDeliversApprovalOverRelay(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client
	srv.setE2ERouter(router)

	cwd := t.TempDir()
	res := srv.dispatcher.launchConversationTurn("run-lc-repro", conversationLaunchParams{
		Agent: "claudeCode", CWD: cwd, Prompt: "run `pwd`, then git commit", IsNew: true,
	}, askEval, noAudit)

	if res.Status != "needsApproval" {
		t.Fatalf("launch status = %q, want needsApproval", res.Status)
	}

	msgType, data := client.lastMessage()
	if data == nil {
		t.Fatal("relay client received no message at all — approval was dropped, not delivered (the reproduced bug)")
	}
	innerType, approvalID := approvalPendingMessage(t, msgType, data)
	if innerType != "approvalPending" {
		t.Fatalf("relay envelope type = %q, want approvalPending", innerType)
	}
	if approvalID == "" {
		t.Fatal("delivered approval had no approvalID")
	}

	pending := srv.approvals.pendingEvents()
	if len(pending) != 1 {
		t.Fatalf("s.approvals.pendingEvents() = %d, want 1 (so a later peer_joined resend can also find it)", len(pending))
	}
	if pending[0].ApprovalID != approvalID {
		t.Fatalf("pending approval id %q != delivered approval id %q", pending[0].ApprovalID, approvalID)
	}
}

// TestLaunchConversationTurnAskDeliversApprovalAfterFreshPair reproduces the
// exact scenario LC-report describes: the relay just paired (fresh peer_joined,
// no churn), then the first send immediately escalates. Delivery must still
// succeed — this was never actually a timing race (see root-cause doc comment
// above), so pairing "settling" first isn't required for the fix to apply,
// but this test pins the literal reported repro shape.
func TestLaunchConversationTurnAskDeliversApprovalAfterFreshPair(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: false}
	router := newE2ERouter(nil, srv)
	router.client = client
	srv.setE2ERouter(router)

	// Simulate the relay's peer_joined firing right now (fresh pair).
	client.paired = true

	cwd := t.TempDir()
	res := srv.dispatcher.launchConversationTurn("run-lc-repro-2", conversationLaunchParams{
		Agent: "claudeCode", CWD: cwd, Prompt: "run `pwd`, then git commit", IsNew: true,
	}, askEval, noAudit)

	if res.Status != "needsApproval" {
		t.Fatalf("launch status = %q, want needsApproval", res.Status)
	}
	msgType, data := client.lastMessage()
	if data == nil {
		t.Fatal("relay client received no message — approval dropped on the immediate-post-pair send")
	}
	if innerType, _ := approvalPendingMessage(t, msgType, data); innerType != "approvalPending" {
		t.Fatalf("relay envelope type = %q, want approvalPending", innerType)
	}
}

// TestDispatchAskDeliversApprovalOverRelay covers the sibling launch-gate
// dispatch() (the plain first-turn path, distinct from conversation-append),
// which had the identical bug (dispatch.go's own "ask" branch discarded its
// ApprovalEvent the same way).
func TestDispatchAskDeliversApprovalOverRelay(t *testing.T) {
	home := t.TempDir()
	srv := newServer(home)
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client
	srv.setE2ERouter(router)

	cwd := t.TempDir()
	res := srv.dispatcher.dispatch(dispatchParams{
		Agent: "codex", CWD: cwd, Prompt: "run `pwd`, then git commit",
	}, askEval, noAudit)

	if res.Status != "needsApproval" {
		t.Fatalf("dispatch status = %q, want needsApproval", res.Status)
	}
	msgType, data := client.lastMessage()
	if data == nil {
		t.Fatal("relay client received no message — approval dropped")
	}
	if innerType, _ := approvalPendingMessage(t, msgType, data); innerType != "approvalPending" {
		t.Fatalf("relay envelope type = %q, want approvalPending", innerType)
	}
}
