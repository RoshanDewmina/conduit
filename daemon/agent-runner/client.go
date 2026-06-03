package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ControlPlaneClient handles all communication with the Conduit control plane.
type ControlPlaneClient struct {
	BaseURL     string
	RunID       string
	RunnerToken string
	HTTPClient  *http.Client
}

// NewClient creates a new ControlPlaneClient.
func NewClient(baseURL, runID, token string) *ControlPlaneClient {
	return &ControlPlaneClient{
		BaseURL:     baseURL,
		RunID:       runID,
		RunnerToken: token,
		HTTPClient:  &http.Client{Timeout: 15 * time.Second},
	}
}

// LogLine represents a single line of output from the agent process.
type LogLine struct {
	Stream string `json:"stream"` // "stdout" or "stderr"
	Text   string `json:"text"`
}

// appendLogsRequest is the request body for AppendLogs.
type appendLogsRequest struct {
	Lines []LogLine `json:"lines"`
}

// appendLogsResponse is the response body from AppendLogs.
type appendLogsResponse struct {
	NextSince int `json:"nextSince"`
}

// AppendLogs POSTs a batch of log lines to the control plane.
// Returns the nextSince cursor (informational).
func (c *ControlPlaneClient) AppendLogs(ctx context.Context, lines []LogLine) (int, error) {
	body, err := json.Marshal(appendLogsRequest{Lines: lines})
	if err != nil {
		return 0, fmt.Errorf("marshal logs request: %w", err)
	}

	url := fmt.Sprintf("%s/runs/%s/logs", c.BaseURL, c.RunID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("build logs request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.RunnerToken)

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("post logs: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("post logs: status %d: %s", resp.StatusCode, string(b))
	}

	var result appendLogsResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		// Not fatal — nextSince is informational.
		return 0, nil
	}
	return result.NextSince, nil
}

// patchRunRequest is the request body for PatchRun.
type patchRunRequest struct {
	Status      string `json:"status"`
	ExitCode    int    `json:"exitCode"`
	CompletedAt string `json:"completedAt"`
}

// PatchRun updates the run's status and exit code at terminal time.
func (c *ControlPlaneClient) PatchRun(ctx context.Context, status string, exitCode int, completedAt string) error {
	body, err := json.Marshal(patchRunRequest{
		Status:      status,
		ExitCode:    exitCode,
		CompletedAt: completedAt,
	})
	if err != nil {
		return fmt.Errorf("marshal patch request: %w", err)
	}

	url := fmt.Sprintf("%s/runs/%s", c.BaseURL, c.RunID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build patch request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.RunnerToken)

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("patch run: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("patch run: status %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// controlResponse is the response body from GetControl.
type controlResponse struct {
	CancelRequested bool `json:"cancelRequested"`
}

// GetControl polls for cancel requests from the control plane.
func (c *ControlPlaneClient) GetControl(ctx context.Context) (cancelRequested bool, err error) {
	url := fmt.Sprintf("%s/runs/%s/control", c.BaseURL, c.RunID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, fmt.Errorf("build control request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.RunnerToken)

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("get control: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return false, fmt.Errorf("get control: status %d: %s", resp.StatusCode, string(b))
	}

	var result controlResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return false, fmt.Errorf("decode control response: %w", err)
	}
	return result.CancelRequested, nil
}
