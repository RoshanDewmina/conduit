package main

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
)

func testdataHome(t *testing.T, name string) string {
	t.Helper()
	return filepath.Join("testdata", name)
}

func TestAgentStatusClaudeFixture(t *testing.T) {
	prev := claudeAuthRunnerForPkg
	t.Cleanup(func() { claudeAuthRunnerForPkg = prev; invalidateClaudeAuthCache() })
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":true}`), nil
	}
	invalidateClaudeAuthCache()
	// Status path is non-blocking — seed last-known so the fixture asserts LoggedIn.
	globalClaudeAuthCache.put(true)
	home := testdataHome(t, "claude-home")
	result := collectAgentStatus(home)
	var claude *AgentVendorStatus
	for i := range result.Agents {
		if result.Agents[i].Agent == "claudeCode" { claude = &result.Agents[i]; break }
	}
	if claude == nil { t.Fatal("missing claudeCode") }
	if claude.LoggedIn == nil || !*claude.LoggedIn { t.Errorf("loggedIn") }
	if claude.Model == nil || *claude.Model != "claude-sonnet-4-20250514" { t.Errorf("model %v", claude.Model) }
	if claude.SessionCount != 1 { t.Errorf("sessions %d", claude.SessionCount) }
	if claude.UsageUSD == nil || *claude.UsageUSD != 2.47 { t.Errorf("usage %v", claude.UsageUSD) }
}

func TestAgentStatusCodexFixture(t *testing.T) {
	t.Parallel()
	result := collectAgentStatus(testdataHome(t, "codex-home"))
	var codex *AgentVendorStatus
	for i := range result.Agents {
		if result.Agents[i].Agent == "codex" { codex = &result.Agents[i]; break }
	}
	if codex == nil { t.Fatal("missing codex") }
	if codex.LoggedIn == nil || !*codex.LoggedIn { t.Errorf("loggedIn") }
	if codex.SessionCount != 1 { t.Errorf("sessions") }
	if codex.UsageUSD == nil || *codex.UsageUSD != 1.25 { t.Errorf("usage") }
}

func TestAgentStatusOpencodeFixture(t *testing.T) {
	t.Parallel()
	result := collectAgentStatus(testdataHome(t, "opencode-home"))
	var oc *AgentVendorStatus
	for i := range result.Agents {
		if result.Agents[i].Agent == "opencode" { oc = &result.Agents[i]; break }
	}
	if oc == nil { t.Fatal("missing opencode") }
	if oc.Model == nil || *oc.Model != "gpt-4.1" { t.Errorf("model") }
	// Usage is now read from SQLite (opencode.db) which requires a driver;
	// the reader stubs to (0, nil, false) so usage is absent in the fixture.
	if oc.UsageUSD != nil { t.Errorf("usage should be nil (stubbed)") }
}

func TestAgentStatusOmitsUsageWhenAbsent(t *testing.T) {
	prev := claudeAuthRunnerForPkg
	t.Cleanup(func() { claudeAuthRunnerForPkg = prev; invalidateClaudeAuthCache() })
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":false}`), nil
	}
	invalidateClaudeAuthCache()
	// Status must not wait on probe; omit LoggedIn on cold miss is fine for this fixture.
	result := collectAgentStatus(testdataHome(t, "empty-home"))
	for _, a := range result.Agents {
		if a.UsageUSD != nil { t.Errorf("%s usage set", a.Agent) }
	}
}

func TestAgentStatusRPCHandler(t *testing.T) {
	t.Parallel()
	home := testdataHome(t, "claude-home")
	params, _ := json.Marshal(agentStatusParams{HomeDir: home})
	s := &server{approvals: newApprovalStore(), dispatcher: newDispatcher()}
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "agent.status", Params: params})
	if len(collectAgentStatus(home).Agents) != 3 { t.Fatal("want 3 agents") }
}
