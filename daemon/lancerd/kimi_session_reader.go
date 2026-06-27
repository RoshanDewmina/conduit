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
// Returns ("","","") for non-message lines.
func kimiMessage(line []byte) (role, text, tool string) {
	var ev struct {
		Type    string `json:"type"`
		Message struct {
			Role    string `json:"role"`
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
			ToolCalls []struct {
				Name string `json:"name"`
			} `json:"toolCalls"`
		} `json:"message"`
	}
	if json.Unmarshal(line, &ev) != nil || ev.Type != "context.append_message" {
		return "", "", ""
	}
	var b strings.Builder
	for _, c := range ev.Message.Content {
		if c.Text != "" {
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString(c.Text)
		}
	}
	t := ""
	if len(ev.Message.ToolCalls) > 0 {
		t = ev.Message.ToolCalls[0].Name
	}
	return ev.Message.Role, b.String(), t
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
		role, text, tool := kimiMessage(sc.Bytes())
		if role == "" {
			continue
		}
		switch role {
		case "user":
			// Skip injected context (system-reminders, plugin/session banners) so the
			// transcript reads as the real exchange, not Kimi's harness scaffolding.
			if text != "" && !isCodexInjectedText(text) {
				msgs = append(msgs, SessionMessage{Role: "user", Text: clampText(text)})
			}
		case "assistant":
			if text != "" {
				msgs = append(msgs, SessionMessage{Role: "assistant", Text: clampText(text)})
			}
			if tool != "" {
				msgs = append(msgs, SessionMessage{Role: "toolCall", ToolName: tool})
			}
		case "tool":
			if text != "" {
				msgs = append(msgs, SessionMessage{Role: "toolResult", Text: clampText(text)})
			}
		}
	}
	return SessionTranscriptResult{Messages: msgs, NextLine: idx, ResetRequired: false}, nil
}
