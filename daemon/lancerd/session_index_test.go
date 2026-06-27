package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeSessionFixture(t *testing.T, home, projectDirName, sessionID string, lines []string, mod time.Time) string {
	t.Helper()
	projDir := filepath.Join(home, ".claude", "projects", projectDirName)
	if err := os.MkdirAll(projDir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(projDir, sessionID+".jsonl")
	content := ""
	for _, l := range lines {
		content += l + "\n"
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, mod, mod); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestBuildSessionIndexTitleAndState(t *testing.T) {
	home := t.TempDir()
	id := "aaaaaaaa-0000-0000-0000-000000000001"
	lines := []string{
		`{"type":"user","sessionId":"` + id + `","cwd":"/Users/x/repo","message":{"role":"user","content":"hello"}}`,
		`{"type":"ai-title","aiTitle":"fix-dead-buttons","sessionId":"` + id + `"}`,
	}
	writeSessionFixture(t, home, "-Users-x-repo", id, lines, time.Now().Add(-10*time.Minute))

	sessions, err := buildSessionIndex(home)
	if err != nil {
		t.Fatalf("buildSessionIndex error: %v", err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d sessions, want 1", len(sessions))
	}
	s := sessions[0]
	if s.SessionID != id {
		t.Errorf("sessionId = %q, want %q", s.SessionID, id)
	}
	if s.Title != "fix-dead-buttons" {
		t.Errorf("title = %q, want ai-title value", s.Title)
	}
	if s.Provider != "claudeCode" {
		t.Errorf("provider = %q, want claudeCode", s.Provider)
	}
	if s.Source != "transcriptObserved" {
		t.Errorf("source = %q, want transcriptObserved (no claude agents enrichment in test)", s.Source)
	}
	if s.State != "historical" {
		t.Errorf("state = %q, want historical (mtime 10m ago, > 3m window)", s.State)
	}
	if s.CWD != "/Users/x/repo" {
		t.Errorf("cwd = %q", s.CWD)
	}
}

func TestBuildSessionIndexRecentlyActive(t *testing.T) {
	home := t.TempDir()
	id := "bbbbbbbb-0000-0000-0000-000000000002"
	lines := []string{
		`{"type":"user","sessionId":"` + id + `","cwd":"/Users/x/repo2","message":{"role":"user","content":"hi there this is a long enough prompt to truncate maybe not"}}`,
	}
	writeSessionFixture(t, home, "-Users-x-repo2", id, lines, time.Now().Add(-30*time.Second))

	sessions, err := buildSessionIndex(home)
	if err != nil {
		t.Fatalf("buildSessionIndex error: %v", err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d sessions, want 1", len(sessions))
	}
	if sessions[0].State != "recentlyActive" {
		t.Errorf("state = %q, want recentlyActive (mtime 30s ago)", sessions[0].State)
	}
	if sessions[0].Title != "hi there this is a long enough prompt to truncate maybe not" {
		t.Errorf("title fallback to first user prompt failed: %q", sessions[0].Title)
	}
}

func TestBuildSessionIndexSortedByLastActivityDescending(t *testing.T) {
	home := t.TempDir()
	older := "cccccccc-0000-0000-0000-000000000003"
	newer := "dddddddd-0000-0000-0000-000000000004"
	writeSessionFixture(t, home, "-Users-x-repo3", older,
		[]string{`{"type":"user","sessionId":"` + older + `","cwd":"/x","message":{"role":"user","content":"a"}}`},
		time.Now().Add(-1*time.Hour))
	writeSessionFixture(t, home, "-Users-x-repo4", newer,
		[]string{`{"type":"user","sessionId":"` + newer + `","cwd":"/y","message":{"role":"user","content":"b"}}`},
		time.Now().Add(-1*time.Minute))

	sessions, err := buildSessionIndex(home)
	if err != nil {
		t.Fatalf("buildSessionIndex error: %v", err)
	}
	if len(sessions) != 2 {
		t.Fatalf("got %d sessions, want 2", len(sessions))
	}
	if sessions[0].SessionID != newer || sessions[1].SessionID != older {
		t.Fatalf("not sorted descending by lastActivity: %+v", sessions)
	}
}

func TestBuildSessionIndexMissingProjectsDirReturnsEmpty(t *testing.T) {
	home := t.TempDir()
	sessions, err := buildSessionIndex(home)
	if err != nil {
		t.Fatalf("missing projects dir should not error, got: %v", err)
	}
	if len(sessions) != 0 {
		t.Fatalf("got %d sessions, want 0", len(sessions))
	}
}

func TestLoadSessionTranscriptUnknownSessionID(t *testing.T) {
	home := t.TempDir()
	_, err := loadSessionTranscript(home, "no-such-session", 0)
	if err == nil {
		t.Fatal("expected error for unknown sessionId")
	}
}

func TestLoadSessionTranscriptResetRequiredOnShrink(t *testing.T) {
	home := t.TempDir()
	id := "eeeeeeee-0000-0000-0000-000000000005"
	lines := []string{
		`{"type":"user","sessionId":"` + id + `","cwd":"/x","message":{"role":"user","content":"one"}}`,
		`{"type":"assistant","sessionId":"` + id + `","message":{"role":"assistant","content":[{"type":"text","text":"two"}]}}`,
		`{"type":"assistant","sessionId":"` + id + `","message":{"role":"assistant","content":[{"type":"text","text":"three"}]}}`,
	}
	writeSessionFixture(t, home, "-Users-x-repo5", id, lines, time.Now())

	result, err := loadSessionTranscript(home, id, 100)
	if err != nil {
		t.Fatalf("loadSessionTranscript error: %v", err)
	}
	if !result.ResetRequired {
		t.Fatal("expected resetRequired=true when sinceLine exceeds current line count")
	}
	if result.NextLine != len(lines) {
		t.Fatalf("nextLine = %d, want %d", result.NextLine, len(lines))
	}
	if len(result.Messages) == 0 {
		t.Fatal("expected messages re-parsed from line 0 after reset")
	}
}

func TestBuildSessionIndexCWDFallsBackPastMetadataLines(t *testing.T) {
	home := t.TempDir()
	id := "ffffffff-0000-0000-0000-000000000006"
	// Mirrors real Claude transcripts: the very first sessionId-bearing line
	// (last-prompt) carries no cwd, so the bare scan's firstSessionMeta finds
	// an empty cwd; inspectTranscript must keep scanning for one.
	lines := []string{
		`{"type":"last-prompt","sessionId":"` + id + `"}`,
		`{"type":"mode","mode":"normal","sessionId":"` + id + `"}`,
		`{"type":"user","sessionId":"` + id + `","cwd":"/Users/x/realcwd","message":{"role":"user","content":"hello"}}`,
	}
	writeSessionFixture(t, home, "-Users-x-realcwd", id, lines, time.Now())

	sessions, err := buildSessionIndex(home)
	if err != nil {
		t.Fatalf("buildSessionIndex error: %v", err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d sessions, want 1", len(sessions))
	}
	if sessions[0].CWD != "/Users/x/realcwd" {
		t.Errorf("cwd = %q, want fallback to scan past metadata-only first lines", sessions[0].CWD)
	}
}

func TestMapClaudeAgentStateNeverPanics(t *testing.T) {
	for _, in := range []string{"busy", "idle", "completed", "totally-unrecognized-value", ""} {
		_ = mapClaudeAgentState(in)
	}
}
