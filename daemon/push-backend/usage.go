package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

type UsageRecord struct {
	ID         string  `json:"id"`
	RunID      string  `json:"runId,omitempty"`
	AgentID    string  `json:"agentId,omitempty"`
	CustomerID string  `json:"customerId"`
	Model      string  `json:"model,omitempty"`
	TokensIn   int     `json:"tokensIn,omitempty"`
	TokensOut  int     `json:"tokensOut,omitempty"`
	Cost       float64 `json:"cost"`
	RecordedAt string  `json:"recordedAt"`
}

type usageIngestRequest struct {
	RunID     string  `json:"runId,omitempty"`
	AgentID   string  `json:"agentId,omitempty"`
	Model     string  `json:"model,omitempty"`
	TokensIn  int     `json:"tokensIn,omitempty"`
	TokensOut int     `json:"tokensOut,omitempty"`
	Cost      float64 `json:"cost"`
}

type usageData struct {
	Records []UsageRecord `json:"records"`
}

var usageStore = struct {
	path string
}{
	path: dataFilePath("USAGE_FILE", "conduit-usage.json"),
}

func registerUsageRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /usage", handleUsageIngest)
}

type usageIngestResponse struct {
	UsageRecord
	Credit *creditDeductResult `json:"credit,omitempty"`
}

func handleUsageIngest(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckUsage); err != nil {
		writeQuotaError(w, err)
		return
	}

	var req usageIngestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.Cost < 0 {
		http.Error(w, "cost must be non-negative", http.StatusBadRequest)
		return
	}

	record := UsageRecord{
		ID:         newResourceID("usage"),
		RunID:      req.RunID,
		AgentID:    req.AgentID,
		CustomerID: ent.CustomerID,
		Model:      req.Model,
		TokensIn:   req.TokensIn,
		TokensOut:  req.TokensOut,
		Cost:       req.Cost,
		RecordedAt: time.Now().UTC().Format(time.RFC3339),
	}

	var data usageData
	if err := loadJSONFile(usageStore.path, &data); err != nil {
		log.Printf("usage: load failed: %v", err)
	}
	data.Records = append(data.Records, record)
	if err := saveJSONFile(usageStore.path, data); err != nil {
		http.Error(w, "failed to persist usage", http.StatusInternalServerError)
		return
	}

	creditResult, err := deductCredits(ent.CustomerID, req.Cost)
	if err != nil {
		http.Error(w, "failed to deduct credits", http.StatusInternalServerError)
		return
	}
	if creditResult.Blocked {
		w.Header().Set("X-Credit-Overage", "blocked")
		http.Error(w, "insufficient prepaid credits; overage not allowed", http.StatusPaymentRequired)
		return
	}

	resp := usageIngestResponse{UsageRecord: record, Credit: &creditResult}
	if creditResult.Overage {
		w.Header().Set("X-Credit-Overage", "true")
	}
	writeJSON(w, http.StatusCreated, resp)
}

func setUsagePath(path string) {
	usageStore.path = path
}

func resetUsageForTests() {
	_ = saveJSONFile(usageStore.path, usageData{})
}
