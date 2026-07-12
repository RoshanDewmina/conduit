package main

import (
	"bytes"
	"database/sql"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// repo_rpc.go — read-only, path-jailed repo/diff RPCs for the Governor+ review
// surface. Wire field names are frozen for lane G2.

const (
	repoFileDefaultMaxBytes = 256 * 1024
	repoFileDiffMaxBytes    = 500 * 1024
)

// ── wire types (frozen) ───────────────────────────────────────────────────

type repoDiffFile struct {
	Path    string `json:"path"`
	Added   int    `json:"added"`
	Removed int    `json:"removed"`
	Status  string `json:"status"`
}

type repoDiffResult struct {
	Supported    bool           `json:"supported"`
	Files        []repoDiffFile `json:"files"`
	TotalAdded   int            `json:"totalAdded"`
	TotalRemoved int            `json:"totalRemoved"`
}

type repoDiffLine struct {
	Kind  string `json:"kind"` // context | add | del
	OldNo *int   `json:"oldNo,omitempty"`
	NewNo *int   `json:"newNo,omitempty"`
	Text  string `json:"text"`
}

type repoDiffHunk struct {
	Header   string         `json:"header"`
	OldStart int            `json:"oldStart"`
	NewStart int            `json:"newStart"`
	Lines    []repoDiffLine `json:"lines"`
}

type repoFileDiffResult struct {
	Hunks     []repoDiffHunk `json:"hunks"`
	Truncated bool           `json:"truncated,omitempty"`
}

type repoTreeEntry struct {
	Name  string `json:"name"`
	IsDir bool   `json:"isDir"`
}

type repoFileResult struct {
	Content   string `json:"content,omitempty"`
	Truncated bool   `json:"truncated,omitempty"`
	Size      int64  `json:"size,omitempty"`
	Binary    bool   `json:"binary,omitempty"`
}

type repoTurnDiffRequest struct {
	ConversationID string `json:"conversationId"`
	TurnID         string `json:"turnId"`
}

type repoSessionDiffRequest struct {
	ConversationID string `json:"conversationId"`
}

type repoFileDiffRequest struct {
	ConversationID string `json:"conversationId"`
	Path           string `json:"path"`
	TurnID         string `json:"turnId,omitempty"`
}

type repoTreeRequest struct {
	ConversationID string `json:"conversationId"`
	Path           string `json:"path"`
}

type repoFileRequest struct {
	ConversationID string `json:"conversationId"`
	Path           string `json:"path"`
	MaxBytes       int    `json:"maxBytes,omitempty"`
}

// ── RPC handlers ──────────────────────────────────────────────────────────

func (s *server) repoTurnDiff(req repoTurnDiffRequest) (repoDiffResult, error) {
	empty := repoDiffResult{Supported: false, Files: []repoDiffFile{}}
	if s.conversations == nil {
		return empty, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" || req.TurnID == "" {
		return empty, fmt.Errorf("conversationId and turnId are required")
	}
	conv, err := s.conversations.conversationByID(req.ConversationID)
	if err != nil {
		return empty, err
	}
	startOID, endOID, err := s.conversations.turnBaselineOIDs(req.ConversationID, req.TurnID)
	if err == sql.ErrNoRows {
		return empty, fmt.Errorf("turn not found")
	}
	if err != nil {
		return empty, err
	}
	if startOID == "" {
		return empty, nil
	}
	if endOID == "" {
		endOID = stampTurnBaseline(conv.CWD)
		if endOID == "" {
			return empty, nil
		}
	}
	return diffTrees(conv.CWD, startOID, endOID)
}

func (s *server) repoSessionDiff(req repoSessionDiffRequest) (repoDiffResult, error) {
	empty := repoDiffResult{Supported: false, Files: []repoDiffFile{}}
	if s.conversations == nil {
		return empty, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" {
		return empty, fmt.Errorf("conversationId is required")
	}
	conv, err := s.conversations.conversationByID(req.ConversationID)
	if err != nil {
		return empty, err
	}
	startOID, err := s.conversations.firstTurnBaselineStart(req.ConversationID)
	if err != nil {
		return empty, err
	}
	if startOID == "" {
		return empty, nil
	}
	endOID := stampTurnBaseline(conv.CWD)
	if endOID == "" {
		return empty, nil
	}
	return diffTrees(conv.CWD, startOID, endOID)
}

func (s *server) repoFileDiff(req repoFileDiffRequest) (repoFileDiffResult, error) {
	empty := repoFileDiffResult{Hunks: []repoDiffHunk{}}
	if s.conversations == nil {
		return empty, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" || req.Path == "" {
		return empty, fmt.Errorf("conversationId and path are required")
	}
	conv, err := s.conversations.conversationByID(req.ConversationID)
	if err != nil {
		return empty, err
	}
	if _, err := ensureAbsUnder(conv.CWD, req.Path); err != nil {
		return empty, err
	}

	var startOID, endOID string
	if req.TurnID != "" {
		startOID, endOID, err = s.conversations.turnBaselineOIDs(req.ConversationID, req.TurnID)
		if err == sql.ErrNoRows {
			return empty, fmt.Errorf("turn not found")
		}
		if err != nil {
			return empty, err
		}
	} else {
		startOID, err = s.conversations.firstTurnBaselineStart(req.ConversationID)
		if err != nil {
			return empty, err
		}
	}
	if startOID == "" {
		return empty, nil
	}
	if endOID == "" {
		endOID = stampTurnBaseline(conv.CWD)
		if endOID == "" {
			return empty, nil
		}
	}

	out, err := gitDiffOut(conv.CWD,
		"--no-pager", "diff", "-U3", startOID, endOID, "--", req.Path)
	if err != nil {
		return empty, fmt.Errorf("git diff: %v", err)
	}
	truncated := false
	if len(out) > repoFileDiffMaxBytes {
		out = out[:repoFileDiffMaxBytes]
		truncated = true
	}
	hunks := parseUnifiedDiffHunks(out)
	return repoFileDiffResult{Hunks: hunks, Truncated: truncated}, nil
}

func (s *server) repoTree(req repoTreeRequest) ([]repoTreeEntry, error) {
	if s.conversations == nil {
		return nil, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" {
		return nil, fmt.Errorf("conversationId is required")
	}
	conv, err := s.conversations.conversationByID(req.ConversationID)
	if err != nil {
		return nil, err
	}
	path := req.Path
	if path == "" {
		path = "."
	}
	resolved, err := ensureAbsUnder(conv.CWD, path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("not a directory")
	}
	dirEntries, err := os.ReadDir(resolved)
	if err != nil {
		return nil, err
	}
	entries := make([]repoTreeEntry, 0, len(dirEntries))
	for _, e := range dirEntries {
		name := e.Name()
		isDir := e.IsDir()
		if !isDir {
			if info, err := os.Stat(filepath.Join(resolved, name)); err == nil {
				isDir = info.IsDir()
			}
		}
		entries = append(entries, repoTreeEntry{Name: name, IsDir: isDir})
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir != entries[j].IsDir {
			return entries[i].IsDir
		}
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})
	return entries, nil
}

func (s *server) repoFile(req repoFileRequest) (repoFileResult, error) {
	if s.conversations == nil {
		return repoFileResult{}, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" || req.Path == "" {
		return repoFileResult{}, fmt.Errorf("conversationId and path are required")
	}
	conv, err := s.conversations.conversationByID(req.ConversationID)
	if err != nil {
		return repoFileResult{}, err
	}
	resolved, err := ensureAbsUnder(conv.CWD, req.Path)
	if err != nil {
		return repoFileResult{}, err
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return repoFileResult{}, err
	}
	if info.IsDir() {
		return repoFileResult{}, fmt.Errorf("not a file")
	}
	maxBytes := req.MaxBytes
	if maxBytes <= 0 {
		maxBytes = repoFileDefaultMaxBytes
	}

	f, err := os.Open(resolved)
	if err != nil {
		return repoFileResult{}, err
	}
	defer f.Close()

	buf := make([]byte, maxBytes+1)
	n, err := io.ReadFull(f, buf)
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		return repoFileResult{}, err
	}
	truncated := n > maxBytes
	if truncated {
		n = maxBytes
	}
	data := buf[:n]
	if bytes.IndexByte(data, 0) >= 0 {
		return repoFileResult{Binary: true, Size: info.Size()}, nil
	}
	return repoFileResult{
		Content:   string(data),
		Truncated: truncated,
		Size:      info.Size(),
	}, nil
}

// ── helpers ───────────────────────────────────────────────────────────────

func diffTrees(cwd, startOID, endOID string) (repoDiffResult, error) {
	empty := repoDiffResult{Supported: false, Files: []repoDiffFile{}}
	if startOID == "" || endOID == "" {
		return empty, nil
	}
	nameOut, err := gitDiffOut(cwd, "diff", "--name-status", startOID, endOID)
	if err != nil {
		return empty, fmt.Errorf("git diff --name-status: %v", err)
	}
	numOut, err := gitDiffOut(cwd, "diff", "--numstat", startOID, endOID)
	if err != nil {
		return empty, fmt.Errorf("git diff --numstat: %v", err)
	}

	statusByPath := map[string]string{}
	for _, f := range parseNameStatus(nameOut) {
		statusByPath[f.Path] = f.Status
	}
	files := []repoDiffFile{}
	totalAdded, totalRemoved := 0, 0
	for _, line := range strings.Split(numOut, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) < 3 {
			continue
		}
		added, removed := 0, 0
		if parts[0] != "-" {
			added, _ = strconv.Atoi(parts[0])
		}
		if parts[1] != "-" {
			removed, _ = strconv.Atoi(parts[1])
		}
		path := parts[len(parts)-1]
		status := statusByPath[path]
		if status == "" {
			status = "modified"
		}
		files = append(files, repoDiffFile{
			Path: path, Added: added, Removed: removed, Status: status,
		})
		totalAdded += added
		totalRemoved += removed
	}
	// Include name-status-only paths (e.g. renames with no numstat line edge cases).
	seen := map[string]bool{}
	for _, f := range files {
		seen[f.Path] = true
	}
	for path, status := range statusByPath {
		if seen[path] {
			continue
		}
		files = append(files, repoDiffFile{Path: path, Status: status})
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].Path < files[j].Path
	})
	return repoDiffResult{
		Supported:    true,
		Files:        files,
		TotalAdded:   totalAdded,
		TotalRemoved: totalRemoved,
	}, nil
}

var hunkHeaderRe = regexp.MustCompile(`^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$`)

func parseUnifiedDiffHunks(diff string) []repoDiffHunk {
	hunks := []repoDiffHunk{}
	var cur *repoDiffHunk
	oldNo, newNo := 0, 0

	flush := func() {
		if cur != nil {
			hunks = append(hunks, *cur)
			cur = nil
		}
	}

	for _, raw := range strings.Split(diff, "\n") {
		if strings.HasPrefix(raw, "@@") {
			flush()
			m := hunkHeaderRe.FindStringSubmatch(raw)
			if m == nil {
				continue
			}
			oldStart, _ := strconv.Atoi(m[1])
			newStart, _ := strconv.Atoi(m[2])
			oldNo, newNo = oldStart, newStart
			h := repoDiffHunk{
				Header:   raw,
				OldStart: oldStart,
				NewStart: newStart,
				Lines:    []repoDiffLine{},
			}
			cur = &h
			continue
		}
		if cur == nil {
			continue
		}
		if raw == "" && cur != nil {
			// Trailing empty from Split — ignore unless it's a context line with no prefix.
			continue
		}
		if len(raw) == 0 {
			continue
		}
		switch raw[0] {
		case ' ':
			o, n := oldNo, newNo
			cur.Lines = append(cur.Lines, repoDiffLine{
				Kind: "context", OldNo: &o, NewNo: &n, Text: raw[1:],
			})
			oldNo++
			newNo++
		case '+':
			n := newNo
			cur.Lines = append(cur.Lines, repoDiffLine{
				Kind: "add", NewNo: &n, Text: raw[1:],
			})
			newNo++
		case '-':
			o := oldNo
			cur.Lines = append(cur.Lines, repoDiffLine{
				Kind: "del", OldNo: &o, Text: raw[1:],
			})
			oldNo++
		case '\\':
			// "\ No newline at end of file" — skip
		}
	}
	flush()
	return hunks
}

// stampTurnBaselinesForAppend is the beginTurn hook: stamp start OID after a
// fresh turn row is created. No-op on empty cwd / non-git / store nil.
func (s *server) stampTurnBaselinesForAppend(cwd, turnID string) {
	if s.conversations == nil || turnID == "" || cwd == "" {
		return
	}
	oid := stampTurnBaseline(cwd)
	_ = s.conversations.setTurnBaselineStart(turnID, oid)
}

// stampTurnBaselineEndForRun stamps the end OID when a ledger-backed run
// reaches a terminal status. Best-effort — never blocks status persistence.
func (s *server) stampTurnBaselineEndForRun(runID, turnID string) {
	if s.conversations == nil || turnID == "" || runID == "" {
		return
	}
	convID, _, err := s.conversations.turnByRunID(runID)
	if err != nil {
		return
	}
	conv, err := s.conversations.conversationByID(convID)
	if err != nil {
		return
	}
	oid := stampTurnBaseline(conv.CWD)
	_ = s.conversations.setTurnBaselineEnd(turnID, oid)
}
