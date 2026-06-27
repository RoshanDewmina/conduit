package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestListAgentCommands_ScansProjectCommandsAndSkills(t *testing.T) {
	t.Setenv("HOME", t.TempDir()) // isolate from the real ~/.claude
	dir := t.TempDir()
	cmds := filepath.Join(dir, ".claude", "commands")
	if err := os.MkdirAll(cmds, 0755); err != nil {
		t.Fatal(err)
	}
	// A command with frontmatter description.
	writeFile(t, filepath.Join(cmds, "review.md"), "---\ndescription: Review the diff\n---\nbody")
	// A command with no frontmatter → first prose line is the description.
	writeFile(t, filepath.Join(cmds, "ship.md"), "# Ship\n\nPush and open a PR")

	skill := filepath.Join(dir, ".claude", "skills", "deep-research")
	if err := os.MkdirAll(skill, 0755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(skill, "SKILL.md"), "---\ndescription: Fan-out research\n---\n")

	got := listAgentCommands(dir, "claudeCode")

	want := map[string]struct {
		desc string
		kind string
	}{
		"/review":        {"Review the diff", "command"},
		"/ship":          {"Push and open a PR", "command"},
		"/deep-research": {"Fan-out research", "skill"},
	}
	found := map[string]agentCommand{}
	for _, c := range got {
		found[c.Name] = c
	}
	for name, w := range want {
		c, ok := found[name]
		if !ok {
			t.Fatalf("missing command %q in %+v", name, got)
		}
		if c.Description != w.desc {
			t.Errorf("%s description = %q, want %q", name, c.Description, w.desc)
		}
		if c.Kind != w.kind {
			t.Errorf("%s kind = %q, want %q", name, c.Kind, w.kind)
		}
		if c.Source != "project" {
			t.Errorf("%s source = %q, want project", name, c.Source)
		}
	}

	// Built-ins are always present and sorted after custom commands.
	if _, ok := found["/clear"]; !ok {
		t.Error("expected /clear builtin")
	}
}

func TestListAgentCommands_EmptyWorkspaceReturnsBuiltinsOnly(t *testing.T) {
	t.Setenv("HOME", t.TempDir()) // isolate from the real ~/.claude
	got := listAgentCommands(t.TempDir(), "claudeCode")
	if len(got) == 0 {
		t.Fatal("expected at least the builtins")
	}
	for _, c := range got {
		if c.Kind != "builtin" {
			t.Errorf("expected only builtins in empty workspace, got %+v", c)
		}
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}
