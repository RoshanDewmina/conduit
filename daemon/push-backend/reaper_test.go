package main

import (
	"sync"
	"testing"
	"time"
)

// recordingProvider records every handle passed to Cancel so tests can assert
// the reaper hard-terminated the right executions.
type recordingProvider struct {
	mu        sync.Mutex
	cancelled []string
}

func (p *recordingProvider) Launch(_ *Agent, _ *AgentRun, _ RunnerEnv) (string, error) {
	return "", nil
}

func (p *recordingProvider) Cancel(handle string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.cancelled = append(p.cancelled, handle)
	return nil
}

func (p *recordingProvider) didCancel(handle string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, h := range p.cancelled {
		if h == handle {
			return true
		}
	}
	return false
}

func seedRun(t *testing.T, run AgentRun) {
	t.Helper()
	controlPlane.mu.Lock()
	controlPlane.data.Runs = append(controlPlane.data.Runs, run)
	_ = persistControlPlane()
	controlPlane.mu.Unlock()
}

func getRunByID(t *testing.T, id string) AgentRun {
	t.Helper()
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, r := range controlPlane.data.Runs {
		if r.ID == id {
			return r
		}
	}
	t.Fatalf("run %s not found", id)
	return AgentRun{}
}

// A non-terminal cloud run older than the max duration must be marked failed and
// its underlying execution torn down (the crashed/hung-runner backstop).
func TestReaperTimesOutStuckRun(t *testing.T) {
	setupTestStores(t)
	rp := &recordingProvider{}
	providerOverrideForTest = func(_ string) RuntimeProvider { return rp }
	t.Cleanup(func() { providerOverrideForTest = nil })

	now := time.Now().UTC()
	seedRun(t, AgentRun{
		ID:             "run_stuck",
		AgentID:        "agent_x",
		Status:         "running",
		Runtime:        "gcp_cloud_run",
		ProviderHandle: "exec/stuck",
		StartedAt:      now.Add(-2 * time.Hour).Format(time.RFC3339),
		CreatedAt:      now.Add(-2 * time.Hour).Format(time.RFC3339),
	})

	reapRunsOnce(now) // default max duration is 60m; 2h-old run must trip it.

	got := getRunByID(t, "run_stuck")
	if got.Status != "failed" {
		t.Fatalf("expected stuck run to be failed, got %q", got.Status)
	}
	if got.ProviderHandle != "" {
		t.Fatalf("expected provider handle cleared after teardown, got %q", got.ProviderHandle)
	}
	if !rp.didCancel("exec/stuck") {
		t.Fatal("expected reaper to hard-cancel the stuck run's execution")
	}
}

// A terminal cloud run that still carries a handle (self-terminate never fired)
// must get a best-effort teardown so paid resources don't leak.
func TestReaperTearsDownTerminalRunWithHandle(t *testing.T) {
	setupTestStores(t)
	rp := &recordingProvider{}
	providerOverrideForTest = func(_ string) RuntimeProvider { return rp }
	t.Cleanup(func() { providerOverrideForTest = nil })

	now := time.Now().UTC()
	seedRun(t, AgentRun{
		ID:             "run_done",
		AgentID:        "agent_y",
		Status:         "succeeded",
		Runtime:        "lightsail",
		ProviderHandle: "conduit-run-run_done",
		StartedAt:      now.Add(-5 * time.Minute).Format(time.RFC3339),
		CreatedAt:      now.Add(-5 * time.Minute).Format(time.RFC3339),
	})

	reapRunsOnce(now)

	got := getRunByID(t, "run_done")
	if got.Status != "succeeded" {
		t.Fatalf("terminal status must be preserved, got %q", got.Status)
	}
	if got.ProviderHandle != "" {
		t.Fatalf("expected handle cleared after teardown, got %q", got.ProviderHandle)
	}
	if !rp.didCancel("conduit-run-run_done") {
		t.Fatal("expected reaper to tear down the leaked instance")
	}
}

// ssh-host runs execute on-device and must never be reaped server-side, even when
// old and non-terminal.
func TestReaperSkipsSSHHostRuns(t *testing.T) {
	setupTestStores(t)
	rp := &recordingProvider{}
	providerOverrideForTest = func(_ string) RuntimeProvider { return rp }
	t.Cleanup(func() { providerOverrideForTest = nil })

	now := time.Now().UTC()
	seedRun(t, AgentRun{
		ID:        "run_ssh",
		AgentID:   "agent_z",
		Status:    "running",
		Runtime:   "ssh-host",
		StartedAt: now.Add(-3 * time.Hour).Format(time.RFC3339),
		CreatedAt: now.Add(-3 * time.Hour).Format(time.RFC3339),
	})

	reapRunsOnce(now)

	got := getRunByID(t, "run_ssh")
	if got.Status != "running" {
		t.Fatalf("ssh-host run must be left untouched, got %q", got.Status)
	}
	if len(rp.cancelled) != 0 {
		t.Fatalf("ssh-host run must not be cancelled, cancelled=%v", rp.cancelled)
	}
}
