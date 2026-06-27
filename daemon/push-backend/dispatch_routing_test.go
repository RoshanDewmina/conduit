package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

// providerFor maps an agent runtime string to a concrete provider. This is
// production routing logic (tests normally stub it via the override), so lock the
// mapping directly with the override cleared.
func TestProviderForRouting(t *testing.T) {
	setProviderOverrideForTest(nil) // exercise the real switch, not the test hook
	t.Cleanup(func() { setProviderOverrideForTest(nil) })
	t.Setenv("LANCER_LOCAL_RUNNER", "") // ensure local-runner shortcut is off

	cases := []struct {
		runtime string
		want    RuntimeProvider
		nilWant bool
	}{
		{"gcp_cloud_run", gcpCloudRunProvider{}, false},
		{"lightsail", lightsailProvider{}, false},
		{"fly", flyProvider{}, false},
		{"GCP_CLOUD_RUN", gcpCloudRunProvider{}, false}, // normalized (case-insensitive)
		{"ssh-host", nil, true},                          // on-device path, never dispatched
		{"", nil, true},                                  // normalizes to ssh-host
		{"bogus-runtime", nil, true},
	}
	for _, c := range cases {
		got := providerFor(c.runtime)
		if c.nilWant {
			if got != nil {
				t.Errorf("providerFor(%q) = %T, want nil", c.runtime, got)
			}
			continue
		}
		if got == nil {
			t.Errorf("providerFor(%q) = nil, want %T", c.runtime, c.want)
			continue
		}
		// Compare concrete dynamic types (providers are zero-size structs).
		if gotType, wantType := typeName(got), typeName(c.want); gotType != wantType {
			t.Errorf("providerFor(%q) = %s, want %s", c.runtime, gotType, wantType)
		}
	}
}

// With LANCER_LOCAL_RUNNER=1 every non-ssh-host runtime routes to the local
// process provider (the dev/e2e path); ssh-host still returns nil.
func TestProviderForLocalRunnerOverride(t *testing.T) {
	setProviderOverrideForTest(nil)
	t.Cleanup(func() { setProviderOverrideForTest(nil) })
	t.Setenv("LANCER_LOCAL_RUNNER", "1")

	if got := providerFor("gcp_cloud_run"); typeName(got) != typeName(processProvider{}) {
		t.Errorf("local runner: gcp routed to %T, want processProvider", got)
	}
	if got := providerFor("ssh-host"); got != nil {
		t.Errorf("local runner: ssh-host routed to %T, want nil", got)
	}
}

// resolveAgentCommand precedence: explicit run.Command > agent config "command" > "claude".
func TestResolveAgentCommandPrecedence(t *testing.T) {
	withCmdConfig := &Agent{Config: json.RawMessage(`{"command":"codex --yolo"}`)}
	noConfig := &Agent{}

	cases := []struct {
		name  string
		agent *Agent
		run   *AgentRun
		want  string
	}{
		{"run command wins", withCmdConfig, &AgentRun{Command: "claude --resume"}, "claude --resume"},
		{"falls back to config command", withCmdConfig, &AgentRun{}, "codex --yolo"},
		{"defaults to claude", noConfig, &AgentRun{}, "claude"},
		{"empty config defaults to claude", &Agent{Config: json.RawMessage(`{}`)}, &AgentRun{}, "claude"},
	}
	for _, c := range cases {
		if got := resolveAgentCommand(c.agent, c.run); got != c.want {
			t.Errorf("%s: resolveAgentCommand = %q, want %q", c.name, got, c.want)
		}
	}
}

func typeName(v any) string {
	if v == nil {
		return "<nil>"
	}
	return fmt.Sprintf("%T", v)
}
