package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"lancer/lancerd/policy"
)

// shipTestRunner passes real git subcommands through to realGitRunner (so the
// e2e test exercises actual git plumbing against a throwaway local fixture
// repo) while faking the gh call boundary — no real GitHub, no network,
// matching the fakeRunner-style subprocess mocking already used in
// git_test.go. Every invocation is recorded so tests can assert exactly what
// ran (in particular: never a merge).
type shipTestRunner struct {
	mu       sync.Mutex
	calls    []string
	ghAuthOK bool
	prURL    string
	prFails  string // when non-empty, "gh pr create" fails with this output
}

func newShipTestRunner() *shipTestRunner {
	return &shipTestRunner{ghAuthOK: true, prURL: "https://github.com/o/r/pull/1"}
}

func (f *shipTestRunner) run(workdir, tool string, args ...string) (string, error) {
	f.mu.Lock()
	f.calls = append(f.calls, tool+" "+strings.Join(args, " "))
	f.mu.Unlock()

	if tool == "gh" {
		switch {
		case len(args) >= 1 && args[0] == "--version":
			return "gh version 2.0.0\n", nil
		case len(args) >= 2 && args[0] == "auth" && args[1] == "status":
			if f.ghAuthOK {
				return "Logged in to github.com\n", nil
			}
			return "", &gitCmdError{exitCode: 1, output: "not logged in"}
		case len(args) >= 2 && args[0] == "pr" && args[1] == "create":
			if f.prFails != "" {
				return f.prFails, &gitCmdError{exitCode: 1, output: f.prFails}
			}
			return f.prURL + "\n", nil
		case len(args) >= 2 && args[0] == "pr" && args[1] == "view":
			return f.prURL, nil
		default:
			return "", nil
		}
	}
	// Every other tool (git) runs for real against the fixture repo.
	return realGitRunner(workdir, tool, args...)
}

func (f *shipTestRunner) callLog() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.calls...)
}

// setupShipFixtureRepo creates a throwaway local "remote" (bare) repo and a
// working checkout pointed at it via `origin`, with one commit already
// pushed — enough for a real ls-remote / push / gh-pr round trip without ever
// touching a real GitHub host.
func setupShipFixtureRepo(t *testing.T) (workDir, base string) {
	t.Helper()
	dir := t.TempDir()
	remoteDir := filepath.Join(dir, "remote.git")
	workDir = filepath.Join(dir, "work")

	run := func(cwd string, args ...string) string {
		t.Helper()
		out, err := realGitRunner(cwd, "git", args...)
		if err != nil {
			t.Fatalf("git %v (cwd=%s) failed: %v (%s)", args, cwd, err, out)
		}
		return out
	}

	run(dir, "init", "--bare", "remote.git")
	run(dir, "init", "work")
	run(workDir, "config", "user.email", "test@example.com")
	run(workDir, "config", "user.name", "Test")
	run(workDir, "remote", "add", "origin", remoteDir)

	if err := os.WriteFile(filepath.Join(workDir, "README.md"), []byte("hello\n"), 0644); err != nil {
		t.Fatalf("write fixture file: %v", err)
	}
	run(workDir, "add", "-A")
	run(workDir, "commit", "-m", "init")

	base = strings.TrimSpace(run(workDir, "rev-parse", "--abbrev-ref", "HEAD"))
	run(workDir, "push", "-u", "origin", base)
	return workDir, base
}

// waitForShipResult drains notifications emitted via s.setEmitter until it
// finds an agent.ship.result for wantApprovalID, or the timeout fires.
func waitForShipResult(t *testing.T, ch <-chan shipActionOutcome, wantApprovalID string) shipActionOutcome {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case outcome := <-ch:
			if outcome.ApprovalID == wantApprovalID {
				return outcome
			}
		case <-deadline:
			t.Fatalf("timed out waiting for agent.ship.result for approval %s", wantApprovalID)
		}
	}
}

func shipResultEmitter(t *testing.T, s *server) <-chan shipActionOutcome {
	t.Helper()
	ch := make(chan shipActionOutcome, 4)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		if err := json.Unmarshal(data, &m); err != nil {
			return nil
		}
		if m.Method != "agent.ship.result" {
			return nil
		}
		var outcome shipActionOutcome
		if err := json.Unmarshal(m.Params, &outcome); err != nil {
			return nil
		}
		select {
		case ch <- outcome:
		default:
		}
		return nil
	})
	return ch
}

// TestShipActionsRiskIsAlwaysHigh locks the fixed risk tier structurally: a
// ship action must be impossible to silently downgrade below "high"
// (policy.RiskLabel/riskOrder — value 2), independent of any caller input.
func TestShipActionsRiskIsAlwaysHigh(t *testing.T) {
	if shipActionRisk != 2 {
		t.Fatalf("shipActionRisk = %d, want 2", shipActionRisk)
	}
	if got := policy.RiskLabel(shipActionRisk); got != "high" {
		t.Fatalf("policy.RiskLabel(shipActionRisk) = %q, want %q", got, "high")
	}
}

func TestShipActionsPreflightReportsReasonsWhenNotReady(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, _ := setupShipFixtureRepo(t)

	f := &shipTestRunner{ghAuthOK: false} // gh installed but not authenticated
	s.git = f.run

	pre := s.shipPreflight(workDir)
	if pre.Ready {
		t.Fatalf("preflight = %+v, want Ready=false (gh not authenticated)", pre)
	}
	if !pre.HasRemote || !pre.RemoteReachable {
		t.Fatalf("preflight = %+v, want HasRemote/RemoteReachable true (real local remote)", pre)
	}
	if pre.GHAuthenticated {
		t.Fatalf("preflight = %+v, want GHAuthenticated=false", pre)
	}
	found := false
	for _, r := range pre.Reasons {
		if strings.Contains(strings.ToLower(r), "auth") {
			found = true
		}
	}
	if !found {
		t.Fatalf("reasons = %v, want an auth-related reason", pre.Reasons)
	}
}

func TestShipActionsProposeRequiresReadyHost(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, _ := setupShipFixtureRepo(t)

	f := &shipTestRunner{ghAuthOK: false}
	s.git = f.run

	_, err := s.proposeShipAction(shipActionParams{Workdir: workDir, Message: "feat: x"})
	if err == nil {
		t.Fatal("propose on an unready host should error, not stage an approval")
	}
	if len(s.approvals.pendingEvents()) != 0 {
		t.Fatalf("an unready-host propose must not stage a pending approval")
	}
}

// TestShipActionsE2EBranchCommitPR is the acceptance-gate loopback test: a
// phone-initiated propose -> approve -> execute round trip that actually
// creates a branch, commits, pushes, and opens a "PR" (gh faked) against a
// real throwaway local git fixture repo.
func TestShipActionsE2EBranchCommitPR(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, base := setupShipFixtureRepo(t)

	f := newShipTestRunner()
	s.git = f.run
	resultCh := shipResultEmitter(t, s)

	// A change to ship — without this, gitShip has nothing to commit.
	if err := os.WriteFile(filepath.Join(workDir, "feature.txt"), []byte("new feature\n"), 0644); err != nil {
		t.Fatalf("write feature file: %v", err)
	}

	params := shipActionParams{
		Workdir:    workDir,
		Branch:     "feature/ship-actions",
		BaseBranch: base,
		Message:    "feat: add feature.txt",
		OpenPR:     true,
		PRBase:     base,
		Title:      "Add feature.txt",
		Body:       "Body text",
	}

	propose, err := s.proposeShipAction(params)
	if err != nil {
		t.Fatalf("proposeShipAction: %v", err)
	}
	if propose.ApprovalID == "" || propose.ContentHash == "" {
		t.Fatalf("propose result = %+v, want non-empty approvalId/contentHash", propose)
	}
	if propose.Risk != 2 {
		t.Fatalf("propose.Risk = %d, want 2 (high)", propose.Risk)
	}

	pending := s.approvals.pendingEvents()
	if len(pending) != 1 {
		t.Fatalf("pending approvals = %d, want 1", len(pending))
	}
	if pending[0].Kind != "shipAction" {
		t.Fatalf("pending kind = %q, want shipAction", pending[0].Kind)
	}
	if pending[0].Risk != 2 {
		t.Fatalf("pending risk = %d, want 2", pending[0].Risk)
	}
	if pending[0].ContentHash != propose.ContentHash {
		t.Fatalf("pending contentHash = %q, want %q", pending[0].ContentHash, propose.ContentHash)
	}

	// The phone's explicit approval — the only path that can trigger execution.
	if _, ok := s.applyDecision(propose.ApprovalID, "approve", "", propose.ContentHash); !ok {
		t.Fatalf("applyDecision(approve) failed")
	}

	outcome := waitForShipResult(t, resultCh, propose.ApprovalID)
	if outcome.Status != "completed" {
		t.Fatalf("outcome = %+v, want status=completed", outcome)
	}
	if outcome.Result == nil || !outcome.Result.Committed || !outcome.Result.Pushed {
		t.Fatalf("outcome.Result = %+v, want committed+pushed", outcome.Result)
	}
	if outcome.Result.PRURL != f.prURL {
		t.Fatalf("outcome.Result.PRURL = %q, want %q", outcome.Result.PRURL, f.prURL)
	}

	// Verify against the real fixture repo: branch exists, HEAD is on it, the
	// commit landed, and the remote actually received the push.
	branchOut, err := realGitRunner(workDir, "git", "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil || strings.TrimSpace(branchOut) != "feature/ship-actions" {
		t.Fatalf("HEAD branch = %q, err=%v, want feature/ship-actions", branchOut, err)
	}
	logOut, err := realGitRunner(workDir, "git", "log", "-1", "--pretty=%s")
	if err != nil || strings.TrimSpace(logOut) != "feat: add feature.txt" {
		t.Fatalf("last commit subject = %q, err=%v", logOut, err)
	}
	remoteRefs, err := realGitRunner(workDir, "git", "ls-remote", "origin", "refs/heads/feature/ship-actions")
	if err != nil || strings.TrimSpace(remoteRefs) == "" {
		t.Fatalf("origin missing pushed branch: out=%q err=%v", remoteRefs, err)
	}

	// PERMANENT scope boundary: no call in this round trip may ever be a merge.
	for _, c := range f.callLog() {
		low := strings.ToLower(c)
		if strings.Contains(low, "merge") {
			t.Fatalf("ship action issued a merge-related command, which is permanently out of scope: %q", c)
		}
	}
}

// TestShipActionsDeniedDoesNotExecute proves a deny decision never runs
// git/gh — the branch is never created, nothing is committed or pushed.
func TestShipActionsDeniedDoesNotExecute(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, base := setupShipFixtureRepo(t)

	f := newShipTestRunner()
	s.git = f.run
	resultCh := shipResultEmitter(t, s)

	if err := os.WriteFile(filepath.Join(workDir, "feature.txt"), []byte("x\n"), 0644); err != nil {
		t.Fatal(err)
	}

	propose, err := s.proposeShipAction(shipActionParams{
		Workdir: workDir, Branch: "feature/denied", BaseBranch: base, Message: "feat: denied",
	})
	if err != nil {
		t.Fatalf("proposeShipAction: %v", err)
	}
	callsBeforeDecision := len(f.callLog())

	if _, ok := s.applyDecision(propose.ApprovalID, "deny", "", propose.ContentHash); !ok {
		t.Fatalf("applyDecision(deny) failed")
	}

	outcome := waitForShipResult(t, resultCh, propose.ApprovalID)
	if outcome.Status != "denied" {
		t.Fatalf("outcome = %+v, want status=denied", outcome)
	}

	branchOut, _ := realGitRunner(workDir, "git", "rev-parse", "--abbrev-ref", "HEAD")
	if strings.TrimSpace(branchOut) == "feature/denied" {
		t.Fatalf("denied ship action must not have created/checked out the branch")
	}
	// awaitShipDecision must not have issued any additional git/gh call after
	// the deny — the preflight calls made during propose are the only ones.
	if got := len(f.callLog()); got != callsBeforeDecision {
		t.Fatalf("calls after deny = %d, want unchanged from %d (no execution)", got, callsBeforeDecision)
	}
}

// TestShipActionsContentHashMismatchRejected proves the same content-hash
// binding guarantee approval.go already provides for hook approvals holds for
// ship actions: a decision whose echoed hash doesn't match the staged event
// is rejected, and the action never resolves/executes on that call.
func TestShipActionsContentHashMismatchRejected(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, _ := setupShipFixtureRepo(t)

	f := newShipTestRunner()
	s.git = f.run
	_ = shipResultEmitter(t, s) // swallow notifications; this test only checks resolve()

	propose, err := s.proposeShipAction(shipActionParams{Workdir: workDir, Message: "feat: x"})
	if err != nil {
		t.Fatalf("proposeShipAction: %v", err)
	}

	if _, ok := s.applyDecision(propose.ApprovalID, "approve", "", "wrong-hash"); ok {
		t.Fatalf("applyDecision must reject a mismatched content hash")
	}
	pending := s.approvals.pendingEvents()
	if len(pending) != 1 {
		t.Fatalf("pending approvals = %d after a rejected decision, want 1 (still staged)", len(pending))
	}

	// The correct hash still resolves it (cleanup / sanity that the mismatch
	// path didn't corrupt the pending entry).
	if _, ok := s.applyDecision(propose.ApprovalID, "deny", "", propose.ContentHash); !ok {
		t.Fatalf("applyDecision with the correct hash should still resolve the approval")
	}
}

// TestShipActionsRPCRegistered guards the wire surface: agent.ship.preflight
// and agent.ship.propose must be reachable via handleMessage, not just as Go
// methods (the audit found agent.ci.recent had this gap once already).
func TestShipActionsRPCRegistered(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	workDir, _ := setupShipFixtureRepo(t)
	f := newShipTestRunner()
	s.git = f.run

	resultCh := make(chan rpcMessage, 4)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		_ = json.Unmarshal(data, &m)
		select {
		case resultCh <- m:
		default:
		}
		return nil
	})

	preflightParams, _ := json.Marshal(map[string]interface{}{"workdir": workDir})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.ship.preflight", Params: preflightParams})

	proposeParams, _ := json.Marshal(shipActionParams{Workdir: workDir, Message: "feat: rpc"})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 2, Method: "agent.ship.propose", Params: proposeParams})

	seen := map[interface{}]bool{}
	deadline := time.After(3 * time.Second)
	for len(seen) < 2 {
		select {
		case m := <-resultCh:
			if m.Error != nil && m.Error.Code == -32601 {
				t.Fatalf("method not found: %+v", m)
			}
			seen[m.ID] = true
		case <-deadline:
			t.Fatalf("timed out waiting for agent.ship.* RPC responses, got %d/2", len(seen))
		}
	}
}
