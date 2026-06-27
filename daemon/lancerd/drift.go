package main

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Drift remediation kinds. Mirrors LancerCore.DriftRemediation.
const (
	driftRemediateApplyFix     = "apply-fix"     // daemon can safely & idempotently repair in place
	driftRemediateCreatePolicy = "create-policy" // resolve by authoring a policy (client-side)
	driftRemediateManual       = "manual"        // no safe automatic action
)

// DriftFinding is one reference in an agent instruction file that no longer
// resolves to a file on disk — "drift between the doc and the repo state".
type DriftFinding struct {
	File        string `json:"file"` // path relative to the scan root
	Line        int    `json:"line"`
	Kind        string `json:"kind"` // "dead-import" | "dead-link"
	Ref         string `json:"ref"`  // the referenced path as written
	Message     string `json:"message"`
	Remediation string `json:"remediation"` // "apply-fix" | "create-policy" | "manual"
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
					Message:     "imported file does not exist",
					Remediation: driftRemediateApplyFix,
				})
			}
		}

		for _, m := range driftLinkRe.FindAllStringSubmatch(line, -1) {
			if target, ok := resolveDriftRef(m[1], dir, root); ok && !fileExists(target) {
				findings = append(findings, DriftFinding{
					File: rel, Line: lineNo, Kind: "dead-link", Ref: m[1],
					Message:     "linked file does not exist",
					Remediation: driftRemediateApplyFix,
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

// DriftRemediateRequest names one finding to repair within a scan root.
type DriftRemediateRequest struct {
	Root string `json:"root"`
	File string `json:"file"` // path relative to root, as reported by the scan
	Line int    `json:"line"`
	Kind string `json:"kind"`
	Ref  string `json:"ref"`
}

// remediateDrift applies the only safe, in-place fix for a dead reference:
// it comments out the offending line in the instruction file so the broken
// `@import` / markdown link no longer misleads an agent, leaving a marker the
// human can act on. It is fail-closed (every precondition must hold or it
// errors without writing) and idempotent (an already-commented line is a no-op
// success). It returns a fresh scan of the root so callers see updated state.
//
// Confined to instruction files inside root; never executes a shell.
func remediateDrift(req DriftRemediateRequest) (DriftReport, error) {
	root := strings.TrimSpace(req.Root)
	if root == "" {
		root, _ = os.Getwd()
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return DriftReport{}, fmt.Errorf("resolve root: %w", err)
	}

	// Resolve the target file strictly inside root — reject traversal.
	relClean := filepath.Clean(filepath.FromSlash(req.File))
	if relClean == "." || filepath.IsAbs(relClean) ||
		relClean == ".." || strings.HasPrefix(relClean, ".."+string(filepath.Separator)) {
		return DriftReport{}, fmt.Errorf("drift: invalid file path %q", req.File)
	}
	target := filepath.Join(absRoot, relClean)
	relCheck, err := filepath.Rel(absRoot, target)
	if err != nil || relCheck == ".." || strings.HasPrefix(relCheck, ".."+string(filepath.Separator)) {
		return DriftReport{}, fmt.Errorf("drift: file escapes root")
	}
	if !isInstructionFile(target) {
		return DriftReport{}, fmt.Errorf("drift: %q is not a remediable instruction file", req.File)
	}
	if req.Line < 1 {
		return DriftReport{}, fmt.Errorf("drift: invalid line %d", req.Line)
	}

	data, err := os.ReadFile(target)
	if err != nil {
		return DriftReport{}, fmt.Errorf("read %s: %w", req.File, err)
	}
	// Preserve trailing-newline shape.
	hadTrailingNewline := strings.HasSuffix(string(data), "\n")
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if req.Line > len(lines) {
		return DriftReport{}, fmt.Errorf("drift: line %d out of range (%d lines)", req.Line, len(lines))
	}

	idx := req.Line - 1
	orig := lines[idx]
	const marker = "<!-- lancer: removed dead reference"

	// Idempotent: if we already neutralised this line, succeed without writing.
	if strings.Contains(orig, marker) {
		return scanDrift(absRoot)
	}
	// Fail-closed: the line must still contain the ref we were asked to fix,
	// so a stale request can't blank out an unrelated (edited) line.
	if req.Ref == "" || !strings.Contains(orig, req.Ref) {
		return DriftReport{}, fmt.Errorf("drift: line %d no longer contains ref %q (re-scan needed)", req.Line, req.Ref)
	}

	// Defang the original so the comment can't itself re-trigger the scanner:
	// strip the `@` import sigil and flatten markdown-link brackets, both of
	// which the scan regexes key on.
	defanged := strings.NewReplacer("@", "", "[", "(", "]", ")").Replace(strings.TrimSpace(orig))
	lines[idx] = fmt.Sprintf("%s %q (was: %s) -->", marker, req.Ref, defanged)

	out := strings.Join(lines, "\n")
	if hadTrailingNewline {
		out += "\n"
	}
	info, statErr := os.Stat(target)
	mode := fs.FileMode(0o644)
	if statErr == nil {
		mode = info.Mode().Perm()
	}
	if err := os.WriteFile(target, []byte(out), mode); err != nil {
		return DriftReport{}, fmt.Errorf("write %s: %w", req.File, err)
	}

	return scanDrift(absRoot)
}
