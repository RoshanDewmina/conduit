package policy

import (
	"path/filepath"
	"strings"
)

// globMatch matches pattern against value using path-style globs (* and **).
func globMatch(pattern, value string) bool {
	pattern = filepath.ToSlash(strings.TrimSpace(pattern))
	value = filepath.ToSlash(strings.TrimSpace(value))
	if pattern == "" {
		return true
	}
	if pattern == "*" || pattern == "**" {
		return true
	}
	ok, err := filepath.Match(pattern, value)
	if err == nil && ok {
		return true
	}
	if strings.Contains(pattern, "**") {
		parts := strings.Split(pattern, "**")
		if len(parts) == 2 {
			return strings.HasPrefix(value, parts[0]) && strings.HasSuffix(value, parts[1])
		}
	}
	return strings.HasSuffix(pattern, "*") && strings.HasPrefix(value, strings.TrimSuffix(pattern, "*"))
}

func ruleMatches(rule Rule, req Request, riskLabel string, paths []string) bool {
	if rule.Agent != "" && rule.Agent != "*" && rule.Agent != req.Agent {
		return false
	}
	tool := req.Tool
	if tool == "" {
		tool = req.Kind
	}
	if rule.Tool != "" && rule.Tool != "*" && rule.Tool != tool {
		return false
	}
	if rule.Kind != "" && rule.Kind != req.Kind {
		return false
	}
	if rule.CWD != "" && !globMatch(rule.CWD, req.CWD) {
		return false
	}
	if rule.MinRisk != "" && riskOrder(riskLabel) < riskOrder(rule.MinRisk) {
		return false
	}
	if rule.MaxRisk != "" && riskOrder(riskLabel) > riskOrder(rule.MaxRisk) {
		return false
	}
	if rule.Match != "" {
		if globMatch(rule.Match, req.Command) {
			return true
		}
		for _, p := range paths {
			if globMatch(rule.Match, p) {
				return true
			}
		}
		return false
	}
	return true
}

func riskOrder(label string) int {
	switch label {
	case "critical":
		return 3
	case "high":
		return 2
	case "medium":
		return 1
	default:
		return 0
	}
}

// ScoreRiskInt mirrors AgentKit risk bands (0=low … 3=critical).
func ScoreRiskInt(command, kind string) int {
	c := strings.ToLower(strings.TrimSpace(command))
	critical := []string{
		"rm -rf /", ":(){:|:&};:", "mkfs", "dd if=", "drop database",
		"kubectl delete ns ", "terraform destroy", "git push --force origin main",
	}
	for _, p := range critical {
		if strings.Contains(c, p) {
			return 3
		}
	}
	high := []string{
		"sudo ", "rm -rf", "chmod 777", "git push --force", "kubectl apply",
	}
	for _, p := range high {
		if strings.Contains(c, p) {
			return 2
		}
	}
	medium := []string{
		"npm install", "pip install", "docker run", "git commit", "git push",
	}
	for _, p := range medium {
		if strings.Contains(c, p) {
			return 1
		}
	}
	switch kind {
	case "credential", "network":
		return 2
	case "fileDelete", "patch", "fileWrite":
		return 1
	default:
		return 0
	}
}

func RiskLabel(r int) string {
	switch r {
	case 3:
		return "critical"
	case 2:
		return "high"
	case 1:
		return "medium"
	default:
		return "low"
	}
}

// ExtractPaths returns cwd-relative paths referenced by the invocation.
func ExtractPaths(command, cwd, toolInput string) []string {
	var out []string
	seen := map[string]bool{}
	add := func(p string) {
		p = strings.TrimSpace(p)
		if p == "" || seen[p] {
			return
		}
		seen[p] = true
		if filepath.IsAbs(p) && cwd != "" {
			if rel, err := filepath.Rel(cwd, p); err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
				p = rel
			}
		}
		out = append(out, filepath.ToSlash(p))
	}
	if command != "" {
		add(command)
	}
	if toolInput == "" {
		return out
	}
	for _, key := range []string{`"file_path"`, `"filePath"`, `"path"`, `"notebook_path"`, `"target_file"`} {
		if idx := strings.Index(toolInput, key); idx >= 0 {
			rest := toolInput[idx+len(key):]
			if q := strings.Index(rest, `"`); q >= 0 {
				rest = rest[q+1:]
				if end := strings.Index(rest, `"`); end > 0 {
					add(rest[:end])
				}
			}
		}
	}
	return out
}

func ruleLabel(rule Rule, index int) string {
	if rule.ID != "" {
		return rule.ID
	}
	parts := []string{string(ParseEffect(rule.Effect))}
	if rule.Agent != "" {
		parts = append(parts, "agent="+rule.Agent)
	}
	if rule.Kind != "" {
		parts = append(parts, "kind="+rule.Kind)
	}
	if rule.Match != "" {
		parts = append(parts, "match="+rule.Match)
	}
	return "rule#" + itoa(index) + ":" + strings.Join(parts, ",")
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
