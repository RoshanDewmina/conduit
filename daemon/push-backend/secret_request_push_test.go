package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHandleSecretRequestRoutesToRegisteredToken(t *testing.T) {
	registry.Lock()
	registry.sessions["sess-secret"] = &sessionRecord{apnsToken: "device-token-secret", seen: time.Now().Unix()}
	registry.Unlock()

	var gotToken string
	var gotEvent secretRequestEvent
	orig := pushSecretRequestFn
	pushSecretRequestFn = func(token string, ev secretRequestEvent) error {
		gotToken = token
		gotEvent = ev
		return nil
	}
	defer func() { pushSecretRequestFn = orig }()

	body, _ := json.Marshal(secretRequestEvent{
		ID: "sec-1", SessionID: "sess-secret", Agent: "claudeCode", ToolName: "Bash",
		CredentialType: "AWS access key", RequestedScope: "s3:read", HostName: "devbox",
	})
	rec := httptest.NewRecorder()
	handleSecretRequest(rec, httptest.NewRequest(http.MethodPost, "/secret-request", bytes.NewReader(body)))

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if gotToken != "device-token-secret" {
		t.Fatalf("routed to token %q", gotToken)
	}
	if gotEvent.ID != "sec-1" || gotEvent.CredentialType != "AWS access key" {
		t.Fatalf("event not forwarded: %+v", gotEvent)
	}
}

func TestHandleSecretRequestDropsUnknownSession(t *testing.T) {
	registry.Lock()
	delete(registry.sessions, "ghost-secret")
	registry.Unlock()
	called := false
	orig := pushSecretRequestFn
	pushSecretRequestFn = func(string, secretRequestEvent) error { called = true; return nil }
	defer func() { pushSecretRequestFn = orig }()

	body, _ := json.Marshal(secretRequestEvent{ID: "x", SessionID: "ghost-secret"})
	rec := httptest.NewRecorder()
	handleSecretRequest(rec, httptest.NewRequest(http.MethodPost, "/secret-request", bytes.NewReader(body)))
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", rec.Code)
	}
	if called {
		t.Fatal("should not push to an unregistered session")
	}
}

func TestHandleSecretRequestMissingSessionID(t *testing.T) {
	body, _ := json.Marshal(secretRequestEvent{ID: "x"})
	rec := httptest.NewRecorder()
	handleSecretRequest(rec, httptest.NewRequest(http.MethodPost, "/secret-request", bytes.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

// TestRedactCredentialSummaryNeverLeaksRaw asserts the alert-body summary
// never echoes anything beyond the generic credential-type category — no
// requestedScope, no credential name/value could leak this way even if a
// caller mistakenly passed one in as the "type".
func TestRedactCredentialSummaryFormat(t *testing.T) {
	cases := map[string]string{
		"":            "An agent is requesting access to a credential",
		"AWS API key": "An agent is requesting access to a AWS API key credential",
	}
	for in, want := range cases {
		if got := redactCredentialSummary(in); got != want {
			t.Errorf("redactCredentialSummary(%q) = %q, want %q", in, got, want)
		}
	}
}
