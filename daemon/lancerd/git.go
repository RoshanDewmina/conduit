package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// git.go — host-side git/PR operations exposed as lancerd RPCs.
//
// The phone is a supervision surface: it reviews the agent's diff, sees the
// branch/status, and ships the work. All git/gh execution happens HERE, on the
// host, so every write lands in the audit log and is policy-gateable — unlike a
// direct-SSH GitClient which bypasses lancerd governance.
//
// Commands run via explicit argv (exec.Command, never `sh -c`) so caller-supplied
// values (workdir, message, branch, PR title/body) can never inject shell.

// ── value types (wire-compatible with Swift GitStatus / Worktree / CIEvent) ──

type gitFileChange struct {
	Path   string `json:"path"`
	Code   string `json:"code"`
	Staged bool   `json:"staged"`
}

type gitStatusResult struct {
	Branch   string          `json:"branch"`
	Upstream string          `json:"upstream,omitempty"`
	Ahead    int             `json:"ahead"`
	Behind   int             `json:"behind"`
	Changes  []gitFileChange `json:"changes"`
}

type gitChangedFile struct {
	Path   string `json:"path"`
	Status string `json:"status"` // added | modified | deleted | renamed
}

type gitShipResult struct {
	Committed bool   `json:"committed"`
	Pushed    bool   `json:"pushed"`
	PRURL     string `json:"prURL,omitempty"`
	Message   string `json:"message,omitempty"`
}

// ── git command runner ────────────────────────────────────────────────────

// gitCommandTimeout bounds every realGitRunner subprocess. A hung git (NFS,
// credential helper, lock wait) must not wedge the relay messageLoop forever.
// Tests may lower this to assert the deadline path without sleeping for 10s.
var gitCommandTimeout = 10 * time.Second

// gitRunner runs a git/gh subcommand in workdir and returns combined output.
// Injectable for tests so the RPC handlers can be exercised without a real repo.
type gitRunner func(workdir, tool string, args ...string) (string, error)

func realGitRunner(workdir, tool string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitCommandTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, tool, args...) // explicit argv — no shell interpolation
	cmd.Dir = workdir
	// Own process group so a deadline kill reaps grandchildren (credential
	// helpers, pager children) — CommandContext alone only signals the root.
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
		return out, &gitCmdError{
			exitCode: -1,
			output:   fmt.Sprintf("git command timed out after %s", gitCommandTimeout),
		}
	}
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return out, &gitCmdError{exitCode: ee.ExitCode(), output: strings.TrimSpace(out)}
		}
		return out, err
	}
	return out, nil
}

type gitCmdError struct {
	exitCode int
	output   string
}

func (e *gitCmdError) Error() string {
	if e.output == "" {
		return fmt.Sprintf("git exited %d", e.exitCode)
	}
	return e.output
}

// gitRun returns the runner wired on the server, defaulting to the real one.
func (s *server) gitRun(workdir, tool string, args ...string) (string, error) {
	run := s.git
	if run == nil {
		run = realGitRunner
	}
	return run(workdir, tool, args...)
}

// ── parsers (mirror GitClient.swift, exercised by tests) ──────────────────

func parseGitStatus(output string) gitStatusResult {
	res := gitStatusResult{Branch: "HEAD", Changes: []gitFileChange{}}
	for _, line := range strings.Split(output, "\n") {
		if strings.HasPrefix(line, "## ") {
			res.Branch, res.Upstream, res.Ahead, res.Behind = parseBranchLine(line[3:])
		} else if len(line) >= 3 {
			code := line[:2]
			path := line[3:]
			if arrow := strings.Index(path, " -> "); arrow >= 0 {
				path = path[arrow+4:]
			}
			x := code[0]
			res.Changes = append(res.Changes, gitFileChange{
				Path:   path,
				Code:   code,
				Staged: x != ' ' && x != '?',
			})
		}
	}
	return res
}

func parseBranchLine(line string) (branch, upstream string, ahead, behind int) {
	branch = "HEAD"
	rest := line
	if bracket := strings.Index(rest, " ["); bracket >= 0 {
		tracking := strings.TrimSuffix(rest[bracket+2:], "]")
		for _, tok := range strings.Split(tracking, ",") {
			parts := strings.Fields(tok)
			if len(parts) != 2 {
				continue
			}
			n, err := strconv.Atoi(parts[1])
			if err != nil {
				continue
			}
			switch parts[0] {
			case "ahead":
				ahead = n
			case "behind":
				behind = n
			}
		}
		rest = rest[:bracket]
	}
	if sep := strings.Index(rest, "..."); sep >= 0 {
		branch = rest[:sep]
		upstream = rest[sep+3:]
		return branch, upstream, ahead, behind
	}
	return strings.TrimSpace(rest), "", ahead, behind
}

func parseNameStatus(output string) []gitChangedFile {
	var files []gitChangedFile
	for _, line := range strings.Split(output, "\n") {
		parts := strings.Split(line, "\t")
		if len(parts) < 2 {
			continue
		}
		code := strings.TrimSpace(parts[0])
		path := parts[len(parts)-1] // rename: take the new path
		status := "modified"
		switch {
		case strings.HasPrefix(code, "A"):
			status = "added"
		case strings.HasPrefix(code, "D"):
			status = "deleted"
		case strings.HasPrefix(code, "R"):
			status = "renamed"
		}
		files = append(files, gitChangedFile{Path: path, Status: status})
	}
	return files
}

// ── RPC handlers ──────────────────────────────────────────────────────────

func (s *server) gitStatus(workdir string) (gitStatusResult, error) {
	out, err := s.gitRun(workdir, "git", "status", "--porcelain=v1", "-b")
	if err != nil {
		return gitStatusResult{}, err
	}
	return parseGitStatus(out), nil
}

func (s *server) gitDiff(workdir, path string, staged bool) (string, error) {
	args := []string{"--no-pager", "diff"}
	if staged {
		args = append(args, "--cached")
	}
	if path != "" {
		args = append(args, "--", path)
	}
	return s.gitRun(workdir, "git", args...)
}

func (s *server) gitChangedFiles(workdir, baseBranch, branch string) ([]gitChangedFile, error) {
	args := []string{"diff", "--name-status"}
	if baseBranch != "" {
		args = append(args, baseBranch)
	}
	if branch != "" {
		args = append(args, branch)
	}
	out, err := s.gitRun(workdir, "git", args...)
	if err != nil {
		return nil, err
	}
	return parseNameStatus(out), nil
}

func (s *server) currentBranch(workdir string) (string, error) {
	out, err := s.gitRun(workdir, "git", "rev-parse", "--abbrev-ref", "HEAD")
	return strings.TrimSpace(out), err
}

// ── clone (Add Workspace → From GitHub Repo) ──────────────────────────────

type gitCloneResult struct {
	Path   string `json:"path"`   // absolute clone destination on the host
	Branch string `json:"branch"` // checked-out branch after clone
}

// validateRepoURL accepts only the git remote forms we expect from the phone:
// https(s)://, ssh://, or scp-style user@host:path. It rejects anything that
// looks like a local path or a flag so a caller can't smuggle `--upload-pack`
// or a filesystem path into the clone argv.
func validateRepoURL(repo string) error {
	repo = strings.TrimSpace(repo)
	if repo == "" {
		return errors.New("repo URL required")
	}
	if strings.HasPrefix(repo, "-") {
		return errors.New("invalid repo URL")
	}
	switch {
	case strings.HasPrefix(repo, "https://"), strings.HasPrefix(repo, "http://"),
		strings.HasPrefix(repo, "ssh://"):
		return nil
	case strings.Contains(repo, "@") && strings.Contains(repo, ":"):
		return nil // scp-style: git@github.com:owner/repo.git
	default:
		return errors.New("repo must be an https or ssh git URL")
	}
}

// repoDirName derives the destination directory name from a clone URL, mirroring
// git's own default (the last path segment minus a trailing ".git").
func repoDirName(repo string) string {
	repo = strings.TrimRight(strings.TrimSpace(repo), "/")
	repo = strings.TrimSuffix(repo, ".git")
	if i := strings.LastIndexAny(repo, "/:"); i >= 0 {
		repo = repo[i+1:]
	}
	return repo
}

// gitClone clones repo into parentDir using the host's existing git/credential
// configuration (HTTPS token cache, gh, or SSH key) — Lancer adds no auth of
// its own. parentDir is confined to the user's home; the derived directory name
// is sanitized so it can't traverse out of it.
func (s *server) gitClone(repo, parentDir, name string) (gitCloneResult, error) {
	if err := validateRepoURL(repo); err != nil {
		return gitCloneResult{}, err
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return gitCloneResult{}, err
	}
	parent := expandHome(parentDir)
	if parent == "" {
		parent = home
	}
	if !filepath.IsAbs(parent) {
		parent = filepath.Join(home, parent)
	}
	parent = filepath.Clean(parent)
	if !withinHome(home, parent) {
		return gitCloneResult{}, errors.New("destination is outside the home directory")
	}

	dirName := strings.TrimSpace(name)
	if dirName == "" {
		dirName = repoDirName(repo)
	}
	// A directory name only — no separators, no traversal.
	if dirName == "" || strings.ContainsAny(dirName, "/\\") || strings.Contains(dirName, "..") {
		return gitCloneResult{}, errors.New("invalid destination name")
	}
	dest := filepath.Join(parent, dirName)
	if _, err := os.Stat(dest); err == nil {
		return gitCloneResult{}, fmt.Errorf("%s already exists", dirName)
	}

	// Explicit argv, run in parentDir. `--` terminates options so the URL can
	// never be parsed as a flag.
	if _, err := s.gitRun(parent, "git", "clone", "--", repo, dirName); err != nil {
		return gitCloneResult{}, err
	}
	branch, _ := s.currentBranch(dest)
	return gitCloneResult{Path: dest, Branch: branch}, nil
}

// gitShip stages + commits + pushes the worktree, then optionally opens a PR.
//
// IDEMPOTENT on partial failure: each stage checks whether its work is already
// done before re-running, so a retry after "commit ok, push failed" only retries
// the push + PR — it does not error on "nothing to commit" or create a duplicate
// PR. The result reports exactly which stages completed so the phone can surface
// a precise state and safely retry.
func (s *server) gitShip(p shipParams) (gitShipResult, error) {
	var res gitShipResult

	// 1. Detect whether there is anything to commit (working tree + index).
	status, err := s.gitStatus(p.Workdir)
	if err != nil {
		return res, err
	}

	if len(status.Changes) > 0 {
		// Stage everything, then commit. `git add -A` is a no-op when clean.
		if _, err := s.gitRun(p.Workdir, "git", "add", "-A"); err != nil {
			return res, fmt.Errorf("stage failed: %w", err)
		}
		if _, err := s.gitRun(p.Workdir, "git", "commit", "-m", p.Message); err != nil {
			// "nothing to commit" can happen on a retry race — treat as already-committed.
			if isNothingToCommit(err) {
				res.Committed = true
			} else {
				return res, fmt.Errorf("commit failed: %w", err)
			}
		} else {
			res.Committed = true
		}
	} else {
		// Nothing in the working tree: the commit either already happened on a prior
		// (partially failed) ship, or there was never anything to ship. Either way the
		// HEAD is what we push — mark committed so a retry proceeds to push/PR.
		res.Committed = true
	}

	// 2. Push (idempotent — pushing an up-to-date branch is a no-op success).
	branch, err := s.currentBranch(p.Workdir)
	if err != nil {
		return res, fmt.Errorf("resolve branch failed: %w", err)
	}
	if _, err := s.gitRun(p.Workdir, "git", "push", "--set-upstream", "origin", branch); err != nil {
		res.Message = "push failed (branch may be behind — rebase on the host): " + err.Error()
		return res, nil // partial success: committed but not pushed; safe to retry.
	}
	res.Pushed = true

	// 3. Open a PR via gh, when requested. A pre-existing PR for the branch is
	//    reported as success (gh prints the existing URL), keeping ship idempotent.
	if p.OpenPR {
		url, prErr := s.openPR(p, branch)
		if prErr != nil {
			res.Message = prErr.Error()
			return res, nil // committed + pushed; PR failed — retryable, not fatal.
		}
		res.PRURL = url
	}
	return res, nil
}

// openPR runs `gh pr create` (or returns an existing PR's URL). Auth failures
// surface a clear, actionable message pointing at the lancer doctor gh check —
// they never hard-error the whole ship (commit + push already succeeded).
func (s *server) openPR(p shipParams, branch string) (string, error) {
	args := []string{"pr", "create", "--title", p.Title, "--body", p.Body}
	if p.Base != "" {
		args = append(args, "--base", p.Base)
	}
	out, err := s.gitRun(p.Workdir, "gh", args...)
	if err != nil {
		low := strings.ToLower(out + " " + err.Error())
		switch {
		case strings.Contains(low, "already exists") || strings.Contains(low, "a pull request for branch"):
			// PR already open for this branch — recover its URL (idempotent ship).
			if url, vErr := s.gitRun(p.Workdir, "gh", "pr", "view", branch, "--json", "url", "-q", ".url"); vErr == nil {
				return strings.TrimSpace(url), nil
			}
			return "", nil
		case strings.Contains(low, "executable file not found"),
			strings.Contains(low, "not found") && strings.Contains(low, "gh:"):
			return "", errors.New("GitHub CLI (gh) is not installed on the host — run `lancer doctor` and install gh to open PRs")
		case strings.Contains(low, "auth") || strings.Contains(low, "gh_token") || strings.Contains(low, "login"):
			return "", errors.New("GitHub CLI (gh) is not authenticated on the host — run `gh auth login` (or set GH_TOKEN); see `lancer doctor`")
		default:
			return "", errors.New("gh pr create failed: " + strings.TrimSpace(out))
		}
	}
	// gh prints the PR URL on the last http line.
	lines := strings.Split(out, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if strings.Contains(line, "http") {
			return line, nil
		}
	}
	return strings.TrimSpace(out), nil
}

func isNothingToCommit(err error) bool {
	var ce *gitCmdError
	if errors.As(err, &ce) {
		low := strings.ToLower(ce.output)
		return strings.Contains(low, "nothing to commit") || strings.Contains(low, "no changes added")
	}
	return false
}

type shipParams struct {
	Workdir string `json:"workdir"`
	Message string `json:"message"`
	OpenPR  bool   `json:"openPR"`
	Base    string `json:"base"`
	Title   string `json:"title"`
	Body    string `json:"body"`
}

// ── worktree listing ────────────────────────────────────────────────────────

type worktreeResult struct {
	ID           string           `json:"id"`
	RepoName     string           `json:"repoName"`
	Branch       string           `json:"branch"`
	Path         string           `json:"path"`
	Status       string           `json:"status"`
	Managed      bool             `json:"managed"`
	ChangedFiles []gitChangedFile `json:"changedFiles"`
	LastActivity string           `json:"lastActivity"`
}

type worktreeCreateParams struct {
	Workdir string `json:"workdir"`
	Branch  string `json:"branch,omitempty"`
	ID      string `json:"id,omitempty"`
}

type worktreeCreateResult struct {
	ID       string `json:"id"`
	Path     string `json:"path"`
	Branch   string `json:"branch"`
	Managed  bool   `json:"managed"`
	RepoRoot string `json:"repoRoot,omitempty"`
}

type worktreeRemoveParams struct {
	Workdir string `json:"workdir"`
	Path    string `json:"path"`
}

type worktreeRemoveResult struct {
	Removed bool `json:"removed"`
}

// managedWorktreesRoot is where lancerd creates per-run isolated checkouts
// (~/.lancer/worktrees/<repo>/<id>). Distinct from vendor scratch dirs like
// .claude/worktrees/ — these are daemon-owned and removable via agent.worktree.remove.
func managedWorktreesRoot(home string) string {
	return filepath.Join(home, ".lancer", "worktrees")
}

func isManagedWorktree(home, path string) bool {
	root := filepath.Clean(managedWorktreesRoot(home))
	path = filepath.Clean(expandHome(path))
	return path == root || strings.HasPrefix(path, root+string(os.PathSeparator))
}

func sanitizeWorktreeID(id string) (string, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return strings.ReplaceAll(newUUID(), "-", ""), nil
	}
	for _, r := range id {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_' {
			return "", errors.New("invalid worktree id")
		}
	}
	return id, nil
}

func (s *server) repoRoot(workdir string) (string, error) {
	out, err := s.gitRun(expandHome(workdir), "git", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// createManagedWorktree runs `git worktree add` into ~/.lancer/worktrees/<repo>/<id>.
// workdir may be any path inside the repo; branch defaults to lancer/run-<id>.
func (s *server) createManagedWorktree(workdir, branch, id string) (worktreeCreateResult, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return worktreeCreateResult{}, err
	}
	workdir = expandHome(workdir)
	if workdir == "" {
		return worktreeCreateResult{}, errors.New("workdir required")
	}
	repoRoot, err := s.repoRoot(workdir)
	if err != nil {
		return worktreeCreateResult{}, fmt.Errorf("not a git repo: %w", err)
	}
	if !withinHome(home, repoRoot) {
		return worktreeCreateResult{}, errors.New("repo is outside the home directory")
	}

	wtID, err := sanitizeWorktreeID(id)
	if err != nil {
		return worktreeCreateResult{}, err
	}
	dest := filepath.Join(managedWorktreesRoot(home), filepath.Base(repoRoot), wtID)
	if !withinHome(home, dest) {
		return worktreeCreateResult{}, errors.New("managed worktree path escapes home")
	}
	if _, err := os.Stat(dest); err == nil {
		return worktreeCreateResult{}, fmt.Errorf("worktree %s already exists", wtID)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0700); err != nil {
		return worktreeCreateResult{}, err
	}

	if branch == "" {
		short := wtID
		if len(short) > 8 {
			short = short[:8]
		}
		branch = "lancer/run-" + short
	}
	if _, err := s.gitRun(repoRoot, "git", "worktree", "add", "-b", branch, dest); err != nil {
		return worktreeCreateResult{}, err
	}
	return worktreeCreateResult{
		ID: wtID, Path: dest, Branch: branch, Managed: true, RepoRoot: repoRoot,
	}, nil
}

// removeManagedWorktree deletes a daemon-managed checkout. Only paths under
// ~/.lancer/worktrees are accepted — never arbitrary worktrees the owner created.
func (s *server) removeManagedWorktree(workdir, path string) (worktreeRemoveResult, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return worktreeRemoveResult{}, err
	}
	path = filepath.Clean(expandHome(path))
	if path == "" {
		return worktreeRemoveResult{}, errors.New("path required")
	}
	if !isManagedWorktree(home, path) {
		return worktreeRemoveResult{}, errors.New("refusing to remove non-managed worktree")
	}
	repoRoot, err := s.repoRoot(workdir)
	if err != nil {
		repoRoot, err = s.repoRoot(path)
		if err != nil {
			return worktreeRemoveResult{}, err
		}
	}
	if _, err := s.gitRun(repoRoot, "git", "worktree", "remove", "--force", path); err != nil {
		return worktreeRemoveResult{}, err
	}
	_ = os.Remove(filepath.Dir(path))
	return worktreeRemoveResult{Removed: true}, nil
}

// listWorktrees parses `git worktree list --porcelain` for workdir's repo and
// annotates each with its branch + dirty/clean status. workdir may be any path
// inside the repo. A supervision board view — not a worktree manager.
func (s *server) listWorktrees(workdir string, managedOnly bool) ([]worktreeResult, error) {
	out, err := s.gitRun(workdir, "git", "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	home, _ := os.UserHomeDir()
	repoName := ""
	if name, nErr := s.gitRun(workdir, "git", "rev-parse", "--show-toplevel"); nErr == nil {
		parts := strings.Split(strings.TrimSpace(name), "/")
		if len(parts) > 0 {
			repoName = parts[len(parts)-1]
		}
	}

	var trees []worktreeResult
	var cur *worktreeResult
	flush := func() {
		if cur == nil {
			return
		}
		// Annotate dirty/clean from a per-worktree status.
		st, sErr := s.gitStatus(cur.Path)
		if sErr == nil {
			cur.Branch = st.Branch
			if len(st.Changes) > 0 {
				cur.Status = "active"
				cur.ChangedFiles = []gitChangedFile{}
				for _, c := range st.Changes {
					cur.ChangedFiles = append(cur.ChangedFiles, gitChangedFile{Path: c.Path, Status: "modified"})
				}
			} else {
				cur.Status = "idle"
			}
		}
		cur.Managed = isManagedWorktree(home, cur.Path)
		if managedOnly && !cur.Managed {
			cur = nil
			return
		}
		trees = append(trees, *cur)
		cur = nil
	}
	for _, line := range strings.Split(out, "\n") {
		switch {
		case strings.HasPrefix(line, "worktree "):
			flush()
			path := strings.TrimPrefix(line, "worktree ")
			cur = &worktreeResult{
				ID:           path,
				RepoName:     repoName,
				Path:         path,
				Status:       "idle",
				ChangedFiles: []gitChangedFile{},
				LastActivity: time.Now().UTC().Format(time.RFC3339),
			}
		case strings.HasPrefix(line, "branch ") && cur != nil:
			cur.Branch = strings.TrimPrefix(strings.TrimPrefix(line, "branch "), "refs/heads/")
		}
	}
	flush()
	return trees, nil
}

// ── CI proxy (bridge push-backend webhook ring buffer → lancerd) ───────────

// recentCIEvents proxies GET /webhooks/recent on the registered push-backend so
// the iOS app's agent.ci.recent call returns the real GitHub webhook events the
// backend has buffered. Returns an empty slice (never an error) when no device /
// backend is registered, so the run/loop detail degrades gracefully.
func (s *server) recentCIEvents(repo string, limit int) ([]CIEvent, error) {
	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev == nil || dev.PushBackendURL == "" || repo == "" {
		return []CIEvent{}, nil
	}
	if limit <= 0 {
		limit = 50
	}
	url := fmt.Sprintf("%s/webhooks/recent?repo=%s&limit=%d",
		strings.TrimRight(dev.PushBackendURL, "/"), repo, limit)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return []CIEvent{}, nil // backend unreachable — degrade, don't fail the detail view.
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return []CIEvent{}, nil
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return []CIEvent{}, nil
	}
	var events []CIEvent
	if err := json.Unmarshal(body, &events); err != nil {
		return []CIEvent{}, nil
	}
	// Normalize the webhook type/status vocabulary to the Swift CIEvent raw values
	// (the phone decodes these into Codable enums — a mismatch drops the whole
	// array). push-backend emits "pr"/"check_run"; Swift expects
	// "pullRequest"/"checkRun".
	for i := range events {
		events[i].Type = normalizeCIType(events[i].Type)
		events[i].Status = normalizeCIStatus(events[i].Status)
	}
	return events, nil
}

func normalizeCIType(t string) string {
	switch t {
	case "pr", "pull_request", "pullRequest":
		return "pullRequest"
	case "check_run", "checkRun":
		return "checkRun"
	default:
		return "status"
	}
}

func normalizeCIStatus(s string) string {
	switch strings.ToLower(s) {
	case "success", "passed", "completed":
		return "success"
	case "failure", "failed", "error":
		if strings.ToLower(s) == "error" {
			return "error"
		}
		return "failure"
	case "pending", "queued", "in_progress", "":
		return "pending"
	default:
		return "pending"
	}
}

// CIEvent mirrors push-backend/webhooks.go CIEvent — the JSON shape the phone's
// LancerCore.CIEvent decodes. Type values: "pr" | "check_run" | "status" map to
// the Swift CIEvent.EventType (pullRequest | checkRun | status) on the client.
type CIEvent struct {
	ID        string    `json:"id"`
	Repo      string    `json:"repo"`
	Type      string    `json:"type"`
	Action    string    `json:"action"`
	PRNumber  int       `json:"prNumber,omitempty"`
	PRTitle   string    `json:"prTitle,omitempty"`
	PRURL     string    `json:"prURL,omitempty"`
	Status    string    `json:"status"`
	Context   string    `json:"context,omitempty"`
	Message   string    `json:"message,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}
