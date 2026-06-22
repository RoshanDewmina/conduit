package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// postDecisionRaw posts an arbitrary JSON body to the decision endpoint with NO
// Authorization header. Used by input-validation tests that must reject before
// reaching the per-session token check.
func postDecisionRaw(t *testing.T, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	return postDecision(t, body, "")
}

// postDecision posts a body with `Authorization: Bearer <token>` (omitted when
// token == "").
func postDecision(t *testing.T, body []byte, token string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	handlePostDecision(rec, req)
	return rec
}

// pollDecisions drains and returns the decisions for a session, authenticating
// with the given relayToken.
func pollDecisions(t *testing.T, sessionID, token string) []decisionRecord {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/decisions?sessionId="+sessionID, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	handlePollDecisions(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("poll: status = %d, want 200", rec.Code)
	}
	var out struct {
		Decisions []decisionRecord `json:"decisions"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return out.Decisions
}

func TestDecisionRelayPostThenPoll(t *testing.T) {
	resetDecisionsForTest()
	resetRegistryForTest()
	const tok = "rt-sessA"
	seedRelayToken(t, "sess-A", tok)

	body, _ := json.Marshal(map[string]string{
		"approvalId": "appr-1", "decision": "approve", "sessionId": "sess-A",
	})
	if rec := postDecision(t, body, tok); rec.Code != http.StatusNoContent {
		t.Fatalf("post: status = %d, want 204", rec.Code)
	}

	got := pollDecisions(t, "sess-A", tok)
	if len(got) != 1 || got[0].ApprovalID != "appr-1" || got[0].Decision != "approve" {
		t.Fatalf("poll returned %+v", got)
	}

	if got2 := pollDecisions(t, "sess-A", tok); len(got2) != 0 {
		t.Fatalf("second poll not empty: %+v", got2)
	}
}

// The core B2 contract: per-session relayToken auth on POST /approval/decision
// (app) and GET /decisions (lancerd). Correct token → success; missing/wrong/
// unknown → 401 with no side effects (fail-safe).
func TestDecisionRelayPerSessionTokenAuth(t *testing.T) {
	resetDecisionsForTest()
	resetRegistryForTest()
	const tok = "rt-correct"
	seedRelayToken(t, "sess-A", tok)

	body, _ := json.Marshal(map[string]string{
		"approvalId": "appr-1", "sessionId": "sess-A", "decision": "approveAlways",
	})

	// POST: missing token → 401, and nothing is enqueued.
	if rec := postDecision(t, body, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("post missing token: status = %d, want 401", rec.Code)
	}
	// POST: wrong token → 401.
	if rec := postDecision(t, body, "rt-wrong"); rec.Code != http.StatusUnauthorized {
		t.Fatalf("post wrong token: status = %d, want 401", rec.Code)
	}
	// POST: unknown session → 401.
	unknownBody, _ := json.Marshal(map[string]string{
		"approvalId": "appr-2", "sessionId": "sess-UNKNOWN", "decision": "approve",
	})
	if rec := postDecision(t, unknownBody, tok); rec.Code != http.StatusUnauthorized {
		t.Fatalf("post unknown session: status = %d, want 401", rec.Code)
	}

	// Fail-safe: no side effects from any of the rejected posts. An authorized
	// poll must drain zero decisions.
	if got := pollDecisions(t, "sess-A", tok); len(got) != 0 {
		t.Fatalf("rejected posts leaked decisions: %+v", got)
	}

	// POST: correct token → 204.
	if rec := postDecision(t, body, tok); rec.Code != http.StatusNoContent {
		t.Fatalf("post correct token: status = %d, want 204", rec.Code)
	}

	// Poll: missing token → 401 and must NOT drain.
	recNoAuth := httptest.NewRecorder()
	handlePollDecisions(recNoAuth, httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil))
	if recNoAuth.Code != http.StatusUnauthorized {
		t.Fatalf("poll missing token: status = %d, want 401", recNoAuth.Code)
	}
	// Poll: wrong token → 401 and must NOT drain.
	recWrong := httptest.NewRecorder()
	reqWrong := httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil)
	reqWrong.Header.Set("Authorization", "Bearer rt-wrong")
	handlePollDecisions(recWrong, reqWrong)
	if recWrong.Code != http.StatusUnauthorized {
		t.Fatalf("poll wrong token: status = %d, want 401", recWrong.Code)
	}

	// Poll: correct token → 200 and drains the queued approveAlways.
	got := pollDecisions(t, "sess-A", tok)
	if len(got) != 1 || got[0].Decision != "approveAlways" {
		t.Fatalf("authorized poll = %+v, want one approveAlways", got)
	}
}

func TestDecisionRelayRejectsMissingFields(t *testing.T) {
	resetDecisionsForTest()
	cases := []struct {
		name string
		body map[string]string
	}{
		{"missing approvalId+sessionId", map[string]string{"decision": "approve"}},
		{"missing sessionId", map[string]string{"approvalId": "a", "decision": "approve"}},
		{"missing approvalId", map[string]string{"sessionId": "s", "decision": "approve"}},
		{"missing decision", map[string]string{"approvalId": "a", "sessionId": "s"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(tc.body)
			if rec := postDecisionRaw(t, body); rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rec.Code)
			}
		})
	}
}

// A decision verb the relay doesn't understand must be rejected at the edge so a
// downstream "unknown == deny" coercion can't turn garbage into an action.
func TestDecisionRelayValidatesDecisionVerb(t *testing.T) {
	cases := []struct {
		decision string
		want     int
	}{
		{"approve", http.StatusNoContent},
		{"approveAlways", http.StatusNoContent},
		{"deny", http.StatusNoContent},
		{"yolo", http.StatusBadRequest},
		{"APPROVE", http.StatusBadRequest},
		{"", http.StatusBadRequest},
	}
	const tok = "rt-verb"
	for _, tc := range cases {
		t.Run(tc.decision, func(t *testing.T) {
			resetDecisionsForTest()
			resetRegistryForTest()
			seedRelayToken(t, "sess-A", tok)
			body, _ := json.Marshal(map[string]string{
				"approvalId": "appr-1", "sessionId": "sess-A", "decision": tc.decision,
			})
			if rec := postDecision(t, body, tok); rec.Code != tc.want {
				t.Fatalf("decision %q: status = %d, want %d", tc.decision, rec.Code, tc.want)
			}
		})
	}
}

// Re-posting the same approvalId (a phone retry) must collapse to a single
// record carrying the latest decision — so the poller delivers it exactly once.
func TestDecisionRelayDedupeByApprovalID(t *testing.T) {
	resetDecisionsForTest()
	resetRegistryForTest()
	const tok = "rt-dedupe"
	seedRelayToken(t, "sess-A", tok)
	for _, d := range []string{"approve", "approveAlways"} {
		body, _ := json.Marshal(map[string]string{
			"approvalId": "appr-1", "sessionId": "sess-A", "decision": d,
		})
		if rec := postDecision(t, body, tok); rec.Code != http.StatusNoContent {
			t.Fatalf("post %q: status = %d, want 204", d, rec.Code)
		}
	}
	got := pollDecisions(t, "sess-A", tok)
	if len(got) != 1 {
		t.Fatalf("dedupe failed: got %d records, want 1: %+v", len(got), got)
	}
	if got[0].Decision != "approveAlways" {
		t.Fatalf("want latest decision approveAlways, got %q", got[0].Decision)
	}
}

func TestDecisionRelayPollRejectsMissingSession(t *testing.T) {
	resetDecisionsForTest()
	rec := httptest.NewRecorder()
	handlePollDecisions(rec, httptest.NewRequest(http.MethodGet, "/decisions", nil))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestDecisionRelayRejectsOversizedBody(t *testing.T) {
	resetDecisionsForTest()
	// Body well over maxRelayBodyBytes must be rejected without decoding.
	big := strings.Repeat("x", maxRelayBodyBytes+1024)
	body, _ := json.Marshal(map[string]string{
		"approvalId": "a", "sessionId": "s", "decision": "approve", "editedToolInput": big,
	})
	if rec := postDecisionRaw(t, body); rec.Code != http.StatusBadRequest {
		t.Fatalf("oversized body: status = %d, want 400", rec.Code)
	}
}

func TestDecisionRelayRejectsOversizedField(t *testing.T) {
	resetDecisionsForTest()
	// Under the body cap but over the per-field cap → rejected as "field too large".
	big := strings.Repeat("y", maxEditedToolInputLen+10)
	body, _ := json.Marshal(map[string]string{
		"approvalId": "a", "sessionId": "s", "decision": "approve", "editedToolInput": big,
	})
	if rec := postDecisionRaw(t, body); rec.Code != http.StatusBadRequest {
		t.Fatalf("oversized field: status = %d, want 400", rec.Code)
	}
}

func TestDecisionRelayPerSessionCap(t *testing.T) {
	resetDecisionsForTest()
	resetRegistryForTest()
	const tok = "rt-cap"
	seedRelayToken(t, "sess-A", tok)
	for i := 0; i < maxDecisionsPerSession; i++ {
		body, _ := json.Marshal(map[string]string{
			"approvalId": fmt.Sprintf("appr-%d", i), "sessionId": "sess-A", "decision": "approve",
		})
		if rec := postDecision(t, body, tok); rec.Code != http.StatusNoContent {
			t.Fatalf("post %d: status = %d, want 204", i, rec.Code)
		}
	}
	// One past the cap (new approvalId) must be rejected.
	body, _ := json.Marshal(map[string]string{
		"approvalId": "appr-overflow", "sessionId": "sess-A", "decision": "approve",
	})
	if rec := postDecision(t, body, tok); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("overflow: status = %d, want 429", rec.Code)
	}
}

func TestEvictExpiredDecisions(t *testing.T) {
	resetDecisionsForTest()
	now := time.Now().Unix()
	decisions.Lock()
	decisions.bySession["fresh"] = []decisionRecord{{ApprovalID: "a", SessionID: "fresh", Decision: "approve", CreatedAt: now}}
	decisions.bySession["stale"] = []decisionRecord{{ApprovalID: "b", SessionID: "stale", Decision: "approve", CreatedAt: now - int64(decisionTTL/time.Second) - 1}}
	evictExpiredDecisionsLocked(now)
	_, freshOK := decisions.bySession["fresh"]
	_, staleOK := decisions.bySession["stale"]
	decisions.Unlock()
	if !freshOK {
		t.Fatal("fresh decision was evicted")
	}
	if staleOK {
		t.Fatal("stale decision was not evicted")
	}
}
