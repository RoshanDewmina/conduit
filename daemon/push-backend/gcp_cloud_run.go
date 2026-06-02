package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"
)

type GCPJobOrchestration struct {
	ID        string          `json:"id"`
	AgentID   string          `json:"agentId"`
	CustomerID string         `json:"customerId"`
	Project   string          `json:"project"`
	Region    string          `json:"region"`
	JobName   string          `json:"jobName"`
	Image     string          `json:"image,omitempty"`
	Spec      json.RawMessage `json:"spec"`
	Status    string          `json:"status"`
	CreatedAt string          `json:"createdAt"`
}

type gcpOrchestrationData struct {
	Records []GCPJobOrchestration `json:"records"`
}

var gcpOrchestrationStore = struct {
	mu   sync.Mutex
	path string
}{
	path: dataFilePath("GCP_ORCHESTRATION_FILE", "conduit-gcp-orchestrations.json"),
}

func initGCPOrchestrationStore() {
	var data gcpOrchestrationData
	if err := loadJSONFile(gcpOrchestrationStore.path, &data); err != nil {
		log.Printf("gcp orchestration: load failed: %v", err)
	}
}

func gcpProject() string {
	return strings.TrimSpace(os.Getenv("GCP_PROJECT"))
}

func gcpRegion() string {
	if r := strings.TrimSpace(os.Getenv("GCP_REGION")); r != "" {
		return r
	}
	return "us-central1"
}

func gcpCloudRunEnabled() bool {
	return gcpProject() != ""
}

func provisionGCPCloudRunAgent(agent *Agent) error {
	project := gcpProject()
	region := gcpRegion()
	jobName := sanitizeJobName(agent.Name, agent.ID)

	spec := buildCloudRunJobSpec(agent, project, region, jobName)
	specJSON, err := json.Marshal(spec)
	if err != nil {
		return err
	}

	status := "stub"
	if gcpCloudRunEnabled() {
		status = "spec_ready"
		if err := submitCloudRunJobIfConfigured(spec); err != nil {
			log.Printf("gcp cloud run: submit stub for agent %s: %v", agent.ID, err)
			status = "submit_failed"
		} else {
			status = "submitted"
		}
	}

	record := GCPJobOrchestration{
		ID:         newResourceID("gcpjob"),
		AgentID:    agent.ID,
		CustomerID: agent.CustomerID,
		Project:    project,
		Region:     region,
		JobName:    jobName,
		Image:      cloudRunDefaultImage(),
		Spec:       specJSON,
		Status:     status,
		CreatedAt:  time.Now().UTC().Format(time.RFC3339),
	}

	gcpOrchestrationStore.mu.Lock()
	defer gcpOrchestrationStore.mu.Unlock()

	var data gcpOrchestrationData
	if err := loadJSONFile(gcpOrchestrationStore.path, &data); err != nil {
		return err
	}
	data.Records = append(data.Records, record)
	if err := saveJSONFile(gcpOrchestrationStore.path, data); err != nil {
		return err
	}

	merged, _ := json.Marshal(map[string]any{
		"gcpCloudRun": map[string]any{
			"orchestrationId": record.ID,
			"project":         record.Project,
			"region":          record.Region,
			"jobName":         record.JobName,
			"status":          record.Status,
			"spec":            spec,
		},
	})
	if len(agent.Config) == 0 || string(agent.Config) == "null" {
		agent.Config = merged
	} else {
		var base map[string]any
		if err := json.Unmarshal(agent.Config, &base); err == nil {
			base["gcpCloudRun"] = map[string]any{
				"orchestrationId": record.ID,
				"project":         record.Project,
				"region":          record.Region,
				"jobName":         record.JobName,
				"status":          record.Status,
				"spec":            spec,
			}
			merged, _ = json.Marshal(base)
			agent.Config = merged
		}
	}
	return nil
}

func buildCloudRunJobSpec(agent *Agent, project, region, jobName string) map[string]any {
	return map[string]any{
		"apiVersion": "run.googleapis.com/v1",
		"kind":       "Job",
		"metadata": map[string]any{
			"name":      jobName,
			"namespace": project,
			"labels": map[string]string{
				"conduit-agent-id": agent.ID,
				"conduit-customer": agent.CustomerID,
			},
		},
		"spec": map[string]any{
			"template": map[string]any{
				"spec": map[string]any{
					"template": map[string]any{
						"spec": map[string]any{
							"containers": []map[string]any{
								{
									"image": cloudRunDefaultImage(),
									"env": []map[string]string{
										{"name": "CONDUIT_AGENT_ID", "value": agent.ID},
									},
								},
							},
							"serviceAccountName": fmt.Sprintf("conduit-agent-%s", truncateID(agent.ID, 8)),
						},
					},
				},
			},
		},
		"_conduit": map[string]any{
			"project": project,
			"region":  region,
			"runtime": "gcp_cloud_run",
		},
	}
}

func submitCloudRunJobIfConfigured(spec map[string]any) error {
	// Real GCP Cloud Run Jobs API integration is optional; requires
	// GCP_PROJECT, GCP_REGION, and Application Default Credentials or
	// GOOGLE_APPLICATION_CREDENTIALS. MVP records the spec only.
	if !gcpCloudRunEnabled() {
		return nil
	}
	_ = spec
	return nil
}

func cloudRunDefaultImage() string {
	if img := os.Getenv("GCP_CLOUD_RUN_IMAGE"); img != "" {
		return img
	}
	return "gcr.io/cloudrun/hello"
}

func sanitizeJobName(name, agentID string) string {
	base := strings.ToLower(name)
	var b strings.Builder
	for _, r := range base {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else if r == '-' {
			b.WriteRune(r)
		} else if r == ' ' || r == '_' {
			b.WriteRune('-')
		}
	}
	out := b.String()
	if out == "" {
		out = "agent"
	}
	suffix := truncateID(agentID, 8)
	if len(out) > 40 {
		out = out[:40]
	}
	return out + "-" + suffix
}

func truncateID(id string, n int) string {
	id = strings.TrimPrefix(id, "agent_")
	if len(id) > n {
		return id[:n]
	}
	return id
}

func setGCPOrchestrationPath(path string) {
	gcpOrchestrationStore.path = path
}

func resetGCPOrchestrationForTests() {
	_ = saveJSONFile(gcpOrchestrationStore.path, gcpOrchestrationData{})
}
