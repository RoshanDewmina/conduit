package main

import (
	"encoding/json"
	"sync"
	"time"
)

// ApprovalEvent mirrors ApprovalPendingParams on the iOS side.
type ApprovalEvent struct {
	ApprovalID string `json:"id"`
	Agent      string `json:"agent"`
	Kind       string `json:"kind"`
	Command    string `json:"command"`
	Patch      string `json:"patch,omitempty"`
	CWD        string `json:"cwd"`
	Risk       int    `json:"risk"`
	Timestamp  string `json:"timestamp"`

	ToolName  string `json:"toolName,omitempty"`
	ToolUseID string `json:"toolUseID,omitempty"`
	SessionID string `json:"agentSessionID,omitempty"`
	ToolInput string `json:"toolInput,omitempty"`

	Files          []string `json:"files,omitempty"`
	TouchesGit     bool     `json:"touchesGit,omitempty"`
	TouchesNetwork bool     `json:"touchesNetwork,omitempty"`
	MatchedRule    string   `json:"matchedRule,omitempty"`
}

type ApprovalDecision struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"`
	EditedToolInput string `json:"editedToolInput,omitempty"`
}

type hookDecision struct {
	decision        string
	editedToolInput string
}

type pendingApproval struct {
	event    ApprovalEvent
	decision chan hookDecision
}

type approvalStore struct {
	mu      sync.Mutex
	pending map[string]*pendingApproval
}

func newApprovalStore() *approvalStore {
	return &approvalStore{pending: make(map[string]*pendingApproval)}
}

func (s *approvalStore) add(event ApprovalEvent) <-chan hookDecision {
	ch := make(chan hookDecision, 1)
	s.mu.Lock()
	s.pending[event.ApprovalID] = &pendingApproval{event: event, decision: ch}
	s.mu.Unlock()
	return ch
}

func (s *approvalStore) resolve(id, decision, editedToolInput string) (ApprovalEvent, bool) {
	s.mu.Lock()
	p, ok := s.pending[id]
	if ok {
		delete(s.pending, id)
	}
	s.mu.Unlock()
	if !ok {
		return ApprovalEvent{}, false
	}
	select {
	case p.decision <- hookDecision{decision: decision, editedToolInput: editedToolInput}:
	default:
	}
	return p.event, true
}

func waitWithTimeout(ch <-chan hookDecision, timeout time.Duration) hookDecision {
	select {
	case d := <-ch:
		return d
	case <-time.After(timeout):
		return hookDecision{decision: "deny"}
	}
}

func marshalPendingNotification(event ApprovalEvent) ([]byte, error) {
	msg := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "agent.approval.pending",
		"params":  event,
	}
	return json.Marshal(msg)
}
