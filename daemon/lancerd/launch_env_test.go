package main

import (
	"os"
	"strings"
	"testing"
)

func pathFrom(env []string) string {
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			return strings.TrimPrefix(e, "PATH=")
		}
	}
	return ""
}

func TestAgentLaunchEnvironmentAugmentsPath(t *testing.T) {
	// Simulate launchd's minimal PATH.
	t.Setenv("PATH", "/usr/bin:/bin")
	dirs := strings.Split(pathFrom(agentLaunchEnvironment()), ":")
	set := map[string]bool{}
	for _, d := range dirs {
		set[d] = true
	}
	for _, want := range []string{"/usr/bin", "/bin", "/opt/homebrew/bin", "/usr/local/bin"} {
		if !set[want] {
			t.Errorf("PATH missing %q (got %v)", want, dirs)
		}
	}
	// The user's existing entries must come FIRST (we only append).
	if dirs[0] != "/usr/bin" || dirs[1] != "/bin" {
		t.Errorf("user PATH not preserved first: %v", dirs)
	}
}

func TestAgentLaunchEnvironmentNoDuplicates(t *testing.T) {
	t.Setenv("PATH", "/opt/homebrew/bin:/usr/bin")
	dirs := strings.Split(pathFrom(agentLaunchEnvironment()), ":")
	counts := map[string]int{}
	for _, d := range dirs {
		counts[d]++
	}
	if counts["/opt/homebrew/bin"] != 1 {
		t.Errorf("/opt/homebrew/bin duplicated: %v", dirs)
	}
}

func TestAgentLaunchEnvironmentEmptyPath(t *testing.T) {
	t.Setenv("PATH", "")
	if !strings.Contains(pathFrom(agentLaunchEnvironment()), "/opt/homebrew/bin") {
		t.Error("empty PATH should still get the agent dirs")
	}
}

func TestLookPathInResolvesAgainstEnvNotProcess(t *testing.T) {
	dir := t.TempDir()
	bin := dir + "/faketool"
	if err := writeExecutable(bin); err != nil {
		t.Fatal(err)
	}
	// The process PATH does NOT contain dir; only the passed env does.
	env := []string{"PATH=/nonexistent:" + dir}
	if got := lookPathIn("faketool", env); got != bin {
		t.Errorf("lookPathIn = %q, want %q", got, bin)
	}
	// A non-executable file is not resolved.
	if got := lookPathIn("missing", env); got != "" {
		t.Errorf("lookPathIn(missing) = %q, want empty", got)
	}
}

func TestLookPathInExcludingSkipsShimDir(t *testing.T) {
	shimDir := t.TempDir()
	realDir := t.TempDir()
	if err := writeExecutable(shimDir + "/claude"); err != nil {
		t.Fatal(err)
	}
	realBin := realDir + "/claude"
	if err := writeExecutable(realBin); err != nil {
		t.Fatal(err)
	}
	// Shim appears first on PATH — excluding it must yield the real binary.
	env := []string{"PATH=" + shimDir + ":" + realDir}
	if got := lookPathInExcluding("claude", env, shimDir); got != realBin {
		t.Fatalf("lookPathInExcluding = %q, want %q", got, realBin)
	}
	if got := lookPathIn("claude", env); got != shimDir+"/claude" {
		t.Fatalf("lookPathIn without exclude = %q, want shim", got)
	}
}

func writeExecutable(path string) error {
	return os.WriteFile(path, []byte("#!/bin/sh\n"), 0o755)
}
