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

const (
	// decisionTTL bounds how long an un-polled decision is retained. conduitd's
	// approval wait is ~120s; we keep a margin then evict so decisions posted for
	// sessions that never poll (dead sessions, or an attacker flooding sessionIds)
	// cannot grow the map without bound. A lost decision fails safe: conduitd's
	// 120s wait elapses and the approval auto-denies.
	decisionTTL = 5 * time.Minute
	// maxDecisionsPerSession caps distinct pending decisions for one session, to
	// bound memory if a known sessionId is flooded with unique approvalIds.
	maxDecisionsPerSession = 64
	// maxDecisionSessions caps the number of distinct sessions held at once.
	maxDecisionSessions = 4096
)

var decisions = struct {
	sync.Mutex
	bySession map[string][]decisionRecord
}{bySession: make(map[string][]decisionRecord)}

func resetDecisionsForTest() {
	decisions.Lock()
	decisions.bySession = make(map[string][]decisionRecord)
	decisions.Unlock()
}

func validDecision(d string) bool {
	switch d {
	case "approve", "approveAlways", "deny":
		return true
	default:
		return false
	}
}

// evictExpiredDecisionsLocked drops decisions older than decisionTTL across all
// sessions. The caller must hold decisions.Mutex.
func evictExpiredDecisionsLocked(now int64) {
	ttl := int64(decisionTTL / time.Second)
	for sid, recs := range decisions.bySession {
		kept := recs[:0]
		for _, rec := range recs {
			if now-rec.CreatedAt < ttl {
				kept = append(kept, rec)
			}
		}
		if len(kept) == 0 {
			delete(decisions.bySession, sid)
		} else {
			decisions.bySession[sid] = kept
		}
	}
}

// handlePostDecision: POST /approval/decision { approvalId, decision, sessionId, editedToolInput? }
//
// Tier-2 auth: requires `Authorization: Bearer <relayToken>` matching the token
// conduitd registered for sessionId (constant-time). Input is validated first so
// malformed requests get a generic 400; a valid-looking request with a
// missing/wrong/unknown token gets 401 with NO side effects (fail-safe — never
// auto-resolve on an auth failure).
func handlePostDecision(w http.ResponseWriter, r *http.Request) {
	var rec decisionRecord
	if !decodeRelayJSON(w, r, &rec) {
		return
	}
	if rec.ApprovalID == "" || rec.SessionID == "" || rec.Decision == "" {
		http.Error(w, "approvalId, sessionId, decision required", http.StatusBadRequest)
		return
	}
	if len(rec.ApprovalID) > maxApprovalIDLen ||
		len(rec.SessionID) > maxSessionIDLen ||
		len(rec.EditedToolInput) > maxEditedToolInputLen {
		http.Error(w, "field too large", http.StatusBadRequest)
		return
	}
	// Fail safe: never relay a decision verb we don't understand. conduitd treats
	// any non-approve value as deny, so silently forwarding garbage could surface
	// as an unintended deny; reject it at the edge instead.
	if !validDecision(rec.Decision) {
		http.Error(w, "decision must be approve, approveAlways, or deny", http.StatusBadRequest)
		return
	}
	if !relaySessionAuthorized(rec.SessionID, bearerToken(r)) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	rec.CreatedAt = time.Now().Unix()

	decisions.Lock()
	defer decisions.Unlock()
	evictExpiredDecisionsLocked(rec.CreatedAt)

	existing := decisions.bySession[rec.SessionID]
	// Idempotent by approvalId: a re-POST (e.g. a phone retry) replaces the prior
	// record for the same approvalId rather than appending a duplicate, so the
	// poller delivers — and conduitd applies — each decision exactly once.
	for i := range existing {
		if existing[i].ApprovalID == rec.ApprovalID {
			existing[i] = rec
			decisions.bySession[rec.SessionID] = existing
			w.WriteHeader(http.StatusNoContent)
			return
		}
	}
	if len(existing) >= maxDecisionsPerSession {
		http.Error(w, "too many pending decisions for session", http.StatusTooManyRequests)
		return
	}
	if _, ok := decisions.bySession[rec.SessionID]; !ok && len(decisions.bySession) >= maxDecisionSessions {
		http.Error(w, "decision capacity reached", http.StatusServiceUnavailable)
		return
	}
	decisions.bySession[rec.SessionID] = append(existing, rec)
	w.WriteHeader(http.StatusNoContent)
}

// handlePollDecisions: GET /decisions?sessionId=... -> { decisions: [...] } and drains them.
//
// Tier-2 auth: requires `Authorization: Bearer <relayToken>` matching the token
// conduitd registered for sessionId (constant-time). A missing/wrong/unknown
// token returns 401 and does NOT drain (fail-safe — an attacker cannot siphon
// another session's decisions, and a 401'd conduitd simply retries while its
// ~120s auto-deny backstops any genuinely undelivered decision).
func handlePollDecisions(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("sessionId")
	if sessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}
	if len(sessionID) > maxSessionIDLen {
		http.Error(w, "sessionId too large", http.StatusBadRequest)
		return
	}
	if !relaySessionAuthorized(sessionID, bearerToken(r)) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	now := time.Now().Unix()
	decisions.Lock()
	evictExpiredDecisionsLocked(now)
	pending := decisions.bySession[sessionID]
	delete(decisions.bySession, sessionID)
	decisions.Unlock()
	if pending == nil {
		pending = []decisionRecord{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"decisions": pending})
}
