package policy

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// SimulationResult is the JSON response for agent.policy.simulate.
type SimulationResult struct {
	GeneratedAt     string         `json:"generatedAt"`
	PeriodDays      int            `json:"periodDays"`
	TotalActions    int            `json:"totalActions"`
	AutoApproved    int            `json:"autoApproved"`
	Asked           int            `json:"asked"`
	Denied          int            `json:"denied"`
	RuleHits        []RuleHit      `json:"ruleHits"`
	RiskDistribution map[string]int `json:"riskDistribution"`
}

// RuleHit summarises how often a particular rule was the decisive match.
type RuleHit struct {
	RuleID         string   `json:"ruleID"`
	Effect         string   `json:"effect"`
	Count          int      `json:"count"`
	SampleCommands []string `json:"sampleCommands"`
}

// auditEntry mirrors the JSONL format in ~/.conduit/audit.log.
type auditEntry struct {
	Timestamp  string `json:"timestamp"`
	Action     string `json:"action"`
	Agent      string `json:"agent"`
	Kind       string `json:"kind"`
	Command    string `json:"command"`
	Effect     string `json:"effect"`
	Rule       string `json:"rule"`
	ApprovalID string `json:"approvalId"`
}

// Simulate replays historical audit entries against a proposed policy.
func Simulate(doc Document, entries []auditEntry, periodDays int) SimulationResult {
	result := SimulationResult{
		GeneratedAt:     time.Now().UTC().Format(time.RFC3339),
		PeriodDays:      periodDays,
		RiskDistribution: map[string]int{},
	}

	ruleCounts := map[string]*RuleHit{}
	ruleSamples := map[string][]string{}

	for _, e := range entries {
		if e.Action != "escalate" && e.Action != "auto-allow" && e.Action != "auto-deny" {
			continue
		}

		risk := ScoreRiskInt(e.Command, e.Kind)
		riskLbl := RiskLabel(risk)

		req := Request{
			Agent:   e.Agent,
			Kind:    e.Kind,
			Command: e.Command,
			Risk:    risk,
		}

		res := Evaluate(doc, req)

		result.TotalActions++
		result.RiskDistribution[riskLbl]++

		switch res.Effect {
		case EffectAllow:
			result.AutoApproved++
		case EffectAsk:
			result.Asked++
		case EffectDeny:
			result.Denied++
		}

		ruleID := res.MatchedRule
		if rh, ok := ruleCounts[ruleID]; ok {
			rh.Count++
			if len(ruleSamples[ruleID]) < 3 && e.Command != "" {
				ruleSamples[ruleID] = append(ruleSamples[ruleID], e.Command)
			}
		} else {
			ruleCounts[ruleID] = &RuleHit{
				RuleID: ruleID,
				Effect: string(res.Effect),
				Count:  1,
			}
			if e.Command != "" {
				ruleSamples[ruleID] = []string{e.Command}
			}
		}
	}

	for id, rh := range ruleCounts {
		rh.SampleCommands = ruleSamples[id]
		result.RuleHits = append(result.RuleHits, *rh)
	}

	// Sort by count descending.
	for i := 0; i < len(result.RuleHits); i++ {
		for j := i + 1; j < len(result.RuleHits); j++ {
			if result.RuleHits[j].Count > result.RuleHits[i].Count {
				result.RuleHits[i], result.RuleHits[j] = result.RuleHits[j], result.RuleHits[i]
			}
		}
	}

	return result
}

// LoadAuditEntries reads the last periodDays worth of audit entries from ~/.conduit/audit.log.
func LoadAuditEntries(home string, periodDays int) ([]auditEntry, error) {
	path := filepath.Join(home, ".conduit", "audit.log")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	cutoff := time.Now().UTC().AddDate(0, 0, -periodDays)
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")

	var entries []auditEntry
	for _, line := range lines {
		if line == "" {
			continue
		}
		var e auditEntry
		if json.Unmarshal([]byte(line), &e) != nil {
			continue
		}
		if e.Timestamp != "" {
			if t, err := time.Parse(time.RFC3339, e.Timestamp); err == nil {
				if t.Before(cutoff) {
					continue
				}
			}
		}
		entries = append(entries, e)
	}
	return entries, nil
}
