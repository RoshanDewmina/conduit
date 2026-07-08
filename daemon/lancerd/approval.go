package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"

	"lancer/lancerd/policy"
)

// normID normalizes an approval ID for case-insensitive lookup. UUIDs are
// case-insensitive (RFC 4122), but Swift's `UUID.uuidString` is UPPERCASE while
// Go generates lowercase — so a phone decision keyed by the uppercase form would
// miss the lowercase-stored pending and the agent would hang to the timeout.
func normID(id string) string { return strings.ToLower(strings.TrimSpace(id)) }

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
	RunID          string   `json:"runId,omitempty"`

	// ContentHash binds this event to the exact content (Command, Patch, CWD,
	// ToolInput) a decision must be computed over. Set once at construction via
	// computeContentHash and never mutated — approvalStore.resolve verifies a
	// decision's echoed hash against this before honoring it.
	ContentHash string `json:"contentHash"`
}

type ApprovalDecision struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"`
	EditedToolInput string `json:"editedToolInput,omitempty"`
	// ContentHash is echoed back by the client from the ApprovalEvent it is
	// deciding on. resolve() rejects a decision whose hash doesn't match the
	// pending event's stored ContentHash — see computeContentHash.
	ContentHash string `json:"contentHash"`
	// AllowRule is an optional scoped, expiring allow rule attached to an
	// "approve" decision ("approve and remember" — task A4). It is distinct
	// from the legacy "approveAlways" prefix-matched rule (appendAllowAlways):
	// that path builds an unscoped, unbounded rule from the command text,
	// which is fine for a rule the daemon derives itself but is forbidden for
	// a rule the phone hands the daemon — see policy.ValidateAllowRule, which
	// every AllowRule is run through before it is ever persisted.
	AllowRule *policy.Rule `json:"allowRule,omitempty"`
}

// computeContentHash canonicalizes the fields a user actually reviews before
// deciding — command, patch, cwd, tool input — into a single SHA-256 digest.
// Fields are joined with \x1f (ASCII unit separator), which cannot occur in
// any of them by construction, so concatenation stays unambiguous without a
// length-prefixed encoding. This must produce byte-identical output to the
// Swift-side canonicalization (Approval.computeContentHash) — the two are
// verified against each other by shared test vectors, not by sharing code.
//
// This is a plain hash, not an HMAC over the E2E session key: the same
// ContentHash must verify identically whether the decision arrives over the
// SSH attach socket, the E2E relay, or the push-backend REST fallback poll —
// and push-backend never holds the per-pairing E2E session key, so an
// HMAC keyed to it would be unverifiable on that path.
func computeContentHash(command, patch, cwd, toolInput string) string {
	sum := sha256.Sum256([]byte(strings.Join([]string{command, patch, cwd, toolInput}, "\x1f")))
	return hex.EncodeToString(sum[:])
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
	s.pending[normID(event.ApprovalID)] = &pendingApproval{event: event, decision: ch}
	s.mu.Unlock()
	return ch
}

func (s *approvalStore) pendingEvents() []ApprovalEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]ApprovalEvent, 0, len(s.pending))
	for _, p := range s.pending {
		out = append(out, p.event)
	}
	return out
}

// resolve is the single delete-under-lock chokepoint for a pending approval.
// contentHash must match the pending event's stored ContentHash — computed
// once at creation over the exact content the human was shown — or the
// decision is rejected without resolving the approval, so a genuine decision
// (or a retry with the correct hash) can still land later. A mismatch is a
// real security event (stale UI, a race, or a forged/corrupted decision), not
// routine noise, so it's logged unconditionally rather than silently dropped.
func (s *approvalStore) resolve(id, decision, editedToolInput, contentHash string) (ApprovalEvent, bool) {
	key := normID(id)
	s.mu.Lock()
	p, ok := s.pending[key]
	if ok && p.event.ContentHash != contentHash {
		s.mu.Unlock()
		log.Printf("security: approval %s decision rejected — content hash mismatch (stale UI, race, or forged decision)", id)
		return ApprovalEvent{}, false
	}
	if ok {
		delete(s.pending, key)
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

// remove drops a pending approval without delivering a decision. Used by the
// hook-wait timeout path to retire an orphaned approval so a late relay-delivered
// decision can't re-resolve (and mis-audit) it after the agent was auto-denied.
func (s *approvalStore) remove(id string) {
	s.mu.Lock()
	delete(s.pending, normID(id))
	s.mu.Unlock()
}

// waitWithTimeout blocks for a decision on ch. The bool reports whether a
// decision was received (true) versus the timeout firing (false → auto-deny).
// The caller uses this to distinguish "a resolver already recorded this
// decision" from "nothing recorded it; audit the auto-deny here."
func waitWithTimeout(ch <-chan hookDecision, timeout time.Duration) (hookDecision, bool) {
	select {
	case d := <-ch:
		return d, true
	case <-time.After(timeout):
		return hookDecision{decision: "deny"}, false
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
