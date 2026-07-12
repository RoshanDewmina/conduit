package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func initFixtureGitRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	run := func(args ...string) {
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
	run("init")
	run("config", "core.autocrlf", "false")
	writeBaselineFile(t, filepath.Join(dir, "README.md"), "# fixture\n")
	run("add", "README.md")
	run("commit", "-m", "init")
	return dir
}

func writeBaselineFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func TestStampTurnBaselineDoesNotTouchUserIndex(t *testing.T) {
	dir := initFixtureGitRepo(t)
	writeBaselineFile(t, filepath.Join(dir, "dirty.txt"), "dirty\n")

	before, err := gitStatusPorcelain(dir)
	if err != nil {
		t.Fatalf("status before: %v", err)
	}
	if !strings.Contains(before, "dirty.txt") {
		t.Fatalf("expected dirty worktree before stamp, got %q", before)
	}

	indexBefore, err := os.ReadFile(filepath.Join(dir, ".git", "index"))
	if err != nil {
		t.Fatalf("read index before: %v", err)
	}

	oid := stampTurnBaseline(dir)
	if oid == "" {
		t.Fatal("expected non-empty baseline OID")
	}

	after, err := gitStatusPorcelain(dir)
	if err != nil {
		t.Fatalf("status after: %v", err)
	}
	if before != after {
		t.Fatalf("git status changed by stampTurnBaseline:\nbefore=%q\nafter=%q", before, after)
	}
	indexAfter, err := os.ReadFile(filepath.Join(dir, ".git", "index"))
	if err != nil {
		t.Fatalf("read index after: %v", err)
	}
	if string(indexBefore) != string(indexAfter) {
		t.Fatal("real .git/index mutated by stampTurnBaseline")
	}
}

func TestStampTurnBaselineNonGitReturnsEmpty(t *testing.T) {
	dir := t.TempDir()
	if oid := stampTurnBaseline(dir); oid != "" {
		t.Fatalf("expected empty OID for non-git cwd, got %q", oid)
	}
}

func TestStampTurnBaselineCapturesUntracked(t *testing.T) {
	dir := initFixtureGitRepo(t)
	start := stampTurnBaseline(dir)
	writeBaselineFile(t, filepath.Join(dir, "new.go"), "package main\n")
	end := stampTurnBaseline(dir)
	if start == "" || end == "" {
		t.Fatalf("oids empty: start=%q end=%q", start, end)
	}
	if start == end {
		t.Fatal("expected different OIDs after adding a file")
	}
	diff, err := diffTrees(dir, start, end)
	if err != nil {
		t.Fatalf("diffTrees: %v", err)
	}
	if !diff.Supported {
		t.Fatal("expected supported diff")
	}
	found := false
	for _, f := range diff.Files {
		if f.Path == "new.go" && f.Status == "added" {
			found = true
			if f.Added < 1 {
				t.Errorf("added lines = %d, want >= 1", f.Added)
			}
		}
	}
	if !found {
		t.Fatalf("new.go not in diff: %+v", diff.Files)
	}
}
