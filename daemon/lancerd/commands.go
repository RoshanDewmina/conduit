package main

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// agentCommand is one slash-command available to an agent in a given workspace:
// a project/user custom command, a skill, or a curated built-in. Surfaced to the
// phone composer's "/" autocomplete via the agent.commands.list RPC.
type agentCommand struct {
	Name        string `json:"name"`        // "/review"
	Description string `json:"description"` // one-line summary
	Source      string `json:"source"`      // "project" | "user" | "builtin"
	Kind        string `json:"kind"`        // "command" | "skill" | "builtin"
}

// listAgentCommands enumerates the slash-commands available for a vendor in cwd.
// It scans the on-disk command/skill directories (no shelling out) and merges a
// curated built-in list. Project entries win over user entries of the same name.
func listAgentCommands(cwd, vendor string) []agentCommand {
	home, _ := os.UserHomeDir()
	root := expandHome(cwd)

	byName := map[string]agentCommand{}
	add := func(c agentCommand) {
		// Project overrides user overrides builtin; first writer of a higher
		// precedence wins. We add in precedence order, so only fill if absent.
		if _, ok := byName[c.Name]; !ok {
			byName[c.Name] = c
		}
	}

	switch vendor {
	case "claudeCode", "claude", "":
		// Precedence: project commands → project skills → user commands → user skills.
		scanCommandDir(filepath.Join(root, ".claude", "commands"), "project", add)
		scanSkillDir(filepath.Join(root, ".claude", "skills"), "project", add)
		if home != "" {
			scanCommandDir(filepath.Join(home, ".claude", "commands"), "user", add)
			scanSkillDir(filepath.Join(home, ".claude", "skills"), "user", add)
		}
		for _, b := range claudeBuiltins {
			add(b)
		}
	case "codex":
		scanCommandDir(filepath.Join(root, ".codex", "prompts"), "project", add)
		if home != "" {
			scanCommandDir(filepath.Join(home, ".codex", "prompts"), "user", add)
			scanSkillDir(filepath.Join(home, ".codex", "skills"), "user", add)
		}
		for _, b := range codexBuiltins {
			add(b)
		}
	default:
		// opencode / kimi / unknown: still surface project .claude commands if any,
		// plus a minimal built-in set, so the composer isn't empty.
		scanCommandDir(filepath.Join(root, ".claude", "commands"), "project", add)
		for _, b := range genericBuiltins {
			add(b)
		}
	}

	out := make([]agentCommand, 0, len(byName))
	for _, c := range byName {
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool {
		// builtins last, then alphabetical.
		if (out[i].Kind == "builtin") != (out[j].Kind == "builtin") {
			return out[j].Kind == "builtin"
		}
		return out[i].Name < out[j].Name
	})
	return out
}

// scanCommandDir adds every *.md in dir as a "/name" command. Precedence between
// dirs is handled by add() (first writer of a name wins).
func scanCommandDir(dir, source string, add func(agentCommand)) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".md")
		add(agentCommand{
			Name:        "/" + name,
			Description: firstMarkdownDescription(filepath.Join(dir, e.Name())),
			Source:      source,
			Kind:        "command",
		})
	}
}

// scanSkillDir adds every subdirectory containing a SKILL.md as a "/name" skill.
func scanSkillDir(dir, source string, add func(agentCommand)) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		skillFile := filepath.Join(dir, e.Name(), "SKILL.md")
		if _, err := os.Stat(skillFile); err != nil {
			continue
		}
		add(agentCommand{
			Name:        "/" + e.Name(),
			Description: firstMarkdownDescription(skillFile),
			Source:      source,
			Kind:        "skill",
		})
	}
}

// firstMarkdownDescription returns a one-line summary for a command/skill file:
// the YAML frontmatter `description:` if present, else the first non-blank,
// non-heading line. Empty string if neither exists.
func firstMarkdownDescription(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	inFrontmatter := false
	captureFolded := false // saw `description: >-`/`|`; grab the next line's text
	var firstProse string
	lineNum := 0
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		lineNum++
		if lineNum == 1 && line == "---" {
			inFrontmatter = true
			continue
		}
		if inFrontmatter {
			if captureFolded {
				if line == "" {
					continue
				}
				if line == "---" {
					return ""
				}
				return clip(line)
			}
			if line == "---" {
				inFrontmatter = false
				continue
			}
			if rest, ok := strings.CutPrefix(line, "description:"); ok {
				val := strings.TrimSpace(rest)
				// YAML block scalars (`>`, `>-`, `|`, `|-`) put the text on the
				// following indented line(s) — grab the first of those instead.
				if val == "" || val == ">" || val == ">-" || val == "|" || val == "|-" {
					captureFolded = true
					continue
				}
				return clip(strings.Trim(val, `"'`))
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if firstProse == "" {
			firstProse = line
			break
		}
	}
	return clip(firstProse)
}

// clip truncates a description to a one-line-friendly length.
func clip(s string) string {
	if len(s) > 140 {
		return s[:140] + "…"
	}
	return s
}

// Curated built-ins. These are informational in Lancer's headless dispatch model
// (the phone shows them so the user knows they exist); custom commands/skills are
// the ones actually invoked by prompt text.
var claudeBuiltins = []agentCommand{
	{Name: "/clear", Description: "Clear conversation history", Source: "builtin", Kind: "builtin"},
	{Name: "/compact", Description: "Summarize and compact the context", Source: "builtin", Kind: "builtin"},
	{Name: "/model", Description: "Switch the model", Source: "builtin", Kind: "builtin"},
	{Name: "/review", Description: "Review the current changes", Source: "builtin", Kind: "builtin"},
	{Name: "/init", Description: "Initialize project context (CLAUDE.md)", Source: "builtin", Kind: "builtin"},
}

var codexBuiltins = []agentCommand{
	{Name: "/clear", Description: "Clear conversation history", Source: "builtin", Kind: "builtin"},
	{Name: "/model", Description: "Switch the model", Source: "builtin", Kind: "builtin"},
	{Name: "/approvals", Description: "Change the approval mode", Source: "builtin", Kind: "builtin"},
}

var genericBuiltins = []agentCommand{
	{Name: "/clear", Description: "Clear conversation history", Source: "builtin", Kind: "builtin"},
	{Name: "/model", Description: "Switch the model", Source: "builtin", Kind: "builtin"},
}
