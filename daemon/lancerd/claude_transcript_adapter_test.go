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

	// system records (stop_hook_summary etc.) AND unrecognized record types are
	// harness bookkeeping and are dropped from transcripts entirely — raw JSON
	// must never render as message text (custom-title/pr-link leak class).
	wantRoles := []string{"user", "assistant", "toolCall", "toolResult"}
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
	if len(msgs) != 0 {
		t.Fatalf("got %+v, want unknown types skipped (raw JSON must never render)", msgs)
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

// TestParseClaudeTranscriptStructuredBlocks asserts tool_use / tool_result /
// thinking / redacted_thinking map onto the canonical SessionMessage fields
// (ToolUseID, InputJSON, IsError, Role "thinking").
func TestParseClaudeTranscriptStructuredBlocks(t *testing.T) {
	dir := t.TempDir()
	lines := []string{
		`{"type":"user","sessionId":"` + fixtureSessionID + `","message":{"role":"user","content":"edit foo"},"timestamp":"2026-06-22T13:00:00Z"}`,
		`{"type":"assistant","sessionId":"` + fixtureSessionID + `","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I should edit the file"},{"type":"redacted_thinking"},{"type":"tool_use","id":"toolu_edit","name":"Edit","input":{"file_path":"/a.go","old_string":"a\nb","new_string":"a\nb\nc"}}]},"timestamp":"2026-06-22T13:00:01Z"}`,
		`{"type":"user","sessionId":"` + fixtureSessionID + `","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_edit","is_error":true,"content":"permission denied"}]},"timestamp":"2026-06-22T13:00:02Z"}`,
	}
	path := writeFixture(t, dir, lines, false)
	msgs, _, _, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	// user + thinking + redacted_thinking + toolCall + toolResult
	if len(msgs) != 5 {
		t.Fatalf("got %d msgs, want 5: %+v", len(msgs), msgs)
	}
	if msgs[1].Role != "thinking" || msgs[1].Text != "I should edit the file" {
		t.Fatalf("thinking = %+v", msgs[1])
	}
	if msgs[2].Role != "thinking" || msgs[2].Text != "(redacted)" {
		t.Fatalf("redacted_thinking = %+v", msgs[2])
	}
	tc := msgs[3]
	if tc.Role != "toolCall" || tc.ToolName != "Edit" || tc.ToolUseID != "toolu_edit" {
		t.Fatalf("toolCall = %+v", tc)
	}
	if tc.Text == "" || !strings.Contains(tc.Text, "Edit") {
		t.Fatalf("toolCall summary Text empty or missing tool name: %q", tc.Text)
	}
	if !strings.Contains(tc.InputJSON, `"file_path"`) || !strings.Contains(tc.InputJSON, `/a.go`) {
		t.Fatalf("InputJSON missing full input: %q", tc.InputJSON)
	}
	tr := msgs[4]
	if tr.Role != "toolResult" || tr.ToolUseID != "toolu_edit" || !tr.IsError || tr.Text != "permission denied" {
		t.Fatalf("toolResult = %+v", tr)
	}
}

func TestComputeEditStats(t *testing.T) {
	cases := []struct {
		name     string
		tool     string
		input    string
		wantAdd  int
		wantRem  int
	}{
		{"edit", "Edit", `{"old_string":"a\nb","new_string":"a\nb\nc"}`, 3, 2},
		{"write", "Write", `{"content":"line1\nline2\nline3"}`, 3, 0},
		{"multi_edit", "MultiEdit", `{"edits":[{"old_string":"x","new_string":"x\ny"},{"old_string":"a\nb","new_string":"a"}]}`, 3, 3},
		{"unknown tool", "Bash", `{"command":"ls"}`, 0, 0},
		{"empty", "Edit", ``, 0, 0},
		{"bad json", "Edit", `{`, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gotAdd, gotRem := computeEditStats(c.tool, c.input)
			if gotAdd != c.wantAdd || gotRem != c.wantRem {
				t.Fatalf("computeEditStats(%q) = (+%d,-%d), want (+%d,-%d)",
					c.name, gotAdd, gotRem, c.wantAdd, c.wantRem)
			}
		})
	}
}

// TestParseClaudeTranscriptPRLinkRendersOnceAsLink proves pr-link harness
// records render as a single markdown PR link (not raw JSON, WT-I) and that
// the per-turn duplicate re-emissions collapse deterministically — including
// under a sinceLine window, which the observed delta-import's per-turn event
// counts rely on.
func TestParseClaudeTranscriptPRLinkRendersOnceAsLink(t *testing.T) {
	dir := t.TempDir()
	pr153 := `{"type":"pr-link","sessionId":"` + fixtureSessionID + `","prNumber":153,"prUrl":"https://github.com/o/r/pull/153","prRepository":"o/r","timestamp":"2026-07-16T23:47:55Z"}`
	pr154 := `{"type":"pr-link","sessionId":"` + fixtureSessionID + `","prNumber":154,"prUrl":"https://github.com/o/r/pull/154","prRepository":"o/r","timestamp":"2026-07-17T00:32:46Z"}`
	lines := []string{
		`{"type":"user","sessionId":"` + fixtureSessionID + `","message":{"role":"user","content":"open a PR"},"timestamp":"2026-07-16T23:40:00Z"}`,
		pr153,
		pr153,
		`{"type":"assistant","sessionId":"` + fixtureSessionID + `","message":{"role":"assistant","content":[{"type":"text","text":"PR opened."}]},"timestamp":"2026-07-16T23:48:00Z"}`,
		pr153,
		pr154,
		pr154,
	}
	path := writeFixture(t, dir, lines, false)

	msgs, _, _, _, err := parseClaudeTranscript(path, 0)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	var prTexts []string
	for _, m := range msgs {
		if strings.Contains(m.Text, "pull/") {
			prTexts = append(prTexts, m.Text)
		}
	}
	if len(prTexts) != 2 {
		t.Fatalf("pr-link messages = %d, want 2 (one per distinct PR): %v", len(prTexts), prTexts)
	}
	if prTexts[0] != "🔀 [PR #153 · o/r](https://github.com/o/r/pull/153)" {
		t.Fatalf("pr-link text = %q", prTexts[0])
	}
	if strings.Contains(prTexts[0], "{") {
		t.Fatal("pr-link rendered raw JSON")
	}

	// Windowed re-read must make the same emit/skip decisions per line:
	// PR 153's first emission (line 2) is outside the window and lines 3/5
	// stay duplicates, so the window emits zero 153 links and exactly one 154.
	windowed, _, _, _, err := parseClaudeTranscript(path, 2)
	if err != nil {
		t.Fatalf("windowed parse error: %v", err)
	}
	count153, count154 := 0, 0
	for _, m := range windowed {
		if strings.Contains(m.Text, "pull/153") {
			count153++
		}
		if strings.Contains(m.Text, "pull/154") {
			count154++
		}
	}
	if count153 != 0 || count154 != 1 {
		t.Fatalf("windowed read emitted %d pr-153 / %d pr-154 links, want 0/1", count153, count154)
	}
}
