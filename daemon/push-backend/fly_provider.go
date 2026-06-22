package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// flyProvider launches a Fly Machine per run via the Fly Machines REST API.
// Requires FLY_API_TOKEN and FLY_APP_NAME environment variables.
type flyProvider struct{}

func flyAppName() string {
	return strings.TrimSpace(os.Getenv("FLY_APP_NAME"))
}

func flyAPIToken() string {
	return strings.TrimSpace(os.Getenv("FLY_API_TOKEN"))
}

func (p flyProvider) Launch(agent *Agent, run *AgentRun, env RunnerEnv) (string, error) {
	appName := flyAppName()
	token := flyAPIToken()
	if appName == "" || token == "" {
		return "", fmt.Errorf("FLY_APP_NAME and FLY_API_TOKEN must be set")
	}

	body := map[string]any{
		"config": map[string]any{
			"image": cloudRunDefaultImage(),
			"env": map[string]string{
				"LANCER_RUN_ID":            env.RunID,
				"LANCER_RUNNER_TOKEN":      env.RunnerToken,
				"LANCER_CONTROL_PLANE_URL": env.ControlPlaneURL,
				"LANCER_COMMAND_ARGV":      buildCommandArgv(env.Command),
				"LANCER_MODEL":             env.Model,
				"LANCER_OPENROUTER_KEY":    env.OpenRouterKey,
				"LANCER_AGENT_ID":          env.AgentID,
			},
			"auto_destroy": true,
			"restart":      map[string]string{"policy": "no"},
		},
	}

	buf, err := json.Marshal(body)
	if err != nil {
		return "", fmt.Errorf("marshal fly machine request: %w", err)
	}

	url := fmt.Sprintf("https://api.machines.dev/v1/apps/%s/machines", appName)
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, url, bytes.NewReader(buf))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("create fly machine: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("fly machines API returned %d", resp.StatusCode)
	}

	var result struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode fly machine response: %w", err)
	}
	return result.ID, nil
}

func (p flyProvider) Cancel(handle string) error {
	if handle == "" {
		return nil
	}
	appName := flyAppName()
	token := flyAPIToken()
	if appName == "" || token == "" {
		return nil
	}

	client := &http.Client{Timeout: 15 * time.Second}

	// Stop the machine first (best-effort)
	stopURL := fmt.Sprintf("https://api.machines.dev/v1/apps/%s/machines/%s/stop", appName, handle)
	stopReq, err := http.NewRequestWithContext(context.Background(), http.MethodPost, stopURL, nil)
	if err == nil {
		stopReq.Header.Set("Authorization", "Bearer "+token)
		resp, err := client.Do(stopReq)
		if err == nil {
			resp.Body.Close()
		}
	}

	// Delete the machine
	deleteURL := fmt.Sprintf("https://api.machines.dev/v1/apps/%s/machines/%s", appName, handle)
	delReq, err := http.NewRequestWithContext(context.Background(), http.MethodDelete, deleteURL, nil)
	if err != nil {
		return err
	}
	delReq.Header.Set("Authorization", "Bearer "+token)
	delResp, err := client.Do(delReq)
	if err != nil {
		return err
	}
	delResp.Body.Close()
	return nil
}
