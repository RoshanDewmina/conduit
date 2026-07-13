package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// SessionMessage is one neutral transcript entry returned by agent.sessions.transcript.
// Pattern from happier packages/protocol/src/sessionMessages/transcriptRawRecordV1.ts (MIT):
// one canonical block schema all vendors normalize into (text / tool_use / tool_result / thinking).
type SessionMessage struct {
	Role      string `json:"role"`
	Text      string `json:"text"`
	ToolName  string `json:"toolName,omitempty"`
	ToolUseID string `json:"toolUseId,omitempty"`
	InputJSON string `json:"inputJson,omitempty"`
	IsError   bool   `json:"isError,omitempty"`
	Timestamp string `json:"timestamp,omitempty"`
}

const (
	maxMessageTextBytes = 16 * 1024
	maxTranscriptBytes  = 2 * 1024 * 1024
	// Initial observed-transcript load returns at most this many of the most
	// recent transcript lines, so a huge session doesn't produce a payload too
	// large to seal/relay/render. Older lines remain reachable via pagination.
	maxObservedTailLines = 200
)

type claudeContentBlock struct {
	Type      string          `json:"type"`
	Text      string          `json:"text"`
	Name      string          `json:"name"`
	ID        string          `json:"id"`
	Input     json.RawMessage `json:"input"`
	Content   json.RawMessage `json:"content"`
	ToolUseID string          `json:"tool_use_id"`
	IsError   bool            `json:"is_error"`
	Thinking  string          `json:"thinking"`
}

type claudeMessage struct {
	Role    string          `json:"role"`
	Content json.RawMessage `json:"content"`
}

type claudeLine struct {
	Type      string          `json:"type"`
	SessionID string          `json:"sessionId"`
	Timestamp string          `json:"timestamp"`
	Message   *claudeMessage  `json:"message"`
	AITitle   string          `json:"aiTitle"`
	Subtype   string          `json:"subtype"`
}

// parseClaudeTranscript parses the JSONL transcript at path, skipping the first
// sinceLine lines (already consumed by the caller), and returns the neutral
// messages found after that plus the new total line count. When the accumulated
// message text exceeds maxTranscriptBytes it drops from the FRONT (oldest) so
// the newest end of a long session is kept — matching loadFullObservedTranscript's
// "full session should end up in the ledger" intent for the tail that fits.
// truncated is true when that front-trim ran. aiTitle is the latest
// {"type":"ai-title","aiTitle":…} value seen (empty if none). It tolerates a
// malformed/partially-written final line and never errors on bad individual
// lines — only a failure to open the file is returned as err.
func parseClaudeTranscript(path string, sinceLine int) (msgs []SessionMessage, nextLine int, truncated bool, aiTitle string, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, sinceLine, false, "", err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)

	// A file actively being written can end mid-write-syscall, leaving the
	// final line incomplete JSON. Buffer all lines first so a malformed final
	// line can be excluded from both parsing and the line count — the next
	// poll re-attempts it once the writer finishes it.
	var lines [][]byte
	for sc.Scan() {
		lines = append(lines, append([]byte(nil), sc.Bytes()...))
	}
	if n := len(lines); n > 0 {
		if _, ok := parseClaudeLine(lines[n-1]); !ok {
			lines = lines[:n-1]
		}
	}

	lineNo := len(lines)
	totalBytes := 0
	for i, raw := range lines {
		if len(strings.TrimSpace(string(raw))) == 0 {
			continue
		}
		// Capture ai-title from the whole file (including skipped prefix lines)
		// so attachObservedSession still gets the session title after a tail load.
		var probe claudeLine
		if json.Unmarshal(raw, &probe) == nil && probe.Type == "ai-title" && probe.AITitle != "" {
			aiTitle = probe.AITitle
		}
		if i+1 <= sinceLine {
			continue
		}
		msg, ok := parseClaudeLine(raw)
		if !ok {
			continue
		}
		for j := range msg {
			msg[j].Text = clampText(msg[j].Text)
			msg[j].InputJSON = clampText(msg[j].InputJSON)
			totalBytes += len(msg[j].Text)
		}
		msgs = append(msgs, msg...)
	}

	// Over budget: drop leading (oldest) messages until we fit. Prefer keeping
	// the newest end — a phone importing a long Claude session cares about
	// recent turns, not the first 2MB of preamble.
	if totalBytes > maxTranscriptBytes {
		truncated = true
		for len(msgs) > 0 && totalBytes > maxTranscriptBytes {
			totalBytes -= len(msgs[0].Text)
			msgs = msgs[1:]
		}
	}
	return msgs, lineNo, truncated, aiTitle, nil
}

// parseClaudeLine converts one raw JSONL line into zero or more neutral
// messages. ok is false only when the line is not valid JSON at all (treated
// as a malformed/partial write and skipped); a recognized-but-empty line
// (e.g. pure metadata) returns ok=true with a nil slice.
func parseClaudeLine(raw []byte) ([]SessionMessage, bool) {
	var l claudeLine
	if err := json.Unmarshal(raw, &l); err != nil {
		return nil, false
	}

	switch l.Type {
	case "user":
		if l.Message == nil {
			return nil, true
		}
		return claudeUserMessages(l, raw), true
	case "assistant":
		if l.Message == nil {
			return nil, true
		}
		return claudeAssistantMessages(l), true
	case "system":
		text := l.Subtype
		if text == "" {
			text = "system event"
		}
		return []SessionMessage{{Role: "system", Text: text, Timestamp: l.Timestamp}}, true
	case "ai-title", "agent-name", "last-prompt", "queue-operation", "attachment",
		"summary", "mode", "permission-mode", "bridge-session", "file-history-snapshot":
		return nil, true
	case "":
		return nil, true
	default:
		text := string(raw)
		if len(text) > maxMessageTextBytes {
			text = text[:maxMessageTextBytes]
		}
		return []SessionMessage{{Role: "unknown", Text: text, Timestamp: l.Timestamp}}, true
	}
}

func claudeUserMessages(l claudeLine, raw []byte) []SessionMessage {
	var contentStr string
	if err := json.Unmarshal(l.Message.Content, &contentStr); err == nil {
		if contentStr == "" {
			return nil
		}
		if isObservedWrapperUserText(contentStr) {
			return nil
		}
		return []SessionMessage{{Role: "user", Text: contentStr, Timestamp: l.Timestamp}}
	}

	var blocks []claudeContentBlock
	if err := json.Unmarshal(l.Message.Content, &blocks); err != nil {
		return nil
	}
	var out []SessionMessage
	for _, b := range blocks {
		switch b.Type {
		case "text":
			if b.Text != "" {
				out = append(out, SessionMessage{Role: "user", Text: b.Text, Timestamp: l.Timestamp})
			}
		case "tool_result":
			out = append(out, SessionMessage{
				Role:      "toolResult",
				Text:      claudeToolResultText(b.Content),
				ToolUseID: b.ToolUseID,
				IsError:   b.IsError,
				Timestamp: l.Timestamp,
			})
		}
	}
	return out
}

func claudeToolResultText(content json.RawMessage) string {
	if len(content) == 0 {
		return ""
	}
	var s string
	if err := json.Unmarshal(content, &s); err == nil {
		return s
	}
	var blocks []claudeContentBlock
	if err := json.Unmarshal(content, &blocks); err == nil {
		var parts []string
		for _, b := range blocks {
			if b.Type == "text" && b.Text != "" {
				parts = append(parts, b.Text)
			}
		}
		return strings.Join(parts, "\n")
	}
	return string(content)
}

func claudeAssistantMessages(l claudeLine) []SessionMessage {
	var blocks []claudeContentBlock
	if err := json.Unmarshal(l.Message.Content, &blocks); err != nil {
		return nil
	}
	var out []SessionMessage
	for _, b := range blocks {
		switch b.Type {
		case "text":
			if b.Text != "" {
				out = append(out, SessionMessage{Role: "assistant", Text: b.Text, Timestamp: l.Timestamp})
			}
		case "thinking":
			out = append(out, SessionMessage{
				Role:      "thinking",
				Text:      b.Thinking,
				Timestamp: l.Timestamp,
			})
		case "redacted_thinking":
			out = append(out, SessionMessage{
				Role:      "thinking",
				Text:      "(redacted)",
				Timestamp: l.Timestamp,
			})
		case "tool_use":
			out = append(out, SessionMessage{
				Role:      "toolCall",
				Text:      claudeToolUseSummary(b.Name, b.Input),
				ToolName:  b.Name,
				ToolUseID: b.ID,
				InputJSON: string(b.Input),
				Timestamp: l.Timestamp,
			})
		}
	}
	return out
}

// computeEditStats best-effort line counts for Claude Edit/Write/MultiEdit
// inputs. Returns (+added, -removed); unknown tools / bad JSON → (0, 0).
func computeEditStats(toolName, inputJSON string) (added, removed int) {
	if inputJSON == "" {
		return 0, 0
	}
	switch toolName {
	case "Edit":
		var in struct {
			OldString string `json:"old_string"`
			NewString string `json:"new_string"`
		}
		if json.Unmarshal([]byte(inputJSON), &in) != nil {
			return 0, 0
		}
		return countLines(in.NewString), countLines(in.OldString)
	case "Write":
		var in struct {
			Content string `json:"content"`
		}
		if json.Unmarshal([]byte(inputJSON), &in) != nil {
			return 0, 0
		}
		return countLines(in.Content), 0
	case "MultiEdit":
		var in struct {
			Edits []struct {
				OldString string `json:"old_string"`
				NewString string `json:"new_string"`
			} `json:"edits"`
		}
		if json.Unmarshal([]byte(inputJSON), &in) != nil {
			return 0, 0
		}
		for _, e := range in.Edits {
			added += countLines(e.NewString)
			removed += countLines(e.OldString)
		}
		return added, removed
	default:
		return 0, 0
	}
}

func countLines(s string) int {
	if s == "" {
		return 0
	}
	return strings.Count(s, "\n") + 1
}

func claudeToolUseSummary(name string, input json.RawMessage) string {
	if len(input) == 0 {
		return name
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(input, &fields); err != nil {
		return name
	}
	for _, key := range []string{"command", "file_path", "path", "query", "prompt", "skill"} {
		if raw, ok := fields[key]; ok {
			var v string
			if json.Unmarshal(raw, &v) == nil && v != "" {
				return fmt.Sprintf("%s: %s", name, v)
			}
		}
	}
	return name
}
