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
		ContentHash: "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3",
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
	if gotEvent.ContentHash != "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3" {
		t.Fatalf("contentHash not forwarded: %+v", gotEvent)
	}
}

func TestApprovalAPNsPayloadCarriesContentHashNotCommand(t *testing.T) {
	ev := approvalEvent{
		ID:          "appr-hash",
		SessionID:   "sess-A",
		Command:     "rm -rf /secret/path",
		Risk:        "high",
		HostName:    "devbox",
		ContentHash: "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3",
	}
	payload, _, body := approvalAPNsPayload(ev)
	if payload["contentHash"] != ev.ContentHash {
		t.Fatalf("contentHash = %v, want %s", payload["contentHash"], ev.ContentHash)
	}
	if payload["approvalId"] != ev.ID || payload["sessionId"] != ev.SessionID {
		t.Fatalf("ids missing: %+v", payload)
	}
	if payload["command"] != nil {
		t.Fatalf("command must not appear in APNs userInfo, got %v", payload["command"])
	}
	if body == ev.Command || strings.Contains(body, "/secret/path") {
		t.Fatalf("alert body must stay redacted, got %q", body)
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
