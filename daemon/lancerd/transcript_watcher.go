package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// BareSession is a discovered Claude Code transcript on disk. Managed=false
// means it was NOT started through the Lancer shim (a "bare" session).
type BareSession struct {
	SessionID      string
	ProjectDir     string
	CWD            string
	TranscriptPath string
	LastModified   time.Time
	Managed        bool
}

// scanTranscripts enumerates <projectsDir>/<project>/<sessionId>.jsonl files and
// extracts each session's id + cwd from the first line that carries them. It is
// strictly read-only and never returns transcript message bodies.
func scanTranscripts(projectsDir string) ([]BareSession, error) {
	projDirs, err := os.ReadDir(projectsDir)
	if err != nil {
		return nil, err
	}
	var out []BareSession
	for _, pd := range projDirs {
		if !pd.IsDir() {
			continue
		}
		dir := filepath.Join(projectsDir, pd.Name())
		files, _ := os.ReadDir(dir)
		for _, f := range files {
			if f.IsDir() || filepath.Ext(f.Name()) != ".jsonl" {
				continue
			}
			path := filepath.Join(dir, f.Name())
			id, cwd := firstSessionMeta(path)
			if id == "" {
				id = strings.TrimSuffix(f.Name(), ".jsonl")
			}
			info, _ := f.Info()
			var mod time.Time
			if info != nil {
				mod = info.ModTime()
			}
			out = append(out, BareSession{
				SessionID:      id,
				ProjectDir:     pd.Name(),
				CWD:            cwd,
				TranscriptPath: path,
				LastModified:   mod,
			})
		}
	}
	return out, nil
}

// firstSessionMeta reads only enough of a transcript to find the first line that
// carries a sessionId, returning that id and its cwd. Never reads message bodies.
func firstSessionMeta(path string) (id, cwd string) {
	f, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<22)
	for sc.Scan() {
		var m struct {
			SessionID string `json:"sessionId"`
			CWD       string `json:"cwd"`
		}
		if json.Unmarshal(sc.Bytes(), &m) == nil && m.SessionID != "" {
			return m.SessionID, m.CWD
		}
	}
	return "", ""
}
