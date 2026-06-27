package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// RunLogEntry is one streamed line of a run's output.
type RunLogEntry struct {
	Seq    int    `json:"seq"`
	Stream string `json:"stream"` // "stdout" | "stderr"
	Text   string `json:"text"`
	Ts     string `json:"ts"`
}

type runLogsData struct {
	Logs map[string][]RunLogEntry `json:"logs"`
}

// runTokensData maps a per-run runner token -> runID. The runner authenticates
// log/status callbacks with its token; the token is NEVER returned to the app
// and is scoped to exactly one run.
type runTokensData struct {
	Tokens map[string]string `json:"tokens"`
}

var runLogsStore = struct {
	mu   sync.Mutex
	path string
}{
	path: dataFilePath("RUN_LOGS_FILE", "lancer-run-logs.json"),
}

var runTokensStore = struct {
	mu   sync.Mutex
	path string
}{
	path: dataFilePath("RUN_TOKENS_FILE", "lancer-run-tokens.json"),
}

func initRunLogsStore() {
	var logs runLogsData
	if err := loadJSONFile(runLogsStore.path, &logs); err != nil {
		log.Printf("run-logs: load failed: %v", err)
	}
	var tokens runTokensData
	if err := loadJSONFile(runTokensStore.path, &tokens); err != nil {
		log.Printf("run-tokens: load failed: %v", err)
	}
}

func registerRunLogRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /runs/{id}/logs", handleAppendRunLogs)
	mux.HandleFunc("GET /runs/{id}/logs", handleGetRunLogs)
	mux.HandleFunc("PATCH /runs/{id}", handlePatchRun)
	mux.HandleFunc("POST /runs/{id}/cancel", handleCancelRun)
	mux.HandleFunc("GET /runs/{id}/control", handleRunControl)
}

// --- runner-token helpers ---

func runnerBearer(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
}

// mintRunToken issues and persists a runner token for a run. Called at dispatch
// time (M6) when a cloud run is provisioned.
func mintRunToken(runID string) (string, error) {
	runTokensStore.mu.Lock()
	defer runTokensStore.mu.Unlock()
	var data runTokensData
	_ = loadJSONFile(runTokensStore.path, &data)
	if data.Tokens == nil {
		data.Tokens = map[string]string{}
	}
	token := newResourceID("rt")
	data.Tokens[token] = runID
	if err := saveJSONFile(runTokensStore.path, data); err != nil {
		return "", err
	}
	return token, nil
}

// resolveRunFromRunnerToken returns the runID a runner token is scoped to.
func resolveRunFromRunnerToken(r *http.Request) (string, bool) {
	token := runnerBearer(r)
	if token == "" {
		return "", false
	}
	runTokensStore.mu.Lock()
	defer runTokensStore.mu.Unlock()
	var data runTokensData
	if err := loadJSONFile(runTokensStore.path, &data); err != nil {
		return "", false
	}
	runID, ok := data.Tokens[token]
	return runID, ok
}

// --- log store helpers ---

func appendRunLogs(runID string, entries []RunLogEntry) (int, error) {
	runLogsStore.mu.Lock()
	defer runLogsStore.mu.Unlock()
	var data runLogsData
	_ = loadJSONFile(runLogsStore.path, &data)
	if data.Logs == nil {
		data.Logs = map[string][]RunLogEntry{}
	}
	existing := data.Logs[runID]
	seq := 0
	if n := len(existing); n > 0 {
		seq = existing[n-1].Seq
	}
	now := time.Now().UTC().Format(time.RFC3339)
	for i := range entries {
		seq++
		entries[i].Seq = seq
		if entries[i].Ts == "" {
			entries[i].Ts = now
		}
		if entries[i].Stream == "" {
			entries[i].Stream = "stdout"
		}
		existing = append(existing, entries[i])
	}
	data.Logs[runID] = existing
	if err := saveJSONFile(runLogsStore.path, data); err != nil {
		return 0, err
	}
	return seq, nil
}

func runLogsSince(runID string, since int) ([]RunLogEntry, int) {
	runLogsStore.mu.Lock()
	defer runLogsStore.mu.Unlock()
	var data runLogsData
	_ = loadJSONFile(runLogsStore.path, &data)
	all := data.Logs[runID]
	out := make([]RunLogEntry, 0, len(all))
	next := since
	for _, e := range all {
		if e.Seq > since {
			out = append(out, e)
			next = e.Seq
		}
	}
	return out, next
}

// --- run mutation helpers ---

func updateRunFields(runID string, apply func(*AgentRun)) bool {
	controlPlane.mu.Lock()
	defer controlPlane.mu.Unlock()
	for i := range controlPlane.data.Runs {
		if controlPlane.data.Runs[i].ID == runID {
			apply(&controlPlane.data.Runs[i])
			controlPlane.data.Runs[i].UpdatedAt = time.Now().UTC().Format(time.RFC3339)
			if err := persistControlPlane(); err != nil {
				log.Printf("run-logs: persist run %s failed: %v", runID, err)
				return false
			}
			return true
		}
	}
	return false
}

func runControlSnapshot(runID string) (status string, cancelRequested bool, ok bool) {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, run := range controlPlane.data.Runs {
		if run.ID == runID {
			return run.Status, run.CancelRequested, true
		}
	}
	return "", false, false
}

// --- handlers ---

type appendLogsRequest struct {
	Lines []struct {
		Stream string `json:"stream"`
		Text   string `json:"text"`
	} `json:"lines"`
}

func handleAppendRunLogs(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tokenRunID, ok := resolveRunFromRunnerToken(r)
	if !ok || tokenRunID != id {
		http.Error(w, "invalid runner token", http.StatusUnauthorized)
		return
	}
	var req appendLogsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	entries := make([]RunLogEntry, 0, len(req.Lines))
	for _, l := range req.Lines {
		entries = append(entries, RunLogEntry{Stream: l.Stream, Text: l.Text})
	}
	next, err := appendRunLogs(id, entries)
	if err != nil {
		http.Error(w, "failed to persist logs", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"nextSince": next})
}

func handleGetRunLogs(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id := r.PathValue("id")
	if !customerOwnsRun(ent, id) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	since := 0
	if s := r.URL.Query().Get("since"); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= 0 {
			since = v
		}
	}
	lines, next := runLogsSince(id, since)
	writeJSON(w, http.StatusOK, map[string]any{"lines": lines, "nextSince": next})
}

type patchRunRequest struct {
	Status      *string `json:"status,omitempty"`
	ExitCode    *int    `json:"exitCode,omitempty"`
	CompletedAt *string `json:"completedAt,omitempty"`
}

func handlePatchRun(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tokenRunID, ok := resolveRunFromRunnerToken(r)
	if !ok || tokenRunID != id {
		http.Error(w, "invalid runner token", http.StatusUnauthorized)
		return
	}
	var req patchRunRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	found := updateRunFields(id, func(run *AgentRun) {
		if req.Status != nil {
			run.Status = *req.Status
		}
		if req.ExitCode != nil {
			run.ExitCode = req.ExitCode
		}
		if req.CompletedAt != nil {
			run.CompletedAt = *req.CompletedAt
		} else if req.Status != nil && isTerminalRunStatus(*req.Status) && run.CompletedAt == "" {
			run.CompletedAt = time.Now().UTC().Format(time.RFC3339)
		}
	})
	if !found {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func handleCancelRun(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id := r.PathValue("id")
	if !customerOwnsRun(ent, id) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	var handle, runtime string
	if !updateRunFields(id, func(run *AgentRun) {
		run.CancelRequested = true
		handle, runtime = run.ProviderHandle, run.Runtime
	}) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	// Cooperative cancel (the runner polls GET /control) is the primary path; this
	// best-effort hard-terminate is the backstop for a runner that hangs without
	// polling. Fire-and-forget so the HTTP response isn't blocked on a cloud call.
	if handle != "" {
		go hardCancel(runtime, handle)
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func handleRunControl(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tokenRunID, ok := resolveRunFromRunnerToken(r)
	if !ok || tokenRunID != id {
		http.Error(w, "invalid runner token", http.StatusUnauthorized)
		return
	}
	status, cancelRequested, found := runControlSnapshot(id)
	if !found {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": status, "cancelRequested": cancelRequested})
}

func isTerminalRunStatus(status string) bool {
	switch status {
	case "succeeded", "failed", "cancelled":
		return true
	}
	return false
}

func setRunLogsPath(path string)   { runLogsStore.path = path }
func setRunTokensPath(path string) { runTokensStore.path = path }

func resetRunLogsForTests() {
	_ = saveJSONFile(runLogsStore.path, runLogsData{})
	_ = saveJSONFile(runTokensStore.path, runTokensData{})
}
