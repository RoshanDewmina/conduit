package main

import (
	"encoding/json"
	"path/filepath"
)

func collectOpencodeStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "opencode"}
	root := filepath.Join(home, ".local", "share", "opencode")
	if !fileExists(root) { return status }
	if loggedIn := opencodeLoggedIn(root); loggedIn != nil { status.LoggedIn = loggedIn }
	if model := opencodeActiveModel(root); model != "" { status.Model = ptrString(model) }
	if usd, period, ok := opencodeUsageUSD(root); ok {
		status.UsageUSD = ptrFloat(usd)
		status.UsagePeriod = period
	}
	return status
}

func opencodeLoggedIn(root string) *bool {
	var doc map[string]json.RawMessage
	if readJSONFile(filepath.Join(root, "config.json"), &doc) && len(doc) > 0 { return ptrBool(true) }
	return ptrBool(false)
}

func opencodeActiveModel(root string) string {
	var cfg struct { Model string `json:"model"` }
	if readJSONFile(filepath.Join(root, "config.json"), &cfg) { return cfg.Model }
	return ""
}

func opencodeUsageUSD(root string) (float64, *string, bool) {
	var usage struct { CostUSD float64 `json:"cost_usd"` }
	if readJSONFile(filepath.Join(root, "usage.json"), &usage) && usage.CostUSD > 0 {
		return usage.CostUSD, usagePeriodToday(), true
	}
	return 0, nil, false
}
