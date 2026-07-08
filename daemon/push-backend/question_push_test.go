package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHandleQuestionRoutesToRegisteredToken(t *testing.T) {
	registry.Lock()
	registry.sessions["sess-question"] = &sessionRecord{apnsToken: "device-token-question", seen: time.Now().Unix()}
	registry.Unlock()

	var gotToken string
	var gotEvent questionEvent
	orig := pushQuestionFn
	pushQuestionFn = func(token string, ev questionEvent) error {
		gotToken = token
		gotEvent = ev
		return nil
	}
	defer func() { pushQuestionFn = orig }()

	body, _ := json.Marshal(questionEvent{
		ID: "q-1", SessionID: "sess-question", Agent: "claudeCode", HostName: "devbox", Confidence: "complete",
	})
	rec := httptest.NewRecorder()
	handleQuestion(rec, httptest.NewRequest(http.MethodPost, "/question", bytes.NewReader(body)))

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if gotToken != "device-token-question" {
		t.Fatalf("routed to token %q", gotToken)
	}
	if gotEvent.ID != "q-1" {
		t.Fatalf("event not forwarded: %+v", gotEvent)
	}
}

func TestHandleQuestionDropsUnknownSession(t *testing.T) {
	registry.Lock()
	delete(registry.sessions, "ghost-question")
	registry.Unlock()
	called := false
	orig := pushQuestionFn
	pushQuestionFn = func(string, questionEvent) error { called = true; return nil }
	defer func() { pushQuestionFn = orig }()

	body, _ := json.Marshal(questionEvent{ID: "x", SessionID: "ghost-question"})
	rec := httptest.NewRecorder()
	handleQuestion(rec, httptest.NewRequest(http.MethodPost, "/question", bytes.NewReader(body)))
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", rec.Code)
	}
	if called {
		t.Fatal("should not push to an unregistered session")
	}
}

func TestHandleQuestionMissingSessionID(t *testing.T) {
	body, _ := json.Marshal(questionEvent{ID: "x"})
	rec := httptest.NewRecorder()
	handleQuestion(rec, httptest.NewRequest(http.MethodPost, "/question", bytes.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}
