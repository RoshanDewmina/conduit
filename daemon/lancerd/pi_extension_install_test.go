package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestInstallPiExtensionIdempotent(t *testing.T) {
	home := t.TempDir()
	if piExtensionInstalled(home) {
		t.Fatal("extension must not report installed before install")
	}
	if err := installPiExtension(home); err != nil {
		t.Fatalf("install: %v", err)
	}
	if !piExtensionInstalled(home) {
		t.Fatal("extension must report installed after install")
	}
	first, err := os.ReadFile(piExtensionPath(home))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if err := installPiExtension(home); err != nil {
		t.Fatalf("re-install: %v", err)
	}
	second, err := os.ReadFile(piExtensionPath(home))
	if err != nil {
		t.Fatalf("re-read: %v", err)
	}
	if string(first) != string(second) {
		t.Fatal("re-install must be byte-identical (idempotent overwrite)")
	}
	if !strings.Contains(string(first), `pi.on("tool_call"`) {
		t.Fatal("extension script must register a tool_call handler")
	}
	if !strings.Contains(string(first), "block: true") {
		t.Fatal("extension script must veto via block:true (fail-closed)")
	}
}

func TestAppendPiExtensionForHome(t *testing.T) {
	home := t.TempDir()
	argv := []string{"pi", "--mode", "json", "-p", "hello"}

	// Not installed: passthrough, untouched.
	if got := appendPiExtensionForHome(argv, home); !reflect.DeepEqual(got, argv) {
		t.Fatalf("uninstalled: want passthrough, got %v", got)
	}

	if err := installPiExtension(home); err != nil {
		t.Fatalf("install: %v", err)
	}

	got := appendPiExtensionForHome(argv, home)
	want := []string{"pi", "-e", filepath.Join(home, ".lancer", "pi-extensions", "lancer-gate.pi.ts"), "--mode", "json", "-p", "hello"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("installed: want %v, got %v", want, got)
	}

	// Non-pi argv passes through even with the extension installed.
	claude := []string{"claude", "-p", "hello"}
	if got := appendPiExtensionForHome(claude, home); !reflect.DeepEqual(got, claude) {
		t.Fatalf("non-pi: want passthrough, got %v", got)
	}
	if got := appendPiExtensionForHome(nil, home); got != nil {
		t.Fatalf("nil argv: want nil, got %v", got)
	}
}

func TestHookWiredForAgentPiStaysFailClosed(t *testing.T) {
	home := t.TempDir()
	wired := hookWiredForAgent(home)
	if wired("pi") {
		t.Fatal("pi must be fail-closed before the extension is installed")
	}
	if err := installPiExtension(home); err != nil {
		t.Fatalf("install: %v", err)
	}
	// Deliberately still false: the extension's model-driven veto has not
	// been live-fire verified (OpenRouter 402 blocked it on 2026-07-18) —
	// see hookWiredForAgent's pi case. Flip together with that case.
	if wired("pi") {
		t.Fatal("pi must stay fail-closed until the extension veto is live-fire verified")
	}
}
