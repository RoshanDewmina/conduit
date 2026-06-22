package main

import (
	"context"
	"os/exec"
	"time"
)

// tmuxLauncher returns a launchFunc that runs the agent inside a detached tmux
// session. Output is polled from capture-pane and emitted as agent.run.output
// chunks; on session death it emits a terminal agent.run.status.
func tmuxLauncher(tmuxName string) launchFunc {
	return func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		args := []string{"new-session", "-d", "-s", tmuxName}
		if cwd != "" {
			args = append(args, "-c", expandHome(cwd))
		}
		args = append(args, "--")
		args = append(args, argv...)
		if err := exec.Command("tmux", args...).Run(); err != nil {
			return nil, err
		}
		emitRunStatus(emit, runID, "running", nil)

		ctx, cancel := context.WithCancel(context.Background())
		go pollTmuxPane(ctx, tmuxName, runID, emit)
		return &procHandle{
			kill: func() {
				cancel()
				_ = exec.Command("tmux", "kill-session", "-t", tmuxName).Run()
			},
			pause:  func() {},
			resume: func() {},
		}, nil
	}
}

func pollTmuxPane(ctx context.Context, tmuxName, runID string, emit emitFunc) {
	var lastLen int
	seq := 0
	ticker := time.NewTicker(400 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			out, err := exec.Command("tmux", "capture-pane", "-p", "-t", tmuxName).Output()
			if err != nil {
				// session gone -> terminal status, stop polling.
				emitRunStatus(emit, runID, "exited", nil)
				return
			}
			if len(out) > lastLen {
				chunk := string(out[lastLen:])
				lastLen = len(out)
				seq++
				emit("agent.run.output", map[string]any{
					"runId": runID, "stream": "stdout", "chunk": chunk, "seq": seq,
				})
			}
		}
	}
}
