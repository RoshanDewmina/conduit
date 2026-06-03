package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// capturingProvider records the RunnerEnv it was launched with so tests can assert
// the dispatch path populated cloud-runner secrets (e.g. the OpenRouter key).
type capturingProvider struct {
	got chan RunnerEnv
}

func (p *capturingProvider) Launch(_ *Agent, _ *AgentRun, env RunnerEnv) (string, error) {
	select {
	case p.got <- env:
	default:
	}
	return "captured", nil
}

func (p *capturingProvider) Cancel(_ string) error { return nil }

func TestOpenRouterKeyPersistRoundTrip(t *testing.T) {
	setupTestStores(t)

	if got := openRouterKeyForCustomer("cus_absent"); got != "" {
		t.Fatalf("expected empty key for unknown customer, got %q", got)
	}
	persistOpenRouterKey("cus_a", "sk-or-aaa")
	persistOpenRouterKey("cus_b", "sk-or-bbb")
	if got := openRouterKeyForCustomer("cus_a"); got != "sk-or-aaa" {
		t.Fatalf("cus_a key = %q, want sk-or-aaa", got)
	}
	if got := openRouterKeyForCustomer("cus_b"); got != "sk-or-bbb" {
		t.Fatalf("cus_b key = %q, want sk-or-bbb", got)
	}
	// Empty inputs are no-ops (never persist a blank key).
	persistOpenRouterKey("cus_c", "")
	if got := openRouterKeyForCustomer("cus_c"); got != "" {
		t.Fatalf("blank key must not persist, got %q", got)
	}
}

// The dispatch path must inject the persisted per-customer OpenRouter key into the
// runner env — without it a cloud run launches with no OPENROUTER_API_KEY and the
// agent command fails auth.
func TestDispatchInjectsOpenRouterKey(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_or", "tok_or")
	tok := clientTokenFor(t, "cus_or")
	t.Setenv("CONTROL_PLANE_PUBLIC_URL", "http://control.test")
	persistOpenRouterKey("cus_or", "sk-or-test")

	cp := &capturingProvider{got: make(chan RunnerEnv, 1)}
	setProviderOverrideForTest(func(_ string) RuntimeProvider { return cp })
	t.Cleanup(func() { setProviderOverrideForTest(nil) })

	// Create a cloud agent.
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"OR Bot","runtime":"gcp_cloud_run"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	handleCreateAgent(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create agent: status=%d body=%s", rec.Code, rec.Body.String())
	}
	var agent Agent
	if err := json.Unmarshal(rec.Body.Bytes(), &agent); err != nil {
		t.Fatal(err)
	}

	// Create a run — fires dispatchRun in a goroutine, which calls the provider.
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/runs", bytes.NewBufferString(`{"agentId":"`+agent.ID+`","command":"claude"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	handleCreateRun(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create run: status=%d body=%s", rec.Code, rec.Body.String())
	}
	var run AgentRun
	if err := json.Unmarshal(rec.Body.Bytes(), &run); err != nil {
		t.Fatal(err)
	}

	select {
	case env := <-cp.got:
		if env.OpenRouterKey != "sk-or-test" {
			t.Fatalf("dispatch env OpenRouterKey = %q, want sk-or-test", env.OpenRouterKey)
		}
		if env.RunnerToken == "" {
			t.Fatal("dispatch env missing runner token")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("provider was not launched within 2s")
	}

	// dispatchRun keeps running after Launch returns (it persists status=running +
	// the provider handle). Wait for that final write so the detached goroutine is
	// done before t.Cleanup removes the TempDir — otherwise cleanup races the write.
	deadline := time.Now().Add(2 * time.Second)
	for {
		if status, _, ok := runControlSnapshot(run.ID); ok && status == "running" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("dispatchRun did not persist status=running within 2s")
		}
		time.Sleep(10 * time.Millisecond)
	}
}
