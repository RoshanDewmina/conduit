package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestRepoTurnDiffAcrossTwoStamps(t *testing.T) {
	dir := initFixtureGitRepo(t)
	store := openTestConversationStore(t)
	s := &server{conversations: store}

	startOID := stampTurnBaseline(dir)
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t1",
		Agent:        "claudeCode",
		Prompt:       "edit",
		CWD:          dir,
	}, dir, "run_turn_diff")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	if err := store.setTurnBaselineStart(res.TurnID, startOID); err != nil {
		t.Fatalf("set start: %v", err)
	}

	writeBaselineFile(t, filepath.Join(dir, "a.go"), "package a\n")
	endOID := stampTurnBaseline(dir)
	if err := store.setTurnBaselineEnd(res.TurnID, endOID); err != nil {
		t.Fatalf("set end: %v", err)
	}

	diff, err := s.repoTurnDiff(repoTurnDiffRequest{
		ConversationID: res.ConversationID,
		TurnID:         res.TurnID,
	})
	if err != nil {
		t.Fatalf("repoTurnDiff: %v", err)
	}
	if !diff.Supported {
		t.Fatal("expected supported=true")
	}
	if diff.TotalAdded < 1 {
		t.Fatalf("totalAdded=%d, want >=1; files=%+v", diff.TotalAdded, diff.Files)
	}
	found := false
	for _, f := range diff.Files {
		if f.Path == "a.go" {
			found = true
			if f.Status != "added" {
				t.Errorf("status=%q, want added", f.Status)
			}
		}
	}
	if !found {
		t.Fatalf("a.go missing from %+v", diff.Files)
	}
}

func TestRepoSessionDiffWithRunningTurn(t *testing.T) {
	dir := initFixtureGitRepo(t)
	store := openTestConversationStore(t)
	s := &server{conversations: store}

	startOID := stampTurnBaseline(dir)
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t-session",
		Agent:        "claudeCode",
		Prompt:       "work",
		CWD:          dir,
	}, dir, "run_session")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	_ = store.setTurnBaselineStart(res.TurnID, startOID)
	// No end OID — turn still running. Session diff uses live write-tree.

	writeBaselineFile(t, filepath.Join(dir, "live.txt"), "hello\n")

	diff, err := s.repoSessionDiff(repoSessionDiffRequest{ConversationID: res.ConversationID})
	if err != nil {
		t.Fatalf("repoSessionDiff: %v", err)
	}
	if !diff.Supported {
		t.Fatal("expected supported=true for running turn session diff")
	}
	found := false
	for _, f := range diff.Files {
		if f.Path == "live.txt" {
			found = true
		}
	}
	if !found {
		t.Fatalf("live.txt missing from session diff: %+v", diff.Files)
	}
}

func TestRepoFileDiffHunkParse(t *testing.T) {
	dir := initFixtureGitRepo(t)
	store := openTestConversationStore(t)
	s := &server{conversations: store}

	writeBaselineFile(t, filepath.Join(dir, "f.txt"), "one\ntwo\nthree\n")
	runBaselineGit(t, dir, "add", "f.txt")
	runBaselineGit(t, dir, "commit", "-m", "add f")

	startOID := stampTurnBaseline(dir)
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t-hunk",
		Agent:        "claudeCode",
		Prompt:       "patch",
		CWD:          dir,
	}, dir, "run_hunk")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	_ = store.setTurnBaselineStart(res.TurnID, startOID)

	writeBaselineFile(t, filepath.Join(dir, "f.txt"), "one\nTWO\nthree\n")
	endOID := stampTurnBaseline(dir)
	_ = store.setTurnBaselineEnd(res.TurnID, endOID)

	out, err := s.repoFileDiff(repoFileDiffRequest{
		ConversationID: res.ConversationID,
		TurnID:         res.TurnID,
		Path:           "f.txt",
	})
	if err != nil {
		t.Fatalf("repoFileDiff: %v", err)
	}
	if len(out.Hunks) == 0 {
		t.Fatal("expected at least one hunk")
	}
	h := out.Hunks[0]
	if h.Header == "" || h.OldStart < 1 || h.NewStart < 1 {
		t.Fatalf("bad hunk header: %+v", h)
	}
	sawDel, sawAdd := false, false
	for _, line := range h.Lines {
		switch line.Kind {
		case "del":
			sawDel = true
			if line.Text != "two" {
				t.Errorf("del text=%q", line.Text)
			}
			if line.OldNo == nil {
				t.Error("del missing oldNo")
			}
		case "add":
			sawAdd = true
			if line.Text != "TWO" {
				t.Errorf("add text=%q", line.Text)
			}
			if line.NewNo == nil {
				t.Error("add missing newNo")
			}
		}
	}
	if !sawDel || !sawAdd {
		t.Fatalf("expected del+add lines, hunk=%+v", h.Lines)
	}
}

func TestRepoTreeAndFileJail(t *testing.T) {
	dir := initFixtureGitRepo(t)
	outside := t.TempDir()
	writeBaselineFile(t, filepath.Join(outside, "secret.txt"), "nope\n")
	if err := os.Symlink(outside, filepath.Join(dir, "escape-link")); err != nil {
		t.Fatalf("symlink: %v", err)
	}
	writeBaselineFile(t, filepath.Join(dir, "ok.txt"), "ok\n")
	mustMkdir(t, filepath.Join(dir, "sub"))
	writeBaselineFile(t, filepath.Join(dir, "sub", "nested.txt"), "n\n")

	store := openTestConversationStore(t)
	s := &server{conversations: store}
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t-jail",
		Agent:        "claudeCode",
		Prompt:       "browse",
		CWD:          dir,
	}, dir, "run_jail")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	entries, err := s.repoTree(repoTreeRequest{ConversationID: res.ConversationID, Path: "."})
	if err != nil {
		t.Fatalf("repoTree: %v", err)
	}
	if len(entries) == 0 {
		t.Fatal("expected entries")
	}
	// dirs first
	if !entries[0].IsDir {
		t.Errorf("expected dirs-first, first=%+v", entries[0])
	}

	file, err := s.repoFile(repoFileRequest{ConversationID: res.ConversationID, Path: "ok.txt"})
	if err != nil {
		t.Fatalf("repoFile: %v", err)
	}
	if file.Content != "ok\n" || file.Binary {
		t.Fatalf("file=%+v", file)
	}

	if _, err := s.repoTree(repoTreeRequest{ConversationID: res.ConversationID, Path: ".."}); err == nil {
		t.Fatal("expected error for .. escape")
	}
	if _, err := s.repoFile(repoFileRequest{ConversationID: res.ConversationID, Path: "/etc/passwd"}); err == nil {
		t.Fatal("expected error for absolute path")
	}
	if _, err := s.repoFile(repoFileRequest{ConversationID: res.ConversationID, Path: "escape-link/secret.txt"}); err == nil {
		t.Fatal("expected error for symlink escape")
	}
	if _, err := s.repoTree(repoTreeRequest{ConversationID: res.ConversationID, Path: "escape-link"}); err == nil {
		t.Fatal("expected error for symlink-dir escape")
	}
}

func TestRepoDiffNonGitSupportedFalse(t *testing.T) {
	dir := t.TempDir()
	store := openTestConversationStore(t)
	s := &server{conversations: store}
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t-nongit",
		Agent:        "claudeCode",
		Prompt:       "x",
		CWD:          dir,
	}, dir, "run_nongit")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	_ = store.setTurnBaselineStart(res.TurnID, stampTurnBaseline(dir)) // empty

	diff, err := s.repoTurnDiff(repoTurnDiffRequest{
		ConversationID: res.ConversationID,
		TurnID:         res.TurnID,
	})
	if err != nil {
		t.Fatalf("repoTurnDiff: %v", err)
	}
	if diff.Supported {
		t.Fatal("expected supported=false for non-git cwd")
	}

	sess, err := s.repoSessionDiff(repoSessionDiffRequest{ConversationID: res.ConversationID})
	if err != nil {
		t.Fatalf("repoSessionDiff: %v", err)
	}
	if sess.Supported {
		t.Fatal("expected supported=false for non-git sessionDiff")
	}
}

func TestParseUnifiedDiffHunks(t *testing.T) {
	diff := `diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
`
	hunks := parseUnifiedDiffHunks(diff)
	if len(hunks) != 1 {
		t.Fatalf("hunks=%d", len(hunks))
	}
	if hunks[0].OldStart != 1 || hunks[0].NewStart != 1 {
		t.Fatalf("starts=%d/%d", hunks[0].OldStart, hunks[0].NewStart)
	}
}

func TestRepoFileBinary(t *testing.T) {
	dir := initFixtureGitRepo(t)
	binPath := filepath.Join(dir, "blob.bin")
	if err := os.WriteFile(binPath, []byte{0x00, 0x01, 0x02}, 0o644); err != nil {
		t.Fatal(err)
	}
	store := openTestConversationStore(t)
	s := &server{conversations: store}
	res, err := store.beginTurn(conversationAppendRequest{
		ClientTurnID: "t-bin",
		Agent:        "claudeCode",
		Prompt:       "x",
		CWD:          dir,
	}, dir, "run_bin")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	out, err := s.repoFile(repoFileRequest{ConversationID: res.ConversationID, Path: "blob.bin"})
	if err != nil {
		t.Fatalf("repoFile: %v", err)
	}
	if !out.Binary || out.Content != "" {
		t.Fatalf("expected binary with no content, got %+v", out)
	}
}

func runBaselineGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(),
		"GIT_AUTHOR_NAME=Lancer Test",
		"GIT_AUTHOR_EMAIL=test@lancer.local",
		"GIT_COMMITTER_NAME=Lancer Test",
		"GIT_COMMITTER_EMAIL=test@lancer.local",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}
