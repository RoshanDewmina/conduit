package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCodexHookIsScopedToLancerDispatches(t *testing.T) {
	if !strings.Contains(codexHookScript, `[[ "${LANCER_GATE:-}" != "1" ]]`) {
		t.Fatal("Codex hook must exit unless LANCER_GATE=1")
	}
}

// TestCodexHookFailsClosedWhenLancerdMissing guards against the fail-open
// regression found in the original docs/codex-lancer-hook.sh draft, which
// auto-approved ("exit 0") when ~/.lancer/bin/lancerd was not executable.
// The fixed script has no such short-circuit — it must fall through to the
// "$LANCERD" agent-hook call and let a natural exec failure land in the
// `printf ...; exit 2` branch, exactly like docs/lancer-hook.sh (Claude).
func TestCodexHookFailsClosedWhenLancerdMissing(t *testing.T) {
	if strings.Contains(codexHookScript, "auto-approving Codex tool call") {
		t.Fatal("codexHookScript must not contain the fail-open auto-approve-when-missing branch")
	}
	if !strings.Contains(codexHookScript, "exit 2") {
		t.Fatal("codexHookScript must still have a fail-closed exit 2 path")
	}
}

func TestWireCodexHookJSONCreatesMissingFile(t *testing.T) {
	home := t.TempDir()
	changed, err := wireCodexHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true on first wire")
	}
	matchers, _, err := parseCodexHooksJSON(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if _, _, found := findCodexHookIndex(matchers, codexHookCommand); !found {
		t.Fatal("Lancer hook command not present after wiring into missing hooks.json")
	}
}

func TestWireCodexHookJSONIsIdempotent(t *testing.T) {
	home := t.TempDir()
	if _, err := wireCodexHookJSON(home); err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}

	changed, err := wireCodexHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("second wire should be a no-op (changed=false)")
	}
	second, err := os.ReadFile(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if string(first) != string(second) {
		t.Fatalf("idempotent re-wire changed hooks.json:\n%s\n->\n%s", first, second)
	}

	matchers, _, err := parseCodexHooksJSON(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if len(matchers) != 1 {
		t.Fatalf("expected exactly 1 PreToolUse matcher after re-wire, got %d", len(matchers))
	}
}

// TestWireCodexHookJSONPreservesExistingConduitEntry is the hard constraint
// from the spec: merging into hooks.json must never clobber or reorder the
// existing conduit-hook.sh entry.
func TestWireCodexHookJSONPreservesExistingConduitEntry(t *testing.T) {
	home := t.TempDir()
	path := codexHooksJSONPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	existing := `{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ~/.codex/hooks/conduit-hook.sh"}
        ]
      }
    ]
  }
}`
	if err := os.WriteFile(path, []byte(existing), 0644); err != nil {
		t.Fatal(err)
	}

	changed, err := wireCodexHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true when lancer hook not yet present")
	}

	matchers, _, err := parseCodexHooksJSON(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(matchers) != 2 {
		t.Fatalf("expected 2 matchers (conduit's + lancer's), got %d", len(matchers))
	}
	if matchers[0].Hooks[0].Command != "bash ~/.codex/hooks/conduit-hook.sh" {
		t.Fatalf("conduit entry was reordered/clobbered: %+v", matchers[0])
	}
	matcherIdx, hookIdx, found := findCodexHookIndex(matchers, codexHookCommand)
	if !found {
		t.Fatal("lancer hook not registered after merge")
	}
	if matcherIdx != 1 || hookIdx != 0 {
		t.Fatalf("expected lancer entry at matcher=1 hook=0, got matcher=%d hook=%d", matcherIdx, hookIdx)
	}
}

func TestWireCodexHookJSONRejectsMalformedJSON(t *testing.T) {
	home := t.TempDir()
	path := codexHooksJSONPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{ not json"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := wireCodexHookJSON(home); err == nil {
		t.Fatal("expected error on malformed hooks.json, got nil")
	}
}

// TestCodexHookWiredRequiresBothJSONAndTrust is the security-critical case:
// hooks.json presence alone must NOT be treated as wired, because Codex
// silently skips an untrusted hook while Lancer would otherwise relax launch
// escalation for it (a security regression per the spec's hard constraint).
func TestCodexHookWiredRequiresBothJSONAndTrust(t *testing.T) {
	home := t.TempDir()

	if codexHookWired(home) {
		t.Fatal("codexHookWired must be false before anything is installed")
	}

	if _, err := wireCodexHookJSON(home); err != nil {
		t.Fatal(err)
	}
	if codexHookWired(home) {
		t.Fatal("codexHookWired must stay false with hooks.json wired but no config.toml trust record — an untrusted hook is silently skipped by Codex")
	}

	// Simulate the owner running codex, /hooks, and trusting the entry: Codex
	// persists an enabled=true record under [hooks.state] keyed by
	// "<hooksJsonPath>:pre_tool_use:<matcherIdx>:<hookIdx>".
	matchers, _, err := parseCodexHooksJSON(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	matcherIdx, hookIdx, found := findCodexHookIndex(matchers, codexHookCommand)
	if !found {
		t.Fatal("precondition: lancer hook should be present in hooks.json")
	}
	key := codexHookTrustKey(codexHooksJSONPath(home), matcherIdx, hookIdx)

	configPath := codexConfigTomlPath(home)
	if err := os.MkdirAll(filepath.Dir(configPath), 0755); err != nil {
		t.Fatal(err)
	}
	toml := "[hooks.state]\n\n[hooks.state.\"" + key + "\"]\n" +
		"trusted_hash = \"sha256:deadbeef\"\n" +
		"enabled = true\n"
	if err := os.WriteFile(configPath, []byte(toml), 0644); err != nil {
		t.Fatal(err)
	}

	if !codexHookWired(home) {
		t.Fatal("codexHookWired should be true once hooks.json is wired AND config.toml trust is enabled=true")
	}
}

// TestCodexHookWiredFalseWhenTrustDisabled matches the live state observed on
// this machine 2026-07-18 (codex-cli 0.135.0 and 0.144.6): the pre-existing
// conduit-hook.sh trust record has enabled=false, which must read as
// untrusted, not wired.
func TestCodexHookWiredFalseWhenTrustDisabled(t *testing.T) {
	home := t.TempDir()
	if _, err := wireCodexHookJSON(home); err != nil {
		t.Fatal(err)
	}
	matchers, _, err := parseCodexHooksJSON(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	matcherIdx, hookIdx, _ := findCodexHookIndex(matchers, codexHookCommand)
	key := codexHookTrustKey(codexHooksJSONPath(home), matcherIdx, hookIdx)

	configPath := codexConfigTomlPath(home)
	if err := os.MkdirAll(filepath.Dir(configPath), 0755); err != nil {
		t.Fatal(err)
	}
	toml := "[hooks.state]\n\n[hooks.state.\"" + key + "\"]\n" +
		"trusted_hash = \"sha256:deadbeef\"\n" +
		"enabled = false\n"
	if err := os.WriteFile(configPath, []byte(toml), 0644); err != nil {
		t.Fatal(err)
	}

	if codexHookWired(home) {
		t.Fatal("codexHookWired must be false when the trust record has enabled=false")
	}
}

func TestInstallCodexHookWritesScriptAndWiresJSON(t *testing.T) {
	home := t.TempDir()
	if err := installCodexHook(home); err != nil {
		t.Fatalf("installCodexHook: %v", err)
	}

	data, err := os.ReadFile(codexHookScriptPath(home))
	if err != nil {
		t.Fatalf("read installed script: %v", err)
	}
	if !strings.Contains(string(data), "LANCER_GATE") {
		t.Fatal("installed codex hook script must gate on LANCER_GATE")
	}

	matchers, _, err := parseCodexHooksJSON(codexHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if _, _, found := findCodexHookIndex(matchers, codexHookCommand); !found {
		t.Fatal("installCodexHook did not register the hook command in hooks.json")
	}

	// install-only: never grants trust.
	if codexHookWired(home) {
		t.Fatal("installCodexHook must never make codexHookWired true on its own — trust is owner-granted")
	}
}
