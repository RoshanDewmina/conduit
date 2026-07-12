package main

import (
	"bufio"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Codex stores each session as a rollout JSONL under ~/.codex/sessions/YYYY/MM/DD/
// rollout-<ts>-<uuid>.jsonl. Lines are {timestamp, type, payload} envelopes; the
// conversation lives in `response_item` lines of payload.type == "message". We skip
// Codex's injected developer/system/context messages (huge base-instructions and
// <environment_context> blobs) so the transcript reads as the real exchange.

func codexSessionsDir(home string) string {
	return filepath.Join(home, ".codex", "sessions")
}

// truncateTitle collapses whitespace and caps a derived session title (a first
// user prompt) to a scannable length. Shared by the Codex and Kimi adapters.
func truncateTitle(s string) string {
	s = strings.TrimSpace(strings.Join(strings.Fields(s), " "))
	const max = 80
	if len(s) > max {
		return s[:max]
	}
	return s
}

func isCodexInjectedText(s string) bool {
	t := strings.TrimSpace(s)
	return strings.HasPrefix(t, "<") ||
		strings.HasPrefix(t, "# AGENTS.md instructions") ||
		strings.HasPrefix(t, "<environment_context") ||
		strings.HasPrefix(t, "<permissions")
}

// codexSessions discovers rollout files and returns a neutral SessionInfo each.
func codexSessions(home string) []SessionInfo {
	root := codexSessionsDir(home)
	if !fileExists(root) {
		return nil
	}
	var out []SessionInfo
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		name := d.Name()
		if !strings.HasPrefix(name, "rollout-") || filepath.Ext(name) != ".jsonl" {
			return nil
		}
		if info := codexInspect(path); info != nil {
			out = append(out, *info)
		}
		return nil
	})
	return out
}

// codexInspect reads a rollout's meta + first real user prompt without loading
// message bodies beyond the title.
func codexInspect(path string) *SessionInfo {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	id, cwd, title := "", "", ""
	lineCount := 0
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)
	for sc.Scan() {
		lineCount++
		var env struct {
			Type    string          `json:"type"`
			Payload json.RawMessage `json:"payload"`
		}
		if json.Unmarshal(sc.Bytes(), &env) != nil {
			continue
		}
		switch env.Type {
		case "session_meta":
			var p struct {
				ID  string `json:"id"`
				CWD string `json:"cwd"`
			}
			if json.Unmarshal(env.Payload, &p) == nil {
				id, cwd = p.ID, p.CWD
			}
		case "response_item":
			if title == "" {
				if role, text := codexMessageText(env.Payload); role == "user" && text != "" && !isCodexInjectedText(text) {
					title = truncateTitle(text)
				}
			}
		}
	}
	if id == "" {
		// Fall back to the uuid in the filename: rollout-<ts>-<uuid>.jsonl
		base := strings.TrimSuffix(filepath.Base(path), ".jsonl")
		if i := strings.LastIndex(base, "-"); i >= 0 && i+1 < len(base) {
			// take the trailing uuid-ish segment group
			parts := strings.SplitN(base, "-", 3)
			if len(parts) == 3 {
				id = parts[2]
			}
		}
	}
	if id == "" {
		return nil
	}
	if title == "" {
		title = filepath.Base(cwd)
		if title == "" || title == "." {
			title = "Codex session"
		}
	}
	fi, _ := f.Stat()
	mod := time.Time{}
	if fi != nil {
		mod = fi.ModTime()
	}
	state := "historical"
	if time.Since(mod) <= recentlyActiveWindow {
		state = "recentlyActive"
	}
	return &SessionInfo{
		SessionID:      id,
		Provider:       "codex",
		Title:          title,
		CWD:            cwd,
		State:          state,
		Source:         "transcriptObserved",
		LastActivity:   mod.UTC().Format(time.RFC3339),
		MessageCount:   lineCount,
		transcriptPath: path,
	}
}

// codexMessageText extracts (role, concatenated text) from a response_item payload
// of type "message". Returns ("","") for non-message items.
func codexMessageText(payload json.RawMessage) (role, text string) {
	var p struct {
		Type    string `json:"type"`
		Role    string `json:"role"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if json.Unmarshal(payload, &p) != nil || p.Type != "message" {
		return "", ""
	}
	var b strings.Builder
	for _, c := range p.Content {
		if c.Text != "" {
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString(c.Text)
		}
	}
	return p.Role, b.String()
}

// codexResponseItem maps one Codex response_item payload onto zero or more
// neutral SessionMessages. Handles message, function_call, and
// function_call_output (previously skipped).
func codexResponseItem(payload json.RawMessage) []SessionMessage {
	var probe struct {
		Type string `json:"type"`
	}
	if json.Unmarshal(payload, &probe) != nil {
		return nil
	}
	switch probe.Type {
	case "message":
		role, text := codexMessageText(payload)
		if text == "" || (role != "user" && role != "assistant") {
			return nil
		}
		if role == "user" && isCodexInjectedText(text) {
			return nil
		}
		return []SessionMessage{{Role: role, Text: clampText(text)}}
	case "function_call":
		var p struct {
			Name      string `json:"name"`
			Arguments string `json:"arguments"`
			CallID    string `json:"call_id"`
		}
		if json.Unmarshal(payload, &p) != nil || p.Name == "" {
			return nil
		}
		inputJSON := p.Arguments
		// Prefer compact JSON; if arguments is already a JSON object string, keep it.
		if inputJSON != "" {
			var raw any
			if json.Unmarshal([]byte(inputJSON), &raw) == nil {
				if b, err := json.Marshal(raw); err == nil {
					inputJSON = string(b)
				}
			}
		}
		summary := p.Name
		if inputJSON != "" {
			summary = claudeToolUseSummary(p.Name, json.RawMessage(inputJSON))
		}
		return []SessionMessage{{
			Role:      "toolCall",
			Text:      clampText(summary),
			ToolName:  p.Name,
			ToolUseID: p.CallID,
			InputJSON: clampText(inputJSON),
		}}
	case "function_call_output":
		var p struct {
			CallID string `json:"call_id"`
			Output string `json:"output"`
		}
		if json.Unmarshal(payload, &p) != nil {
			return nil
		}
		return []SessionMessage{{
			Role:      "toolResult",
			Text:      clampText(p.Output),
			ToolUseID: p.CallID,
		}}
	default:
		return nil
	}
}

// codexFindTranscriptPath locates a rollout file by session id (uuid). Used by the
// transcript RPC so it never accepts a caller-supplied path.
func codexFindTranscriptPath(home, sessionID string) string {
	root := codexSessionsDir(home)
	if !fileExists(root) {
		return ""
	}
	found := ""
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || found != "" {
			return nil
		}
		if strings.Contains(d.Name(), sessionID) && strings.HasSuffix(d.Name(), ".jsonl") {
			found = path
		}
		return nil
	})
	return found
}

func codexTranscript(home, sessionID string, sinceLine int) (SessionTranscriptResult, error) {
	path := codexFindTranscriptPath(home, sessionID)
	if path == "" {
		return SessionTranscriptResult{}, errUnknownSessionID
	}
	f, err := os.Open(path)
	if err != nil {
		return SessionTranscriptResult{}, err
	}
	defer f.Close()

	msgs := make([]SessionMessage, 0, 32)
	idx, total := 0, 0
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)
	for sc.Scan() {
		idx++
		if idx <= sinceLine {
			continue
		}
		total += len(sc.Bytes())
		if total > maxTranscriptBytes {
			break
		}
		var env struct {
			Type    string          `json:"type"`
			Payload json.RawMessage `json:"payload"`
		}
		if json.Unmarshal(sc.Bytes(), &env) != nil || env.Type != "response_item" {
			continue
		}
		msgs = append(msgs, codexResponseItem(env.Payload)...)
	}
	return SessionTranscriptResult{Messages: msgs, NextLine: idx, ResetRequired: false}, nil
}
