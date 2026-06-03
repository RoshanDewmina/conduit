package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// createAgentViaAPI POSTs an agent and returns it. GCP is unconfigured in tests
// (no GCP_PROJECT), so provisioning records a stub and teardown is a no-op — the
// delete path never reaches out to real GCP.
func createAgentViaAPI(t *testing.T, base, tok, runtime string) Agent {
	t.Helper()
	body := `{"name":"Del Bot","runtime":"` + runtime + `"}`
	req, _ := http.NewRequest(http.MethodPost, base+"/agents", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create agent: status=%d", resp.StatusCode)
	}
	var a Agent
	if err := json.NewDecoder(resp.Body).Decode(&a); err != nil {
		t.Fatal(err)
	}
	return a
}

func deleteAgentReq(t *testing.T, base, tok, agentID string) int {
	t.Helper()
	req, _ := http.NewRequest(http.MethodDelete, base+"/agents/"+agentID, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	return resp.StatusCode
}

func TestDeleteAgent(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_del", "del-token")
	tok := clientTokenFor(t, "cus_del")
	// A second, unrelated customer used to prove ownership isolation.
	seedActiveEntitlement(t, "cus_other", "other-token")
	otherTok := clientTokenFor(t, "cus_other")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)
	registerRunLogRoutes(mux)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	t.Run("happy path deletes and is then gone", func(t *testing.T) {
		agent := createAgentViaAPI(t, srv.URL, tok, "gcp_cloud_run")
		if code := deleteAgentReq(t, srv.URL, tok, agent.ID); code != http.StatusOK {
			t.Fatalf("delete: want 200, got %d", code)
		}
		// GET now 404s.
		req, _ := http.NewRequest(http.MethodGet, srv.URL+"/agents/"+agent.ID, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("get after delete: want 404, got %d", resp.StatusCode)
		}
		// Second delete is now 404 (idempotent at the record level).
		if code := deleteAgentReq(t, srv.URL, tok, agent.ID); code != http.StatusNotFound {
			t.Fatalf("double delete: want 404, got %d", code)
		}
	})

	t.Run("another customer's agent is not visible", func(t *testing.T) {
		agent := createAgentViaAPI(t, srv.URL, tok, "gcp_cloud_run")
		if code := deleteAgentReq(t, srv.URL, otherTok, agent.ID); code != http.StatusNotFound {
			t.Fatalf("cross-tenant delete: want 404, got %d", code)
		}
		// Owner can still delete it — it was untouched.
		if code := deleteAgentReq(t, srv.URL, tok, agent.ID); code != http.StatusOK {
			t.Fatalf("owner delete after cross-tenant attempt: want 200, got %d", code)
		}
	})

	t.Run("refuses while a non-terminal run exists", func(t *testing.T) {
		agent := createAgentViaAPI(t, srv.URL, tok, "gcp_cloud_run")
		// Seed a running run directly (bypass dispatch) so the guard has something to catch.
		seedRun(t, AgentRun{
			ID:         "run_active_del",
			AgentID:    agent.ID,
			CustomerID: "cus_del",
			Status:     "running",
		})
		if code := deleteAgentReq(t, srv.URL, tok, agent.ID); code != http.StatusConflict {
			t.Fatalf("delete with active run: want 409, got %d", code)
		}
		// Flip the run terminal; delete now succeeds.
		updateRunFields("run_active_del", func(r *AgentRun) { r.Status = "succeeded" })
		if code := deleteAgentReq(t, srv.URL, tok, agent.ID); code != http.StatusOK {
			t.Fatalf("delete after run terminal: want 200, got %d", code)
		}
	})
}
