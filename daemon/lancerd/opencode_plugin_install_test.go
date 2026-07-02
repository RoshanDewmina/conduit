package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOpencodeGateInstallAndWired(t *testing.T) {
	home := t.TempDir()

	if opencodeGateWired(home) {
		t.Fatal("opencodeGateWired should be false before install")
	}

	if err := installOpencodeGate(home); err != nil {
		t.Fatalf("installOpencodeGate: %v", err)
	}

	if !opencodeGateWired(home) {
		t.Fatal("opencodeGateWired should be true after install")
	}

	pluginPath := filepath.Join(home, ".config", "opencode", "plugins", "lancer-gate.js")
	data, err := os.ReadFile(pluginPath)
	if err != nil {
		t.Fatalf("read installed plugin: %v", err)
	}
	got := string(data)
	if !strings.Contains(got, "process.env.LANCER_GATE") {
		t.Fatal("plugin must gate on LANCER_GATE env var")
	}
	if !strings.Contains(got, `"tool.execute.before"`) {
		t.Fatal("plugin must hook tool.execute.before")
	}
	if strings.Contains(got, "CONDUIT_GATE") {
		t.Fatal("plugin must not reference the stale pre-rebrand CONDUIT_GATE var")
	}
}
