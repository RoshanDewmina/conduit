package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// fs.go — host-side filesystem browsing for the "Add Workspace → From Machine"
// flow. The phone lists directories under the user's home to pick a project dir
// without typing an absolute path.
//
// Fail-closed: every path is resolved and confined to the user's home directory.
// A request that would escape $HOME returns an error rather than listing it, so
// the phone can never browse /etc, /root, or another user's files.

type fsEntry struct {
	Name  string `json:"name"`
	IsDir bool   `json:"isDir"`
}

type fsListResult struct {
	// Path echoes the resolved directory with the home prefix folded back to "~"
	// so the phone can show a stable breadcrumb.
	Path    string    `json:"path"`
	Parent  string    `json:"parent,omitempty"`
	Entries []fsEntry `json:"entries"`
}

// fsList returns the directory entries under path, confined to the user's home.
// An empty path lists the home directory itself.
func (s *server) fsList(path string) (fsListResult, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return fsListResult{}, err
	}

	resolved := expandHome(path)
	if resolved == "" {
		resolved = home
	}
	if !filepath.IsAbs(resolved) {
		resolved = filepath.Join(home, resolved)
	}
	resolved = filepath.Clean(resolved)

	if !withinHome(home, resolved) {
		return fsListResult{}, fmt.Errorf("path is outside the home directory")
	}

	info, err := os.Stat(resolved)
	if err != nil {
		return fsListResult{}, err
	}
	if !info.IsDir() {
		return fsListResult{}, fmt.Errorf("not a directory")
	}

	dirEntries, err := os.ReadDir(resolved)
	if err != nil {
		return fsListResult{}, err
	}

	entries := make([]fsEntry, 0, len(dirEntries))
	for _, e := range dirEntries {
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue // hidden files/dirs are noise for a project picker
		}
		isDir := e.IsDir()
		if !isDir {
			// Resolve symlinks so a linked project directory still shows as a dir.
			if info, err := os.Stat(filepath.Join(resolved, name)); err == nil {
				isDir = info.IsDir()
			}
		}
		entries = append(entries, fsEntry{Name: name, IsDir: isDir})
	}
	// Directories first, then files, each alphabetical — a predictable browse order.
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir != entries[j].IsDir {
			return entries[i].IsDir
		}
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})

	res := fsListResult{Path: foldHome(home, resolved), Entries: entries}
	if resolved != home && withinHome(home, filepath.Dir(resolved)) {
		res.Parent = foldHome(home, filepath.Dir(resolved))
	}
	return res, nil
}

// withinHome reports whether target is home or a descendant of it.
func withinHome(home, target string) bool {
	if target == home {
		return true
	}
	rel, err := filepath.Rel(home, target)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))
}

// foldHome replaces a leading home directory with "~" for display.
func foldHome(home, path string) string {
	if path == home {
		return "~"
	}
	if rel, err := filepath.Rel(home, path); err == nil && !strings.HasPrefix(rel, "..") {
		return "~/" + rel
	}
	return path
}
