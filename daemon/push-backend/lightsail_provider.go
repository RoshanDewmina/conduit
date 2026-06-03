package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"strings"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lightsail"
	"github.com/aws/aws-sdk-go-v2/service/lightsail/types"
)

// lightsailProvider provisions one Lightsail instance per run.
// The instance runs the agent-runner binary via a user-data bootstrap script.
// Instances are tagged with conduit-run-id for cleanup sweeps.
type lightsailProvider struct{}

func (p lightsailProvider) Launch(agent *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return "", fmt.Errorf("load AWS config: %w", err)
	}
	client := lightsail.NewFromConfig(cfg)

	instanceName := fmt.Sprintf("conduit-run-%s", run.ID)
	userData := buildLightsailUserData(env)

	az := lightsailAZ()
	blueprintID := "amazon_linux_2"
	bundleID := "nano_3_0"
	input := &lightsail.CreateInstancesInput{
		InstanceNames:    []string{instanceName},
		AvailabilityZone: &az,
		BlueprintId:      &blueprintID,
		BundleId:         &bundleID,
		UserData:         &userData,
		Tags: []types.Tag{
			{Key: strPtr("conduit-run-id"), Value: strPtr(run.ID)},
			{Key: strPtr("conduit-agent-id"), Value: strPtr(agent.ID)},
		},
	}

	_, err = client.CreateInstances(ctx, input)
	if err != nil {
		return "", fmt.Errorf("create Lightsail instance: %w", err)
	}
	return instanceName, nil
}

func (p lightsailProvider) Cancel(handle string) error {
	if handle == "" {
		return nil
	}
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	client := lightsail.NewFromConfig(cfg)
	_, err = client.DeleteInstance(ctx, &lightsail.DeleteInstanceInput{
		InstanceName: &handle,
	})
	return err
}

func lightsailAZ() string {
	region := strings.TrimSpace(os.Getenv("AWS_REGION"))
	if region == "" {
		region = "us-east-1"
	}
	return region + "a"
}

// buildLightsailUserData generates the EC2 user-data bootstrap script.
// All values are base64-encoded before embedding so no shell metacharacter
// in any user-controlled field (command, model name, etc.) can break out.
// base64 output is [A-Za-z0-9+/=] — no shell injection possible.
func buildLightsailUserData(env RunnerEnv) string {
	b64 := func(s string) string { return base64.StdEncoding.EncodeToString([]byte(s)) }
	argv := buildCommandArgv(env.Command)
	return fmt.Sprintf(`#!/bin/bash
set -e
export CONDUIT_RUN_ID=$(echo '%s' | base64 -d)
export CONDUIT_RUNNER_TOKEN=$(echo '%s' | base64 -d)
export CONDUIT_CONTROL_PLANE_URL=$(echo '%s' | base64 -d)
export CONDUIT_COMMAND_ARGV=$(echo '%s' | base64 -d)
export CONDUIT_MODEL=$(echo '%s' | base64 -d)
export CONDUIT_AGENT_ID=$(echo '%s' | base64 -d)
_CPURL=$(echo '%s' | base64 -d)
curl -fsSL "${_CPURL}/agent-runner-linux-amd64" -o /usr/local/bin/agent-runner \
  || { echo "runner download failed"; exit 1; }
chmod +x /usr/local/bin/agent-runner
/usr/local/bin/agent-runner
`,
		b64(env.RunID),
		b64(env.RunnerToken),
		b64(env.ControlPlaneURL),
		b64(argv),
		b64(env.Model),
		b64(env.AgentID),
		b64(env.ControlPlaneURL),
	)
}

func strPtr(s string) *string { return &s }
