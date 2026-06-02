package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// clientTokenFor retrieves the server-issued bearer token for a seeded customer.
func clientTokenFor(t *testing.T, customerID string) string {
	t.Helper()
	ent, ok := getEntitlementStore().GetByCustomerID(customerID)
	if !ok {
		t.Fatalf("no entitlement found for %s", customerID)
	}
	if ent.ClientToken == "" {
		t.Fatalf("entitlement for %s has no ClientToken", customerID)
	}
	return ent.ClientToken
}

func bearerHeader(token string) string {
	return "Bearer " + token
}

func TestAgentAndRunHandlers(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_agent", "agent-token")
	tok := clientTokenFor(t, "cus_agent")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)

	// Create agent — identity comes from bearer token, not request body.
	createBody := `{"name":"Deploy Bot","runtime":"ssh-host"}`
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(createBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
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

	// List agents.
	req = httptest.NewRequest(http.MethodGet, "/agents", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list agents status=%d", rec.Code)
	}

	// Get agent.
	req = httptest.NewRequest(http.MethodGet, "/agents/"+agent.ID, nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("get agent status=%d", rec.Code)
	}

	// Create run.
	runBody := `{"agentId":"` + agent.ID + `","command":"echo hello"}`
	req = httptest.NewRequest(http.MethodPost, "/runs", bytes.NewBufferString(runBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create run status=%d body=%s", rec.Code, rec.Body.String())
	}

	var run AgentRun
	if err := json.Unmarshal(rec.Body.Bytes(), &run); err != nil {
		t.Fatal(err)
	}

	// Get run.
	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID, nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("get run status=%d", rec.Code)
	}

	// List runs.
	req = httptest.NewRequest(http.MethodGet, "/runs?agentId="+agent.ID, nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list runs status=%d", rec.Code)
	}
}

func TestHostedAPIRequiresBearer(t *testing.T) {
	setupTestStores(t)

	mux := http.NewServeMux()
	registerAgentRoutes(mux)

	// No Authorization header → 401.
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"x"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}

	// Invalid bearer token → 401.
	req = httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"x"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer invalid-token-that-does-not-exist")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for bad token, got %d", rec.Code)
	}
}

func TestUsageIngest(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_usage", "usage-token")
	tok := clientTokenFor(t, "cus_usage")

	mux := http.NewServeMux()
	registerUsageRoutes(mux)

	body := `{"model":"anthropic/claude-3.5-sonnet","tokensIn":100,"tokensOut":50,"cost":0.012}`
	req := httptest.NewRequest(http.MethodPost, "/usage", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("usage ingest status=%d body=%s", rec.Code, rec.Body.String())
	}

	var resp usageIngestResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.CustomerID != "cus_usage" || resp.Cost != 0.012 {
		t.Fatalf("unexpected usage record: %+v", resp)
	}
}
