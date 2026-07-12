package main

import (
	"encoding/json"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// Ephemeral live-status ticker for the phone's status pill (Governor+ G3).
// Orca precedent: status comes from structured tool/hook events, never from
// stream-text regex. These notifications MUST NOT become conversation-ledger
// rows — see persistConversationEvent (server.go).
const (
	liveStatusMethod = "agent.run.liveStatus" // relay type: runStatus

	liveStatusStarting  = "starting"
	liveStatusThinking  = "thinking"
	liveStatusTool      = "tool"
	liveStatusStreaming = "streaming"

	liveStatusTargetCap = 80
)

// liveStatusTracker dedupes per-run status emissions so the phone only sees
// state CHANGES (same state+tool+target is suppressed).
type liveStatusTracker struct {
	mu   sync.Mutex
	last map[string]string // runID → dedupe key
}

func newLiveStatusTracker() *liveStatusTracker {
	return &liveStatusTracker{last: map[string]string{}}
}

var defaultLiveStatus = newLiveStatusTracker()

func clearLiveStatus(runID string) {
	defaultLiveStatus.clear(runID)
}

func (t *liveStatusTracker) clear(runID string) {
	if runID == "" {
		return
	}
	t.mu.Lock()
	delete(t.last, runID)
	t.mu.Unlock()
}

// emitLiveStatus publishes agent.run.liveStatus when the (state, toolName,
// target) triple differs from the last emission for this runID.
func emitLiveStatus(emit emitFunc, runID, state, toolName, target string) {
	defaultLiveStatus.emit(emit, runID, state, toolName, target)
}

func (t *liveStatusTracker) emit(emit emitFunc, runID, state, toolName, target string) {
	if emit == nil || runID == "" || state == "" {
		return
	}
	toolName = strings.TrimSpace(toolName)
	target = truncateLiveStatusTarget(strings.TrimSpace(target))
	key := state + "\x00" + toolName + "\x00" + target

	t.mu.Lock()
	if t.last[runID] == key {
		t.mu.Unlock()
		return
	}
	t.last[runID] = key
	t.mu.Unlock()

	params := map[string]any{
		"runId": runID,
		"state": state,
		"at":    time.Now().UTC().Format(time.RFC3339),
	}
	if toolName != "" {
		params["toolName"] = toolName
	}
	if target != "" {
		params["target"] = target
	}
	emit(liveStatusMethod, params)
}

// liveStatusToolTarget picks the first useful tool-input field for the pill
// caption: file_path, then command, then path, then query — capped at 80 chars.
func liveStatusToolTarget(inputJSON string) string {
	inputJSON = strings.TrimSpace(inputJSON)
	if inputJSON == "" {
		return ""
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(inputJSON), &m); err != nil {
		return ""
	}
	for _, key := range []string{"file_path", "command", "path", "query"} {
		if v, ok := m[key].(string); ok {
			if s := strings.TrimSpace(v); s != "" {
				return truncateLiveStatusTarget(s)
			}
		}
	}
	return ""
}

func truncateLiveStatusTarget(s string) string {
	if s == "" {
		return ""
	}
	if utf8.RuneCountInString(s) <= liveStatusTargetCap {
		return s
	}
	runes := []rune(s)
	return string(runes[:liveStatusTargetCap])
}

func emitLiveStatusStarting(emit emitFunc, runID string) {
	emitLiveStatus(emit, runID, liveStatusStarting, "", "")
}

func emitLiveStatusThinking(emit emitFunc, runID string) {
	emitLiveStatus(emit, runID, liveStatusThinking, "", "")
}

func emitLiveStatusStreaming(emit emitFunc, runID string) {
	emitLiveStatus(emit, runID, liveStatusStreaming, "", "")
}

func emitLiveStatusTool(emit emitFunc, runID, toolName, inputJSON string) {
	emitLiveStatus(emit, runID, liveStatusTool, toolName, liveStatusToolTarget(inputJSON))
}
