package main

import (
	"encoding/json"
	"os"
	"strings"
	"time"
)

// RunnerEnv is the env contract handed to every runner, regardless of provider.
type RunnerEnv struct {
	RunID           string
	RunnerToken     string
	ControlPlaneURL string
	Command         string
	Model           string
	OpenRouterKey   string
	AgentID         string
}

// RuntimeProvider launches a single run's container/VM. Non-blocking beyond launch.
// Cancellation is cooperative — runner polls GET /runs/{id}/control.
type RuntimeProvider interface {
	Launch(agent *Agent, run *AgentRun, env RunnerEnv) (handle string, err error)
	Cancel(handle string) error
}

// providerOverrideForTest is set only in tests to inject a fake provider.
// In production code this is always nil.
var providerOverrideForTest func(runtime string) RuntimeProvider

// providerFor selects the provider for an agent's runtime.
// ssh-host returns nil (on-device path, never dispatched server-side).
func providerFor(runtime string) RuntimeProvider {
	if providerOverrideForTest != nil {
		return providerOverrideForTest(runtime)
	}
	if os.Getenv("CONDUIT_LOCAL_RUNNER") == "1" && normalizeRuntime(runtime) != "ssh-host" {
		return processProvider{}
	}
	switch normalizeRuntime(runtime) {
	case "gcp_cloud_run":
		return gcpCloudRunProvider{}
	case "lightsail":
		return lightsailProvider{}
	case "fly":
		return flyProvider{}
	default:
		return nil
	}
}

// dispatchRun is invoked AFTER a run is persisted. Mints a scoped runner token,
// builds the env, and launches via the provider. On failure marks the run failed
// with a log line (never leaves it stuck pending).
func dispatchRun(agent *Agent, run *AgentRun) {
	prov := providerFor(agent.Runtime)
	if prov == nil {
		return // ssh-host: executed on-device by the app, not here
	}
	baseURL := controlPlaneBaseURL()
	if baseURL == "" {
		failRun(run.ID, "CONTROL_PLANE_PUBLIC_URL is not set; cannot dispatch cloud run")
		return
	}
	token, err := mintRunToken(run.ID)
	if err != nil {
		failRun(run.ID, "failed to mint runner token: "+err.Error())
		return
	}
	env := RunnerEnv{
		RunID:           run.ID,
		RunnerToken:     token,
		ControlPlaneURL: baseURL,
		Command:         resolveAgentCommand(agent, run),
		Model:           agentConfigString(agent, "model"),
		AgentID:         agent.ID,
	}
	handle, err := prov.Launch(agent, run, env)
	if err != nil {
		failRun(run.ID, "failed to launch cloud runtime: "+err.Error())
		return
	}
	_ = handle
	updateRunFields(run.ID, func(r *AgentRun) {
		r.Status = "running"
	})
}

// failRun marks a run failed and appends an explanatory log line.
func failRun(runID, msg string) {
	_, _ = appendRunLogs(runID, []RunLogEntry{{Stream: "stderr", Text: msg}})
	updateRunFields(runID, func(r *AgentRun) {
		r.Status = "failed"
		if r.CompletedAt == "" {
			r.CompletedAt = nowRFC3339()
		}
	})
}

// controlPlaneBaseURL returns the public base URL for runner callbacks.
func controlPlaneBaseURL() string {
	return strings.TrimRight(strings.TrimSpace(os.Getenv("CONTROL_PLANE_PUBLIC_URL")), "/")
}

// resolveAgentCommand returns the command to run: run.Command > agent config "command" > "claude".
func resolveAgentCommand(agent *Agent, run *AgentRun) string {
	if run.Command != "" {
		return run.Command
	}
	if cmd := agentConfigString(agent, "command"); cmd != "" {
		return cmd
	}
	return "claude"
}

// agentConfigString extracts a string key from the agent's JSON Config.
func agentConfigString(agent *Agent, key string) string {
	if len(agent.Config) == 0 {
		return ""
	}
	var m map[string]any
	if err := json.Unmarshal(agent.Config, &m); err != nil {
		return ""
	}
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

// nowRFC3339 returns the current UTC time as RFC3339.
func nowRFC3339() string {
	return time.Now().UTC().Format(time.RFC3339)
}
