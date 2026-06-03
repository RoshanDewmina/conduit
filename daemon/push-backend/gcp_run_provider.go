package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"google.golang.org/api/option"
	runv2 "google.golang.org/api/run/v2"
)

// gcpCloudRunProvider implements RuntimeProvider for GCP Cloud Run Jobs.
// One Cloud Run Job is created per agent (provisioned at agent-creation time via
// provisionGCPCloudRunAgent); one Job Execution is launched per run.
type gcpCloudRunProvider struct{}

func (p gcpCloudRunProvider) Launch(agent *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	project := gcpProject()
	region := gcpRegion()
	if project == "" {
		return "", fmt.Errorf("GCP_PROJECT not configured")
	}
	// Refuse to launch against the inert sample image — it has no agent-runner, so
	// the run would hang silently until the reaper fails it. Failing here surfaces
	// an actionable error via failRun instead of a mystery stuck run.
	if imageIsPlaceholder() {
		return "", fmt.Errorf("GCP_CLOUD_RUN_IMAGE is not set; refusing to launch against placeholder image %q (build/push the agent-runner image and set GCP_CLOUD_RUN_IMAGE)", placeholderCloudRunImage)
	}

	jobName := sanitizeJobName(agent.Name, agent.ID)

	ctx := context.Background()
	svc, err := runv2.NewService(ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return "", fmt.Errorf("create Cloud Run service: %w", err)
	}

	parent := fmt.Sprintf("projects/%s/locations/%s", project, region)
	fullJobName := fmt.Sprintf("%s/jobs/%s", parent, jobName)

	// Per-execution env overrides (run-specific secrets injected at launch time)
	execEnvOverrides := []*runv2.GoogleCloudRunV2EnvVar{
		{Name: "CONDUIT_RUN_ID", Value: env.RunID},
		{Name: "CONDUIT_RUNNER_TOKEN", Value: env.RunnerToken},
		{Name: "CONDUIT_CONTROL_PLANE_URL", Value: env.ControlPlaneURL},
		{Name: "CONDUIT_COMMAND_ARGV", Value: buildCommandArgv(env.Command)},
		{Name: "CONDUIT_MODEL", Value: env.Model},
		{Name: "CONDUIT_OPENROUTER_KEY", Value: env.OpenRouterKey},
		{Name: "CONDUIT_AGENT_ID", Value: env.AgentID},
	}

	runReq := &runv2.GoogleCloudRunV2RunJobRequest{
		Overrides: &runv2.GoogleCloudRunV2Overrides{
			ContainerOverrides: []*runv2.GoogleCloudRunV2ContainerOverride{
				{Env: execEnvOverrides},
			},
		},
	}

	op, err := svc.Projects.Locations.Jobs.Run(fullJobName, runReq).Context(ctx).Do()
	if err != nil {
		return "", fmt.Errorf("run Cloud Run job %s: %w", fullJobName, err)
	}

	return op.Name, nil // long-running operation name used as the execution handle
}

func (p gcpCloudRunProvider) Cancel(handle string) error {
	if handle == "" {
		return nil
	}
	ctx := context.Background()
	svc, err := runv2.NewService(ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return fmt.Errorf("create Cloud Run service: %w", err)
	}
	_, err = svc.Projects.Locations.Jobs.Executions.Cancel(handle,
		&runv2.GoogleCloudRunV2CancelExecutionRequest{}).Context(ctx).Do()
	return err
}

// buildCommandArgv converts a command string to a JSON array string suitable
// for CONDUIT_COMMAND_ARGV. Safe: the runner uses exec.Command (no shell expansion).
// Defined here; shared by lightsail_provider.go and fly_provider.go via the same package.
func buildCommandArgv(command string) string {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		parts = []string{"claude"}
	}
	b, _ := json.Marshal(parts)
	return string(b)
}
