package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// processProvider runs the agent-runner binary as a local process.
// Enabled by setting LANCER_LOCAL_RUNNER=1. The runner binary path
// defaults to "agent-runner" (must be in PATH) or LANCER_RUNNER_PATH.
type processProvider struct{}

func (p processProvider) Launch(agent *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	runnerPath := os.Getenv("LANCER_RUNNER_PATH")
	if runnerPath == "" {
		runnerPath = "agent-runner"
	}
	cmd := exec.Command(runnerPath)
	// The runner requires LANCER_COMMAND_ARGV (a JSON array) and exits if it is
	// missing — it never parses LANCER_COMMAND. Send the same ARGV form the cloud
	// providers use so the local e2e path matches production exactly.
	cmd.Env = append(os.Environ(),
		"LANCER_RUN_ID="+env.RunID,
		"LANCER_RUNNER_TOKEN="+env.RunnerToken,
		"LANCER_CONTROL_PLANE_URL="+env.ControlPlaneURL,
		"LANCER_COMMAND_ARGV="+buildCommandArgv(env.Command),
		"LANCER_MODEL="+env.Model,
		"LANCER_OPENROUTER_KEY="+env.OpenRouterKey,
		"LANCER_AGENT_ID="+env.AgentID,
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
