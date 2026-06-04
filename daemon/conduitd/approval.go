package main

import (
	"encoding/json"
	"sync"
	"time"
)

// ApprovalEvent mirrors the JSON sent from the iOS DaemonChannel.
// Field names match ApprovalPendingParams on the iOS side exactly.
type ApprovalEvent struct {
	ApprovalID string `json:"id"` // iOS expects "id" not "approvalId"
	Agent      string `json:"agent"`
	Kind       string `json:"kind"`
	Command    string `json:"command"`
	Patch      string `json:"patch,omitempty"`
	CWD        string `json:"cwd"`
	Risk       int    `json:"risk"` // iOS expects int: 0=low 1=medium 2=high 3=critical
	Timestamp  string `json:"timestamp"`

	// Structured tool-use fields — populated when conduitd is invoked from a
	// Claude Code or Codex PreToolUse hook. All optional (omitted when empty).
	ToolName  string `json:"toolName,omitempty"`
	ToolUseID string `json:"toolUseID,omitempty"`
	SessionID string `json:"sessionID,omitempty"`
	ToolInput string `json:"toolInput,omitempty"`
}

// ApprovalDecision is the response written back after the user acts on iOS.
type ApprovalDecision struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"` // "approve" | "approveAlways" | "deny"
	EditedToolInput string `json:"editedToolInput,omitempty"`
}

// hookDecision is delivered to a waiting agent-hook connection.
type hookDecision struct {
	decision        string
	editedToolInput string
}

// pendingApproval holds the event and a channel for the decision.
type pendingApproval struct {
	event    ApprovalEvent
	decision chan hookDecision
}

// approvalStore is the in-memory registry of approvals awaiting a decision.
type approvalStore struct {
	mu      sync.Mutex
	pending map[string]*pendingApproval
}

func newApprovalStore() *approvalStore {
	return &approvalStore{pending: make(map[string]*pendingApproval)}
}

// add registers a new pending approval and returns the decision channel.
func (s *approvalStore) add(event ApprovalEvent) <-chan hookDecision {
	ch := make(chan hookDecision, 1)
	s.mu.Lock()
	s.pending[event.ApprovalID] = &pendingApproval{event: event, decision: ch}
	s.mu.Unlock()
	return ch
}

// resolve delivers a decision for the given approval ID.
// Returns the pending event when found (for always-rule creation).
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

// waitWithTimeout blocks until a decision arrives or the timeout elapses.
func waitWithTimeout(ch <-chan hookDecision, timeout time.Duration) hookDecision {
	select {
	case d := <-ch:
		return d
	case <-time.After(timeout):
		return hookDecision{decision: "deny"}
	}
}

// marshalEvent serialises an ApprovalEvent into a JSON-RPC notification map.
func marshalPendingNotification(event ApprovalEvent) ([]byte, error) {
	msg := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "agent.approval.pending",
		"params":  event,
	}
	return json.Marshal(msg)
}
