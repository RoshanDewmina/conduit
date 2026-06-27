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

func TestScanDriftMarksDeadRefsRemediable(t *testing.T) {
	root := t.TempDir()
	writeDriftFile(t, filepath.Join(root, "CLAUDE.md"), "@missing.md")
	report, err := scanDrift(root)
	if err != nil {
		t.Fatalf("scanDrift: %v", err)
	}
	if len(report.Findings) != 1 {
		t.Fatalf("findings = %+v, want 1", report.Findings)
	}
	if report.Findings[0].Remediation != driftRemediateApplyFix {
		t.Errorf("remediation = %q, want %q", report.Findings[0].Remediation, driftRemediateApplyFix)
	}
}

func TestRemediateDriftCommentsOutDeadRefAndIsIdempotent(t *testing.T) {
	root := t.TempDir()
	body := strings.Join([]string{
		"# guide",
		"@missing.md",
		"keep me",
	}, "\n")
	writeDriftFile(t, filepath.Join(root, "CLAUDE.md"), body)

	before, err := scanDrift(root)
	if err != nil {
		t.Fatalf("scanDrift: %v", err)
	}
	if len(before.Findings) != 1 {
		t.Fatalf("setup: findings = %+v, want 1", before.Findings)
	}
	f := before.Findings[0]

	after, err := remediateDrift(DriftRemediateRequest{
		Root: root, File: f.File, Line: f.Line, Kind: f.Kind, Ref: f.Ref,
	})
	if err != nil {
		t.Fatalf("remediateDrift: %v", err)
	}
	if len(after.Findings) != 0 {
		t.Fatalf("after remediation findings = %+v, want 0", after.Findings)
	}

	got, err := os.ReadFile(filepath.Join(root, "CLAUDE.md"))
	if err != nil {
		t.Fatal(err)
	}
	gs := string(got)
	if strings.Contains(gs, "@missing.md") {
		// the bare ref must be gone (only inside the marker comment, if at all)
		if !strings.Contains(gs, "lancer: removed dead reference") {
			t.Fatalf("dead ref not neutralised: %q", gs)
		}
	}
	if !strings.Contains(gs, "keep me") || !strings.Contains(gs, "# guide") {
		t.Errorf("unrelated lines were altered: %q", gs)
	}

	// Idempotent: a second pass on the same line is a no-op success.
	if _, err := remediateDrift(DriftRemediateRequest{
		Root: root, File: f.File, Line: f.Line, Kind: f.Kind, Ref: f.Ref,
	}); err != nil {
		t.Fatalf("second remediateDrift (idempotent): %v", err)
	}
}

func TestRemediateDriftFailsClosed(t *testing.T) {
	root := t.TempDir()
	writeDriftFile(t, filepath.Join(root, "CLAUDE.md"), "@missing.md")

	cases := []struct {
		name string
		req  DriftRemediateRequest
	}{
		{"escapes root", DriftRemediateRequest{Root: root, File: "../evil.md", Line: 1, Ref: "@x.md"}},
		{"absolute path", DriftRemediateRequest{Root: root, File: "/etc/passwd", Line: 1, Ref: "x"}},
		{"not instruction file", DriftRemediateRequest{Root: root, File: "README.md", Line: 1, Ref: "x"}},
		{"stale ref", DriftRemediateRequest{Root: root, File: "CLAUDE.md", Line: 1, Ref: "@notthere.md"}},
		{"line out of range", DriftRemediateRequest{Root: root, File: "CLAUDE.md", Line: 99, Ref: "@missing.md"}},
		{"bad line", DriftRemediateRequest{Root: root, File: "CLAUDE.md", Line: 0, Ref: "@missing.md"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := remediateDrift(tc.req); err == nil {
				t.Errorf("expected error, got nil")
			}
		})
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
