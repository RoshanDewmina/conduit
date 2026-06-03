package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// fakeProvider is a RuntimeProvider that simulates a well-behaved cloud runner:
// it fires a goroutine that POSTs log lines then PATCHes the run to succeeded.
type fakeProvider struct {
	serverURL string
}

func (p *fakeProvider) Launch(_ *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	go func() {
		// Give the dispatch goroutine time to write status=running before we call back.
		time.Sleep(20 * time.Millisecond)

		client := &http.Client{Timeout: 5 * time.Second}
		authHeader := "Bearer " + env.RunnerToken

		// POST log lines
		logBody := `{"lines":[{"stream":"stdout","text":"fake runner started"},{"stream":"stdout","text":"fake runner done"}]}`
		req, _ := http.NewRequest(http.MethodPost, env.ControlPlaneURL+"/runs/"+env.RunID+"/logs", bytes.NewBufferString(logBody))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", authHeader)
		resp, err := client.Do(req)
		if err != nil {
			return
		}
		resp.Body.Close()

		// PATCH run to succeeded
		exitCode := 0
		patchPayload, _ := json.Marshal(map[string]any{
			"status":      "succeeded",
			"exitCode":    exitCode,
			"completedAt": time.Now().UTC().Format(time.RFC3339),
		})
		req, _ = http.NewRequest(http.MethodPatch, env.ControlPlaneURL+"/runs/"+env.RunID, bytes.NewReader(patchPayload))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", authHeader)
		resp, err = client.Do(req)
		if err != nil {
			return
		}
		resp.Body.Close()
	}()
	return fmt.Sprintf("fake:%s", run.ID), nil
}

func (p *fakeProvider) Cancel(_ string) error { return nil }

func TestDispatchRunEndToEnd(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_dispatch", "dispatch-token")
	tok := clientTokenFor(t, "cus_dispatch")

	// Build the full mux with all required routes.
	mux := http.NewServeMux()
	registerAgentRoutes(mux)
	registerRunLogRoutes(mux)

	// Start a real HTTP test server so the fake provider can call back over HTTP.
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Set the control plane URL and wire up the fake provider.
	t.Setenv("CONTROL_PLANE_PUBLIC_URL", srv.URL)
	fp := &fakeProvider{serverURL: srv.URL}
	providerOverrideForTest = func(_ string) RuntimeProvider { return fp }
	t.Cleanup(func() { providerOverrideForTest = nil })

	// Create an agent with a cloud runtime.
	agentBody := `{"name":"Dispatch Bot","runtime":"gcp_cloud_run"}`
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/agents", bytes.NewBufferString(agentBody))
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
	var agent Agent
	if err := json.NewDecoder(resp.Body).Decode(&agent); err != nil {
		t.Fatal(err)
	}

	// Create a run — this triggers dispatchRun in a goroutine.
	runBody := fmt.Sprintf(`{"agentId":"%s","command":"echo hello"}`, agent.ID)
	req, _ = http.NewRequest(http.MethodPost, srv.URL+"/runs", bytes.NewBufferString(runBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create run: status=%d", resp.StatusCode)
	}
	var run AgentRun
	if err := json.NewDecoder(resp.Body).Decode(&run); err != nil {
		t.Fatal(err)
	}
	if run.ID == "" {
		t.Fatal("run has no ID")
	}

	// Poll GET /runs/{id} until status == succeeded or 2 s elapses.
	deadline := time.Now().Add(2 * time.Second)
	var finalRun AgentRun
	for time.Now().Before(deadline) {
		req, _ = http.NewRequest(http.MethodGet, srv.URL+"/runs/"+run.ID, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err = http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		var r AgentRun
		if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
			resp.Body.Close()
			t.Fatal(err)
		}
		resp.Body.Close()
		if r.Status == "succeeded" || r.Status == "failed" {
			finalRun = r
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	if finalRun.Status != "succeeded" {
		t.Fatalf("run did not reach succeeded within 2s; final status=%q", finalRun.Status)
	}
	if finalRun.CompletedAt == "" {
		t.Fatal("expected completedAt to be set on succeeded run")
	}

	// Verify log lines were posted by the fake runner.
	req, _ = http.NewRequest(http.MethodGet, srv.URL+"/runs/"+run.ID+"/logs?since=0", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var logsResp struct {
		Lines     []RunLogEntry `json:"lines"`
		NextSince int           `json:"nextSince"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&logsResp); err != nil {
		t.Fatal(err)
	}
	if len(logsResp.Lines) < 2 {
		t.Fatalf("expected at least 2 log lines from fake runner, got %d: %+v", len(logsResp.Lines), logsResp.Lines)
	}
	foundStarted, foundDone := false, false
	for _, l := range logsResp.Lines {
		if l.Text == "fake runner started" {
			foundStarted = true
		}
		if l.Text == "fake runner done" {
			foundDone = true
		}
	}
	if !foundStarted || !foundDone {
		t.Fatalf("missing expected log lines; got: %+v", logsResp.Lines)
	}
}
