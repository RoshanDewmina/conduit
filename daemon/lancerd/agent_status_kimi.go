package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

type kimiUsage struct {
	TotalTokens  int     `json:"total_tokens"`
	TotalCostUSD float64 `json:"total_cost_usd"`
}

func collectKimiStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "kimi"}
	kimiDir := filepath.Join(home, ".kimi-code")

	sessionIndex := filepath.Join(kimiDir, "session_index.jsonl")
	if entries, err := countJSONLLines(sessionIndex); err == nil {
		status.SessionCount = entries
	}

	if data, err := os.ReadFile(filepath.Join(kimiDir, "credentials")); err == nil {
		if strings.TrimSpace(string(data)) != "" {
			loggedIn := true
			status.LoggedIn = &loggedIn
		}
	}

	if data, err := os.ReadFile(filepath.Join(kimiDir, "config.toml")); err == nil {
		content := string(data)
		for _, line := range strings.Split(content, "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "model") || strings.HasPrefix(line, "default_model") {
				parts := strings.SplitN(line, "=", 2)
				if len(parts) == 2 {
					model := strings.Trim(strings.TrimSpace(parts[1]), "\"")
					status.Model = &model
					break
				}
			}
		}
	}

	count := countRunningProcesses("kimi", []string{"kimi"})
	status.RunningCount = count

	return status
}

func countJSONLLines(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	count := 0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var obj map[string]interface{}
		if json.Unmarshal([]byte(line), &obj) == nil {
			count++
		}
	}
	return count, nil
}
