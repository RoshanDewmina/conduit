package main

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// decisionRecord is a phone-posted approval decision awaiting pickup by the
// conduitd resident that owns the session. In-memory is sufficient: a decision
// only needs to outlive conduitd's ~120s approval wait.
type decisionRecord struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"` // approve | approveAlways | deny
	EditedToolInput string `json:"editedToolInput,omitempty"`
	SessionID       string `json:"sessionId"`
	CreatedAt       int64  `json:"createdAt"`
}

var decisions = struct {
	sync.Mutex
	bySession map[string][]decisionRecord
}{bySession: make(map[string][]decisionRecord)}

func resetDecisionsForTest() {
	decisions.Lock()
	decisions.bySession = make(map[string][]decisionRecord)
	decisions.Unlock()
}

// handlePostDecision: POST /approval/decision { approvalId, decision, sessionId, editedToolInput? }
func handlePostDecision(w http.ResponseWriter, r *http.Request) {
	var rec decisionRecord
	if err := json.NewDecoder(r.Body).Decode(&rec); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if rec.ApprovalID == "" || rec.SessionID == "" || rec.Decision == "" {
		http.Error(w, "approvalId, sessionId, decision required", http.StatusBadRequest)
		return
	}
	rec.CreatedAt = time.Now().Unix()
	decisions.Lock()
	decisions.bySession[rec.SessionID] = append(decisions.bySession[rec.SessionID], rec)
	decisions.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// handlePollDecisions: GET /decisions?sessionId=... -> { decisions: [...] } and drains them.
func handlePollDecisions(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("sessionId")
	if sessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}
	decisions.Lock()
	pending := decisions.bySession[sessionID]
	delete(decisions.bySession, sessionID)
	decisions.Unlock()
	if pending == nil {
		pending = []decisionRecord{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"decisions": pending})
}
