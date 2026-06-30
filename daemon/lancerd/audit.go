package main

import (
	"crypto/sha256"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// AuditEntry is one JSONL line in ~/.lancer/audit.log (matches Swift AuditLogEntry).
type AuditEntry struct {
	Timestamp  string `json:"timestamp"`
	Action     string `json:"action"`
	Agent      string `json:"agent,omitempty"`
	Kind       string `json:"kind,omitempty"`
	Command    string `json:"command,omitempty"`
	Effect     string `json:"effect,omitempty"`
	Rule       string `json:"rule,omitempty"`
	ApprovalID string `json:"approvalId,omitempty"`
	Hash       string `json:"hash"`
	PrevHash   string `json:"prevHash"`
}

// auditEntryPayload is used to compute the hash of an entry without the hash fields.
type auditEntryPayload struct {
	Timestamp  string `json:"timestamp"`
	Action     string `json:"action"`
	Agent      string `json:"agent,omitempty"`
	Kind       string `json:"kind,omitempty"`
	Command    string `json:"command,omitempty"`
	Effect     string `json:"effect,omitempty"`
	Rule       string `json:"rule,omitempty"`
	ApprovalID string `json:"approvalId,omitempty"`
}

// VerificationResult is the return type for audit chain verification.
type VerificationResult struct {
	Valid          bool   `json:"valid"`
	BrokenAt       int    `json:"brokenAt,omitempty"`
	EntryCount     int    `json:"entryCount"`
	FirstTimestamp string `json:"firstTimestamp,omitempty"`
	LastTimestamp  string `json:"lastTimestamp,omitempty"`
}

type auditLog struct {
	mu   sync.Mutex
	path string
}

func newAuditLog(home string) *auditLog {
	return &auditLog{path: filepath.Join(home, ".lancer", "audit.log")}
}

func computeEntryHash(entry AuditEntry) string {
	payload := auditEntryPayload{
		Timestamp:  entry.Timestamp,
		Action:     entry.Action,
		Agent:      entry.Agent,
		Kind:       entry.Kind,
		Command:    entry.Command,
		Effect:     entry.Effect,
		Rule:       entry.Rule,
		ApprovalID: entry.ApprovalID,
	}
	data, _ := json.Marshal(payload)
	h := sha256.Sum256(data)
	return encodeHex(h[:])
}

func encodeHex(b []byte) string {
	const hexTable = "0123456789abcdef"
	out := make([]byte, len(b)*2)
	for i, v := range b {
		out[i*2] = hexTable[v>>4]
		out[i*2+1] = hexTable[v&0x0f]
	}
	return string(out)
}

func (a *auditLog) append(entry AuditEntry) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if entry.Timestamp == "" {
		entry.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	entry.Command = redactSecrets(entry.Command)

	// Compute prevHash from the last entry in the log.
	lastHash := a.lastHashLocked()
	entry.PrevHash = lastHash

	// Compute hash of this entry.
	entry.Hash = computeEntryHash(entry)

	line, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(a.path), 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(a.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(append(line, '\n'))
	return err
}

// lastHashLocked returns the hash of the last entry in the log.
// Caller must hold a.mu.
func (a *auditLog) lastHashLocked() string {
	data, err := os.ReadFile(a.path)
	if err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if lines[i] == "" {
			continue
		}
		var e AuditEntry
		if json.Unmarshal([]byte(lines[i]), &e) == nil && e.Hash != "" {
			return e.Hash
		}
	}
	return ""
}

// Verify reads all entries and recomputes the chain, returning a VerificationResult.
func (a *auditLog) Verify() VerificationResult {
	a.mu.Lock()
	defer a.mu.Unlock()

	data, err := os.ReadFile(a.path)
	if err != nil {
		return VerificationResult{Valid: true}
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	var entries []AuditEntry
	for _, line := range lines {
		if line == "" {
			continue
		}
		var e AuditEntry
		if json.Unmarshal([]byte(line), &e) == nil {
			entries = append(entries, e)
		}
	}

	result := VerificationResult{EntryCount: len(entries)}
	if len(entries) == 0 {
		result.Valid = true
		return result
	}
	result.FirstTimestamp = entries[0].Timestamp
	result.LastTimestamp = entries[len(entries)-1].Timestamp

	expectedPrev := ""
	for i, e := range entries {
		if e.PrevHash != expectedPrev {
			result.BrokenAt = i
			return result
		}
		recomputed := computeEntryHash(e)
		if recomputed != e.Hash {
			result.BrokenAt = i
			return result
		}
		expectedPrev = e.Hash
	}
	result.Valid = true
	return result
}

// exportJSONL returns the full hash-chained log as a JSONL string.
func (a *auditLog) exportJSONL() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	data, err := os.ReadFile(a.path)
	if err != nil {
		return ""
	}
	return string(data)
}

func (a *auditLog) tail(limit int) ([]AuditEntry, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	data, err := os.ReadFile(a.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if limit <= 0 || limit > len(lines) {
		limit = len(lines)
	}
	start := len(lines) - limit
	if start < 0 {
		start = 0
	}
	var out []AuditEntry
	for _, line := range lines[start:] {
		if line == "" {
			continue
		}
		var e AuditEntry
		if json.Unmarshal([]byte(line), &e) == nil {
			out = append(out, e)
		}
	}
	return out, nil
}

var secretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(api[_-]?key|token|secret|password|authorization)\s*[=:]\s*\S+`),
	regexp.MustCompile(`(?i)bearer\s+[a-z0-9._-]+`),
	regexp.MustCompile(`sk-[a-zA-Z0-9]{10,}`),
	regexp.MustCompile(`ghp_[a-zA-Z0-9]{20,}`),
}

func redactSecrets(s string) string {
	if s == "" {
		return s
	}
	out := s
	for _, re := range secretPatterns {
		out = re.ReplaceAllString(out, "[REDACTED]")
	}
	return out
}
