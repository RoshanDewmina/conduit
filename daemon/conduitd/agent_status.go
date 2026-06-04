package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type agentStatusParams struct {
	HomeDir string `json:"homeDir,omitempty"`
}

type AgentVendorStatus struct {
	Agent        string   `json:"agent"`
	LoggedIn     *bool    `json:"loggedIn,omitempty"`
	Model        *string  `json:"model,omitempty"`
	SessionCount int      `json:"sessionCount"`
	RunningCount int      `json:"runningCount,omitempty"`
	UsageUSD     *float64 `json:"usageUSD,omitempty"`
	UsagePeriod  *string  `json:"usagePeriod,omitempty"`
}

type AgentStatusResult struct {
	Agents      []AgentVendorStatus `json:"agents"`
	CollectedAt string              `json:"collectedAt"`
}

func collectAgentStatus(home string) AgentStatusResult {
	if home == "" {
		home = agentHomeDir()
	}
	out := []AgentVendorStatus{collectClaudeStatus(home), collectCodexStatus(home), collectOpencodeStatus(home)}
	return AgentStatusResult{Agents: out, CollectedAt: time.Now().UTC().Format(time.RFC3339)}
}

func agentHomeDir() string {
	if v := os.Getenv("CONDUIT_AGENT_HOME"); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return home
}

func ptrBool(v bool) *bool       { return &v }
func ptrString(v string) *string { if v == "" { return nil }; return &v }
func ptrFloat(v float64) *float64 { return &v }
func usagePeriodToday() *string { s := "today"; return &s }

func fileExists(path string) bool { _, err := os.Stat(path); return err == nil }

func countJSONLFiles(root string) int {
	if root == "" { return 0 }
	n := 0
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() { return nil }
		if filepath.Ext(path) == ".jsonl" { n++ }
		return nil
	})
	return n
}

func readJSONFile(path string, dest any) bool {
	data, err := os.ReadFile(path)
	if err != nil { return false }
	return json.Unmarshal(data, dest) == nil
}
