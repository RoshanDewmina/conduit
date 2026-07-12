package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
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

	msgs, nextLine, truncated, aiTitle, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if truncated {
		t.Fatal("small fixture should not be truncated")
	}
	if aiTitle != "fix-dead-buttons" {
		t.Errorf("aiTitle = %q, want fix-dead-buttons", aiTitle)
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

	first, nextLine, _, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(first) == 0 {
		t.Fatal("expected some messages on first parse")
	}

	more := append(lines, `{"type":"assistant","sessionId":"`+fixtureSessionID+`","message":{"role":"assistant","content":[{"type":"text","text":"one more thing"}]},"timestamp":"2026-06-22T13:00:09Z"}`)
	path = writeFixture(t, dir, more, false)

	second, nextLine2, _, _, err := parseClaudeTranscript(path, nextLine)
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

	msgs, nextLine, _, _, err := parseClaudeTranscript(path, 0)
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

	msgs, _, _, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("should never error on bad lines, got: %v", err)
	}
	if len(msgs) != 1 || msgs[0].Role != "unknown" {
		t.Fatalf("got %+v, want one unknown-role message", msgs)
	}
}

func TestParseClaudeTranscriptMissingFileErrors(t *testing.T) {
	_, _, _, _, err := parseClaudeTranscript(filepath.Join(t.TempDir(), "missing.jsonl"), 0)
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

// TestParseClaudeTranscriptKeepsNewestWhenOverBudget proves that when the
// accumulated message text exceeds maxTranscriptBytes, we drop from the FRONT
// (oldest) so the newest end of a long session is what remains.
func TestParseClaudeTranscriptKeepsNewestWhenOverBudget(t *testing.T) {
	dir := t.TempDir()
	// Per-message text is capped at maxMessageTextBytes (16KB), so we need
	// enough messages that the capped sum exceeds maxTranscriptBytes (2MB).
	perMsg := strings.Repeat("X", maxMessageTextBytes)
	need := (maxTranscriptBytes / maxMessageTextBytes) + 3
	lines := make([]string, 0, need+1)
	lines = append(lines, fmt.Sprintf(
		`{"type":"user","sessionId":"%s","message":{"role":"user","content":"OLD_MARKER %s"},"timestamp":"2026-01-01T00:00:00Z"}`,
		fixtureSessionID, perMsg))
	for i := 1; i < need-1; i++ {
		lines = append(lines, fmt.Sprintf(
			`{"type":"assistant","sessionId":"%s","message":{"role":"assistant","content":[{"type":"text","text":"MID_%d %s"}]},"timestamp":"2026-01-01T00:%02d:00Z"}`,
			fixtureSessionID, i, perMsg, i%60))
	}
	lines = append(lines, fmt.Sprintf(
		`{"type":"assistant","sessionId":"%s","message":{"role":"assistant","content":[{"type":"text","text":"NEW_MARKER %s"}]},"timestamp":"2026-01-01T23:59:00Z"}`,
		fixtureSessionID, perMsg))
	path := writeFixture(t, dir, lines, false)

	msgs, _, truncated, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if !truncated {
		t.Fatal("expected truncated=true when over maxTranscriptBytes")
	}
	if len(msgs) == 0 {
		t.Fatal("expected some newest messages to remain")
	}
	joined := ""
	for _, m := range msgs {
		joined += m.Text
	}
	if strings.Contains(joined, "OLD_MARKER") {
		t.Fatal("oldest front message should have been dropped to stay under budget")
	}
	if !strings.Contains(joined, "NEW_MARKER") {
		t.Fatal("newest message must be kept when the byte cap trips")
	}
	total := 0
	for _, m := range msgs {
		total += len(m.Text)
	}
	if total > maxTranscriptBytes {
		t.Fatalf("kept %d bytes, want <= %d", total, maxTranscriptBytes)
	}
}

func TestParseClaudeTranscriptAITitleLatestWins(t *testing.T) {
	dir := t.TempDir()
	lines := []string{
		`{"type":"ai-title","aiTitle":"first-title","sessionId":"` + fixtureSessionID + `"}`,
		`{"type":"user","sessionId":"` + fixtureSessionID + `","message":{"role":"user","content":"hello"},"timestamp":"2026-01-01T00:00:00Z"}`,
		`{"type":"ai-title","aiTitle":"latest-title","sessionId":"` + fixtureSessionID + `"}`,
	}
	path := writeFixture(t, dir, lines, false)
	_, _, _, aiTitle, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if aiTitle != "latest-title" {
		t.Fatalf("aiTitle = %q, want latest-title", aiTitle)
	}
}
