package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// feedbackGitHubAPIBase is the GitHub REST API origin. Tests override it to an
// httptest server so no real network is used.
var feedbackGitHubAPIBase = "https://api.github.com"

var feedbackHTTPClient = &http.Client{Timeout: 15 * time.Second}

const (
	feedbackRateLimitMax    = 5
	feedbackRateLimitWindow = time.Hour
	feedbackMessageMinLen   = 10
	feedbackMessageMaxLen   = 4000
	feedbackFieldMaxLen     = 100
	feedbackTitleMaxLen     = 72
)

type feedbackRequest struct {
	Type        string `json:"type"`
	Message     string `json:"message"`
	AppVersion  string `json:"appVersion"`
	Build       string `json:"build"`
	OSVersion   string `json:"osVersion"`
	DeviceModel string `json:"deviceModel"`
}

type feedbackSuccessResponse struct {
	Issue int    `json:"issue"`
	URL   string `json:"url"`
}

type githubCreateIssueRequest struct {
	Title  string   `json:"title"`
	Body   string   `json:"body"`
	Labels []string `json:"labels"`
}

type githubCreateIssueResponse struct {
	Number  int    `json:"number"`
	HTMLURL string `json:"html_url"`
}

var feedbackRateLimiter = struct {
	mu   sync.Mutex
	byIP map[string][]time.Time
}{
	byIP: make(map[string][]time.Time),
}

func registerFeedbackRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /feedback", handleFeedback)
}

func resetFeedbackRateLimiter() {
	feedbackRateLimiter.mu.Lock()
	defer feedbackRateLimiter.mu.Unlock()
	feedbackRateLimiter.byIP = make(map[string][]time.Time)
}

func handleFeedback(w http.ResponseWriter, r *http.Request) {
	ip := feedbackClientIP(r)

	token := strings.TrimSpace(os.Getenv("FEEDBACK_GITHUB_TOKEN"))
	repo := strings.TrimSpace(os.Getenv("FEEDBACK_GITHUB_REPO"))
	if token == "" || repo == "" {
		log.Printf("feedback: type=? ip=%s error=unconfigured", ip)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "feedback_unconfigured"})
		return
	}

	if !feedbackAllow(ip) {
		log.Printf("feedback: type=? ip=%s error=rate_limited", ip)
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "rate_limited"})
		return
	}

	var req feedbackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("feedback: type=? ip=%s error=bad_json", ip)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_json"})
		return
	}

	if err := validateFeedbackRequest(&req); err != nil {
		log.Printf("feedback: type=%s ip=%s error=validation", req.Type, ip)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	issue, err := createFeedbackGitHubIssue(token, repo, req)
	if err != nil {
		log.Printf("feedback: type=%s ip=%s error=github_upstream", req.Type, ip)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "github_upstream"})
		return
	}

	log.Printf("feedback: type=%s ip=%s issue=%d", req.Type, ip, issue.Number)
	writeJSON(w, http.StatusCreated, feedbackSuccessResponse{
		Issue: issue.Number,
		URL:   issue.HTMLURL,
	})
}

func validateFeedbackRequest(req *feedbackRequest) error {
	switch req.Type {
	case "bug", "feature", "other":
	default:
		return fmt.Errorf("invalid_type")
	}

	req.Message = strings.TrimSpace(req.Message)
	msgLen := utf8.RuneCountInString(req.Message)
	if msgLen < feedbackMessageMinLen || msgLen > feedbackMessageMaxLen {
		return fmt.Errorf("invalid_message")
	}

	req.AppVersion = trimFeedbackField(req.AppVersion)
	req.Build = trimFeedbackField(req.Build)
	req.OSVersion = trimFeedbackField(req.OSVersion)
	req.DeviceModel = trimFeedbackField(req.DeviceModel)
	if len(req.AppVersion) > feedbackFieldMaxLen ||
		len(req.Build) > feedbackFieldMaxLen ||
		len(req.OSVersion) > feedbackFieldMaxLen ||
		len(req.DeviceModel) > feedbackFieldMaxLen {
		return fmt.Errorf("invalid_field")
	}
	return nil
}

func trimFeedbackField(s string) string {
	return strings.TrimSpace(s)
}

func feedbackIssueTitle(typ, message string) string {
	prefix := "[" + typ + "] "
	runes := []rune(message)
	if len(runes) > feedbackTitleMaxLen {
		runes = runes[:feedbackTitleMaxLen]
	}
	return prefix + string(runes)
}

func feedbackIssueBody(req feedbackRequest, now time.Time) string {
	var b strings.Builder
	b.WriteString(req.Message)
	b.WriteString("\n\n### Diagnostics\n")
	b.WriteString("- appVersion: ")
	b.WriteString(req.AppVersion)
	b.WriteByte('\n')
	b.WriteString("- build: ")
	b.WriteString(req.Build)
	b.WriteByte('\n')
	b.WriteString("- osVersion: ")
	b.WriteString(req.OSVersion)
	b.WriteByte('\n')
	b.WriteString("- deviceModel: ")
	b.WriteString(req.DeviceModel)
	b.WriteByte('\n')
	b.WriteString("- timestamp: ")
	b.WriteString(now.UTC().Format(time.RFC3339))
	b.WriteByte('\n')
	return b.String()
}

func createFeedbackGitHubIssue(token, repo string, req feedbackRequest) (*githubCreateIssueResponse, error) {
	payload := githubCreateIssueRequest{
		Title:  feedbackIssueTitle(req.Type, req.Message),
		Body:   feedbackIssueBody(req, time.Now()),
		Labels: []string{req.Type},
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	url := strings.TrimRight(feedbackGitHubAPIBase, "/") + "/repos/" + repo + "/issues"
	httpReq, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+token)
	httpReq.Header.Set("Accept", "application/vnd.github+json")
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := feedbackHTTPClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("github status %d", resp.StatusCode)
	}

	var issue githubCreateIssueResponse
	if err := json.Unmarshal(body, &issue); err != nil {
		return nil, err
	}
	if issue.Number == 0 || issue.HTMLURL == "" {
		return nil, fmt.Errorf("github response missing issue fields")
	}
	return &issue, nil
}

func feedbackClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if len(parts) > 0 {
			ip := strings.TrimSpace(parts[0])
			if ip != "" {
				return ip
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func feedbackAllow(ip string) bool {
	now := time.Now()
	cutoff := now.Add(-feedbackRateLimitWindow)

	feedbackRateLimiter.mu.Lock()
	defer feedbackRateLimiter.mu.Unlock()

	stamps := feedbackRateLimiter.byIP[ip]
	kept := stamps[:0]
	for _, ts := range stamps {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	if len(kept) >= feedbackRateLimitMax {
		feedbackRateLimiter.byIP[ip] = kept
		return false
	}
	kept = append(kept, now)
	feedbackRateLimiter.byIP[ip] = kept
	return true
}
