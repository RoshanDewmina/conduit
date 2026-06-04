package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// alwaysRule matches future tool calls from the same agent/tool with a command prefix.
type alwaysRule struct {
	Agent  string `json:"agent"`
	Tool   string `json:"tool"`
	Prefix string `json:"prefix"`
}

type alwaysRuleStore struct {
	mu    sync.Mutex
	rules []alwaysRule
	path  string
}

func newAlwaysRuleStore() *alwaysRuleStore {
	home, _ := os.UserHomeDir()
	path := filepath.Join(home, ".conduit", "always-rules.json")
	s := &alwaysRuleStore{path: path}
	s.load()
	return s
}

func (s *alwaysRuleStore) load() {
	data, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	var rules []alwaysRule
	if json.Unmarshal(data, &rules) == nil {
		s.rules = rules
	}
}

func (s *alwaysRuleStore) persist() {
	s.mu.Lock()
	rules := append([]alwaysRule(nil), s.rules...)
	path := s.path
	s.mu.Unlock()

	_ = os.MkdirAll(filepath.Dir(path), 0700)
	data, err := json.MarshalIndent(rules, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(path, data, 0600)
}

func (s *alwaysRuleStore) add(rule alwaysRule) {
	if rule.Agent == "" || rule.Prefix == "" {
		return
	}
	s.mu.Lock()
	for _, existing := range s.rules {
		if existing.Agent == rule.Agent && existing.Tool == rule.Tool && existing.Prefix == rule.Prefix {
			s.mu.Unlock()
			return
		}
	}
	s.rules = append(s.rules, rule)
	s.mu.Unlock()
	s.persist()
}

func (s *alwaysRuleStore) matches(event ApprovalEvent) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	cmd := strings.TrimSpace(event.Command)
	for _, rule := range s.rules {
		if rule.Agent != "" && rule.Agent != event.Agent {
			continue
		}
		if rule.Tool != "" && rule.Tool != event.ToolName {
			continue
		}
		if rule.Prefix != "" && !strings.HasPrefix(cmd, rule.Prefix) {
			continue
		}
		return true
	}
	return false
}

func alwaysRuleFromEvent(event ApprovalEvent) alwaysRule {
	tool := event.ToolName
	if tool == "" {
		tool = event.Kind
	}
	prefix := strings.TrimSpace(event.Command)
	if len(prefix) > 120 {
		prefix = prefix[:120]
	}
	return alwaysRule{
		Agent:  event.Agent,
		Tool:   tool,
		Prefix: prefix,
	}
}
