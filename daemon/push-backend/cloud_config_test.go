package main

import (
	"strings"
	"testing"
)

// controlPlaneBaseURL prefers CONTROL_PLANE_PUBLIC_URL but must fall back to
// PUBLIC_BASE_URL (the deploy env historically set only the latter). A missing
// fallback would fail every cloud dispatch.
func TestControlPlaneBaseURLFallback(t *testing.T) {
	cases := []struct {
		name      string
		primary   string // CONTROL_PLANE_PUBLIC_URL
		secondary string // PUBLIC_BASE_URL
		want      string
	}{
		{"primary wins", "https://cp.example.com", "https://other.example.com", "https://cp.example.com"},
		{"falls back to PUBLIC_BASE_URL", "", "http://35.201.3.231:8080", "http://35.201.3.231:8080"},
		{"trailing slash trimmed", "https://cp.example.com/", "", "https://cp.example.com"},
		{"fallback trailing slash trimmed", "", "http://host:8080/", "http://host:8080"},
		{"both empty -> empty", "", "", ""},
		{"whitespace primary treated as empty", "   ", "http://fallback:8080", "http://fallback:8080"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("CONTROL_PLANE_PUBLIC_URL", c.primary)
			t.Setenv("PUBLIC_BASE_URL", c.secondary)
			if got := controlPlaneBaseURL(); got != c.want {
				t.Fatalf("controlPlaneBaseURL() = %q, want %q", got, c.want)
			}
		})
	}
}

// cloudRunDefaultImage / imageIsPlaceholder behavior.
func TestCloudRunImageResolution(t *testing.T) {
	t.Run("unset -> placeholder", func(t *testing.T) {
		t.Setenv("GCP_CLOUD_RUN_IMAGE", "")
		if !imageIsPlaceholder() {
			t.Fatal("expected placeholder when GCP_CLOUD_RUN_IMAGE unset")
		}
		if got := cloudRunDefaultImage(); got != placeholderCloudRunImage {
			t.Fatalf("default image = %q, want placeholder", got)
		}
	})
	t.Run("set -> real image, not placeholder", func(t *testing.T) {
		t.Setenv("GCP_CLOUD_RUN_IMAGE", "gcr.io/proj/agent-runner:abc123")
		if imageIsPlaceholder() {
			t.Fatal("real image must not be reported as placeholder")
		}
		if got := cloudRunDefaultImage(); got != "gcr.io/proj/agent-runner:abc123" {
			t.Fatalf("image = %q, want the configured value", got)
		}
	})
	t.Run("whitespace-only -> placeholder", func(t *testing.T) {
		t.Setenv("GCP_CLOUD_RUN_IMAGE", "   ")
		if !imageIsPlaceholder() {
			t.Fatal("whitespace-only image must be treated as unset/placeholder")
		}
	})
}

// gcpCloudRunProvider.Launch must refuse the placeholder image before making any GCP
// call, so a misconfigured deployment fails fast with an actionable error instead of
// launching a job that hangs. GCP_PROJECT is set so we get past the project check;
// the image guard must fire before any runv2 service call (no creds needed).
func TestGCPLaunchRefusesPlaceholderImage(t *testing.T) {
	t.Setenv("GCP_PROJECT", "test-project")
	t.Setenv("GCP_CLOUD_RUN_IMAGE", "") // -> placeholder

	_, err := gcpCloudRunProvider{}.Launch(
		&Agent{ID: "agent_x", Name: "X"},
		&AgentRun{ID: "run_x"},
		RunnerEnv{RunID: "run_x", Command: "echo hi"},
	)
	if err == nil {
		t.Fatal("expected Launch to refuse the placeholder image, got nil error")
	}
	if !strings.Contains(err.Error(), "GCP_CLOUD_RUN_IMAGE") {
		t.Fatalf("error should name the missing var, got: %v", err)
	}
}

// With a real image configured, Launch passes the guard and proceeds to the GCP call
// (which then fails on missing creds in the test env — that's fine; we only assert it
// got PAST the placeholder guard, i.e. the error is not the placeholder refusal).
func TestGCPLaunchPassesGuardWithRealImage(t *testing.T) {
	t.Setenv("GCP_PROJECT", "test-project")
	t.Setenv("GCP_CLOUD_RUN_IMAGE", "gcr.io/test-project/agent-runner:v1")

	_, err := gcpCloudRunProvider{}.Launch(
		&Agent{ID: "agent_y", Name: "Y"},
		&AgentRun{ID: "run_y"},
		RunnerEnv{RunID: "run_y", Command: "echo hi"},
	)
	// We expect SOME error (no GCP creds in test), but NOT the placeholder refusal.
	if err != nil && strings.Contains(err.Error(), "placeholder image") {
		t.Fatalf("guard wrongly fired for a real image: %v", err)
	}
}
