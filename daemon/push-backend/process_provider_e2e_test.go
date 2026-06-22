package main

import (
	"net/http"
	"net/http/httptest"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestProcessProviderRealRunnerE2E builds the real agent-runner binary and drives
// it through the processProvider against the actual control-plane log/status/control
// endpoints — no cloud, no mocks. This is the regression guard for the ARGV contract:
// the runner hard-requires LANCER_COMMAND_ARGV and exits without it, so a provider
// that sends LANCER_COMMAND would silently never produce logs or flip status.
func TestProcessProviderRealRunnerE2E(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("posix-only e2e")
	}
	setupTestStores(t)

	// Build the real runner binary from the sibling module.
	binPath := filepath.Join(t.TempDir(), "agent-runner")
	build := exec.Command("go", "build", "-o", binPath, ".")
	build.Dir = filepath.Join("..", "agent-runner")
	if out, err := build.CombinedOutput(); err != nil {
		t.Skipf("could not build agent-runner (skipping e2e): %v\n%s", err, out)
	}
	t.Setenv("LANCER_RUNNER_PATH", binPath)

	// Real control-plane endpoints the runner calls back into.
	mux := http.NewServeMux()
	registerRunLogRoutes(mux)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Seed a run + mint its scoped runner token (what dispatchRun would do).
	const runID = "run_e2e"
	seedRun(t, AgentRun{
		ID:        runID,
		AgentID:   "agent_e2e",
		Status:    "running",
		Runtime:   "gcp_cloud_run",
		StartedAt: time.Now().UTC().Format(time.RFC3339),
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	})
	token, err := mintRunToken(runID)
	if err != nil {
		t.Fatalf("mint token: %v", err)
	}

	// Launch the real runner via the process provider with a command that emits a
	// recognizable line and exits 0.
	_, err = processProvider{}.Launch(
		&Agent{ID: "agent_e2e"},
		&AgentRun{ID: runID},
		RunnerEnv{
			RunID:           runID,
			RunnerToken:     token,
			ControlPlaneURL: srv.URL,
			Command:         "echo lancer-e2e-marker",
			AgentID:         "agent_e2e",
		},
	)
	if err != nil {
		t.Fatalf("launch runner: %v", err)
	}

	// Poll until the runner streams the marker line AND patches the run terminal.
	deadline := time.Now().Add(15 * time.Second)
	var sawMarker bool
	var finalStatus string
	for time.Now().Before(deadline) {
		lines, _ := runLogsSince(runID, 0)
		for _, l := range lines {
			if strings.Contains(l.Text, "lancer-e2e-marker") {
				sawMarker = true
			}
		}
		if status, _, ok := runControlSnapshot(runID); ok && isTerminalRunStatus(status) {
			finalStatus = status
			break
		}
		time.Sleep(150 * time.Millisecond)
	}

	if !sawMarker {
		t.Fatal("runner never streamed the marker line — ARGV contract likely broken")
	}
	if finalStatus != "succeeded" {
		t.Fatalf("expected run to be patched succeeded, got %q", finalStatus)
	}
}
