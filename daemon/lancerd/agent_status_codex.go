package main

import (
	"encoding/json"
	"path/filepath"
)

func collectCodexStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "codex"}
	codexDir := filepath.Join(home, ".codex")
	status.SessionCount = countJSONLFiles(filepath.Join(codexDir, "sessions"))
	if loggedIn := codexLoggedIn(codexDir); loggedIn != nil { status.LoggedIn = loggedIn }
	if usd, period, ok := codexUsageUSD(codexDir); ok {
		status.UsageUSD = ptrFloat(usd)
		status.UsagePeriod = period
	}
	return status
}

func codexLoggedIn(codexDir string) *bool {
	for _, name := range []string{"auth.json", "credentials.json"} {
		path := filepath.Join(codexDir, name)
		if fileExists(path) {
			var doc map[string]json.RawMessage
			if readJSONFile(path, &doc) && len(doc) > 0 { return ptrBool(true) }
		}
	}
	if fileExists(codexDir) { return ptrBool(false) }
	return nil
}

func codexUsageUSD(codexDir string) (float64, *string, bool) {
	var usage struct {
		TodayUSD float64 `json:"today_usd"`
		CostUSD  float64 `json:"cost_usd"`
	}
	if readJSONFile(filepath.Join(codexDir, "usage.json"), &usage) {
		if usage.TodayUSD > 0 { return usage.TodayUSD, usagePeriodToday(), true }
		if usage.CostUSD > 0 { return usage.CostUSD, usagePeriodToday(), true }
	}
	return 0, nil, false
}
