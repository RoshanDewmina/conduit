package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDecisionRelayPostThenPoll(t *testing.T) {
	resetDecisionsForTest()

	body, _ := json.Marshal(map[string]string{
		"approvalId": "appr-1", "decision": "approve", "sessionId": "sess-A",
	})
	rec := httptest.NewRecorder()
	handlePostDecision(rec, httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body)))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("post: status = %d, want 204", rec.Code)
	}

	rec2 := httptest.NewRecorder()
	handlePollDecisions(rec2, httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil))
	if rec2.Code != http.StatusOK {
		t.Fatalf("poll: status = %d, want 200", rec2.Code)
	}
	var out struct {
		Decisions []decisionRecord `json:"decisions"`
	}
	_ = json.Unmarshal(rec2.Body.Bytes(), &out)
	if len(out.Decisions) != 1 || out.Decisions[0].ApprovalID != "appr-1" || out.Decisions[0].Decision != "approve" {
		t.Fatalf("poll returned %+v", out.Decisions)
	}

	rec3 := httptest.NewRecorder()
	handlePollDecisions(rec3, httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil))
	var out2 struct {
		Decisions []decisionRecord `json:"decisions"`
	}
	_ = json.Unmarshal(rec3.Body.Bytes(), &out2)
	if len(out2.Decisions) != 0 {
		t.Fatalf("second poll not empty: %+v", out2.Decisions)
	}
}

func TestDecisionRelayRejectsMissingFields(t *testing.T) {
	resetDecisionsForTest()
	body, _ := json.Marshal(map[string]string{"decision": "approve"})
	rec := httptest.NewRecorder()
	handlePostDecision(rec, httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}
