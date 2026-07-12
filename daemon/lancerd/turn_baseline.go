package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// turn_baseline.go — shadow git tree OIDs for per-turn / session diffs.
//
// Baselines are stamped with a temporary GIT_INDEX_FILE so the user's real
// index, HEAD, and worktree are never mutated. Empty OID means "not a git
// repo" (or stamp failed); repo.*Diff RPCs then return {supported:false}.

const turnBaselineTimeout = 15 * time.Second

// stampTurnBaseline returns a tree OID capturing cwd's current tracked+untracked
// state via a private index, or "" when cwd is not a git work tree / stamp fails.
func stampTurnBaseline(cwd string) string {
	cwd = strings.TrimSpace(cwd)
	if cwd == "" {
		return ""
	}
	info, err := os.Stat(cwd)
	if err != nil || !info.IsDir() {
		return ""
	}
	if !isGitWorkTree(cwd) {
		return ""
	}

	tmp, err := os.CreateTemp("", "lancer-turn-index-*")
	if err != nil {
		return ""
	}
	indexPath := tmp.Name()
	_ = tmp.Close()
	defer os.Remove(indexPath)

	env := append(os.Environ(), "GIT_INDEX_FILE="+indexPath)

	// Seed the private index from HEAD (empty tree if unborn — still OK for add).
	if err := gitEnv(cwd, env, "read-tree", "HEAD"); err != nil {
		_ = gitEnv(cwd, env, "read-tree", "--empty")
	}
	if err := gitEnv(cwd, env, "add", "-A", "."); err != nil {
		return ""
	}
	out, err := gitEnvOut(cwd, env, "write-tree")
	if err != nil {
		return ""
	}
	oid := strings.TrimSpace(out)
	if len(oid) != 40 && len(oid) != 64 { // SHA-1 or SHA-256
		return ""
	}
	return oid
}

func isGitWorkTree(cwd string) bool {
	out, err := gitEnvOut(cwd, os.Environ(), "rev-parse", "--is-inside-work-tree")
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == "true"
}

func gitEnv(cwd string, env []string, args ...string) error {
	_, err := gitEnvOut(cwd, env, args...)
	return err
}

func gitEnvOut(cwd string, env []string, args ...string) (string, error) {
	return gitEnvOutAllowDiff(cwd, env, false, args...)
}

// gitDiffOut runs git and treats exit code 1 as success (git's "diffs found" signal).
func gitDiffOut(cwd string, args ...string) (string, error) {
	return gitEnvOutAllowDiff(cwd, os.Environ(), true, args...)
}

func gitEnvOutAllowDiff(cwd string, env []string, allowDiffExit bool, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), turnBaselineTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = cwd
	cmd.Env = env
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	out := buf.String()
	if ctx.Err() == context.DeadlineExceeded {
		if proc := cmd.Process; proc != nil {
			_ = syscall.Kill(-proc.Pid, syscall.SIGKILL)
		}
		return out, ctx.Err()
	}
	if err != nil {
		if allowDiffExit {
			var ee *exec.ExitError
			if errors.As(err, &ee) && ee.ExitCode() == 1 {
				return out, nil
			}
		}
		return out, err
	}
	return out, nil
}

// gitStatusPorcelain is a test helper surface: returns `git status --porcelain`
// without touching the index. Used to assert stampTurnBaseline leaves user state alone.
func gitStatusPorcelain(cwd string) (string, error) {
	return gitEnvOut(cwd, os.Environ(), "status", "--porcelain=v1")
}

// ensureAbsUnder resolves path relative to root and rejects escapes / symlink escapes.
// Absolute request paths are rejected (clients must send cwd-relative paths).
func ensureAbsUnder(root, path string) (string, error) {
	root = filepath.Clean(root)
	if path == "" {
		path = "."
	}
	if filepath.IsAbs(path) {
		return "", errPathJail("path escapes conversation cwd")
	}
	candidate := filepath.Clean(filepath.Join(root, path))

	rootReal, err := filepath.EvalSymlinks(root)
	if err != nil {
		rootReal = root
	}
	candReal, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		parent, leaf := filepath.Dir(candidate), filepath.Base(candidate)
		parentReal, perr := filepath.EvalSymlinks(parent)
		if perr != nil {
			return "", errPathJail("path escapes conversation cwd")
		}
		candReal = filepath.Join(parentReal, leaf)
	}

	rel, err := filepath.Rel(rootReal, candReal)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", errPathJail("path escapes conversation cwd")
	}
	return candReal, nil
}

type pathJailError struct{ msg string }

func (e pathJailError) Error() string { return e.msg }

func errPathJail(msg string) error { return pathJailError{msg: msg} }
