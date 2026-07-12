package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

var errUnknownSessionID = errors.New("unknown sessionId")

// SessionInfo is one discovered Claude Code session, as returned by
// agent.sessions.list. Field names/shapes are fixed by the wire contract —
// the iOS app builds against this exact JSON.
type SessionInfo struct {
	SessionID    string `json:"sessionId"`
	Provider     string `json:"provider"`
	Title        string `json:"title"`
	CWD          string `json:"cwd"`
	State        string `json:"state"`
	Source       string `json:"source"`
	LastActivity string `json:"lastActivity"`
	MessageCount int    `json:"messageCount"`

	transcriptPath string
}

const recentlyActiveWindow = 3 * time.Minute

// buildSessionIndex discovers every Claude Code transcript under home's
// ~/.claude/projects, enriches state from `claude agents --json --all` for
// the sessions that command knows about (backgrounded/active ones only —
// interactive sessions started directly in a terminal are not covered, which
// is expected), and returns the merged, lastActivity-descending list.
// sessionIndexCache memoizes buildSessionIndex results for a short TTL. The
// phone's Agents section polls every ~5s over the relay; without a cache each
// poll re-walked ~/.claude/projects and ~/.codex/sessions (observed at 778MB /
// hundreds of JSONL files), which is wasted work even now that handlers run
// off the message loop.
var sessionIndexCache struct {
	mu      sync.Mutex
	home    string
	result  []SessionInfo
	fetched time.Time
}

const sessionIndexCacheTTL = 5 * time.Second

func buildSessionIndex(home string) ([]SessionInfo, error) {
	if home == "" {
		home = agentHomeDir()
	}
	sessionIndexCache.mu.Lock()
	if sessionIndexCache.home == home && time.Since(sessionIndexCache.fetched) < sessionIndexCacheTTL && sessionIndexCache.result != nil {
		cached := sessionIndexCache.result
		sessionIndexCache.mu.Unlock()
		return cached, nil
	}
	sessionIndexCache.mu.Unlock()
	result, err := buildSessionIndexUncached(home)
	if err == nil {
		sessionIndexCache.mu.Lock()
		sessionIndexCache.home = home
		sessionIndexCache.result = result
		sessionIndexCache.fetched = time.Now()
		sessionIndexCache.mu.Unlock()
	}
	return result, err
}

func buildSessionIndexUncached(home string) ([]SessionInfo, error) {
	projectsDir := filepath.Join(home, ".claude", "projects")
	bare, err := scanTranscripts(projectsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return []SessionInfo{}, nil
		}
		return nil, err
	}

	// Sort by mtime descending and cap before the expensive inspect loop.
	// The final sort+cap below still handles the combined list correctly.
	sort.Slice(bare, func(i, j int) bool {
		return bare[i].LastModified.After(bare[j].LastModified)
	})
	if len(bare) > maxSessionsReturned {
		bare = bare[:maxSessionsReturned]
	}

	enrich := fetchClaudeAgents()

	out := make([]SessionInfo, 0, len(bare))
	for _, b := range bare {
		if b.SessionID == "" {
			continue
		}
		title, cwd, lineCount := inspectTranscript(b.TranscriptPath, b.CWD)
		info := SessionInfo{
			SessionID:      b.SessionID,
			Provider:       "claudeCode",
			CWD:            cwd,
			Title:          title,
			MessageCount:   lineCount,
			Source:         "transcriptObserved",
			LastActivity:   b.LastModified.UTC().Format(time.RFC3339),
			transcriptPath: b.TranscriptPath,
		}
		if e, ok := enrich[b.SessionID]; ok {
			info.Source = "providerManaged"
			info.State = e.state
		} else if time.Since(b.LastModified) <= recentlyActiveWindow {
			info.State = "recentlyActive"
		} else {
			info.State = "historical"
		}
		out = append(out, info)
	}

	// Other providers store sessions differently (OpenCode = SQLite, Codex/Kimi =
	// their own JSONL formats). Each appends neutral SessionInfo; the Claude
	// transcript scan stays the backbone.
	out = append(out, openCodeSessions(home)...)
	out = append(out, codexSessions(home)...)
	out = append(out, kimiSessions(home)...)

	sort.Slice(out, func(i, j int) bool { return out[i].LastActivity > out[j].LastActivity })
	// Cap to the most-recent sessions: the phone is a glanceable surface and
	// shipping hundreds of historical sessions over the relay is what made the list
	// scroll-laggy. Recent/active sessions are what matter.
	if len(out) > maxSessionsReturned {
		out = out[:maxSessionsReturned]
	}
	return out, nil
}

const maxSessionsReturned = 60

// findSessionTranscriptPath locates the on-disk transcript path for a
// sessionId via the same scan buildSessionIndex uses, so the transcript RPC
// never accepts a caller-supplied path. Empty return means unknown id.
func findSessionTranscriptPath(home, sessionID string) string {
	if home == "" {
		home = agentHomeDir()
	}
	if sessionID == "" {
		return ""
	}
	projectsDir := filepath.Join(home, ".claude", "projects")
	bare, err := scanTranscripts(projectsDir)
	if err != nil {
		return ""
	}
	for _, b := range bare {
		if b.SessionID == sessionID {
			return b.TranscriptPath
		}
	}
	return ""
}

type claudeAgentEnrichment struct {
	state string
}

var (
	agentCacheMu      sync.Mutex
	agentCacheResult  map[string]claudeAgentEnrichment
	agentCacheTime    time.Time
	agentCacheTTL     = 10 * time.Second
)

// fetchClaudeAgents runs `claude agents --json --all` with a short timeout and
// parses whatever it returns defensively — its schema is not contractual, so
// any shape that isn't a sessionId+state pair is simply skipped. A failure,
// timeout, or empty result yields an empty map (transcript-only enrichment).
// Results are cached for agentCacheTTL to avoid a 5s shell-out on every list call.
func fetchClaudeAgents() map[string]claudeAgentEnrichment {
	agentCacheMu.Lock()
	if agentCacheResult != nil && time.Since(agentCacheTime) < agentCacheTTL {
		cached := agentCacheResult
		agentCacheMu.Unlock()
		return cached
	}
	agentCacheMu.Unlock()

	out := map[string]claudeAgentEnrichment{}
	bin, err := exec.LookPath("claude")
	if err != nil {
		return out
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	data, err := exec.CommandContext(ctx, bin, "agents", "--json", "--all").Output()
	if err != nil || len(data) == 0 {
		return out
	}
	var rows []map[string]json.RawMessage
	if json.Unmarshal(data, &rows) != nil {
		return out
	}
	for _, row := range rows {
		var sessionID string
		if raw, ok := row["sessionId"]; ok {
			_ = json.Unmarshal(raw, &sessionID)
		}
		if sessionID == "" {
			continue
		}
		var rawState string
		if raw, ok := row["status"]; ok {
			_ = json.Unmarshal(raw, &rawState)
		} else if raw, ok := row["state"]; ok {
			_ = json.Unmarshal(raw, &rawState)
		}
		out[sessionID] = claudeAgentEnrichment{state: mapClaudeAgentState(rawState)}
	}

	agentCacheMu.Lock()
	agentCacheResult = out
	agentCacheTime = time.Now()
	agentCacheMu.Unlock()

	return out
}

func mapClaudeAgentState(raw string) string {
	switch raw {
	case "busy", "running", "working":
		return "working"
	case "waiting_input", "waitingForInput", "needs_input":
		return "waitingForInput"
	case "idle":
		return "idle"
	case "completed", "done", "failed", "stopped":
		return "completed"
	default:
		return "unknown"
	}
}

// inspectTranscript makes one pass over the transcript to extract everything
// buildSessionIndex needs beyond what the bare scan gives: the title (the
// ai-title line if present, else the first user prompt text, else the cwd
// basename), a cwd fallback (firstSessionMeta often lands on a metadata line
// like "last-prompt" that carries no cwd — scan further for one), and the
// line count for messageCount.
func inspectTranscript(path, bareCWD string) (title, cwd string, lineCount int) {
	cwd = bareCWD
	f, err := os.Open(path)
	if err != nil {
		return filepath.Base(cwd), cwd, 0
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)
	var aiTitle, firstUserText string
	for sc.Scan() {
		lineCount++
		var probe struct {
			Type    string `json:"type"`
			AITitle string `json:"aiTitle"`
			CWD     string `json:"cwd"`
			Message *struct {
				Role    string          `json:"role"`
				Content json.RawMessage `json:"content"`
			} `json:"message"`
		}
		if json.Unmarshal(sc.Bytes(), &probe) != nil {
			continue
		}
		if cwd == "" && probe.CWD != "" {
			cwd = probe.CWD
		}
		if aiTitle == "" && probe.Type == "ai-title" && probe.AITitle != "" {
			aiTitle = probe.AITitle
		}
		if firstUserText == "" && probe.Type == "user" && probe.Message != nil {
			var s string
			if json.Unmarshal(probe.Message.Content, &s) == nil && s != "" {
				firstUserText = s
			}
		}
	}

	switch {
	case aiTitle != "":
		title = aiTitle
	case firstUserText != "":
		if len(firstUserText) > 80 {
			firstUserText = firstUserText[:80]
		}
		title = firstUserText
	default:
		title = filepath.Base(cwd)
	}
	return title, cwd, lineCount
}

// SessionTranscriptResult is the agent.sessions.transcript RPC result.
type SessionTranscriptResult struct {
	Messages      []SessionMessage `json:"messages"`
	NextLine      int              `json:"nextLine"`
	ResetRequired bool             `json:"resetRequired"`
	// Truncated is true when message text exceeded maxTranscriptBytes and
	// oldest messages were dropped so the newest end remains.
	Truncated bool `json:"truncated,omitempty"`
	// Title is the latest Claude ai-title value when present (attach imports
	// use this; live transcript RPCs may leave it empty for other providers).
	Title string `json:"title,omitempty"`
}

// loadSessionTranscript resolves sessionID to its on-disk transcript path
// (rejecting unknown ids) and parses messages since sinceLine, signaling
// resetRequired if the file has shrunk/rotated since the caller's sinceLine.
func loadSessionTranscript(home, sessionID string, sinceLine int) (SessionTranscriptResult, error) {
	if home == "" {
		home = agentHomeDir()
	}
	// Route by provider. OpenCode ids are "ses_…", Kimi ids are "session_…".
	// Codex and Claude ids are both bare UUIDs, so try Claude's on-disk transcript
	// first and fall back to Codex's rollout files when Claude doesn't have it.
	switch {
	case isOpenCodeSessionID(sessionID):
		return openCodeTranscript(home, sessionID, sinceLine)
	case strings.HasPrefix(sessionID, "session_"):
		return kimiTranscript(home, sessionID, sinceLine)
	}
	path := findSessionTranscriptPath(home, sessionID)
	if path == "" {
		if codexFindTranscriptPath(home, sessionID) != "" {
			return codexTranscript(home, sessionID, sinceLine)
		}
		return SessionTranscriptResult{}, errUnknownSessionID
	}
	resetRequired := false
	if sinceLine > 0 {
		if n := countTranscriptLines(path); n < sinceLine {
			sinceLine = 0
			resetRequired = true
		}
	} else {
		// Initial load (sinceLine==0): only return the TAIL of a long transcript.
		// A multi-thousand-message session (e.g. 2000+ lines) serialized whole is
		// too large to seal+relay+render and would just spin — and the viewer wants
		// recent activity, not the start. Start near the end; subsequent polls
		// continue from nextLine. Caps payload to ~maxObservedTailLines messages.
		if n := countTranscriptLines(path); n > maxObservedTailLines {
			sinceLine = n - maxObservedTailLines
		}
	}
	msgs, nextLine, truncated, aiTitle, err := parseClaudeTranscript(path, sinceLine)
	if err != nil {
		return SessionTranscriptResult{}, err
	}
	if msgs == nil {
		msgs = []SessionMessage{}
	}
	return SessionTranscriptResult{
		Messages:      msgs,
		NextLine:      nextLine,
		ResetRequired: resetRequired,
		Truncated:     truncated,
		Title:         aiTitle,
	}, nil
}

// loadFullObservedTranscript is like loadSessionTranscript but always returns
// the complete transcript regardless of length. agent.conversations
// .attachObservedSession (Task 9) imports into host-local SQLite rather than
// serializing the result over an RPC transport, so the tail-cap
// loadSessionTranscript applies to Claude sessions for live viewing (see
// maxObservedTailLines) doesn't apply here — a full session, however long,
// should end up in the ledger.
func loadFullObservedTranscript(home, sessionID string) (SessionTranscriptResult, error) {
	if home == "" {
		home = agentHomeDir()
	}
	switch {
	case isOpenCodeSessionID(sessionID):
		return openCodeTranscript(home, sessionID, 0)
	case strings.HasPrefix(sessionID, "session_"):
		return kimiTranscript(home, sessionID, 0)
	}
	path := findSessionTranscriptPath(home, sessionID)
	if path == "" {
		if codexFindTranscriptPath(home, sessionID) != "" {
			return codexTranscript(home, sessionID, 0)
		}
		return SessionTranscriptResult{}, errUnknownSessionID
	}
	msgs, _, truncated, aiTitle, err := parseClaudeTranscript(path, 0)
	if err != nil {
		return SessionTranscriptResult{}, err
	}
	if msgs == nil {
		msgs = []SessionMessage{}
	}
	return SessionTranscriptResult{Messages: msgs, Truncated: truncated, Title: aiTitle}, nil
}

func countTranscriptLines(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<24)
	n := 0
	for sc.Scan() {
		n++
	}
	return n
}
