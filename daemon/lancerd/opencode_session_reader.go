package main

import (
	"context"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// OpenCode stores sessions in a SQLite database, not per-session JSONL files like
// Claude. Rather than pull a cgo/pure-Go SQLite driver into the daemon, we shell
// out to the read-only `sqlite3` CLI (present on macOS/Linux) — matching how the
// rest of the daemon enriches state via external tools. If `sqlite3` or the DB is
// absent, the reader returns nothing and OpenCode simply doesn't appear (the
// Claude backbone is unaffected).

func openCodeDBPath(home string) string {
	return filepath.Join(home, ".local", "share", "opencode", "opencode.db")
}

// openCodeSessionID prefix — OpenCode session ids look like "ses_…", which lets
// loadSessionTranscript route a transcript request to the right provider without
// a separate lookup table.
func isOpenCodeSessionID(id string) bool { return strings.HasPrefix(id, "ses_") }

func sqlite3Query(dbPath, query string) ([]map[string]any, bool) {
	if _, err := exec.LookPath("sqlite3"); err != nil {
		return nil, false
	}
	if !fileExists(dbPath) {
		return nil, false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	// -readonly never locks the live DB; immutable avoids WAL recovery on a DB
	// another process is writing.
	cmd := exec.CommandContext(ctx, "sqlite3", "-readonly", "-json", dbPath, query)
	out, err := cmd.Output()
	if err != nil || len(out) == 0 {
		return nil, false
	}
	var rows []map[string]any
	if json.Unmarshal(out, &rows) != nil {
		return nil, false
	}
	return rows, true
}

// openCodeSessions lists top-level OpenCode sessions (newest first, capped).
func openCodeSessions(home string) []SessionInfo {
	db := openCodeDBPath(home)
	rows, ok := sqlite3Query(db,
		`SELECT s.id, s.directory, s.title, s.time_updated,
		        (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS msg_count
		 FROM session s
		 WHERE s.parent_id IS NULL AND s.time_archived IS NULL
		 ORDER BY s.time_updated DESC
		 LIMIT 100;`)
	if !ok {
		return nil
	}
	out := make([]SessionInfo, 0, len(rows))
	for _, r := range rows {
		id := asString(r["id"])
		if id == "" {
			continue
		}
		updated := asEpochMillis(r["time_updated"])
		state := "historical"
		if !updated.IsZero() && time.Since(updated) <= recentlyActiveWindow {
			state = "recentlyActive"
		}
		title := asString(r["title"])
		if title == "" {
			title = filepath.Base(asString(r["directory"]))
		}
		out = append(out, SessionInfo{
			SessionID:    id,
			Provider:     "opencode",
			Title:        title,
			CWD:          asString(r["directory"]),
			State:        state,
			Source:       "transcriptObserved",
			LastActivity: updated.UTC().Format(time.RFC3339),
			MessageCount: asInt(r["msg_count"]),
		})
	}
	return out
}

// openCodeTranscript reads a session's parts and maps them to neutral messages.
// `sinceLine` is honored as a part offset so incremental fetch stays cheap.
func openCodeTranscript(home, sessionID string, sinceLine int) (SessionTranscriptResult, error) {
	db := openCodeDBPath(home)
	// Join part→message so a text part inherits its message's role (OpenCode stores
	// user/assistant on the message, not the part) — without this every turn reads
	// as the assistant.
	rows, ok := sqlite3Query(db,
		`SELECT p.data AS data, json_extract(m.data, '$.role') AS role
		 FROM part p JOIN message m ON p.message_id = m.id
		 WHERE p.session_id = '`+sqlEscape(sessionID)+`'
		 ORDER BY p.time_created;`)
	if !ok {
		return SessionTranscriptResult{}, errUnknownSessionID
	}
	resetRequired := false
	if sinceLine > len(rows) {
		sinceLine = 0
		resetRequired = true
	}
	msgs := make([]SessionMessage, 0, len(rows))
	total := 0
	for i, r := range rows {
		total += len(asString(r["data"]))
		if total > maxTranscriptBytes {
			break
		}
		if i < sinceLine {
			continue
		}
		if m, ok := openCodePartToMessage(asString(r["data"]), asString(r["role"])); ok {
			msgs = append(msgs, m)
		}
	}
	return SessionTranscriptResult{Messages: msgs, NextLine: len(rows), ResetRequired: resetRequired}, nil
}

// openCodePartToMessage maps one OpenCode `part.data` JSON object to a neutral
// SessionMessage. Unknown/empty parts return ok=false so they're skipped rather
// than rendered as noise.
func openCodePartToMessage(raw, messageRole string) (SessionMessage, bool) {
	if raw == "" {
		return SessionMessage{}, false
	}
	var p struct {
		Type  string `json:"type"`
		Text  string `json:"text"`
		Tool  string `json:"tool"`
		State struct {
			Input any `json:"input"`
		} `json:"state"`
	}
	if json.Unmarshal([]byte(raw), &p) != nil {
		return SessionMessage{}, false
	}
	msg := SessionMessage{}
	switch p.Type {
	case "text":
		msg.Role = "assistant"
		if messageRole == "user" {
			msg.Role = "user"
		}
		msg.Text = clampText(p.Text)
	case "tool":
		msg.Role = "toolCall"
		msg.ToolName = p.Tool
		msg.Text = clampText(openCodeToolSummary(p.Tool, p.State.Input))
		if p.State.Input != nil {
			if b, err := json.Marshal(p.State.Input); err == nil {
				msg.InputJSON = clampText(string(b))
			}
		}
	case "reasoning":
		msg.Role = "thinking"
		msg.Text = clampText(p.Text)
	default:
		return SessionMessage{}, false
	}
	if msg.Text == "" && msg.ToolName == "" {
		return SessionMessage{}, false
	}
	return msg, true
}

func openCodeToolSummary(tool string, input any) string {
	m, ok := input.(map[string]any)
	if !ok {
		return tool
	}
	for _, k := range []string{"command", "filePath", "path", "pattern"} {
		if v, ok := m[k].(string); ok && v != "" {
			return v
		}
	}
	return tool
}

// MARK: small JSON-value coercion helpers (sqlite3 -json yields strings/numbers)

func asString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	default:
		return ""
	}
}

func asInt(v any) int {
	switch x := v.(type) {
	case float64:
		return int(x)
	case string:
		n, _ := strconv.Atoi(x)
		return n
	default:
		return 0
	}
}

func asEpochMillis(v any) time.Time {
	switch x := v.(type) {
	case float64:
		if x <= 0 {
			return time.Time{}
		}
		return time.UnixMilli(int64(x))
	case string:
		n, err := strconv.ParseInt(x, 10, 64)
		if err != nil || n <= 0 {
			return time.Time{}
		}
		return time.UnixMilli(n)
	default:
		return time.Time{}
	}
}

func clampText(s string) string {
	if len(s) > maxMessageTextBytes {
		return s[:maxMessageTextBytes]
	}
	return s
}

func sqlEscape(s string) string { return strings.ReplaceAll(s, "'", "''") }
