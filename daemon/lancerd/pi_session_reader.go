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

// Pi (@earendil-works/pi-coding-agent, bin "pi") stores each session as a
// JSONL file under ~/.pi/agent/sessions/<sanitized-cwd>/<ISO-ts>_<sessionId>.jsonl.
// Live-verified 2026-07-18 against pi 0.80.10 (see docs/CHANGELOG.md and the
// captured fixtures under scratchpad/pi-smoke/): the first line is always a
// {type:"session",version:3,id,timestamp,cwd} header; subsequent lines are
// {type,id,parentId,timestamp,...} envelopes. Observed entry types:
// "model_change", "thinking_level_change", and "message" (wrapping
// {message:{role:user|assistant|toolResult, content:[...]}}). Unknown entry
// types are skipped, never treated as an error (session format is not a
// contractual API — pi's own docs make no format-stability guarantee).

func piSessionsRoot(home string) string {
	return filepath.Join(home, ".pi", "agent", "sessions")
}

// piSanitizeCWD reproduces pi's on-disk directory naming for a cwd: every "/"
// and "." becomes "-", then the result is padded with leading/trailing "-"
// until it starts and ends with "--". Reverse-engineered from live captures
// (a cwd of ".../scratchpad/pi-smoke" produced directory
// "--...-scratchpad-pi-smoke--") rather than from pi's source, since the
// sanitizer itself is internal, unexported behavior — re-verify against a
// newer pi release if session discovery ever silently returns nothing.
func piSanitizeCWD(cwd string) string {
	s := strings.NewReplacer("/", "-", ".", "-").Replace(cwd)
	for !strings.HasPrefix(s, "--") {
		s = "-" + s
	}
	for !strings.HasSuffix(s, "--") {
		s = s + "-"
	}
	return s
}

// piSessions discovers every Pi session JSONL under home's ~/.pi/agent/sessions
// and returns a neutral SessionInfo each. Walks the whole tree (not just the
// current cwd's sanitized subdirectory) so sessions from any project surface,
// matching codexSessions'/kimiSessions' behavior.
func piSessions(home string) []SessionInfo {
	root := piSessionsRoot(home)
	if !fileExists(root) {
		return nil
	}
	var out []SessionInfo
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if filepath.Ext(d.Name()) != ".jsonl" {
			return nil
		}
		if info := piInspect(path); info != nil {
			out = append(out, *info)
		}
		return nil
	})
	return out
}

// piInspect reads one session file's header + first real user prompt without
// loading every message body beyond the title.
func piInspect(path string) *SessionInfo {
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
			Type string `json:"type"`
		}
		if json.Unmarshal(sc.Bytes(), &env) != nil {
			continue
		}
		switch env.Type {
		case "session":
			var p struct {
				ID  string `json:"id"`
				CWD string `json:"cwd"`
			}
			if json.Unmarshal(sc.Bytes(), &p) == nil {
				id, cwd = p.ID, p.CWD
			}
		case "message":
			if title == "" {
				if role, text := piMessageText(sc.Bytes()); role == "user" && text != "" {
					title = truncateTitle(text)
				}
			}
		}
	}
	if id == "" {
		return nil
	}
	if title == "" {
		title = filepath.Base(cwd)
		if title == "" || title == "." {
			title = "Pi session"
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
		Provider:       "pi",
		Title:          title,
		CWD:            cwd,
		State:          state,
		Source:         "transcriptObserved",
		LastActivity:   mod.UTC().Format(time.RFC3339),
		MessageCount:   lineCount,
		transcriptPath: path,
	}
}

// piMessageText extracts (role, concatenated text) from a top-level "message"
// entry's user/assistant text content. Returns ("","") for anything else
// (toolResult messages, non-text-only content).
func piMessageText(line []byte) (role, text string) {
	var env struct {
		Type    string `json:"type"`
		Message struct {
			Role    string `json:"role"`
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		} `json:"message"`
	}
	if json.Unmarshal(line, &env) != nil || env.Type != "message" {
		return "", ""
	}
	if env.Message.Role != "user" && env.Message.Role != "assistant" {
		return "", ""
	}
	var b strings.Builder
	for _, c := range env.Message.Content {
		if c.Type == "text" && c.Text != "" {
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString(c.Text)
		}
	}
	return env.Message.Role, b.String()
}

// piMessageEntry maps one top-level "message" envelope onto zero or more
// neutral SessionMessages. Handles user/assistant text, assistant thinking,
// assistant toolCall content parts, and role:"toolResult" messages — the
// union documented in research-repos/pi packages/ai/src/types.ts:327-417
// (MIT, Copyright 2025 Mario Zechner — patterns only, no verbatim code
// copied) and confirmed against real captures under scratchpad/pi-smoke/.
// Unknown content-part types are skipped, not errored.
func piMessageEntry(line []byte) []SessionMessage {
	var env struct {
		Type      string          `json:"type"`
		Timestamp string          `json:"timestamp"`
		Message   json.RawMessage `json:"message"`
	}
	if json.Unmarshal(line, &env) != nil || env.Type != "message" {
		return nil
	}

	var roleProbe struct {
		Role string `json:"role"`
	}
	if json.Unmarshal(env.Message, &roleProbe) != nil {
		return nil
	}

	switch roleProbe.Role {
	case "user":
		var m struct {
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		}
		if json.Unmarshal(env.Message, &m) != nil {
			return nil
		}
		var b strings.Builder
		for _, c := range m.Content {
			if c.Type == "text" && c.Text != "" {
				if b.Len() > 0 {
					b.WriteString("\n")
				}
				b.WriteString(c.Text)
			}
		}
		if b.Len() == 0 {
			return nil
		}
		return []SessionMessage{{Role: "user", Text: clampText(b.String()), Timestamp: env.Timestamp}}

	case "assistant":
		var m struct {
			Content []struct {
				Type      string          `json:"type"`
				Text      string          `json:"text"`
				Thinking  string          `json:"thinking"`
				ID        string          `json:"id"`
				Name      string          `json:"name"`
				Arguments json.RawMessage `json:"arguments"`
			} `json:"content"`
		}
		if json.Unmarshal(env.Message, &m) != nil {
			return nil
		}
		var out []SessionMessage
		for _, c := range m.Content {
			switch c.Type {
			case "text":
				if c.Text != "" {
					out = append(out, SessionMessage{Role: "assistant", Text: clampText(c.Text), Timestamp: env.Timestamp})
				}
			case "thinking":
				if c.Thinking != "" {
					out = append(out, SessionMessage{Role: "thinking", Text: clampText(c.Thinking), Timestamp: env.Timestamp})
				}
			case "toolCall":
				if c.Name == "" {
					continue
				}
				inputJSON := ""
				if len(c.Arguments) > 0 {
					var raw any
					if json.Unmarshal(c.Arguments, &raw) == nil {
						if b, err := json.Marshal(raw); err == nil {
							inputJSON = string(b)
						}
					}
				}
				summary := c.Name
				if inputJSON != "" {
					summary = claudeToolUseSummary(c.Name, json.RawMessage(inputJSON))
				}
				out = append(out, SessionMessage{
					Role:      "toolCall",
					Text:      clampText(summary),
					ToolName:  c.Name,
					ToolUseID: c.ID,
					InputJSON: clampText(inputJSON),
					Timestamp: env.Timestamp,
				})
			}
		}
		return out

	case "toolResult":
		var m struct {
			ToolCallID string `json:"toolCallId"`
			ToolName   string `json:"toolName"`
			IsError    bool   `json:"isError"`
			Content    []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		}
		if json.Unmarshal(env.Message, &m) != nil {
			return nil
		}
		var b strings.Builder
		for _, c := range m.Content {
			if c.Type == "text" && c.Text != "" {
				if b.Len() > 0 {
					b.WriteString("\n")
				}
				b.WriteString(c.Text)
			}
		}
		return []SessionMessage{{
			Role:      "toolResult",
			Text:      clampText(b.String()),
			ToolName:  m.ToolName,
			ToolUseID: m.ToolCallID,
			IsError:   m.IsError,
			Timestamp: env.Timestamp,
		}}

	default:
		return nil
	}
}

// piFindTranscriptPath locates a session file by session id (uuid). Used by
// the transcript RPC so it never accepts a caller-supplied path.
func piFindTranscriptPath(home, sessionID string) string {
	root := piSessionsRoot(home)
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

func piTranscript(home, sessionID string, sinceLine int) (SessionTranscriptResult, error) {
	path := piFindTranscriptPath(home, sessionID)
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
		msgs = append(msgs, piMessageEntry(sc.Bytes())...)
	}
	return SessionTranscriptResult{Messages: msgs, NextLine: idx, ResetRequired: false}, nil
}
