package main

import (
	"bufio"
	"context"
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

func main() {
	// 1. Read and validate required env vars
	runID := os.Getenv("LANCER_RUN_ID")
	token := os.Getenv("LANCER_RUNNER_TOKEN")
	baseURL := os.Getenv("LANCER_CONTROL_PLANE_URL")
	commandArgvJSON := os.Getenv("LANCER_COMMAND_ARGV")

	if runID == "" || token == "" || baseURL == "" || commandArgvJSON == "" {
		log.Fatalf("required env vars missing: LANCER_RUN_ID, LANCER_RUNNER_TOKEN, LANCER_CONTROL_PLANE_URL, LANCER_COMMAND_ARGV")
	}

	var argv []string
	if err := json.Unmarshal([]byte(commandArgvJSON), &argv); err != nil || len(argv) == 0 {
		log.Fatalf("LANCER_COMMAND_ARGV must be a valid non-empty JSON array: %v", err)
	}

	client := NewClient(baseURL, runID, token)

	// 2. Build child env (pass model/key if set; never log the token)
	childEnv := append(os.Environ(), agentChildEnv()...)

	// 3. Set up context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle OS signals
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		cancel()
	}()

	// 4. Launch the child process
	// argv[0] is always the explicit binary path — never use sh -c with string interpolation.
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Env = childEnv

	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		log.Fatalf("stdout pipe: %v", err)
	}
	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		log.Fatalf("stderr pipe: %v", err)
	}

	if err := cmd.Start(); err != nil {
		log.Fatalf("start command: %v", err)
	}

	log.Printf("agent-runner: started run=%s agent=%s", runID, os.Getenv("LANCER_AGENT_ID"))

	// 5. Stream logs to control plane
	// Collect lines from both pipes and batch-flush every 250ms or 50 lines.
	logCh := make(chan LogLine, 200)

	var wg sync.WaitGroup

	wg.Add(1)
	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stdoutPipe)
		for scanner.Scan() {
			logCh <- LogLine{Stream: "stdout", Text: scanner.Text()}
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stderrPipe)
		for scanner.Scan() {
			logCh <- LogLine{Stream: "stderr", Text: scanner.Text()}
		}
	}()

	// Log flush goroutine: batches lines and sends them to the control plane.
	// Flushes on: batch size >= 50, or ticker every 250ms, or channel close.
	flushDone := make(chan struct{})
	go func() {
		defer close(flushDone)
		var batch []LogLine
		ticker := time.NewTicker(250 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case line, ok := <-logCh:
				if !ok {
					// Channel closed — flush remaining and exit.
					if len(batch) > 0 {
						_, _ = client.AppendLogs(context.Background(), batch)
					}
					return
				}
				batch = append(batch, line)
				if len(batch) >= 50 {
					_, _ = client.AppendLogs(ctx, batch)
					batch = batch[:0]
				}
			case <-ticker.C:
				if len(batch) > 0 {
					_, _ = client.AppendLogs(ctx, batch)
					batch = batch[:0]
				}
			}
		}
	}()

	// 6. Poll for cancel requests every 3 seconds.
	go func() {
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if cancelled, err := client.GetControl(ctx); err == nil && cancelled {
					log.Printf("agent-runner: cancel requested for run=%s; killing child", runID)
					cancel()
					return
				}
			}
		}
	}()

	// Wait for both pipe scanners to finish, then close the log channel.
	wg.Wait()
	close(logCh)

	// Wait for the flush goroutine to drain before proceeding.
	<-flushDone

	// 7. Wait for command exit and report terminal status.
	err = cmd.Wait()
	completedAt := time.Now().UTC().Format(time.RFC3339)

	status := "succeeded"
	exitCode := 0
	if err != nil {
		if ctx.Err() != nil {
			status = "cancelled"
		} else {
			status = "failed"
		}
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = 1
		}
	}

	log.Printf("agent-runner: run=%s status=%s exitCode=%d", runID, status, exitCode)

	// Use a fresh context for the final PATCH — even if ctx was cancelled we must report status.
	if patchErr := client.PatchRun(context.Background(), status, exitCode, completedAt); patchErr != nil {
		log.Printf("agent-runner: failed to patch run status: %v", patchErr)
	}

	if status == "succeeded" {
		os.Exit(0)
	} else {
		os.Exit(exitCode)
	}
}

// agentChildEnv returns the env additions handed to the agent command, derived from
// the LANCER_* env the control plane injects. It is split out from main() so the
// OpenRouter wiring can be unit-tested.
//
// The bundled Claude Code CLI authenticates via the Anthropic env vars, NOT
// OPENROUTER_API_KEY. Per OpenRouter's docs, routing Claude Code through OpenRouter's
// Anthropic-compatible API requires:
//   - ANTHROPIC_BASE_URL = https://openrouter.ai/api   (note: no /v1 suffix)
//   - ANTHROPIC_AUTH_TOKEN = the OpenRouter key
//   - ANTHROPIC_API_KEY = ""  (must be explicitly empty so the CLI doesn't prefer a
//     stale/inherited key over the auth token)
// OPENROUTER_API_KEY is also exported for any agent command that reads it directly.
func agentChildEnv() []string {
	var env []string
	if model := os.Getenv("LANCER_MODEL"); model != "" {
		env = append(env, "ANTHROPIC_MODEL="+model, "OPENROUTER_DEFAULT_MODEL="+model)
	}
	if key := os.Getenv("LANCER_OPENROUTER_KEY"); key != "" {
		base := os.Getenv("LANCER_OPENROUTER_BASE_URL")
		if base == "" {
			base = "https://openrouter.ai/api"
		}
		env = append(env,
			"OPENROUTER_API_KEY="+key,
			"ANTHROPIC_BASE_URL="+base,
			"ANTHROPIC_AUTH_TOKEN="+key,
			"ANTHROPIC_API_KEY=",
		)
	}
	return env
}
