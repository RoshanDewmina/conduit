package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAuditRedaction(t *testing.T) {
	in := "export API_KEY=supersecret token=abc123 Bearer eyJhbGciOi sk-live-abcdefghijklmnop"
	out := redactSecrets(in)
	if strings.Contains(out, "supersecret") || strings.Contains(out, "abc123") {
		t.Fatalf("secrets not redacted: %q", out)
	}
	if !strings.Contains(out, "[REDACTED]") {
		t.Fatalf("expected redaction marker in %q", out)
	}
}

func TestAuditStoreAppendTail(t *testing.T) {
	home := t.TempDir()
	s := newAuditLog(home)
	if err := s.append(AuditEntry{Action: "policy", Effect: "allow", Agent: "claudeCode", Command: "ls"}); err != nil {
		t.Fatal(err)
	}
	if err := s.append(AuditEntry{Action: "decision", Effect: "deny", Command: "password=hunter2"}); err != nil {
		t.Fatal(err)
	}
	entries, err := s.tail(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("want 2 entries, got %d", len(entries))
	}
	if strings.Contains(entries[1].Command, "hunter2") {
		t.Fatal("tail should return redacted command")
	}
	info, err := os.Stat(s.path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("audit.log mode = %o, want 0600", info.Mode().Perm())
	}
}

func TestAuditLogPathUnderHome(t *testing.T) {
	home := t.TempDir()
	s := newAuditLog(home)
	want := filepath.Join(home, ".lancer", "audit.log")
	if s.path != want {
		t.Fatalf("path = %q, want %q", s.path, want)
	}
}
