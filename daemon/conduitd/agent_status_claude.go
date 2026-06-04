package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

func collectClaudeStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "claudeCode"}
	claudeDir := filepath.Join(home, ".claude")
	projectsDir := filepath.Join(claudeDir, "projects")
	status.SessionCount = countClaudeSessionFiles(projectsDir)
	if loggedIn := claudeLoggedIn(claudeDir); loggedIn != nil { status.LoggedIn = loggedIn }
	if model := claudeActiveModel(claudeDir); model != "" { status.Model = ptrString(model) }
	if usd, period, ok := claudeUsageUSD(claudeDir); ok {
		status.UsageUSD = ptrFloat(usd)
		status.UsagePeriod = period
	}
	return status
}

func countClaudeSessionFiles(projectsDir string) int {
	if !fileExists(projectsDir) { return 0 }
	n := 0
	entries, _ := os.ReadDir(projectsDir)
	for _, ent := range entries {
		if !ent.IsDir() { continue }
		sessions, _ := os.ReadDir(filepath.Join(projectsDir, ent.Name()))
		for _, s := range sessions {
			if !s.IsDir() && strings.HasSuffix(s.Name(), ".jsonl") { n++ }
		}
	}
	return n
}

func claudeLoggedIn(claudeDir string) *bool {
	if fileExists(filepath.Join(claudeDir, ".credentials.json")) {
		var cred map[string]json.RawMessage
		if readJSONFile(filepath.Join(claudeDir, ".credentials.json"), &cred) && len(cred) > 0 {
			return ptrBool(true)
		}
	}
	if fileExists(claudeDir) { return ptrBool(false) }
	return nil
}

func claudeActiveModel(claudeDir string) string {
	var settings struct { Model string `json:"model"` }
	if readJSONFile(filepath.Join(claudeDir, "settings.json"), &settings) { return settings.Model }
	return ""
}

func claudeUsageUSD(claudeDir string) (float64, *string, bool) {
	return parseStatuslineCostUSD(filepath.Join(claudeDir, "statusline.jsonl"))
}

func parseStatuslineCostUSD(path string) (float64, *string, bool) {
	if !fileExists(path) { return 0, nil, false }
	f, err := os.Open(path)
	if err != nil { return 0, nil, false }
	defer f.Close()
	var last *float64
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var row map[string]json.RawMessage
		if json.Unmarshal(sc.Bytes(), &row) != nil { continue }
		for _, key := range []string{"cost_usd", "costUSD", "total_cost_usd", "totalCostUSD"} {
			if raw, ok := row[key]; ok {
				var v float64
				if json.Unmarshal(raw, &v) == nil && v >= 0 { last = &v }
			}
		}
	}
	if last == nil { return 0, nil, false }
	return *last, usagePeriodToday(), true
}
