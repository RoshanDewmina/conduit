package main

import (
	"encoding/json"
	"path/filepath"
)

func collectOpencodeStatus(home string) AgentVendorStatus {
	status := AgentVendorStatus{Agent: "opencode"}
	root := filepath.Join(home, ".config", "opencode")
	if !fileExists(root) { return status }
	if loggedIn := opencodeLoggedIn(root); loggedIn != nil { status.LoggedIn = loggedIn }
	if model := opencodeActiveModel(root); model != "" { status.Model = ptrString(model) }
	if usd, period, ok := opencodeUsageUSD(home); ok {
		status.UsageUSD = ptrFloat(usd)
		status.UsagePeriod = period
	}
	return status
}

func opencodeLoggedIn(root string) *bool {
	var doc map[string]json.RawMessage
	if readJSONFile(filepath.Join(root, "opencode.json"), &doc) && len(doc) > 0 { return ptrBool(true) }
	return ptrBool(false)
}

func opencodeActiveModel(root string) string {
	var cfg struct { Model string `json:"model"` }
	if readJSONFile(filepath.Join(root, "opencode.json"), &cfg) { return cfg.Model }
	return ""
}

func opencodeUsageUSD(home string) (float64, *string, bool) {
	dbPath := filepath.Join(home, ".local", "share", "opencode", "opencode.db")
	if !fileExists(dbPath) { return 0, nil, false }
	return 0, nil, false
}
