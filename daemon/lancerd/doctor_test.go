package main

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func lookPathFor(present ...string) lookPathFunc {
	set := map[string]bool{}
	for _, p := range present {
		set[p] = true
	}
	return func(name string) (string, error) {
		if set[name] {
			return "/usr/bin/" + name, nil
		}
		return "", errors.New("not found")
	}
}

func TestCheckLancerDir(t *testing.T) {
	dir := t.TempDir()
	lancer := filepath.Join(dir, ".lancer")
	if err := os.MkdirAll(lancer, 0700); err != nil {
		t.Fatal(err)
	}
	if r := checkLancerDir(lancer); r.status != statusOK {
		t.Fatalf("present 0700 dir: status = %v (%s)", r.status, r.message)
	}

	if r := checkLancerDir(filepath.Join(dir, "missing")); r.status != statusFail || !r.critical {
		t.Fatalf("missing dir: status = %v critical = %v", r.status, r.critical)
	}

	loose := filepath.Join(dir, "loose")
	if err := os.MkdirAll(loose, 0755); err != nil {
		t.Fatal(err)
	}
	if r := checkLancerDir(loose); r.status != statusWarn {
		t.Fatalf("loose perms: status = %v", r.status)
	}
}

func TestCheckInstalledBinary(t *testing.T) {
	dir := t.TempDir()
	if r := checkInstalledBinary(dir); r.status != statusWarn {
		t.Fatalf("missing binary: status = %v", r.status)
	}
	binDir := filepath.Join(dir, "bin")
	if err := os.MkdirAll(binDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(binDir, "lancerd"), []byte("x"), 0755); err != nil {
		t.Fatal(err)
	}
	if r := checkInstalledBinary(dir); r.status != statusOK {
		t.Fatalf("present binary: status = %v", r.status)
	}
}

func TestCheckPolicy(t *testing.T) {
	dir := t.TempDir()
	if r := checkPolicy(dir); r.status != statusWarn {
		t.Fatalf("absent policy: status = %v", r.status)
	}

	path := filepath.Join(dir, "policy.yaml")
	if err := os.WriteFile(path, []byte("default: ask\nrules: []\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if r := checkPolicy(dir); r.status != statusOK {
		t.Fatalf("valid policy: status = %v (%s)", r.status, r.message)
	}

	if err := os.WriteFile(path, []byte("default: ask\nrules: [: bad"), 0600); err != nil {
		t.Fatal(err)
	}
	if r := checkPolicy(dir); r.status != statusFail || !r.critical {
		t.Fatalf("corrupt policy: status = %v critical = %v", r.status, r.critical)
	}
}

func TestCheckResidentDaemon(t *testing.T) {
	dir := t.TempDir()
	failDial := func(string, string, time.Duration) (net.Conn, error) {
		return nil, errors.New("refused")
	}
	if r := checkResidentDaemon(dir, failDial); r.status != statusWarn {
		t.Fatalf("absent socket: status = %v", r.status)
	}

	sock := filepath.Join(dir, socketFileName)
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	if r := checkResidentDaemon(dir, net.DialTimeout); r.status != statusOK {
		t.Fatalf("live socket: status = %v (%s)", r.status, r.message)
	}
	if r := checkResidentDaemon(dir, failDial); r.status != statusWarn {
		t.Fatalf("dead socket: status = %v", r.status)
	}
}

func TestCheckAgentCLIs(t *testing.T) {
	if r := checkAgentCLIs(lookPathFor("codex")); r.status != statusOK {
		t.Fatalf("one agent: status = %v", r.status)
	}
	if r := checkAgentCLIs(lookPathFor()); r.status != statusWarn {
		t.Fatalf("no agents: status = %v", r.status)
	}
}

func TestCheckPython(t *testing.T) {
	if r := checkPython(lookPathFor("python3")); r.status != statusOK {
		t.Fatalf("python present: status = %v", r.status)
	}
	if r := checkPython(lookPathFor()); r.status != statusWarn {
		t.Fatalf("python missing: status = %v", r.status)
	}
}

func TestCheckHooks(t *testing.T) {
	home := t.TempDir()
	// Nothing installed → warn.
	if r := checkHooks(home); r.status != statusWarn {
		t.Fatalf("nothing installed: status = %v", r.status)
	}

	// Script present but settings.json NOT wired → still warn (Finding #10: the
	// script alone is a false positive; Claude never calls it without wiring).
	hookDir := filepath.Join(home, ".claude", "hooks")
	if err := os.MkdirAll(hookDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(hookDir, "lancer-hook.sh"), []byte("#!/bin/sh\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if r := checkHooks(home); r.status != statusWarn {
		t.Fatalf("script-only (unwired): status = %v (%s)", r.status, r.message)
	}

	// Wire it (script already exists) → OK.
	if _, err := wireClaudeHookSettings(home); err != nil {
		t.Fatal(err)
	}
	if r := checkHooks(home); r.status != statusOK {
		t.Fatalf("script + wired: status = %v (%s)", r.status, r.message)
	}
}

func TestCheckAuditLog(t *testing.T) {
	dir := t.TempDir()
	if r := checkAuditLog(dir); r.status != statusOK {
		t.Fatalf("absent audit: status = %v", r.status)
	}
	path := filepath.Join(dir, "audit.log")
	if err := os.WriteFile(path, []byte("{}\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if r := checkAuditLog(dir); r.status != statusOK {
		t.Fatalf("writable audit: status = %v", r.status)
	}
}

func TestCheckQueue(t *testing.T) {
	dir := t.TempDir()
	if r := checkQueue(dir); r.status != statusOK {
		t.Fatalf("absent queue: status = %v", r.status)
	}
	path := filepath.Join(dir, queueFileName)
	if err := os.WriteFile(path, []byte(`{"a":1}`), 0600); err != nil {
		t.Fatal(err)
	}
	if r := checkQueue(dir); r.status != statusOK {
		t.Fatalf("valid queue: status = %v (%s)", r.status, r.message)
	}
	if err := os.WriteFile(path, []byte("not json"), 0600); err != nil {
		t.Fatal(err)
	}
	if r := checkQueue(dir); r.status != statusWarn {
		t.Fatalf("corrupt queue: status = %v", r.status)
	}
}

func TestCollectDoctorResultsOrderAndCount(t *testing.T) {
	dir := t.TempDir()
	results := collectDoctorResults(dir, "/tmp/lancerd", dir, lookPathFor(), func(string, string, time.Duration) (net.Conn, error) {
		return nil, errors.New("nope")
	})
	if len(results) != 13 {
		t.Fatalf("expected 13 checks, got %d", len(results))
	}
	if results[0].name != "version" {
		t.Fatalf("first check = %q", results[0].name)
	}
	if results[len(results)-1].name != "shim wrapper" {
		t.Fatalf("last check = %q", results[len(results)-1].name)
	}
}
