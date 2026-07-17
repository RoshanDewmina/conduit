package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func setupFeedbackTest(t *testing.T, githubHandler http.HandlerFunc) *httptest.Server {
	t.Helper()
	resetFeedbackRateLimiter()

	var srv *httptest.Server
	if githubHandler != nil {
		srv = httptest.NewServer(githubHandler)
		t.Cleanup(srv.Close)
		feedbackGitHubAPIBase = srv.URL
		t.Setenv("FEEDBACK_GITHUB_TOKEN", "test-token")
		t.Setenv("FEEDBACK_GITHUB_REPO", "owner/feedback-repo")
	} else {
		feedbackGitHubAPIBase = "https://api.github.com"
		t.Setenv("FEEDBACK_GITHUB_TOKEN", "")
		t.Setenv("FEEDBACK_GITHUB_REPO", "")
	}
	t.Cleanup(func() {
		feedbackGitHubAPIBase = "https://api.github.com"
		resetFeedbackRateLimiter()
	})
	return srv
}

func feedbackMux() *http.ServeMux {
	mux := http.NewServeMux()
	registerFeedbackRoutes(mux)
	return mux
}

func postFeedback(t *testing.T, mux http.Handler, body string, ip string, xff string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if ip != "" {
		req.RemoteAddr = ip + ":12345"
	}
	if xff != "" {
		req.Header.Set("X-Forwarded-For", xff)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func validFeedbackBody() string {
	return `{
		"type": "bug",
		"message": "Something broke when I tapped approve",
		"appVersion": "1.2.3",
		"build": "456",
		"osVersion": "18.0",
		"deviceModel": "iPhone16,1"
	}`
}

func TestFeedbackSuccessCreatesGitHubIssue(t *testing.T) {
	var (
		mu        sync.Mutex
		gotReq    *http.Request
		gotBody   []byte
		gotAuth   string
		gotAccept string
	)
	setupFeedbackTest(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		body, _ := io.ReadAll(r.Body)
		gotReq = r
		gotBody = body
		gotAuth = r.Header.Get("Authorization")
		gotAccept = r.Header.Get("Accept")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"number":42,"html_url":"https://github.com/owner/feedback-repo/issues/42"}`))
	})

	rec := postFeedback(t, feedbackMux(), validFeedbackBody(), "1.2.3.4", "")
	if rec.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Issue int    `json:"issue"`
		URL   string `json:"url"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Issue != 42 || resp.URL != "https://github.com/owner/feedback-repo/issues/42" {
		t.Fatalf("unexpected response: %+v", resp)
	}

	mu.Lock()
	defer mu.Unlock()
	if gotReq == nil {
		t.Fatal("github API was not called")
	}
	if gotReq.Method != http.MethodPost {
		t.Fatalf("method=%s", gotReq.Method)
	}
	if gotReq.URL.Path != "/repos/owner/feedback-repo/issues" {
		t.Fatalf("path=%s", gotReq.URL.Path)
	}
	if gotAuth != "Bearer test-token" {
		t.Fatalf("Authorization=%q", gotAuth)
	}
	if gotAccept != "application/vnd.github+json" {
		t.Fatalf("Accept=%q", gotAccept)
	}

	var issue struct {
		Title  string   `json:"title"`
		Body   string   `json:"body"`
		Labels []string `json:"labels"`
	}
	if err := json.Unmarshal(gotBody, &issue); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(issue.Title, "[bug] ") {
		t.Fatalf("title=%q", issue.Title)
	}
	if !strings.Contains(issue.Title, "Something broke when I tapped approve") {
		t.Fatalf("title missing message: %q", issue.Title)
	}
	if !strings.Contains(issue.Body, "Something broke when I tapped approve") {
		t.Fatalf("body missing message: %q", issue.Body)
	}
	if !strings.Contains(issue.Body, "### Diagnostics") {
		t.Fatalf("body missing diagnostics: %q", issue.Body)
	}
	for _, want := range []string{"1.2.3", "456", "18.0", "iPhone16,1"} {
		if !strings.Contains(issue.Body, want) {
			t.Fatalf("body missing %q: %q", want, issue.Body)
		}
	}
	if len(issue.Labels) != 1 || issue.Labels[0] != "bug" {
		t.Fatalf("labels=%v", issue.Labels)
	}
}

func TestFeedbackGitHub500Returns502(t *testing.T) {
	setupFeedbackTest(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"message":"boom"}`))
	})

	rec := postFeedback(t, feedbackMux(), validFeedbackBody(), "1.2.3.4", "")
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestFeedbackUnconfiguredReturns503(t *testing.T) {
	setupFeedbackTest(t, nil)

	rec := postFeedback(t, feedbackMux(), validFeedbackBody(), "1.2.3.4", "")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["error"] != "feedback_unconfigured" {
		t.Fatalf("resp=%v", resp)
	}
}

func TestFeedbackBadTypeReturns400(t *testing.T) {
	setupFeedbackTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("github should not be called")
	})

	body := `{"type":"typo","message":"This message is long enough"}`
	rec := postFeedback(t, feedbackMux(), body, "1.2.3.4", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestFeedbackShortMessageReturns400(t *testing.T) {
	setupFeedbackTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("github should not be called")
	})

	body := `{"type":"bug","message":"too short"}`
	rec := postFeedback(t, feedbackMux(), body, "1.2.3.4", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestFeedbackRateLimitPerIP(t *testing.T) {
	setupFeedbackTest(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"number":1,"html_url":"https://github.com/owner/feedback-repo/issues/1"}`))
	})
	mux := feedbackMux()
	body := validFeedbackBody()

	for i := 0; i < 5; i++ {
		rec := postFeedback(t, mux, body, "", "10.0.0.1, 10.0.0.2")
		if rec.Code != http.StatusCreated {
			t.Fatalf("call %d status=%d body=%s", i+1, rec.Code, rec.Body.String())
		}
	}
	rec := postFeedback(t, mux, body, "", "10.0.0.1, 10.0.0.2")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("6th same IP status=%d body=%s", rec.Code, rec.Body.String())
	}

	other := postFeedback(t, mux, body, "", "10.0.0.9")
	if other.Code != http.StatusCreated {
		t.Fatalf("different IP status=%d body=%s", other.Code, other.Body.String())
	}
}
