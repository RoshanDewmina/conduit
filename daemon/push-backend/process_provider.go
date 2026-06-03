package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// processProvider runs the agent-runner binary as a local process.
// Enabled by setting CONDUIT_LOCAL_RUNNER=1. The runner binary path
// defaults to "agent-runner" (must be in PATH) or CONDUIT_RUNNER_PATH.
type processProvider struct{}

func (p processProvider) Launch(agent *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	runnerPath := os.Getenv("CONDUIT_RUNNER_PATH")
	if runnerPath == "" {
		runnerPath = "agent-runner"
	}
	cmd := exec.Command(runnerPath)
	cmd.Env = append(os.Environ(),
		"CONDUIT_RUN_ID="+env.RunID,
		"CONDUIT_RUNNER_TOKEN="+env.RunnerToken,
		"CONDUIT_CONTROL_PLANE_URL="+env.ControlPlaneURL,
		"CONDUIT_COMMAND="+env.Command,
		"CONDUIT_MODEL="+env.Model,
		"CONDUIT_AGENT_ID="+env.AgentID,
	)
	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start local runner: %w", err)
	}
	return fmt.Sprintf("pid:%d", cmd.Process.Pid), nil
}

func (p processProvider) Cancel(handle string) error {
	// Best-effort: find the process and kill it
	if strings.HasPrefix(handle, "pid:") {
		pidStr := strings.TrimPrefix(handle, "pid:")
		proc, err := os.FindProcess(parseIntOr(pidStr, 0))
		if err == nil && proc != nil {
			_ = proc.Signal(os.Interrupt)
		}
	}
	return nil
}

func parseIntOr(s string, def int) int {
	var n int
	if _, err := fmt.Sscan(s, &n); err != nil {
		return def
	}
	return n
}
