package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Kimi Code stores each session under ~/.kimi-code/sessions/<wd-hash>/session_<id>/
// agents/main/wire.jsonl, indexed by ~/.kimi-code/session_index.jsonl. The wire log
// is typed events; conversation turns are `context.append_message` lines carrying a
// {role, content:[{type,text}], toolCalls} message.

func kimiIndexPath(home string) string {
	return filepath.Join(home, ".kimi-code", "session_index.jsonl")
}

type kimiIndexEntry struct {
	SessionID  string `json:"sessionId"`
	SessionDir string `json:"sessionDir"`
	WorkDir    string `json:"workDir"`
}

func kimiWirePath(sessionDir string) string {
	return filepath.Join(sessionDir, "agents", "main", "wire.jsonl")
}

func kimiReadIndex(home string) []kimiIndexEntry {
	f, err := os.Open(kimiIndexPath(home))
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []kimiIndexEntry
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<16), 1<<20)
	for sc.Scan() {
		var e kimiIndexEntry
		if json.Unmarshal(sc.Bytes(), &e) == nil && e.SessionID != "" {
			out = append(out, e)
		}
	}
	return out
}

func kimiSessions(home string) []SessionInfo {
	var out []SessionInfo
	for _, e := range kimiReadIndex(home) {
		wire := kimiWirePath(e.SessionDir)
		fi, err := os.Stat(wire)
		if err != nil {
			continue
		}
		mod := fi.ModTime()
		state := "historical"
		if time.Since(mod) <= recentlyActiveWindow {
			state = "recentlyActive"
		}
		title, count := kimiInspect(wire)
		if title == "" {
			title = filepath.Base(e.WorkDir)
			if title == "" || title == "." {
				title = "Kimi session"
			}
		}
		out = append(out, SessionInfo{
			SessionID:      e.SessionID,
			Provider:       "kimi",
			Title:          title,
			CWD:            e.WorkDir,
			State:          state,
			Source:         "transcriptObserved",
			LastActivity:   mod.UTC().Format(time.RFC3339),
			MessageCount:   count,
			transcriptPath: wire,
		})
	}
	return out
}

func kimiInspect(wire string) (title string, count int) {
	f, err := os.Open(wire)
	if err != nil {
		return "", 0
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)
	for sc.Scan() {
		count++
		if title != "" {
			continue
		}
		if role, text, _ := kimiMessage(sc.Bytes()); role == "user" && text != "" && !isCodexInjectedText(text) {
			title = truncateTitle(text)
		}
	}
	return title, count
}

// kimiMessage parses a context.append_message line into (role, text, toolName).
// Returns ("","","") for non-message lines. toolName is the first tool call's
// name when present (flat or nested function.name).
func kimiMessage(line []byte) (role, text, tool string) {
	msgs := kimiMessagesFromLine(line)
	if len(msgs) == 0 {
		return "", "", ""
	}
	// Preserve the historical helper contract: role/text from the first message,
	// tool from the first toolCall (which may be msgs[0] or a later sibling).
	role = msgs[0].Role
	text = msgs[0].Text
	for _, m := range msgs {
		if m.Role == "toolCall" && m.ToolName != "" {
			tool = m.ToolName
			break
		}
	}
	if role == "toolCall" {
		// Assistant lines that are tool-only still report as assistant+tool for
		// the inspect/title path; prefer the textual role when present.
		role = "assistant"
		text = ""
	}
	return role, text, tool
}

// kimiMessagesFromLine converts one wire.jsonl line into zero or more neutral
// SessionMessages (assistant prose + toolCall entries with InputJSON).
func kimiMessagesFromLine(line []byte) []SessionMessage {
	var ev struct {
		Type    string `json:"type"`
		Message struct {
			Role    string `json:"role"`
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
			ToolCalls []struct {
				ID       string `json:"id"`
				Name     string `json:"name"`
				Arguments any    `json:"arguments"`
				Function *struct {
					Name      string `json:"name"`
					Arguments any    `json:"arguments"`
				} `json:"function"`
			} `json:"toolCalls"`
		} `json:"message"`
	}
	if json.Unmarshal(line, &ev) != nil || ev.Type != "context.append_message" {
		return nil
	}
	var text strings.Builder
	for _, c := range ev.Message.Content {
		if c.Text != "" {
			if text.Len() > 0 {
				text.WriteString("\n")
			}
			text.WriteString(c.Text)
		}
	}
	var out []SessionMessage
	switch ev.Message.Role {
	case "user":
		if text.Len() > 0 && !isCodexInjectedText(text.String()) {
			out = append(out, SessionMessage{Role: "user", Text: clampText(text.String())})
		}
	case "assistant":
		if text.Len() > 0 {
			out = append(out, SessionMessage{Role: "assistant", Text: clampText(text.String())})
		}
		for _, tc := range ev.Message.ToolCalls {
			name := tc.Name
			args := tc.Arguments
			id := tc.ID
			if tc.Function != nil {
				if tc.Function.Name != "" {
					name = tc.Function.Name
				}
				if tc.Function.Arguments != nil {
					args = tc.Function.Arguments
				}
			}
			if name == "" {
				continue
			}
			inputJSON := kimiArgsJSON(args)
			summary := name
			if inputJSON != "" {
				summary = claudeToolUseSummary(name, json.RawMessage(inputJSON))
			}
			out = append(out, SessionMessage{
				Role:      "toolCall",
				Text:      clampText(summary),
				ToolName:  name,
				ToolUseID: id,
				InputJSON: clampText(inputJSON),
			})
		}
	case "tool":
		if text.Len() > 0 {
			out = append(out, SessionMessage{Role: "toolResult", Text: clampText(text.String())})
		}
	}
	return out
}

func kimiArgsJSON(args any) string {
	if args == nil {
		return ""
	}
	switch v := args.(type) {
	case string:
		// OpenAI-style: arguments is a JSON string.
		var raw any
		if json.Unmarshal([]byte(v), &raw) == nil {
			if b, err := json.Marshal(raw); err == nil {
				return string(b)
			}
		}
		return v
	default:
		b, err := json.Marshal(v)
		if err != nil {
			return ""
		}
		return string(b)
	}
}

func kimiFindWirePath(home, sessionID string) string {
	for _, e := range kimiReadIndex(home) {
		if e.SessionID == sessionID {
			return kimiWirePath(e.SessionDir)
		}
	}
	return ""
}

func kimiTranscript(home, sessionID string, sinceLine int) (SessionTranscriptResult, error) {
	wire := kimiFindWirePath(home, sessionID)
	if wire == "" {
		return SessionTranscriptResult{}, errUnknownSessionID
	}
	f, err := os.Open(wire)
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
		msgs = append(msgs, kimiMessagesFromLine(sc.Bytes())...)
	}
	return SessionTranscriptResult{Messages: msgs, NextLine: idx, ResetRequired: false}, nil
}
