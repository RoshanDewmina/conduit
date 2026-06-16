package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestScanTranscriptsExtractsSessionID(t *testing.T) {
	root := t.TempDir()
	proj := filepath.Join(root, "-Users-x-repo")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	id := "114ca340-6508-4a10-aeb5-dcad9e1b6a71"
	line := `{"type":"user","sessionId":"` + id + `","cwd":"/Users/x/repo","message":{}}` + "\n"
	if err := os.WriteFile(filepath.Join(proj, id+".jsonl"), []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := scanTranscripts(root)
	if err != nil || len(got) != 1 {
		t.Fatalf("got %d sessions err=%v", len(got), err)
	}
	if got[0].SessionID != id || got[0].CWD != "/Users/x/repo" {
		t.Fatalf("parsed %+v", got[0])
	}
}

func TestScanTranscriptsFallsBackToFilename(t *testing.T) {
	root := t.TempDir()
	proj := filepath.Join(root, "-proj")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	id := "abc-123"
	// A transcript whose lines carry no sessionId -> fall back to filename.
	if err := os.WriteFile(filepath.Join(proj, id+".jsonl"), []byte(`{"type":"ai-title"}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := scanTranscripts(root)
	if err != nil || len(got) != 1 {
		t.Fatalf("got %d sessions err=%v", len(got), err)
	}
	if got[0].SessionID != id {
		t.Fatalf("fallback id = %q, want %q", got[0].SessionID, id)
	}
}
