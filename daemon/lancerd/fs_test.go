package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFsListHomeRootedAndSorted(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	mustMkdir(t, filepath.Join(home, "projects"))
	mustMkdir(t, filepath.Join(home, "apps"))
	mustMkdir(t, filepath.Join(home, ".hidden"))
	mustWrite(t, filepath.Join(home, "notes.txt"))

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	res, err := s.fsList("~")
	if err != nil {
		t.Fatalf("fsList: %v", err)
	}
	if res.Path != "~" {
		t.Errorf("path = %q, want ~", res.Path)
	}
	// .hidden is skipped; dirs come before files; each group alphabetical.
	want := []fsEntry{
		{Name: "apps", IsDir: true},
		{Name: "projects", IsDir: true},
		{Name: "notes.txt", IsDir: false},
	}
	if len(res.Entries) != len(want) {
		t.Fatalf("entries = %d (%+v), want %d", len(res.Entries), res.Entries, len(want))
	}
	for i, w := range want {
		if res.Entries[i] != w {
			t.Errorf("entries[%d] = %+v, want %+v", i, res.Entries[i], w)
		}
	}
}

func TestFsListRejectsEscapeOutsideHome(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	if _, err := s.fsList("~/../../etc"); err == nil {
		t.Error("expected error for path outside home, got nil")
	}
	if _, err := s.fsList("/etc"); err == nil {
		t.Error("expected error for absolute path outside home, got nil")
	}
}

func TestFsListReportsParent(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	mustMkdir(t, filepath.Join(home, "projects", "lancer"))
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	res, err := s.fsList("~/projects")
	if err != nil {
		t.Fatalf("fsList: %v", err)
	}
	if res.Parent != "~" {
		t.Errorf("parent = %q, want ~", res.Parent)
	}
}

func TestValidateRepoURL(t *testing.T) {
	ok := []string{
		"https://github.com/owner/repo.git",
		"http://example.com/x.git",
		"ssh://git@github.com/owner/repo.git",
		"git@github.com:owner/repo.git",
	}
	for _, u := range ok {
		if err := validateRepoURL(u); err != nil {
			t.Errorf("validateRepoURL(%q) = %v, want nil", u, err)
		}
	}
	bad := []string{"", "  ", "/etc/passwd", "../repo", "--upload-pack=evil", "file:///tmp/x"}
	for _, u := range bad {
		if err := validateRepoURL(u); err == nil {
			t.Errorf("validateRepoURL(%q) = nil, want error", u)
		}
	}
}

func TestRepoDirName(t *testing.T) {
	cases := map[string]string{
		"https://github.com/owner/repo.git":  "repo",
		"https://github.com/owner/repo":      "repo",
		"git@github.com:owner/my-app.git":    "my-app",
		"ssh://git@host/path/to/thing.git/":  "thing",
	}
	for in, want := range cases {
		if got := repoDirName(in); got != want {
			t.Errorf("repoDirName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGitCloneHappyPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	mustMkdir(t, filepath.Join(home, "projects"))

	f := &fakeRunner{
		outputs: map[string]string{"git rev-parse": "main\n"},
		errs:    map[string]error{},
	}
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.git = f.run

	res, err := s.gitClone("https://github.com/owner/repo.git", "~/projects", "")
	if err != nil {
		t.Fatalf("gitClone: %v", err)
	}
	if want := filepath.Join(home, "projects", "repo"); res.Path != want {
		t.Errorf("path = %q, want %q", res.Path, want)
	}
	if res.Branch != "main" {
		t.Errorf("branch = %q, want main", res.Branch)
	}
}

func TestGitCloneRejectsBadInput(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()
	s.git = (&fakeRunner{outputs: map[string]string{}, errs: map[string]error{}}).run

	if _, err := s.gitClone("not-a-url", "~/projects", ""); err == nil {
		t.Error("expected error for bad URL")
	}
	if _, err := s.gitClone("https://github.com/o/r.git", "~/../../tmp", ""); err == nil {
		t.Error("expected error for parent outside home")
	}
	if _, err := s.gitClone("https://github.com/o/r.git", "~", "../escape"); err == nil {
		t.Error("expected error for traversal in name")
	}
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
}

func mustWrite(t *testing.T, path string) {
	t.Helper()
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
