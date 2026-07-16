package main

import (
	"bytes"
	"encoding/xml"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// assertWellFormedXML walks every token in data and fails the test if the XML
// decoder ever errors, without requiring a struct that mirrors the full
// (and partly heterogeneous — key/string/array/true/dict siblings) plist schema.
func assertWellFormedXML(t *testing.T, data []byte) {
	t.Helper()
	dec := xml.NewDecoder(bytes.NewReader(data))
	// launchd plists reference an external DTD; disable strict entity
	// resolution requirements that would otherwise reject the DOCTYPE.
	dec.Strict = false
	for {
		_, err := dec.Token()
		if err == io.EOF {
			return
		}
		if err != nil {
			t.Fatalf("plist is not well-formed XML: %v\n%s", err, data)
		}
	}
}

func TestInstallLaunchdWritesRelaySecretIntoEnvironmentVariables(t *testing.T) {
	home := t.TempDir()
	t.Setenv("APPROVAL_RELAY_SECRET", "s3cr3t-value")

	binary := filepath.Join(home, ".lancer", "bin", "lancerd")
	if err := installLaunchd(binary, home); err != nil {
		t.Fatalf("installLaunchd: %v", err)
	}

	data, err := os.ReadFile(launchdPlistPath(home))
	if err != nil {
		t.Fatalf("read plist: %v", err)
	}
	assertWellFormedXML(t, data)

	if !strings.Contains(string(data), "<key>EnvironmentVariables</key>") {
		t.Fatal("expected EnvironmentVariables dict in plist when APPROVAL_RELAY_SECRET is set")
	}
	if !strings.Contains(string(data), "<key>APPROVAL_RELAY_SECRET</key><string>s3cr3t-value</string>") {
		t.Fatalf("expected APPROVAL_RELAY_SECRET value in plist, got:\n%s", data)
	}
}

func TestInstallLaunchdEscapesRelaySecretForXML(t *testing.T) {
	home := t.TempDir()
	raw := `weird<&>"'value`
	t.Setenv("APPROVAL_RELAY_SECRET", raw)

	binary := filepath.Join(home, ".lancer", "bin", "lancerd")
	if err := installLaunchd(binary, home); err != nil {
		t.Fatalf("installLaunchd: %v", err)
	}

	data, err := os.ReadFile(launchdPlistPath(home))
	if err != nil {
		t.Fatalf("read plist: %v", err)
	}
	// The raw, unescaped value must never appear verbatim — it would break the
	// plist's XML structure (e.g. the bare "<" would be parsed as a new tag).
	if strings.Contains(string(data), "<string>"+raw+"</string>") {
		t.Fatalf("secret value was embedded unescaped, plist:\n%s", data)
	}
	assertWellFormedXML(t, data)

	want := "<key>APPROVAL_RELAY_SECRET</key><string>" + escapePlistString(raw) + "</string>"
	if !strings.Contains(string(data), want) {
		t.Fatalf("expected escaped secret %q in plist, got:\n%s", want, data)
	}

	// Round-trip: decoding the escaped form must recover the original value.
	dec := xml.NewDecoder(strings.NewReader("<string>" + escapePlistString(raw) + "</string>"))
	tok, err := dec.Token() // StartElement
	if err != nil {
		t.Fatalf("decode start: %v", err)
	}
	_ = tok
	tok, err = dec.Token() // CharData
	if err != nil {
		t.Fatalf("decode chardata: %v", err)
	}
	cd, ok := tok.(xml.CharData)
	if !ok {
		t.Fatalf("expected CharData, got %T", tok)
	}
	if string(cd) != raw {
		t.Fatalf("escaped secret did not round-trip: got %q want %q", string(cd), raw)
	}
}

func TestInstallLaunchdWithoutRelaySecretStillProducesValidPlist(t *testing.T) {
	home := t.TempDir()
	t.Setenv("APPROVAL_RELAY_SECRET", "")

	binary := filepath.Join(home, ".lancer", "bin", "lancerd")
	if err := installLaunchd(binary, home); err != nil {
		t.Fatalf("installLaunchd: %v", err)
	}

	data, err := os.ReadFile(launchdPlistPath(home))
	if err != nil {
		t.Fatalf("read plist: %v", err)
	}
	assertWellFormedXML(t, data)

	if !strings.Contains(string(data), "<key>EnvironmentVariables</key>") {
		t.Fatal("expected EnvironmentVariables dict (PATH) even when APPROVAL_RELAY_SECRET is unset")
	}
	if !strings.Contains(string(data), "<key>PATH</key><string>") {
		t.Fatalf("expected PATH in EnvironmentVariables, got:\n%s", data)
	}
	if strings.Contains(string(data), "<key>APPROVAL_RELAY_SECRET</key>") {
		t.Fatal("did not expect APPROVAL_RELAY_SECRET when unset and no prior plist")
	}
	if !strings.Contains(string(data), "<key>Label</key><string>dev.lancer.lancerd</string>") {
		t.Fatalf("expected base plist fields to still be present, got:\n%s", data)
	}
}

func TestInstallLaunchdPreservesRelaySecretAndWritesPATH(t *testing.T) {
	home := t.TempDir()
	t.Setenv("APPROVAL_RELAY_SECRET", "keep-me")
	binary := filepath.Join(home, ".lancer", "bin", "lancerd")
	if err := installLaunchd(binary, home); err != nil {
		t.Fatalf("first install: %v", err)
	}
	t.Setenv("APPROVAL_RELAY_SECRET", "")
	if err := installLaunchd(binary, home); err != nil {
		t.Fatalf("reinstall without env secret: %v", err)
	}
	data, err := os.ReadFile(launchdPlistPath(home))
	if err != nil {
		t.Fatalf("read plist: %v", err)
	}
	if !strings.Contains(string(data), "<key>APPROVAL_RELAY_SECRET</key><string>keep-me</string>") {
		t.Fatalf("expected preserved secret, got:\n%s", data)
	}
	if !strings.Contains(string(data), "/opt/homebrew/bin") {
		t.Fatalf("expected Homebrew on PATH, got:\n%s", data)
	}
	// PATH value must not include the shim dir; ProgramArguments still
	// legitimately references ~/.lancer/bin/lancerd as the daemon binary.
	pathStart := strings.Index(string(data), "<key>PATH</key><string>")
	if pathStart < 0 {
		t.Fatal("PATH key missing")
	}
	pathRest := string(data)[pathStart:]
	pathEnd := strings.Index(pathRest, "</string>")
	pathVal := pathRest[:pathEnd]
	if strings.Contains(pathVal, ".lancer/bin") {
		t.Fatalf("daemon PATH must not include Lancer shim dir, got PATH=%s", pathVal)
	}
}
