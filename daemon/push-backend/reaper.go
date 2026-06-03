package main

import (
	"log"
	"os"
	"strconv"
	"time"
)

// hardCancel best-effort terminates the underlying provider execution for a run.
// No-op for ssh-host (providerFor returns nil) or an empty handle. Never returns
// an error to callers — cancellation is best-effort and must not block them.
func hardCancel(runtime, handle string) {
	if handle == "" {
		return
	}
	prov := providerFor(runtime)
	if prov == nil {
		return
	}
	if err := prov.Cancel(handle); err != nil {
		log.Printf("reaper: cancel %s/%s failed: %v", runtime, handle, err)
	}
}

func reaperInterval() time.Duration {
	if n := envInt("RUN_REAPER_INTERVAL_SEC"); n > 0 {
		return time.Duration(n) * time.Second
	}
	return 2 * time.Minute
}

func maxRunDuration() time.Duration {
	if n := envInt("RUN_MAX_DURATION_SEC"); n > 0 {
		return time.Duration(n) * time.Second
	}
	return 60 * time.Minute
}

func envInt(key string) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return 0
}

// startRunReaper launches the background reconciler. Two jobs:
//  1. Teardown backstop — a terminal run that still carries a provider handle gets
//     a best-effort Cancel (so a self-terminate that never fired can't leak a paid
//     Lightsail instance / Fly machine), then the handle is cleared so it isn't
//     cancelled again.
//  2. Timeout reconciler — a non-terminal cloud run older than maxRunDuration is
//     marked failed and torn down. Prevents a crashed/hung runner from stranding a
//     run in pending/running forever (the runner can't PATCH if it died).
//
// Disabled with CONDUIT_DISABLE_REAPER=1. Tests drive reapRunsOnce directly.
func startRunReaper() {
	if os.Getenv("CONDUIT_DISABLE_REAPER") == "1" {
		return
	}
	go func() {
		ticker := time.NewTicker(reaperInterval())
		defer ticker.Stop()
		for range ticker.C {
			reapRunsOnce(time.Now().UTC())
		}
	}()
}

func snapshotRuns() []AgentRun {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	out := make([]AgentRun, len(controlPlane.data.Runs))
	copy(out, controlPlane.data.Runs)
	return out
}

// reapRunsOnce performs one reconcile pass. Snapshots runs under the read lock,
// then acts without holding it (provider Cancel makes network calls; updateRunFields
// re-locks). Same-package lowercase so tests can call it deterministically.
func reapRunsOnce(now time.Time) {
	maxDur := maxRunDuration()
	for _, run := range snapshotRuns() {
		// ssh-host runs execute on-device and are never dispatched/reaped here.
		if normalizeRuntime(run.Runtime) == "ssh-host" {
			continue
		}

		if isTerminalRunStatus(run.Status) {
			if run.ProviderHandle != "" {
				hardCancel(run.Runtime, run.ProviderHandle)
				updateRunFields(run.ID, func(r *AgentRun) { r.ProviderHandle = "" })
			}
			continue
		}

		// Non-terminal: enforce a hard wall-clock cap as a crash/hang backstop.
		started := parseRFC3339OrZero(run.StartedAt)
		if started.IsZero() {
			started = parseRFC3339OrZero(run.CreatedAt)
		}
		if !started.IsZero() && now.Sub(started) > maxDur {
			log.Printf("reaper: run %s exceeded max duration (%s); marking failed", run.ID, maxDur)
			failRun(run.ID, "run exceeded maximum duration; marked failed and torn down by the reaper")
			if run.ProviderHandle != "" {
				hardCancel(run.Runtime, run.ProviderHandle)
				updateRunFields(run.ID, func(r *AgentRun) { r.ProviderHandle = "" })
			}
		}
	}
}

func parseRFC3339OrZero(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Time{}
	}
	return t
}
