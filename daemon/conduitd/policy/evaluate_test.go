package policy

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func req(agent, kind, command, cwd, tool string) Request {
	return Request{
		Agent:   agent,
		Kind:    kind,
		Command: command,
		CWD:     cwd,
		Tool:    tool,
		Risk:    -1,
	}
}

func TestEvaluateDenyBeatsAllow(t *testing.T) {
	doc := Document{
		Rules: []Rule{
			{Effect: "allow", Agent: "claudeCode"},
			{Effect: "deny", Match: "rm -rf*"},
		},
	}
	res := Evaluate(doc, req("claudeCode", "command", "rm -rf /tmp", "/repo", "Bash"))
	if res.Effect != EffectDeny {
		t.Fatalf("deny should beat allow, got %v (%s)", res.Effect, res.MatchedRule)
	}
}

func TestEvaluateAskBeatsAllow(t *testing.T) {
	doc := Document{
		Rules: []Rule{
			{Effect: "allow", Kind: "command"},
			{Effect: "ask", Kind: "patch"},
		},
	}
	res := Evaluate(doc, req("claudeCode", "patch", "diff", "/repo", ""))
	if res.Effect != EffectAsk {
		t.Fatalf("ask should beat allow, got %v", res.Effect)
	}
}

func TestEvaluateFailClosedDefault(t *testing.T) {
	doc := Document{}
	res := Evaluate(doc, req("claudeCode", "fileWrite", "x", "/repo", ""))
	if res.Effect != EffectAsk || !res.FromDefault {
		t.Fatalf("empty doc must default to ask, got %v fromDefault=%v", res.Effect, res.FromDefault)
	}
}

func TestGlobMatchCommand(t *testing.T) {
	doc := Document{
		Rules: []Rule{{Effect: "deny", Match: "npm test*"}},
	}
	res := Evaluate(doc, req("claudeCode", "command", "npm test -- --filter a", "/repo", ""))
	if res.Effect != EffectDeny {
		t.Fatal("npm test* should deny")
	}
}

func TestMigrateAlwaysRulesJSON(t *testing.T) {
	dir := t.TempDir()
	jsonPath := filepath.Join(dir, "always-rules.json")
	yamlPath := filepath.Join(dir, "policy-always.yaml")
	_ = os.WriteFile(jsonPath, []byte(`[{"agent":"codex","tool":"Bash","prefix":"make test"}]`), 0600)
	if err := MigrateAlwaysRulesJSON(jsonPath, yamlPath); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(yamlPath)
	if !strings.Contains(string(data), "make test") {
		t.Fatalf("missing migrated rule: %s", data)
	}
}

func TestAppendAllowRule(t *testing.T) {
	dir := t.TempDir()
	home := filepath.Dir(dir)
	_ = os.MkdirAll(filepath.Join(home, ".conduit"), 0700)
	// use dir as fake home by passing dir's parent... simpler: pass dir as home
	if err := os.MkdirAll(filepath.Join(dir, ".conduit"), 0700); err != nil {
		t.Fatal(err)
	}
	// AppendAllowRule uses home/.conduit — pass dir
	rule := AllowRuleFromPrefix("claudeCode", "Bash", "npm test")
	if err := AppendAllowRule(dir, rule); err != nil {
		t.Fatal(err)
	}
	doc, err := LoadFile(filepath.Join(dir, ".conduit", AlwaysPolicyFile))
	if err != nil {
		t.Fatal(err)
	}
	if len(doc.Rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(doc.Rules))
	}
}

func TestEvaluateDocumentsStrictest(t *testing.T) {
	docs := []Document{
		{Rules: []Rule{{Effect: "allow", Match: "echo*"}}},
		{Rules: []Rule{{Effect: "deny", Kind: "network"}}},
	}
	res := EvaluateDocuments(docs, req("claudeCode", "network", "curl x", "/repo", ""))
	if res.Effect != EffectDeny {
		t.Fatalf("deny across docs should win, got %v", res.Effect)
	}
}

func TestDefaultDocumentBehavior(t *testing.T) {
	doc := DefaultDocument()

	cases := []struct {
		name   string
		kind   string
		cmd    string
		want   Effect
	}{
		{"low command allow", "command", "ls -la", EffectAllow},
		{"medium command ask", "command", "npm install", EffectAsk},
		{"patch ask", "patch", "diff content", EffectAsk},
		{"critical command deny", "command", "rm -rf /", EffectDeny},
		{"credential deny", "credential", "export API_KEY=x", EffectDeny},
		{"network deny", "network", "curl https://example.com", EffectDeny},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := Evaluate(doc, req("claudeCode", tc.kind, tc.cmd, "/repo", ""))
			if res.Effect != tc.want {
				t.Fatalf("got %v (%s), want %v", res.Effect, res.MatchedRule, tc.want)
			}
		})
	}
}
