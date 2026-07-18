package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPiSanitizeCWD(t *testing.T) {
	// Live-captured 2026-07-18 against pi 0.80.10: cwd → on-disk directory name.
	cwd := "/private/tmp/claude-501/-Volumes-LancerDev-lancer--claude-worktrees-vendor-cli-parity-multi-account-209d7c/e203bdad-364b-4694-967b-fd9fcf6bc4ed/scratchpad/pi-smoke"
	want := "--private-tmp-claude-501--Volumes-LancerDev-lancer--claude-worktrees-vendor-cli-parity-multi-account-209d7c-e203bdad-364b-4694-967b-fd9fcf6bc4ed-scratchpad-pi-smoke--"
	if got := piSanitizeCWD(cwd); got != want {
		t.Fatalf("piSanitizeCWD(%q) = %q, want %q", cwd, got, want)
	}
}

func TestPiMessageTextUserAssistant(t *testing.T) {
	role, text := piMessageText([]byte(`{"type":"message","id":"429f283d","parentId":"698329a1","timestamp":"2026-07-18T21:59:38.521Z","message":{"role":"user","content":[{"type":"text","text":"Reply with only the word ok and do not edit files."}],"timestamp":1784411978521}}`))
	if role != "user" || text != "Reply with only the word ok and do not edit files." {
		t.Fatalf("user msg → (%q,%q)", role, text)
	}

	// Non-message entries (session header, model_change, thinking_level_change)
	// must not be mistaken for a title candidate.
	if role, _ := piMessageText([]byte(`{"type":"model_change","id":"ff18a27a","parentId":null,"timestamp":"2026-07-18T21:59:38.516Z","provider":"openrouter","modelId":"deepseek/deepseek-v4-flash"}`)); role != "" {
		t.Fatalf("model_change should not be a message, got role %q", role)
	}
}

func TestPiMessageEntryAssistantThinkingAndText(t *testing.T) {
	// Real capture: scratchpad/pi-smoke/pi-stream.jsonl message_end (session-format equivalent).
	line := `{"type":"message","id":"2fe69d43","parentId":"429f283d","timestamp":"2026-07-18T21:59:40.129Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"The user wants me to reply with only the word \"ok\" and not edit any files.","thinkingSignature":"reasoning"},{"type":"text","text":"okok"}],"api":"openai-completions","provider":"openrouter","model":"deepseek/deepseek-v4-flash","stopReason":"stop","timestamp":1784411978612}}`
	msgs := piMessageEntry([]byte(line))
	if len(msgs) != 2 {
		t.Fatalf("got %d msgs, want 2 (thinking + text): %+v", len(msgs), msgs)
	}
	if msgs[0].Role != "thinking" || !strings.Contains(msgs[0].Text, "reply with only the word") {
		t.Fatalf("msgs[0] = %+v", msgs[0])
	}
	if msgs[1].Role != "assistant" || msgs[1].Text != "okok" {
		t.Fatalf("msgs[1] = %+v", msgs[1])
	}
}

func TestPiMessageEntryToolCallAndToolResult(t *testing.T) {
	// Real capture: session file from a live `pi --mode json -p "...bash tool..."` run
	// (scratchpad/pi-smoke/pi-session-with-toolcall.jsonl entries 4 and 5).
	toolCallLine := `{"type":"message","id":"2fe69d43","parentId":"429f283d","timestamp":"2026-07-18T22:48:50.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"The user wants me to run a bash command.","thinkingSignature":"reasoning"},{"type":"toolCall","id":"call_b9f249ce2d674bb7831a0efd","name":"bash","arguments":{"command":"echo fixture-tool-test"}}]}}`
	msgs := piMessageEntry([]byte(toolCallLine))
	var tc *SessionMessage
	for i := range msgs {
		if msgs[i].Role == "toolCall" {
			tc = &msgs[i]
			break
		}
	}
	if tc == nil {
		t.Fatalf("expected toolCall in %+v", msgs)
	}
	if tc.ToolName != "bash" || tc.ToolUseID != "call_b9f249ce2d674bb7831a0efd" {
		t.Fatalf("toolCall = %+v", tc)
	}
	if !strings.Contains(tc.InputJSON, `"command"`) || !strings.Contains(tc.InputJSON, "fixture-tool-test") {
		t.Fatalf("InputJSON = %q", tc.InputJSON)
	}

	toolResultLine := `{"type":"message","id":"bc8511af","parentId":"2fe69d43","timestamp":"2026-07-18T22:48:51.000Z","message":{"role":"toolResult","toolCallId":"call_b9f249ce2d674bb7831a0efd","toolName":"bash","content":[{"type":"text","text":"fixture-tool-test\n"}],"isError":false,"timestamp":1784414941263}}`
	out := piMessageEntry([]byte(toolResultLine))
	if len(out) != 1 || out[0].Role != "toolResult" || out[0].ToolUseID != "call_b9f249ce2d674bb7831a0efd" || out[0].ToolName != "bash" {
		t.Fatalf("toolResult → %+v", out)
	}
	if !strings.Contains(out[0].Text, "fixture-tool-test") {
		t.Fatalf("toolResult text = %q", out[0].Text)
	}
	if out[0].IsError {
		t.Fatalf("toolResult should not be flagged isError")
	}
}

// TestPiMessageEntryUnknownTypeDoesNotError is the spec's required negative
// test: an unknown/forward-compat entry type must parse to nothing, never
// error or emit a bogus message.
func TestPiMessageEntryUnknownTypeDoesNotError(t *testing.T) {
	for _, line := range []string{
		`{"type":"model_change","id":"x","parentId":null,"timestamp":"2026-07-18T21:59:38.516Z","provider":"openrouter","modelId":"deepseek/deepseek-v4-flash"}`,
		`{"type":"thinking_level_change","id":"y","parentId":"x","timestamp":"2026-07-18T21:59:38.516Z","thinkingLevel":"high"}`,
		`{"type":"some_future_event_type","id":"z","payload":{"anything":"goes here"}}`,
		`not even json`,
	} {
		msgs := piMessageEntry([]byte(line))
		if msgs != nil {
			t.Fatalf("unknown/non-message line %q should yield nil, got %+v", line, msgs)
		}
	}
}

func TestPiInspectAndSessionsDiscovery(t *testing.T) {
	dir := t.TempDir()
	home := dir
	cwd := filepath.Join(dir, "project")
	sanitized := piSanitizeCWD(cwd)
	sessionDir := filepath.Join(piSessionsRoot(home), sanitized)
	if err := os.MkdirAll(sessionDir, 0755); err != nil {
		t.Fatal(err)
	}
	sessionID := "019f773d-faf4-7c6b-80f0-aba6c7d05745"
	sessionFile := filepath.Join(sessionDir, "2026-07-18T21-59-38-484Z_"+sessionID+".jsonl")

	lines := []string{
		mustJSONLine(t, map[string]any{"type": "session", "version": 3, "id": sessionID, "timestamp": "2026-07-18T21:59:38.484Z", "cwd": cwd}),
		mustJSONLine(t, map[string]any{"type": "model_change", "id": "a", "parentId": nil, "timestamp": "2026-07-18T21:59:38.516Z", "provider": "openrouter", "modelId": "deepseek/deepseek-v4-flash"}),
		mustJSONLine(t, map[string]any{"type": "message", "id": "b", "parentId": "a", "timestamp": "2026-07-18T21:59:38.521Z", "message": map[string]any{"role": "user", "content": []map[string]any{{"type": "text", "text": "hello pi, run a quick check"}}}}),
	}
	if err := os.WriteFile(sessionFile, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		t.Fatal(err)
	}

	sessions := piSessions(home)
	if len(sessions) != 1 {
		t.Fatalf("got %d sessions, want 1: %+v", len(sessions), sessions)
	}
	s := sessions[0]
	if s.SessionID != sessionID || s.Provider != "pi" || s.CWD != cwd {
		t.Fatalf("session = %+v", s)
	}
	if s.Title != "hello pi, run a quick check" {
		t.Fatalf("title = %q", s.Title)
	}

	found := piFindTranscriptPath(home, sessionID)
	if found != sessionFile {
		t.Fatalf("piFindTranscriptPath = %q, want %q", found, sessionFile)
	}

	result, err := piTranscript(home, sessionID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Messages) != 1 || result.Messages[0].Role != "user" {
		t.Fatalf("transcript = %+v", result)
	}

	if _, err := piTranscript(home, "unknown-session-id", 0); err != errUnknownSessionID {
		t.Fatalf("expected errUnknownSessionID, got %v", err)
	}
}

func mustJSONLine(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
