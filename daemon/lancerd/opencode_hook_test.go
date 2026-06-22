package main

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"lancer/lancerd/policy"
)

func TestNormalizeAgentSourceOpencode(t *testing.T) {
	cases := map[string]string{
		"opencode":     "opencode",
		"OpenCode":     "opencode",
		"open-code":    "opencode",
		"open_code":    "opencode",
		"sst-opencode": "opencode",
		"claude":       "claudeCode",
		"claude-code":  "claudeCode",
	}
	for in, want := range cases {
		if got := normalizeAgentSource(in); got != want {
			t.Errorf("normalizeAgentSource(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestNormalizeKindOpencodeTools(t *testing.T) {
	if got := normalizeKind("edit"); got != "patch" {
		t.Errorf("edit -> %q, want patch", got)
	}
	if got := normalizeKind("bash"); got != "command" {
		t.Errorf("bash -> %q, want command", got)
	}
}

func TestOpencodeFixtureRoundTripToInboxNotification(t *testing.T) {
	fixture := filepath.Join("testdata", "opencode", "pretooluse-bash.json")
	payload, err := loadOpencodeFixture(fixture)
	if err != nil {
		t.Fatal(err)
	}

	event := approvalEventFromOpencodeFixture(payload)
	if event.Agent != "opencode" {
		t.Fatalf("agent = %q", event.Agent)
	}
	if event.Kind != "command" {
		t.Fatalf("kind = %q", event.Kind)
	}
	if event.Command != "npm test" {
		t.Fatalf("command = %q", event.Command)
	}
	if event.ToolName != "Bash" {
		t.Fatalf("toolName = %q", event.ToolName)
	}
	if event.SessionID != "ses_opencode_fixture_01" {
		t.Fatalf("sessionID = %q", event.SessionID)
	}

	frame, err := marshalPendingNotification(event)
	if err != nil {
		t.Fatal(err)
	}

	var envelope struct {
		Method string                 `json:"method"`
		Params map[string]interface{} `json:"params"`
	}
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.Method != "agent.approval.pending" {
		t.Fatalf("method = %q", envelope.Method)
	}
	if envelope.Params["agent"] != "opencode" {
		t.Fatalf("params.agent = %v", envelope.Params["agent"])
	}
	if envelope.Params["agentSessionID"] != "ses_opencode_fixture_01" {
		t.Fatalf("params.agentSessionID = %v", envelope.Params["agentSessionID"])
	}
	if envelope.Params["toolName"] != "Bash" {
		t.Fatalf("params.toolName = %v", envelope.Params["toolName"])
	}
}

func TestAlwaysRuleMatchesOpencodeAgent(t *testing.T) {
	home := t.TempDir()
	engine := newPolicyEngine(home)
	event := ApprovalEvent{
		ApprovalID: "id-1",
		Agent:      "opencode",
		Kind:       "command",
		Command:    "npm test",
		CWD:        "/repo",
		Risk:       0,
		ToolName:   "Bash",
	}
	if err := engine.appendAllowAlways(event); err != nil {
		t.Fatal(err)
	}
	res := engine.evaluate(event)
	if res.Effect != policy.EffectAllow {
		t.Fatalf("always rule should allow, got %v (%s)", res.Effect, res.MatchedRule)
	}
}
