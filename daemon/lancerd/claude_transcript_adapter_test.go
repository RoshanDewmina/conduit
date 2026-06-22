package main

import (
	"os"
	"path/filepath"
	"testing"
)

const fixtureSessionID = "114ca340-6508-4a10-aeb5-dcad9e1b6a71"

func fixtureTranscriptLines() []string {
	return []string{
		`{"type":"ai-title","aiTitle":"fix-dead-buttons","sessionId":"` + fixtureSessionID + `"}`,
		`{"type":"user","sessionId":"` + fixtureSessionID + `","cwd":"/Users/x/repo","message":{"role":"user","content":"please fix the dead button"},"timestamp":"2026-06-22T13:00:00Z"}`,
		`{"type":"assistant","sessionId":"` + fixtureSessionID + `","message":{"role":"assistant","content":[{"type":"text","text":"Sure, let me look."}]},"timestamp":"2026-06-22T13:00:05Z"}`,
		`{"type":"assistant","sessionId":"` + fixtureSessionID + `","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"grep -rn dead button"}}]},"timestamp":"2026-06-22T13:00:06Z"}`,
		`{"type":"user","sessionId":"` + fixtureSessionID + `","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"no matches"}]},"timestamp":"2026-06-22T13:00:07Z"}`,
		`{"type":"weird-future-type","sessionId":"` + fixtureSessionID + `","somethingNew":true}`,
		`{"type":"system","subtype":"stop_hook_summary","sessionId":"` + fixtureSessionID + `","timestamp":"2026-06-22T13:00:08Z"}`,
	}
}

func writeFixture(t *testing.T, dir string, lines []string, truncatedFinal bool) string {
	t.Helper()
	path := filepath.Join(dir, fixtureSessionID+".jsonl")
	content := ""
	for _, l := range lines {
		content += l + "\n"
	}
	if truncatedFinal {
		content += `{"type":"assistant","sessionId":"` + fixtureSessionID + `","message":{"role":"ass`
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestParseClaudeTranscriptRolesAndOrder(t *testing.T) {
	dir := t.TempDir()
	path := writeFixture(t, dir, fixtureTranscriptLines(), false)

	msgs, nextLine, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if nextLine != len(fixtureTranscriptLines()) {
		t.Fatalf("nextLine = %d, want %d", nextLine, len(fixtureTranscriptLines()))
	}

	wantRoles := []string{"user", "assistant", "toolCall", "toolResult", "unknown", "system"}
	if len(msgs) != len(wantRoles) {
		t.Fatalf("got %d messages, want %d: %+v", len(msgs), len(wantRoles), msgs)
	}
	for i, role := range wantRoles {
		if msgs[i].Role != role {
			t.Errorf("msgs[%d].Role = %q, want %q (text=%q)", i, msgs[i].Role, role, msgs[i].Text)
		}
	}

	if msgs[0].Text != "please fix the dead button" {
		t.Errorf("user text = %q", msgs[0].Text)
	}
	if msgs[1].Text != "Sure, let me look." {
		t.Errorf("assistant text = %q", msgs[1].Text)
	}
	if msgs[2].ToolName != "Bash" {
		t.Errorf("toolCall.ToolName = %q, want Bash", msgs[2].ToolName)
	}
	if msgs[2].Text == "" {
		t.Errorf("toolCall summary text empty")
	}
	if msgs[3].Text != "no matches" {
		t.Errorf("toolResult text = %q", msgs[3].Text)
	}
	if msgs[4].Role != "unknown" {
		t.Errorf("weird-future-type should map to unknown role")
	}
}

func TestParseClaudeTranscriptIncrementalSinceLine(t *testing.T) {
	dir := t.TempDir()
	lines := fixtureTranscriptLines()
	path := writeFixture(t, dir, lines, false)

	first, nextLine, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(first) == 0 {
		t.Fatal("expected some messages on first parse")
	}

	more := append(lines, `{"type":"assistant","sessionId":"`+fixtureSessionID+`","message":{"role":"assistant","content":[{"type":"text","text":"one more thing"}]},"timestamp":"2026-06-22T13:00:09Z"}`)
	path = writeFixture(t, dir, more, false)

	second, nextLine2, err := parseClaudeTranscript(path, nextLine)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(second) != 1 {
		t.Fatalf("incremental fetch got %d messages, want 1: %+v", len(second), second)
	}
	if second[0].Text != "one more thing" {
		t.Errorf("incremental message text = %q", second[0].Text)
	}
	if nextLine2 != len(more) {
		t.Fatalf("nextLine2 = %d, want %d", nextLine2, len(more))
	}
}

func TestParseClaudeTranscriptTruncatedFinalLineTolerated(t *testing.T) {
	dir := t.TempDir()
	path := writeFixture(t, dir, fixtureTranscriptLines(), true)

	msgs, nextLine, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("truncated final line should not error, got: %v", err)
	}
	if nextLine != len(fixtureTranscriptLines()) {
		t.Fatalf("nextLine = %d, should not count the truncated partial line", nextLine)
	}
	if len(msgs) == 0 {
		t.Fatal("expected messages from the well-formed lines despite truncated tail")
	}
}

func TestParseClaudeTranscriptUnknownTypeNeverCrashes(t *testing.T) {
	dir := t.TempDir()
	lines := []string{
		`{"type":"totally-new-thing","sessionId":"` + fixtureSessionID + `","payload":{"nested":[1,2,3]}}`,
		`not even json`,
	}
	path := writeFixture(t, dir, lines, false)

	msgs, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("should never error on bad lines, got: %v", err)
	}
	if len(msgs) != 1 || msgs[0].Role != "unknown" {
		t.Fatalf("got %+v, want one unknown-role message", msgs)
	}
}

func TestParseClaudeTranscriptMissingFileErrors(t *testing.T) {
	_, _, err := parseClaudeTranscript(filepath.Join(t.TempDir(), "missing.jsonl"), 0)
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}
