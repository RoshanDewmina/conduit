package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScanDriftFindsDeadRefsOnly(t *testing.T) {
	root := t.TempDir()
	writeDriftFile(t, filepath.Join(root, "good.md"), "ok")
	writeDriftFile(t, filepath.Join(root, "docs", "here.md"), "ok")
	writeDriftFile(t, filepath.Join(root, "CLAUDE.md"), strings.Join([]string{
		"@good.md",                         // resolves -> not a finding
		"@missing.md",                      // dead import
		"see [here](docs/here.md)",         // resolves
		"see [gone](docs/gone.md)",         // dead link
		"external [site](https://x.com/a)", // skipped (URL)
		"contact noreply@anthropic.com",    // skipped (email, not an import)
		"a [section](#anchor) ref",         // skipped (anchor)
		"global @/etc/outside.md import",   // skipped (outside root)
	}, "\n"))

	report, err := scanDrift(root)
	if err != nil {
		t.Fatalf("scanDrift: %v", err)
	}
	if report.Scanned != 1 {
		t.Fatalf("scanned = %d, want 1", report.Scanned)
	}

	got := map[string]bool{}
	for _, f := range report.Findings {
		got[f.Kind+":"+f.Ref] = true
	}
	want := []string{"dead-import:missing.md", "dead-link:docs/gone.md"}
	if len(report.Findings) != len(want) {
		t.Fatalf("findings = %+v, want exactly %v", report.Findings, want)
	}
	for _, w := range want {
		if !got[w] {
			t.Errorf("missing expected finding %q (got %+v)", w, report.Findings)
		}
	}
}

func writeDriftFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
