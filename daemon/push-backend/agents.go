package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

type Agent struct {
	ID                string          `json:"id"`
	CustomerID        string          `json:"customerId"`
	OrgID             string          `json:"orgId,omitempty"`
	AppAccountToken   string          `json:"appAccountToken,omitempty"`
	Name              string          `json:"name"`
	Description       string          `json:"description,omitempty"`
	Runtime           string          `json:"runtime"`
	Config            json.RawMessage `json:"config,omitempty"`
	OpenRouterKeyHash string          `json:"openRouterKeyHash,omitempty"`
	CreatedAt         string          `json:"createdAt"`
	UpdatedAt         string          `json:"updatedAt"`
}

type AgentRun struct {
	ID          string `json:"id"`
	AgentID     string `json:"agentId"`
	CustomerID  string `json:"customerId"`
	OrgID       string `json:"orgId,omitempty"`
	Status      string `json:"status"`
	Command     string `json:"command,omitempty"`
	StartedAt   string `json:"startedAt,omitempty"`
	CompletedAt string `json:"completedAt,omitempty"`
	ExitCode    *int   `json:"exitCode,omitempty"`
	// CancelRequested is set by POST /runs/{id}/cancel; cloud runners poll it
	// (GET /runs/{id}/control) and terminate. Never carries auth material.
	CancelRequested bool   `json:"cancelRequested,omitempty"`
	CreatedAt       string `json:"createdAt"`
	UpdatedAt       string `json:"updatedAt"`
}

type createAgentRequest struct {
	Name        string          `json:"name"`
	Description string          `json:"description,omitempty"`
	Runtime     string          `json:"runtime"`
	Config      json.RawMessage `json:"config,omitempty"`
}

type createRunRequest struct {
	AgentID string `json:"agentId"`
	Command string `json:"command,omitempty"`
	Status  string `json:"status,omitempty"`
}

type controlPlaneData struct {
	Agents []Agent    `json:"agents"`
	Runs   []AgentRun `json:"runs"`
}

var controlPlane = struct {
	mu   sync.RWMutex
	path string
	data controlPlaneData
}{
	path: dataFilePath("CONTROL_PLANE_FILE", "conduit-control-plane.json"),
	data: controlPlaneData{},
}

func initControlPlaneStore() {
	if err := loadJSONFile(controlPlane.path, &controlPlane.data); err != nil {
		log.Printf("control-plane: load failed: %v", err)
	}
}

func persistControlPlane() error {
	return saveJSONFile(controlPlane.path, controlPlane.data)
}

func newResourceID(prefix string) string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return prefix + "_" + hex.EncodeToString(b)
}

func registerAgentRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /agents", handleCreateAgent)
	mux.HandleFunc("GET /agents", handleListAgents)
	mux.HandleFunc("GET /agents/{id}", handleGetAgent)
	mux.HandleFunc("POST /runs", handleCreateRun)
	mux.HandleFunc("GET /runs/{id}", handleGetRun)
	mux.HandleFunc("GET /runs", handleListRuns)
}

func handleCreateAgent(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckAgent); err != nil {
		writeQuotaError(w, err)
		return
	}

	var req createAgentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}
	req.Runtime = normalizeRuntime(req.Runtime)
	if err := validateRuntime(req.Runtime); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	keyHash, _, err := ensureOpenRouterSubKey(ent)
	if err != nil {
		log.Printf("openrouter provision failed: %v", err)
		http.Error(w, "failed to provision AI key", http.StatusBadGateway)
		return
	}

	now := time.Now().UTC().Format(time.RFC3339)
	agent := Agent{
		ID:                newResourceID("agent"),
		CustomerID:        ent.CustomerID,
		OrgID:             ent.OrgID,
		AppAccountToken:   ent.AppAccountToken,
		Name:              req.Name,
		Description:       req.Description,
		Runtime:           req.Runtime,
		Config:            req.Config,
		OpenRouterKeyHash: keyHash,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	if err := provisionRuntimeIfNeeded(&agent); err != nil {
		log.Printf("runtime provision failed: %v", err)
		http.Error(w, "failed to provision runtime", http.StatusBadGateway)
		return
	}

	controlPlane.mu.Lock()
	controlPlane.data.Agents = append(controlPlane.data.Agents, agent)
	err = persistControlPlane()
	controlPlane.mu.Unlock()
	if err != nil {
		http.Error(w, "failed to persist agent", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, agent)
}

func handleListAgents(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	out := make([]Agent, 0)
	for _, agent := range controlPlane.data.Agents {
		if resourceVisibleToEntitlement(ent, agent.CustomerID, agent.OrgID) {
			out = append(out, agent)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"agents": out})
}

func handleGetAgent(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	id := r.PathValue("id")
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, agent := range controlPlane.data.Agents {
		if agent.ID == id {
			if !resourceVisibleToEntitlement(ent, agent.CustomerID, agent.OrgID) {
				http.Error(w, "agent not found", http.StatusNotFound)
				return
			}
			writeJSON(w, http.StatusOK, agent)
			return
		}
	}
	http.Error(w, "agent not found", http.StatusNotFound)
}

func handleCreateRun(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckRun); err != nil {
		writeQuotaError(w, err)
		return
	}

	var req createRunRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.AgentID == "" {
		http.Error(w, "agentId is required", http.StatusBadRequest)
		return
	}

	controlPlane.mu.Lock()
	defer controlPlane.mu.Unlock()

	var agent *Agent
	for i := range controlPlane.data.Agents {
		if controlPlane.data.Agents[i].ID == req.AgentID {
			agent = &controlPlane.data.Agents[i]
			break
		}
	}
	if agent == nil || !resourceVisibleToEntitlement(ent, agent.CustomerID, agent.OrgID) {
		http.Error(w, "agent not found", http.StatusNotFound)
		return
	}

	status := req.Status
	if status == "" {
		status = "pending"
	}
	now := time.Now().UTC().Format(time.RFC3339)
	run := AgentRun{
		ID:         newResourceID("run"),
		AgentID:    req.AgentID,
		CustomerID: ent.CustomerID,
		OrgID:      ent.OrgID,
		Status:     status,
		Command:    req.Command,
		StartedAt:  now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	controlPlane.data.Runs = append(controlPlane.data.Runs, run)
	if err := persistControlPlane(); err != nil {
		http.Error(w, "failed to persist run", http.StatusInternalServerError)
		return
	}
	agentCopy, runCopy := *agent, run
	go dispatchRun(&agentCopy, &runCopy)
	writeJSON(w, http.StatusCreated, run)
}

func handleGetRun(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	id := r.PathValue("id")
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, run := range controlPlane.data.Runs {
		if run.ID == id {
			if !resourceVisibleToEntitlement(ent, run.CustomerID, run.OrgID) {
				http.Error(w, "run not found", http.StatusNotFound)
				return
			}
			writeJSON(w, http.StatusOK, run)
			return
		}
	}
	http.Error(w, "run not found", http.StatusNotFound)
}

func handleListRuns(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	agentID := strings.TrimSpace(r.URL.Query().Get("agentId"))
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	out := make([]AgentRun, 0)
	for _, run := range controlPlane.data.Runs {
		if !resourceVisibleToEntitlement(ent, run.CustomerID, run.OrgID) {
			continue
		}
		if agentID != "" && run.AgentID != agentID {
			continue
		}
		out = append(out, run)
	}
	writeJSON(w, http.StatusOK, map[string]any{"runs": out})
}

func resetControlPlaneForTests() {
	controlPlane.mu.Lock()
	controlPlane.data = controlPlaneData{}
	controlPlane.mu.Unlock()
}

func setControlPlanePath(path string) {
	controlPlane.mu.Lock()
	controlPlane.path = path
	controlPlane.data = controlPlaneData{}
	controlPlane.mu.Unlock()
}
