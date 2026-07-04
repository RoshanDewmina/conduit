package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHandleApprovalRoutesToRegisteredToken(t *testing.T) {
	registry.Lock()
	registry.sessions["sess-A"] = &sessionRecord{apnsToken: "device-token-xyz", seen: time.Now().Unix()}
	registry.Unlock()

	var gotToken string
	var gotEvent approvalEvent
	orig := pushApprovalFn
	pushApprovalFn = func(token string, ev approvalEvent) error {
		gotToken = token
		gotEvent = ev
		return nil
	}
	defer func() { pushApprovalFn = orig }()

	body, _ := json.Marshal(approvalEvent{
		ID: "appr-1", SessionID: "sess-A", Command: "rm -rf build/", Risk: "high", HostName: "devbox",
	})
	rec := httptest.NewRecorder()
	handleApproval(rec, httptest.NewRequest(http.MethodPost, "/approval", bytes.NewReader(body)))

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if gotToken != "device-token-xyz" {
		t.Fatalf("routed to token %q", gotToken)
	}
	if gotEvent.ID != "appr-1" || gotEvent.Command != "rm -rf build/" {
		t.Fatalf("event not forwarded: %+v", gotEvent)
	}
}

func TestHandleApprovalDropsUnknownSession(t *testing.T) {
	registry.Lock()
	delete(registry.sessions, "ghost")
	registry.Unlock()
	called := false
	orig := pushApprovalFn
	pushApprovalFn = func(string, approvalEvent) error { called = true; return nil }
	defer func() { pushApprovalFn = orig }()

	body, _ := json.Marshal(approvalEvent{ID: "x", SessionID: "ghost"})
	rec := httptest.NewRecorder()
	handleApproval(rec, httptest.NewRequest(http.MethodPost, "/approval", bytes.NewReader(body)))
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", rec.Code)
	}
	if called {
		t.Fatal("should not push to an unregistered session")
	}
}

func TestAskQuestionApprovalAlertBodyRedacted(t *testing.T) {
	sensitiveQuestion := "Should I delete /etc/passwd and export AWS_SECRET=supersecret?"
	body := approvalAlertBody(approvalEvent{
		Kind:     "askQuestion",
		Question: sensitiveQuestion,
		Risk:     "high",
		Command:  "rm -rf /",
	})
	if body != "Your agent needs your input" {
		t.Errorf("body = %q, want generic redacted copy", body)
	}
	if strings.Contains(body, sensitiveQuestion) {
		t.Errorf("alert body leaked raw question: %q", body)
	}
	for _, fragment := range []string{"/etc/passwd", "supersecret", "delete"} {
		if strings.Contains(body, fragment) {
			t.Errorf("alert body leaked sensitive fragment %q: %q", fragment, body)
		}
	}
}
