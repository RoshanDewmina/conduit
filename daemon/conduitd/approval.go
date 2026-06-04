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
	ApprovalID string `json:"approvalId"`
	Decision   string `json:"decision"` // "approve" | "deny"
}

// pendingApproval holds the event and a channel for the decision.
type pendingApproval struct {
	event    ApprovalEvent
	decision chan string // receives "approve" or "deny"
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
// The caller should receive from the channel (with timeout) to get the decision.
func (s *approvalStore) add(event ApprovalEvent) <-chan string {
	ch := make(chan string, 1)
	s.mu.Lock()
	s.pending[event.ApprovalID] = &pendingApproval{event: event, decision: ch}
	s.mu.Unlock()
	return ch
}

// resolve delivers a decision for the given approval ID.
// Returns true if the approval was found and the decision delivered.
func (s *approvalStore) resolve(id, decision string) bool {
	s.mu.Lock()
	p, ok := s.pending[id]
	if ok {
		delete(s.pending, id)
	}
	s.mu.Unlock()
	if !ok {
		return false
	}
	select {
	case p.decision <- decision:
	default:
	}
	return true
}

// waitWithTimeout blocks until a decision arrives or the timeout elapses.
// Returns the decision string ("approve" / "deny") or "deny" on timeout.
func waitWithTimeout(ch <-chan string, timeout time.Duration) string {
	select {
	case d := <-ch:
		return d
	case <-time.After(timeout):
		return "deny"
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
