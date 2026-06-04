package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"conduit/conduitd/policy"
)

// BlastRadius describes scope of an escalated approval (wire + Swift ApprovalBlastRadius).
type BlastRadius struct {
	Files          []string `json:"files,omitempty"`
	TouchesGit     bool     `json:"touchesGit,omitempty"`
	TouchesNetwork bool     `json:"touchesNetwork,omitempty"`
	MatchedRule    string   `json:"matchedRule,omitempty"`
}

func computeBlastRadius(event ApprovalEvent, matchedRule string) BlastRadius {
	br := BlastRadius{MatchedRule: matchedRule}
	if event.Kind == "network" {
		br.TouchesNetwork = true
	}
	if touchesGitCommand(event.Command) {
		br.TouchesGit = true
	}
	paths := policy.ExtractPaths(event.Command, event.CWD, event.ToolInput)
	br.Files = gitStatusFiles(event.CWD, paths)
	if len(br.Files) > 0 {
		br.TouchesGit = true
	}
	if len(paths) > 0 && len(br.Files) == 0 {
		br.Files = uniqueStrings(paths, 20)
	}
	return br
}

func touchesGitCommand(cmd string) bool {
	c := strings.ToLower(cmd)
	for _, g := range []string{"git commit", "git push", "git reset", "git checkout", "git merge", "git rebase", "git add"} {
		if strings.Contains(c, g) {
			return true
		}
	}
	return false
}

func gitStatusFiles(cwd string, hints []string) []string {
	if cwd == "" {
		return nil
	}
	if _, err := os.Stat(filepath.Join(cwd, ".git")); err != nil {
		return nil
	}
	out, err := exec.Command("git", "-C", cwd, "status", "--porcelain").Output()
	if err != nil {
		return nil
	}
	var files []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if len(line) < 4 {
			continue
		}
		p := strings.TrimSpace(line[3:])
		if p != "" {
			files = append(files, filepath.ToSlash(p))
		}
	}
	if len(files) == 0 && len(hints) > 0 {
		return uniqueStrings(hints, 20)
	}
	return uniqueStrings(files, 30)
}

func uniqueStrings(in []string, max int) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		s = filepath.ToSlash(strings.TrimSpace(s))
		if s == "" || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
		if len(out) >= max {
			break
		}
	}
	return out
}
