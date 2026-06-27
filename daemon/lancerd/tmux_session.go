package main

import (
	"context"
	"os/exec"
	"time"
)

// tmuxBinary resolves `tmux` to an absolute path against the augmented launch
// PATH. Under launchd the daemon's inherited PATH is minimal (/usr/bin:/bin:…)
// and would not find Homebrew's tmux, so a bare exec.Command("tmux") fails and
// every shim spawn silently falls back to passthrough (invisible to the phone).
// Falls back to the bare name if resolution fails, so dev/test on a normal PATH
// still works.
func tmuxBinary() string {
	if p := lookPathIn("tmux", agentLaunchEnvironment()); p != "" {
		return p
	}
	return "tmux"
}

// tmuxLauncher returns a launchFunc that runs the agent inside a detached tmux
// session. Output is polled from capture-pane and emitted as agent.run.output
// chunks; on session death it emits a terminal agent.run.status.
func tmuxLauncher(tmuxName string) launchFunc {
	tmux := tmuxBinary()
	return func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		args := []string{"new-session", "-d", "-s", tmuxName}
		if cwd != "" {
			args = append(args, "-c", expandHome(cwd))
		}
		args = append(args, "--")
		args = append(args, argv...)
		if err := exec.Command(tmux, args...).Run(); err != nil {
			return nil, err
		}
		emitRunStatus(emit, runID, "running", nil)

		ctx, cancel := context.WithCancel(context.Background())
		go pollTmuxPane(ctx, tmux, tmuxName, runID, emit)
		return &procHandle{
			kill: func() {
				cancel()
				_ = exec.Command(tmux, "kill-session", "-t", tmuxName).Run()
			},
			pause:  func() {},
			resume: func() {},
		}, nil
	}
}

func pollTmuxPane(ctx context.Context, tmux, tmuxName, runID string, emit emitFunc) {
	var lastLen int
	seq := 0
	ticker := time.NewTicker(400 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			out, err := exec.Command(tmux, "capture-pane", "-p", "-t", tmuxName).Output()
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
