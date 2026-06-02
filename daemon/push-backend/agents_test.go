package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAgentAndRunHandlers(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_agent", "agent-token")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)

	createBody := `{
		"customerId":"cus_agent",
		"appAccountToken":"agent-token",
		"name":"Deploy Bot",
		"runtime":"ssh-host"
	}`
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(createBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create agent status=%d body=%s", rec.Code, rec.Body.String())
	}

	var agent Agent
	if err := json.Unmarshal(rec.Body.Bytes(), &agent); err != nil {
		t.Fatal(err)
	}
	if agent.ID == "" || agent.OpenRouterKeyHash == "" {
		t.Fatalf("unexpected agent: %+v", agent)
	}

	req = httptest.NewRequest(http.MethodGet, "/agents?customerId=cus_agent", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list agents status=%d", rec.Code)
	}

	runBody := `{"agentId":"` + agent.ID + `","command":"echo hello"}`
	req = httptest.NewRequest(http.MethodPost, "/runs", bytes.NewBufferString(runBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Customer-Id", "cus_agent")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create run status=%d body=%s", rec.Code, rec.Body.String())
	}

	var run AgentRun
	if err := json.Unmarshal(rec.Body.Bytes(), &run); err != nil {
		t.Fatal(err)
	}

	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID+"?customerId=cus_agent", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("get run status=%d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/runs?agentId="+agent.ID+"&customerId=cus_agent", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list runs status=%d", rec.Code)
	}
}

func TestHostedAPIRequiresEntitlement(t *testing.T) {
	setupTestStores(t)

	mux := http.NewServeMux()
	registerAgentRoutes(mux)

	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"x","customerId":"cus_none"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestUsageIngest(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_usage", "usage-token")

	mux := http.NewServeMux()
	registerUsageRoutes(mux)

	body := `{"customerId":"cus_usage","model":"anthropic/claude-3.5-sonnet","tokensIn":100,"tokensOut":50,"cost":0.012}`
	req := httptest.NewRequest(http.MethodPost, "/usage", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("usage ingest status=%d body=%s", rec.Code, rec.Body.String())
	}

	var record UsageRecord
	if err := json.Unmarshal(rec.Body.Bytes(), &record); err != nil {
		t.Fatal(err)
	}
	if record.CustomerID != "cus_usage" || record.Cost != 0.012 {
		t.Fatalf("unexpected usage record: %+v", record)
	}
}
