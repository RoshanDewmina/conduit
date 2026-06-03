package main

import (
	"fmt"
	"strings"
)

var allowedRuntimes = map[string]bool{
	"ssh-host":      true,
	"fly":           true,
	"gcp_cloud_run": true,
	"lightsail":     true,
}

func normalizeRuntime(runtime string) string {
	r := strings.TrimSpace(strings.ToLower(runtime))
	if r == "" {
		return "ssh-host"
	}
	return r
}

func validateRuntime(runtime string) error {
	r := normalizeRuntime(runtime)
	if !allowedRuntimes[r] {
		return fmt.Errorf("unsupported runtime %q; allowed: ssh-host, fly, gcp_cloud_run, lightsail", runtime)
	}
	return nil
}

func provisionRuntimeIfNeeded(agent *Agent) error {
	switch normalizeRuntime(agent.Runtime) {
	case "gcp_cloud_run":
		return provisionGCPCloudRunAgent(agent)
	case "lightsail":
		return provisionLightsailAgent(agent)
	case "fly":
		return nil // no pre-provisioning for Fly; machines are created per-run by flyProvider.Launch
	default:
		return nil
	}
}

// teardownRuntimeIfNeeded best-effort releases provider resources provisioned for
// an agent (currently the GCP Cloud Run Job). Best-effort: callers log and proceed
// so a provider hiccup never blocks deleting the control-plane record.
func teardownRuntimeIfNeeded(agent *Agent) error {
	switch normalizeRuntime(agent.Runtime) {
	case "gcp_cloud_run":
		return deleteCloudRunJobIfConfigured(sanitizeJobName(agent.Name, agent.ID))
	default:
		return nil // lightsail/fly/ssh-host have no pre-provisioned per-agent resource
	}
}

func provisionLightsailAgent(agent *Agent) error {
	// MVP: accept lightsail runtime and record provisioning metadata for iOS
	// LightsailProvisioner callbacks; no AWS API calls from push-backend yet.
	if len(agent.Config) == 0 || string(agent.Config) == "null" {
		return nil
	}
	return nil
}
