package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestKimiHookIsScopedToLancerDispatches(t *testing.T) {
	if !strings.Contains(kimiHookScript, `[[ "${LANCER_GATE:-}" != "1" ]]`) {
		t.Fatal("Kimi hook must exit unless LANCER_GATE=1")
	}
}

func TestWireKimiHookJSONCreatesMissingFile(t *testing.T) {
	home := t.TempDir()
	changed, err := wireKimiHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true on first wire")
	}
	matchers, _, err := parseKimiHooksJSON(kimiHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if _, _, found := findKimiHookIndex(matchers, kimiHookCommand); !found {
		t.Fatal("Lancer hook command not present after wiring into missing hooks.json")
	}
}

func TestWireKimiHookJSONIsIdempotent(t *testing.T) {
	home := t.TempDir()
	if _, err := wireKimiHookJSON(home); err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(kimiHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}

	changed, err := wireKimiHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("second wire should be a no-op (changed=false)")
	}
	second, err := os.ReadFile(kimiHooksJSONPath(home))
	if err != nil {
		t.Fatal(err)
	}
	if string(first) != string(second) {
		t.Fatalf("idempotent re-wire changed hooks.json:\n%s\n->\n%s", first, second)
	}
}

// TestWireKimiHookJSONPreservesExistingConduitEntry mirrors the equivalent
// Codex test: merging must never clobber or reorder the existing
// conduit-hook.sh entry in ~/.kimi-code/hooks.json.
func TestWireKimiHookJSONPreservesExistingConduitEntry(t *testing.T) {
	home := t.TempDir()
	path := kimiHooksJSONPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	existing := `{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ~/.kimi-code/hooks/conduit-hook.sh"}
        ]
      }
    ]
  }
}`
	if err := os.WriteFile(path, []byte(existing), 0644); err != nil {
		t.Fatal(err)
	}

	changed, err := wireKimiHookJSON(home)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("expected changed=true when lancer hook not yet present")
	}

	matchers, _, err := parseKimiHooksJSON(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(matchers) != 2 {
		t.Fatalf("expected 2 matchers (conduit's + lancer's), got %d", len(matchers))
	}
	if matchers[0].Hooks[0].Command != "bash ~/.kimi-code/hooks/conduit-hook.sh" {
		t.Fatalf("conduit entry was reordered/clobbered: %+v", matchers[0])
	}
	if _, _, found := findKimiHookIndex(matchers, kimiHookCommand); !found {
		t.Fatal("lancer hook not registered after merge")
	}
}

func TestKimiHookInstalledReflectsScriptAndJSON(t *testing.T) {
	home := t.TempDir()
	if kimiHookInstalled(home) {
		t.Fatal("kimiHookInstalled should be false before install")
	}
	if err := installKimiHook(home); err != nil {
		t.Fatalf("installKimiHook: %v", err)
	}
	if !kimiHookInstalled(home) {
		t.Fatal("kimiHookInstalled should be true after install")
	}
}

// TestHookWiredForAgentKimiStaysFailClosed is the spec's required negative
// test: even after a full install, hookWiredForAgent must still return false
// for kimi (relaxLaunchEscalation never trusts it) — the "Kimi decision" in
// the spec is that this is not revisited until a live-fire proof exists.
func TestHookWiredForAgentKimiStaysFailClosed(t *testing.T) {
	home := t.TempDir()
	if err := installKimiHook(home); err != nil {
		t.Fatalf("installKimiHook: %v", err)
	}
	if !kimiHookInstalled(home) {
		t.Fatal("precondition: kimi hook should be installed")
	}

	wired := hookWiredForAgent(home)
	if wired("kimi") {
		t.Fatal("hookWiredForAgent(\"kimi\") must stay false even when the hook script/config are installed")
	}
}

func TestHookWiredForAgentUnknownVendorFailsClosed(t *testing.T) {
	home := t.TempDir()
	wired := hookWiredForAgent(home)
	if wired("some-future-agent") {
		t.Fatal("hookWiredForAgent must default to false for an unrecognized vendor")
	}
}

func TestHookWiredForAgentCursorStaysFailClosed(t *testing.T) {
	home := t.TempDir()
	wired := hookWiredForAgent(home)
	for _, bin := range []string{"agent", "cursor-agent"} {
		if wired(bin) {
			t.Fatalf("hookWiredForAgent(%q) must stay false until a Cursor PreToolUse-equivalent exists", bin)
		}
	}
}
