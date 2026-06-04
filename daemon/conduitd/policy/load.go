package policy

import (
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

const (
	GlobalPolicyFile = "policy.yaml"
	AlwaysPolicyFile = "policy-always.yaml"
)

// ConduitDir returns ~/.conduit (or $home/.conduit).
func ConduitDir(home string) string {
	return filepath.Join(home, ".conduit")
}

func GlobalPolicyPath(home string) string {
	return filepath.Join(ConduitDir(home), GlobalPolicyFile)
}

func AlwaysPolicyPath(home string) string {
	return filepath.Join(ConduitDir(home), AlwaysPolicyFile)
}

func RepoPolicyPath(cwd string) string {
	return filepath.Join(cwd, ".conduit", GlobalPolicyFile)
}

// LoadFile reads one YAML policy document.
func LoadFile(path string) (Document, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Document{}, err
	}
	var doc Document
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return Document{}, err
	}
	if doc.Default == "" {
		doc.Default = string(EffectAsk)
	}
	return doc, nil
}

// SaveFile writes a policy document (0600).
func SaveFile(path string, doc Document) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := yaml.Marshal(doc)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

// LoadRepoPolicy walks up from cwd for .conduit/policy.yaml.
func LoadRepoPolicy(cwd string) (Document, string, error) {
	dir, err := filepath.Abs(cwd)
	if err != nil {
		dir = cwd
	}
	for {
		candidate := filepath.Join(dir, ".conduit", GlobalPolicyFile)
		if _, err := os.Stat(candidate); err == nil {
			doc, err := LoadFile(candidate)
			return doc, candidate, err
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return Document{}, "", os.ErrNotExist
}

// LoadAllForCWD loads repo policy (if any) and global/default for merged evaluation.
// policy-always.yaml is evaluated separately so explicit user allow rules win on match.
func LoadAllForCWD(cwd, home string) ([]Document, error) {
	var docs []Document
	if cwd != "" {
		if doc, _, err := LoadRepoPolicy(cwd); err == nil {
			docs = append(docs, doc)
		}
	}
	globalPath := GlobalPolicyPath(home)
	if doc, err := LoadFile(globalPath); err == nil {
		docs = append(docs, doc)
	} else if os.IsNotExist(err) {
		docs = append(docs, DefaultDocument())
	}
	return docs, nil
}

// AppendAllowRule appends an allow rule to ~/.conduit/policy-always.yaml (deduped).
func AppendAllowRule(home string, rule Rule) error {
	path := AlwaysPolicyPath(home)
	doc, err := LoadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			doc = Document{Default: string(EffectAllow)}
		} else {
			return err
		}
	}
	rule.Effect = string(EffectAllow)
	for _, existing := range doc.Rules {
		if existing.Agent == rule.Agent && existing.Tool == rule.Tool && existing.Match == rule.Match {
			return nil
		}
	}
	doc.Rules = append(doc.Rules, rule)
	return SaveFile(path, doc)
}

// MarshalYAML returns the YAML text for a document.
func MarshalYAML(doc Document) (string, error) {
	data, err := yaml.Marshal(doc)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
