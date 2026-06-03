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

func provisionLightsailAgent(agent *Agent) error {
	// MVP: accept lightsail runtime and record provisioning metadata for iOS
	// LightsailProvisioner callbacks; no AWS API calls from push-backend yet.
	if len(agent.Config) == 0 || string(agent.Config) == "null" {
		return nil
	}
	return nil
}
