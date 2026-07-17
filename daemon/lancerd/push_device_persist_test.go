package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestPersistedDeviceRoundTrip proves the push registration survives a
// save/load cycle and that junk/missing files fail closed to nil (WT-E:
// daemon restarts orphaned app-closed push until the next foreground
// deviceRegister because s.device was memory-only).
func TestPersistedDeviceRoundTrip(t *testing.T) {
	dir := t.TempDir()
	s := &server{home: dir}

	if got := s.loadPersistedDevice(); got != nil {
		t.Fatalf("missing file should load nil, got %+v", got)
	}

	s.savePersistedDevice(&registeredDevice{
		PushBackendURL: "https://conduit-push.fly.dev",
		SessionID:      "sess-abc",
	})
	got := s.loadPersistedDevice()
	if got == nil || got.SessionID != "sess-abc" || got.PushBackendURL != "https://conduit-push.fly.dev" {
		t.Fatalf("round trip = %+v", got)
	}

	info, err := os.Stat(filepath.Join(dir, "push-device.json"))
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("perm = %o, want 600", info.Mode().Perm())
	}

	if err := os.WriteFile(filepath.Join(dir, "push-device.json"), []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := s.loadPersistedDevice(); got != nil {
		t.Fatalf("junk file should load nil, got %+v", got)
	}

	if err := os.WriteFile(filepath.Join(dir, "push-device.json"), []byte(`{"pushBackendURL":"x","sessionID":""}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := s.loadPersistedDevice(); got != nil {
		t.Fatalf("empty sessionID should load nil (fail closed), got %+v", got)
	}
}
