package main

import (
	"bufio"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// DriftFinding is one reference in an agent instruction file that no longer
// resolves to a file on disk — "drift between the doc and the repo state".
type DriftFinding struct {
	File    string `json:"file"` // path relative to the scan root
	Line    int    `json:"line"`
	Kind    string `json:"kind"` // "dead-import" | "dead-link"
	Ref     string `json:"ref"`  // the referenced path as written
	Message string `json:"message"`
}

// DriftReport is the result of one scan over a repo's instruction topology.
type DriftReport struct {
	Root     string         `json:"root"`
	Scanned  int            `json:"scanned"` // instruction files read
	Findings []DriftFinding `json:"findings"`
}

var driftIgnoreDirs = map[string]bool{
	".git": true, "node_modules": true, "build": true, ".build": true,
	"DerivedData": true, "SourcePackages": true, "Pods": true,
	".worktrees": true, "worktrees": true, "vendor": true,
}

// instruction-file basenames the agents actually load (Claude, Codex, Gemini, Kimi, skills).
var driftInstructionNames = map[string]bool{
	"CLAUDE.md": true, "AGENTS.md": true, "GEMINI.md": true,
	"KIMI.md": true, "SKILL.md": true,
}

// @import: an `@path` not preceded by a word char (so emails like a@b.com are
// excluded), capturing a path-like token. Post-filtered to doc extensions below.
var driftImportRe = regexp.MustCompile(`(?:^|[^\w@/])@([A-Za-z0-9_./~-]+)`)

// markdown link target: [text](target)
var driftLinkRe = regexp.MustCompile(`\[[^\]]*\]\(([^)\s]+)\)`)

var driftImportExts = map[string]bool{".md": true, ".markdown": true, ".txt": true}

// scanDrift walks root, reads every agent instruction file, and reports
// references (imports + markdown links) that point at files which do not exist.
func scanDrift(root string) (DriftReport, error) {
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return DriftReport{}, err
	}
	report := DriftReport{Root: absRoot, Findings: []DriftFinding{}}

	// ponytail: bound the traversal so a caller that passes an empty root (the
	// daemon's cwd could be `/`) can't walk the whole filesystem. Raise if a
	// real repo legitimately exceeds it.
	const maxDriftDirs = 20000
	dirsSeen := 0

	walkErr := filepath.WalkDir(absRoot, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil // skip unreadable entries rather than abort the whole scan
		}
		if d.IsDir() {
			if path != absRoot && driftIgnoreDirs[d.Name()] {
				return filepath.SkipDir
			}
			dirsSeen++
			if dirsSeen > maxDriftDirs {
				return filepath.SkipAll
			}
			return nil
		}
		if !isInstructionFile(path) {
			return nil
		}
		report.Scanned++
		report.Findings = append(report.Findings, scanInstructionFile(path, absRoot)...)
		return nil
	})
	return report, walkErr
}

func isInstructionFile(path string) bool {
	if driftInstructionNames[filepath.Base(path)] {
		return true
	}
	// .claude/rules/*.md are path-scoped instruction files too.
	return strings.Contains(filepath.ToSlash(path), "/.claude/rules/") &&
		strings.EqualFold(filepath.Ext(path), ".md")
}

func scanInstructionFile(path, root string) []DriftFinding {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	rel, err := filepath.Rel(root, path)
	if err != nil {
		rel = path
	}
	dir := filepath.Dir(path)

	var findings []DriftFinding
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := scanner.Text()

		for _, m := range driftImportRe.FindAllStringSubmatch(line, -1) {
			ref := strings.TrimRight(m[1], ".,;:)")
			if !driftImportExts[strings.ToLower(filepath.Ext(ref))] {
				continue // only doc imports; skips @decorators, @handles, etc.
			}
			if target, ok := resolveDriftRef(ref, dir, root); ok && !fileExists(target) {
				findings = append(findings, DriftFinding{
					File: rel, Line: lineNo, Kind: "dead-import", Ref: ref,
					Message: "imported file does not exist",
				})
			}
		}

		for _, m := range driftLinkRe.FindAllStringSubmatch(line, -1) {
			if target, ok := resolveDriftRef(m[1], dir, root); ok && !fileExists(target) {
				findings = append(findings, DriftFinding{
					File: rel, Line: lineNo, Kind: "dead-link", Ref: m[1],
					Message: "linked file does not exist",
				})
			}
		}
	}
	return findings
}

// resolveDriftRef returns an absolute target path and true only when the ref is
// a local path that lives inside root (so we never flag external URLs, anchors,
// or home/absolute paths outside the repo we can't assess).
func resolveDriftRef(ref, fileDir, root string) (string, bool) {
	ref = strings.TrimSpace(ref)
	if i := strings.IndexAny(ref, "#?"); i >= 0 {
		ref = ref[:i]
	}
	if ref == "" || strings.Contains(ref, "://") || strings.HasPrefix(ref, "mailto:") || strings.HasPrefix(ref, "~") {
		return "", false
	}
	var p string
	if filepath.IsAbs(ref) {
		p = filepath.Clean(ref)
	} else {
		p = filepath.Clean(filepath.Join(fileDir, ref))
	}
	relToRoot, err := filepath.Rel(root, p)
	if err != nil || relToRoot == ".." || strings.HasPrefix(relToRoot, ".."+string(filepath.Separator)) {
		return "", false
	}
	return p, true
}
