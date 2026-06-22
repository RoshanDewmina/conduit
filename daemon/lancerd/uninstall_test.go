package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRemoveIfExistsIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "f")
	if err := os.WriteFile(p, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	if !removeIfExists(p) {
		t.Fatal("expected first removeIfExists to report removal")
	}
	if removeIfExists(p) {
		t.Fatal("expected second removeIfExists to report nothing to remove")
	}
	if _, err := os.Stat(p); !os.IsNotExist(err) {
		t.Fatalf("file should be gone, got err=%v", err)
	}
}

func TestUninstallLaunchdRemovesPlist(t *testing.T) {
	home := t.TempDir()
	plist := launchdPlistPath(home)
	if err := os.MkdirAll(filepath.Dir(plist), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(plist, []byte("<plist/>"), 0644); err != nil {
		t.Fatal(err)
	}
	// launchctl may be absent/fail in CI — uninstallLaunchd ignores that and must
	// still remove the plist file.
	uninstallLaunchd(home)
	if _, err := os.Stat(plist); !os.IsNotExist(err) {
		t.Fatalf("plist should be removed, got err=%v", err)
	}
	// Idempotent: a second call with no plist must not panic or error.
	uninstallLaunchd(home)
}

func TestLaunchdPlistPathMatchesInstaller(t *testing.T) {
	// The uninstall path must equal the label/path the installer writes, or an
	// uninstall would silently leave the unit behind.
	got := launchdPlistPath("/Users/x")
	want := "/Users/x/Library/LaunchAgents/dev.lancer.lancerd.plist"
	if got != want {
		t.Fatalf("plist path drift: got %q want %q", got, want)
	}
}
