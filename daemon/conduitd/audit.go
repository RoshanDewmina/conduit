package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// AuditEntry is one JSONL line in ~/.conduit/audit.log (matches Swift AuditLogEntry).
type AuditEntry struct {
	Timestamp  string `json:"timestamp"`
	Action     string `json:"action"`
	Agent      string `json:"agent,omitempty"`
	Kind       string `json:"kind,omitempty"`
	Command    string `json:"command,omitempty"`
	Effect     string `json:"effect,omitempty"`
	Rule       string `json:"rule,omitempty"`
	ApprovalID string `json:"approvalId,omitempty"`
}

type auditLog struct {
	mu   sync.Mutex
	path string
}

func newAuditLog(home string) *auditLog {
	return &auditLog{path: filepath.Join(home, ".conduit", "audit.log")}
}

func (a *auditLog) append(entry AuditEntry) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if entry.Timestamp == "" {
		entry.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	entry.Command = redactSecrets(entry.Command)
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
