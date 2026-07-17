package policy

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCWDOverrideLookupSetAndPersist(t *testing.T) {
	home := t.TempDir()
	repoA := filepath.Join(home, "repoA")
	repoB := filepath.Join(home, "repoB")

	if err := SetCWDOverride(home, repoA, EffectAllow); err != nil {
		t.Fatal(err)
	}
	if err := SetCWDOverride(home, repoB, EffectAsk); err != nil {
		t.Fatal(err)
	}

	gotA, okA := LookupCWDOverride(home, repoA)
	gotB, okB := LookupCWDOverride(home, repoB)
	if !okA || gotA != EffectAllow {
		t.Fatalf("repoA override = (%v, %v), want (allow, true)", gotA, okA)
	}
	if !okB || gotB != EffectAsk {
		t.Fatalf("repoB override = (%v, %v), want (ask, true)", gotB, okB)
	}

	// Restart: new process equivalent = fresh Lookup against same home.
	gotA2, okA2 := LookupCWDOverride(home, repoA)
	if !okA2 || gotA2 != EffectAllow {
		t.Fatalf("persisted repoA override = (%v, %v), want (allow, true)", gotA2, okA2)
	}
}

func TestCWDOverrideCorruptFileFallsClosed(t *testing.T) {
	home := t.TempDir()
	path := CWDOverridePath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{{{not-yaml"), 0600); err != nil {
		t.Fatal(err)
	}
	if mode, ok := LookupCWDOverride(home, "/tmp/repoA"); ok {
		t.Fatalf("corrupt override file must not yield a mode, got %v", mode)
	}
}

func TestCWDOverrideInvalidModeIgnored(t *testing.T) {
	home := t.TempDir()
	path := CWDOverridePath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	body := "overrides:\n  /tmp/repoA: bypassPermissions\n"
	if err := os.WriteFile(path, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	if mode, ok := LookupCWDOverride(home, "/tmp/repoA"); ok {
		t.Fatalf("invalid mode must be ignored, got %v", mode)
	}
}

func TestIsGlobalCWD(t *testing.T) {
	if !IsGlobalCWD("") || !IsGlobalCWD("~") || !IsGlobalCWD("  ~  ") {
		t.Fatal("empty/~ must be global")
	}
	if IsGlobalCWD("/tmp/repo") {
		t.Fatal("/tmp/repo must not be global")
	}
}
