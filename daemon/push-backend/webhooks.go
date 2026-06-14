package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

// ── GitHub webhook types ──────────────────────────────────────────────────

type githubEvent struct {
	Action      string        `json:"action"`
	PullRequest *githubPRInfo `json:"pull_request,omitempty"`
	CheckRun    *githubCheckRun `json:"check_run,omitempty"`
	Repository  githubRepoInfo `json:"repository"`
	Sender      githubUserInfo `json:"sender"`
}

type githubPRInfo struct {
	Number int    `json:"number"`
	Title  string `json:"title"`
	URL    string `json:"html_url"`
	State  string `json:"state"`
	Merged bool   `json:"merged"`
	Head   struct {
		Ref string `json:"ref"`
		SHA string `json:"sha"`
	} `json:"head"`
	Base struct {
		Ref string `json:"ref"`
		SHA string `json:"sha"`
	} `json:"base"`
}

type githubCheckRun struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	Output     struct {
		Title   string `json:"title"`
		Summary string `json:"summary"`
	} `json:"output"`
}

type githubRepoInfo struct {
	Name     string `json:"name"`
	FullName string `json:"full_name"`
}

type githubUserInfo struct {
	Login string `json:"login"`
}

// ── CI event store (in-memory ring buffer) ────────────────────────────────

const (
	maxCIEventsPerRepo = 100
	ciEventTTL         = 24 * time.Hour
)

// CIEvent is a normalized CI/PR event stored for the iOS app to poll.
type CIEvent struct {
	ID        string    `json:"id"`
	Repo      string    `json:"repo"`
	Type      string    `json:"type"`      // "pr", "check_run", "status"
	Action    string    `json:"action"`
	PRNumber  int       `json:"prNumber,omitempty"`
	PRTitle   string    `json:"prTitle,omitempty"`
	PRURL     string    `json:"prURL,omitempty"`
	Status    string    `json:"status"`    // "success", "failure", "pending", "error"
	Context   string    `json:"context,omitempty"`
	Message   string    `json:"message,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

var ciStore = struct {
	sync.RWMutex
	events map[string][]CIEvent
}{events: make(map[string][]CIEvent)}

func storeCIEvent(ev CIEvent) {
	ciStore.Lock()
	defer ciStore.Unlock()

	events := ciStore.events[ev.Repo]
	events = append(events, ev)
	if len(events) > maxCIEventsPerRepo {
		events = events[len(events)-maxCIEventsPerRepo:]
	}
	ciStore.events[ev.Repo] = events
}

func getRecentCIEvents(repo string, limit int) []CIEvent {
	ciStore.RLock()
	defer ciStore.RUnlock()

	events := ciStore.events[repo]
	if limit <= 0 || limit > len(events) {
		limit = len(events)
	}
	result := make([]CIEvent, limit)
	copy(result, events[len(events)-limit:])

	now := time.Now()
	filtered := result[:0]
	for _, ev := range result {
		if now.Sub(ev.Timestamp) < ciEventTTL {
			filtered = append(filtered, ev)
		}
	}
	return filtered
}

// ── Webhook signature verification ────────────────────────────────────────

func verifyGitHubSignature(payload []byte, r *http.Request) bool {
	secret := os.Getenv("GITHUB_WEBHOOK_SECRET")
	if secret == "" {
		// Fail closed: without a configured secret we cannot authenticate the
		// sender, so reject rather than process forged events.
		return false
	}
	sig := r.Header.Get("X-Hub-Signature-256")
	if sig == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(sig), []byte(expected))
}

// ── GitHub webhook handler ────────────────────────────────────────────────

func handleGitHubWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20)) // 1 MiB max
	if err != nil {
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}

	if !verifyGitHubSignature(body, r) {
		http.Error(w, "invalid signature", http.StatusUnauthorized)
		return
	}

	eventType := r.Header.Get("X-GitHub-Event")
	if eventType == "ping" {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"msg":"pong"}`))
		return
	}

	var ev githubEvent
	if err := json.Unmarshal(body, &ev); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	repo := ev.Repository.FullName
	if repo == "" {
		repo = ev.Repository.Name
	}

	switch eventType {
	case "pull_request":
		if ev.PullRequest != nil {
			pr := ev.PullRequest
			status := "pending"
			if ev.Action == "closed" {
				if pr.Merged {
					status = "success"
				} else {
					status = "failure"
				}
			} else if ev.Action == "opened" || ev.Action == "reopened" {
				status = "pending"
			}

			storeCIEvent(CIEvent{
				ID:        strconv.Itoa(int(time.Now().UnixNano())),
				Repo:      repo,
				Type:      "pr",
				Action:    ev.Action,
				PRNumber:  pr.Number,
				PRTitle:   pr.Title,
				PRURL:     pr.URL,
				Status:    status,
				Context:   "pull_request",
				Message:   pr.Title,
				Timestamp: time.Now(),
			})
			log.Printf("webhook: PR #%d %s on %s", pr.Number, ev.Action, repo)
		}

	case "check_run":
		if ev.CheckRun != nil {
			cr := ev.CheckRun
			status := cr.Conclusion
			if status == "" {
				status = cr.Status
			}
			if status == "" {
				status = "pending"
			}

			storeCIEvent(CIEvent{
				ID:        strconv.Itoa(int(time.Now().UnixNano())),
				Repo:      repo,
				Type:      "check_run",
				Action:    ev.Action,
				Status:    status,
				Context:   cr.Name,
				Message:   cr.Output.Summary,
				Timestamp: time.Now(),
			})
			log.Printf("webhook: check_run %s (%s) on %s", cr.Name, status, repo)
		}

	case "status":
		// Commit status events carry state + context directly
		var statusEv struct {
			State       string `json:"state"`
			Description string `json:"description"`
			TargetURL   string `json:"target_url"`
			Context     string `json:"context"`
			Commit      struct {
				SHA string `json:"sha"`
			} `json:"commit"`
		}
		if err := json.Unmarshal(body, &statusEv); err == nil {
			storeCIEvent(CIEvent{
				ID:        strconv.Itoa(int(time.Now().UnixNano())),
				Repo:      repo,
				Type:      "status",
				Action:    "status",
				Status:    statusEv.State,
				Context:   statusEv.Context,
				Message:   statusEv.Description,
				Timestamp: time.Now(),
			})
			log.Printf("webhook: status %s (%s) on %s", statusEv.State, statusEv.Context, repo)
		}

	default:
		log.Printf("webhook: ignoring event type %s", eventType)
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── Recent events endpoint ────────────────────────────────────────────────

func handleRecentEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	repo := r.URL.Query().Get("repo")
	if repo == "" {
		http.Error(w, "repo parameter required", http.StatusBadRequest)
		return
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	events := getRecentCIEvents(repo, limit)
	writeJSON(w, http.StatusOK, events)
}

func initWebhookRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /webhooks/github", handleGitHubWebhook)
	mux.HandleFunc("GET /webhooks/recent", handleRecentEvents)
}
