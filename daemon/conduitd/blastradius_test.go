package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestBlastRadiusGitFixture(t *testing.T) {
	dir := t.TempDir()
	runGit(t, dir, "init")
	_ = os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi"), 0644)
	runGit(t, dir, "add", "README.md")
	runGit(t, dir, "commit", "-m", "init")
	_ = os.WriteFile(filepath.Join(dir, "dirty.txt"), []byte("x"), 0644)

	event := ApprovalEvent{
		Kind:    "patch",
		Command: "apply patch",
		CWD:     dir,
	}
	br := computeBlastRadius(event, "rule#0:ask")
	if !br.TouchesGit {
		t.Fatal("expected touchesGit in git repo")
	}
	found := false
	for _, f := range br.Files {
		if f == "dirty.txt" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected dirty.txt in blast files, got %v", br.Files)
	}
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=t@t.com", "GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=t@t.com")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}
