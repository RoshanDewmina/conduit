package policy

import (
	"encoding/json"
	"os"
	"strings"
)

type alwaysRuleJSON struct {
	Agent  string `json:"agent"`
	Tool   string `json:"tool"`
	Prefix string `json:"prefix"`
}

// MigrateAlwaysRulesJSON converts legacy always-rules.json into policy-always.yaml.
func MigrateAlwaysRulesJSON(alwaysJSONPath, alwaysYAMLPath string) error {
	data, err := os.ReadFile(alwaysJSONPath)
	if err != nil {
		return err
	}
	var legacy []alwaysRuleJSON
	if err := json.Unmarshal(data, &legacy); err != nil {
		return err
	}

	doc, err := LoadFile(alwaysYAMLPath)
	if err != nil {
		if os.IsNotExist(err) {
			doc = Document{Default: string(EffectAllow)}
		} else {
			return err
		}
	}

	for _, r := range legacy {
		if r.Prefix == "" {
			continue
		}
		match := strings.TrimSpace(r.Prefix)
		if match != "" && !strings.HasSuffix(match, "*") {
			match += "*"
		}
		doc.Rules = append(doc.Rules, Rule{
			ID:     "migrated-" + r.Agent + "-" + r.Tool,
			Effect: string(EffectAllow),
			Agent:  r.Agent,
			Tool:   r.Tool,
			Match:  match,
		})
	}
	return SaveFile(alwaysYAMLPath, doc)
}

// AllowRuleFromPrefix builds an allow rule for approve-always decisions.
func AllowRuleFromPrefix(agent, tool, commandPrefix string) Rule {
	match := strings.TrimSpace(commandPrefix)
	if match != "" && !strings.HasSuffix(match, "*") {
		match += "*"
	}
	return Rule{
		Effect: string(EffectAllow),
		Agent:  agent,
		Tool:   tool,
		Match:  match,
	}
}
