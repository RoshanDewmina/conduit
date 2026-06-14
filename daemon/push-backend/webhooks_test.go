package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func signGitHubPayload(secret, payload string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func postWebhook(t *testing.T, payload, signature string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/webhooks/github", strings.NewReader(payload))
	req.Header.Set("X-GitHub-Event", "ping")
	if signature != "" {
		req.Header.Set("X-Hub-Signature-256", signature)
	}
	rec := httptest.NewRecorder()
	handleGitHubWebhook(rec, req)
	return rec
}

// Unset secret must fail closed: the request is rejected, not accepted.
func TestWebhook_UnsetSecret_Rejected(t *testing.T) {
	t.Setenv("GITHUB_WEBHOOK_SECRET", "")
	payload := `{"zen":"ping"}`
	rec := postWebhook(t, payload, signGitHubPayload("anything", payload))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("unset secret should be rejected with 401, got %d", rec.Code)
	}
}

func TestWebhook_SetSecret_ValidSignature_Accepted(t *testing.T) {
	secret := "supersecret"
	t.Setenv("GITHUB_WEBHOOK_SECRET", secret)
	payload := `{"zen":"ping"}`
	rec := postWebhook(t, payload, signGitHubPayload(secret, payload))
	if rec.Code != http.StatusOK {
		t.Fatalf("valid signature should be accepted with 200 (ping pong), got %d", rec.Code)
	}
}

func TestWebhook_SetSecret_BadSignature_Rejected(t *testing.T) {
	t.Setenv("GITHUB_WEBHOOK_SECRET", "supersecret")
	payload := `{"zen":"ping"}`
	rec := postWebhook(t, payload, signGitHubPayload("wrongsecret", payload))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("bad signature should be rejected with 401, got %d", rec.Code)
	}
}

func TestWebhook_SetSecret_MissingSignature_Rejected(t *testing.T) {
	t.Setenv("GITHUB_WEBHOOK_SECRET", "supersecret")
	rec := postWebhook(t, `{"zen":"ping"}`, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("missing signature should be rejected with 401, got %d", rec.Code)
	}
}
