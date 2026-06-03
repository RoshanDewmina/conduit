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
	runID := os.Getenv("CONDUIT_RUN_ID")
	token := os.Getenv("CONDUIT_RUNNER_TOKEN")
	baseURL := os.Getenv("CONDUIT_CONTROL_PLANE_URL")
	commandArgvJSON := os.Getenv("CONDUIT_COMMAND_ARGV")

	if runID == "" || token == "" || baseURL == "" || commandArgvJSON == "" {
		log.Fatalf("required env vars missing: CONDUIT_RUN_ID, CONDUIT_RUNNER_TOKEN, CONDUIT_CONTROL_PLANE_URL, CONDUIT_COMMAND_ARGV")
	}

	var argv []string
	if err := json.Unmarshal([]byte(commandArgvJSON), &argv); err != nil || len(argv) == 0 {
		log.Fatalf("CONDUIT_COMMAND_ARGV must be a valid non-empty JSON array: %v", err)
	}

	client := NewClient(baseURL, runID, token)

	// 2. Build child env (pass model/key if set; never log the token)
	childEnv := os.Environ()
	if model := os.Getenv("CONDUIT_MODEL"); model != "" {
		childEnv = append(childEnv, "ANTHROPIC_MODEL="+model)
		childEnv = append(childEnv, "OPENROUTER_DEFAULT_MODEL="+model)
	}
	if key := os.Getenv("CONDUIT_OPENROUTER_KEY"); key != "" {
		childEnv = append(childEnv, "OPENROUTER_API_KEY="+key)
	}

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

	log.Printf("agent-runner: started run=%s agent=%s", runID, os.Getenv("CONDUIT_AGENT_ID"))

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
