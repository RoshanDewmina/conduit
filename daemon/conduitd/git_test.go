package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParseGitStatus(t *testing.T) {
	out := "## feat/x...origin/feat/x [ahead 2, behind 1]\n M src/a.ts\n?? new.txt\nA  staged.go\nR  old.go -> renamed.go\n"
	st := parseGitStatus(out)
	if st.Branch != "feat/x" {
		t.Errorf("branch = %q, want feat/x", st.Branch)
	}
	if st.Upstream != "origin/feat/x" {
		t.Errorf("upstream = %q", st.Upstream)
	}
	if st.Ahead != 2 || st.Behind != 1 {
		t.Errorf("ahead/behind = %d/%d, want 2/1", st.Ahead, st.Behind)
	}
	if len(st.Changes) != 4 {
		t.Fatalf("changes = %d, want 4", len(st.Changes))
	}
	// " M" is unstaged; "A " and "R " are staged; "??" is untracked (not staged).
	want := map[string]bool{"src/a.ts": false, "new.txt": false, "staged.go": true, "renamed.go": true}
	for _, c := range st.Changes {
		if w, ok := want[c.Path]; !ok || w != c.Staged {
			t.Errorf("%s staged=%v, want %v", c.Path, c.Staged, w)
		}
	}
}

func TestParseNameStatus(t *testing.T) {
	out := "A\tadded.go\nM\tmod.go\nD\tgone.go\nR100\told.go\trenamed.go\n"
	files := parseNameStatus(out)
	if len(files) != 4 {
		t.Fatalf("files = %d, want 4", len(files))
	}
	exp := []gitChangedFile{
		{"added.go", "added"}, {"mod.go", "modified"}, {"gone.go", "deleted"}, {"renamed.go", "renamed"},
	}
	for i, e := range exp {
		if files[i] != e {
			t.Errorf("files[%d] = %+v, want %+v", i, files[i], e)
		}
	}
}

// fakeRunner records git invocations and returns scripted outputs/errors keyed
// by the first arg (subcommand). Tool ("git"/"gh") + subcommand identifies the call.
type fakeRunner struct {
	calls   []string
	outputs map[string]string
	errs    map[string]error
}

func (f *fakeRunner) run(workdir, tool string, args ...string) (string, error) {
	key := tool
	if len(args) > 0 {
		key = tool + " " + args[0]
	}
	f.calls = append(f.calls, key+" | "+strings.Join(args, " "))
	return f.outputs[key], f.errs[key]
}

func TestGitShipFullPath(t *testing.T) {
	f := &fakeRunner{
		outputs: map[string]string{
			"git status":    "## feat/x\n M a.go\n",
			"git rev-parse":  "feat/x\n",
			"gh pr":         "https://github.com/o/r/pull/42\n",
		},
		errs: map[string]error{},
	}
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.git = f.run

	res, err := s.gitShip(shipParams{Workdir: "/repo", Message: "feat: x", OpenPR: true, Base: "main", Title: "t", Body: "b"})
	if err != nil {
		t.Fatalf("ship error: %v", err)
	}
	if !res.Committed || !res.Pushed {
		t.Errorf("committed/pushed = %v/%v, want true/true", res.Committed, res.Pushed)
	}
	if res.PRURL != "https://github.com/o/r/pull/42" {
		t.Errorf("prURL = %q", res.PRURL)
	}
}

// Idempotency: a retry after "commit ok, push failed" must succeed without
// re-committing and without erroring — push + PR retry only.
func TestGitShipIdempotentRetryAfterPushFailure(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	// First attempt: working tree dirty, push fails.
	f1 := &fakeRunner{
		outputs: map[string]string{"git status": "## feat/x\n M a.go\n", "git rev-parse": "feat/x\n"},
		errs:    map[string]error{"git push": &gitCmdError{exitCode: 1, output: "rejected"}},
	}
	s.git = f1.run
	res1, err := s.gitShip(shipParams{Workdir: "/repo", Message: "m"})
	if err != nil {
		t.Fatalf("attempt 1 hard error: %v", err)
	}
	if !res1.Committed || res1.Pushed {
		t.Errorf("attempt 1: committed/pushed = %v/%v, want true/false", res1.Committed, res1.Pushed)
	}
	if res1.Message == "" {
		t.Error("attempt 1: expected a push-failure message")
	}

	// Retry: tree now clean (commit landed), push succeeds. Must NOT error on
	// "nothing to commit" and must report pushed.
	f2 := &fakeRunner{
		outputs: map[string]string{"git status": "## feat/x\n", "git rev-parse": "feat/x\n"},
		errs:    map[string]error{},
	}
	s.git = f2.run
	res2, err := s.gitShip(shipParams{Workdir: "/repo", Message: "m"})
	if err != nil {
		t.Fatalf("retry hard error: %v", err)
	}
	if !res2.Committed || !res2.Pushed {
		t.Errorf("retry: committed/pushed = %v/%v, want true/true", res2.Committed, res2.Pushed)
	}
	// Retry must not have run a commit (clean tree).
	for _, c := range f2.calls {
		if strings.HasPrefix(c, "git commit") {
			t.Errorf("retry re-ran commit on a clean tree: %v", f2.calls)
		}
	}
}

// "nothing to commit" mid-ship must be treated as already-committed, not a hard error.
func TestGitShipNothingToCommitTolerated(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	f := &fakeRunner{
		outputs: map[string]string{"git status": "## feat/x\n M a.go\n", "git rev-parse": "feat/x\n"},
		errs:    map[string]error{"git commit": &gitCmdError{exitCode: 1, output: "nothing to commit, working tree clean"}},
	}
	s.git = f.run
	res, err := s.gitShip(shipParams{Workdir: "/repo", Message: "m"})
	if err != nil {
		t.Fatalf("hard error: %v", err)
	}
	if !res.Committed || !res.Pushed {
		t.Errorf("committed/pushed = %v/%v, want true/true", res.Committed, res.Pushed)
	}
}

// PR auth failure must NOT fail the whole ship — commit+push succeed, a clear
// message surfaces, prURL is empty (retryable).
func TestGitShipPRAuthFailureGraceful(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	f := &fakeRunner{
		outputs: map[string]string{"git status": "## feat/x\n M a.go\n", "git rev-parse": "feat/x\n"},
		errs:    map[string]error{"gh pr": &gitCmdError{exitCode: 4, output: "gh auth login required"}},
	}
	s.git = f.run
	res, err := s.gitShip(shipParams{Workdir: "/repo", Message: "m", OpenPR: true})
	if err != nil {
		t.Fatalf("PR auth failure should not hard-error: %v", err)
	}
	if !res.Committed || !res.Pushed {
		t.Errorf("committed/pushed = %v/%v, want true/true", res.Committed, res.Pushed)
	}
	if res.PRURL != "" {
		t.Errorf("prURL = %q, want empty on auth failure", res.PRURL)
	}
	if !strings.Contains(strings.ToLower(res.Message), "auth") {
		t.Errorf("message = %q, want an auth hint", res.Message)
	}
}

// Existing PR for the branch → idempotent: recover the URL via `gh pr view`.
func TestGitShipExistingPRRecovered(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	f := &fakeRunner{
		outputs: map[string]string{
			"git status":   "## feat/x\n M a.go\n",
			"git rev-parse": "feat/x\n",
			"gh pr":        "https://github.com/o/r/pull/9\n", // gh pr view output
		},
		errs: map[string]error{
			// gh pr create fails because a PR already exists.
		},
	}
	// Make `gh pr create` fail with "already exists" but `gh pr view` succeed.
	// Both share the "gh pr" key, so script via a closure instead.
	calls := 0
	s.git = func(workdir, tool string, args ...string) (string, error) {
		if tool == "gh" && len(args) >= 2 && args[0] == "pr" && args[1] == "create" {
			return "a pull request for branch feat/x already exists", &gitCmdError{exitCode: 1, output: "already exists"}
		}
		if tool == "gh" && len(args) >= 2 && args[0] == "pr" && args[1] == "view" {
			return "https://github.com/o/r/pull/9", nil
		}
		calls++
		return f.outputs["git "+args[0]], f.errs["git "+args[0]]
	}
	res, err := s.gitShip(shipParams{Workdir: "/repo", Message: "m", OpenPR: true})
	if err != nil {
		t.Fatalf("hard error: %v", err)
	}
	if res.PRURL != "https://github.com/o/r/pull/9" {
		t.Errorf("prURL = %q, want recovered existing PR url", res.PRURL)
	}
}

func TestRecentCIEventsProxiesBackend(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/webhooks/recent" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		if r.URL.Query().Get("repo") != "o/r" {
			t.Errorf("repo param = %q", r.URL.Query().Get("repo"))
		}
		events := []CIEvent{{
			ID: "1", Repo: "o/r", Type: "pr", Status: "success",
			PRNumber: 42, Timestamp: time.Now(),
		}, {
			ID: "2", Repo: "o/r", Type: "check_run", Status: "failure", Context: "build", Timestamp: time.Now(),
		}}
		_ = json.NewEncoder(w).Encode(events)
	}))
	defer backend.Close()

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.deviceMu.Lock()
	s.device = &registeredDevice{PushBackendURL: backend.URL, SessionID: "sess"}
	s.deviceMu.Unlock()

	events, err := s.recentCIEvents("o/r", 50)
	if err != nil {
		t.Fatalf("recentCIEvents error: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("events = %d, want 2", len(events))
	}
	// Type vocabulary must be normalized to the Swift CIEvent raw values.
	if events[0].Type != "pullRequest" {
		t.Errorf("event[0].Type = %q, want pullRequest", events[0].Type)
	}
	if events[1].Type != "checkRun" {
		t.Errorf("event[1].Type = %q, want checkRun", events[1].Type)
	}
}

func TestRecentCIEventsNoDeviceReturnsEmpty(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	events, err := s.recentCIEvents("o/r", 50)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if len(events) != 0 {
		t.Errorf("events = %d, want 0 (no registered backend)", len(events))
	}
}

// agent.ci.recent must be a registered RPC (the audit found it was never wired).
func TestAgentCIRecentRegistered(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	resultCh := make(chan rpcMessage, 1)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		_ = json.Unmarshal(data, &m)
		select {
		case resultCh <- m:
		default:
		}
		return nil
	})
	params, _ := json.Marshal(map[string]interface{}{"repo": "o/r", "limit": 10})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.ci.recent", Params: params})
	select {
	case res := <-resultCh:
		if res.Error != nil && res.Error.Code == -32601 {
			t.Fatal("agent.ci.recent is not registered (method not found)")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no result emitted for agent.ci.recent")
	}
}
