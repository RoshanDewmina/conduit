package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeFakeTmux installs a script named "tmux" early on PATH that records argv.
func writeFakeTmux(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	script := "#!/bin/sh\necho \"$@\" >> \"" + filepath.Join(dir, "calls.log") + "\"\nexit 0\n"
	if err := os.WriteFile(filepath.Join(dir, "tmux"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

func TestTmuxLauncherStartsDetachedSession(t *testing.T) {
	dir := writeFakeTmux(t)
	launch := tmuxLauncher("conduit-test01")
	emit := func(method string, params any) {}
	_, err := launch([]string{"claude", "--resume", "x"}, "/tmp", "run1", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	log, _ := os.ReadFile(filepath.Join(dir, "calls.log"))
	if !strings.Contains(string(log), "new-session") || !strings.Contains(string(log), "conduit-test01") {
		t.Fatalf("tmux not invoked with new-session/name: %q", log)
	}
}
