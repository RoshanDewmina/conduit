package main

import (
	"os"
	"path/filepath"
	"strings"
)

func collectCopilotStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "copilot"}
	copilotDir := filepath.Join(home, ".copilot")

	sessionsDir := filepath.Join(copilotDir, "sessions")
	if entries, err := os.ReadDir(sessionsDir); err == nil {
		count := 0
		for _, e := range entries {
			if e.IsDir() || strings.HasSuffix(e.Name(), ".jsonl") || strings.HasSuffix(e.Name(), ".json") {
				count++
			}
		}
		status.SessionCount = count
	}

	if data, err := os.ReadFile(filepath.Join(copilotDir, "auth.json")); err == nil {
		if strings.TrimSpace(string(data)) != "" && strings.Contains(string(data), "token") {
			loggedIn := true
			status.LoggedIn = &loggedIn
		}
	}

	count := countRunningProcesses("copilot", []string{"copilot"})
	status.RunningCount = count

	return status
}
