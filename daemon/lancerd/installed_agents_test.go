package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInstalledAgentsDetectsByDir(t *testing.T) {
	dir := t.TempDir()
	// Pretend only claude + opencode are installed in a custom PATH dir.
	for _, b := range []string{"claude", "opencode"} {
		if err := os.WriteFile(filepath.Join(dir, b), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	// Point HOME at an empty dir so the standard augmented locations are empty.
	t.Setenv("HOME", t.TempDir())

	got := installedAgents(nil)
	has := map[string]bool{}
	for _, v := range got {
		has[v] = true
	}
	if !has["claudeCode"] || !has["opencode"] {
		t.Fatalf("expected claudeCode + opencode detected, got %v", got)
	}
	// kimi was not created in the temp PATH and HOME is empty → must be absent.
	if has["kimi"] {
		t.Fatalf("kimi should not be detected when absent, got %v", got)
	}
}
