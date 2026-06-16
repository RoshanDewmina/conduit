package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"

	"conduit/conduitd/policy"
)

type checkStatus int

const (
	statusOK checkStatus = iota
	statusWarn
	statusFail
)

func (s checkStatus) symbol() string {
	switch s {
	case statusOK:
		return "✓"
	case statusWarn:
		return "⚠"
	default:
		return "✗"
	}
}

type checkResult struct {
	name     string
	status   checkStatus
	message  string
	hint     string
	critical bool
}

// lookPathFunc mirrors exec.LookPath so checks stay testable without a real PATH.
type lookPathFunc func(string) (string, error)

// dialFunc mirrors net.DialTimeout so the daemon-reachability check is testable.
type dialFunc func(network, addr string, timeout time.Duration) (net.Conn, error)

func runDoctor() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	conduit := filepath.Join(home, ".conduit")
	if dir := os.Getenv("CONDUIT_STATE_DIR"); dir != "" {
		conduit = dir
	}

	exe, _ := os.Executable()
	results := collectDoctorResults(conduit, exe, home, exec.LookPath, net.DialTimeout)
	printDoctorReport(os.Stdout, results)

	for _, r := range results {
		if r.critical && r.status == statusFail {
			return fmt.Errorf("critical checks failed")
		}
	}
	return nil
}

func collectDoctorResults(conduitDir, exePath, home string, look lookPathFunc, dial dialFunc) []checkResult {
	return []checkResult{
		checkVersion(exePath),
		checkConduitDir(conduitDir),
		checkInstalledBinary(conduitDir),
		checkPolicy(conduitDir),
		checkResidentDaemon(conduitDir, dial),
		checkAgentCLIs(look),
		checkPython(look),
		checkHooks(home),
		checkAuditLog(conduitDir),
		checkQueue(conduitDir),
		checkOSArch(),
		checkRelayPairing(conduitDir),
		checkShimWrapper(home, look),
	}
}

func checkVersion(exePath string) checkResult {
	msg := fmt.Sprintf("conduitd %s", version)
	if exePath != "" {
		msg = fmt.Sprintf("conduitd %s (%s)", version, exePath)
	}
	return checkResult{name: "version", status: statusOK, message: msg}
}

func checkConduitDir(conduitDir string) checkResult {
	info, err := os.Stat(conduitDir)
	if err != nil {
		return checkResult{
			name:     "state dir",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("%s missing", conduitDir),
			hint:     "run: conduitd install",
		}
	}
	if !info.IsDir() {
		return checkResult{
			name:     "state dir",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("%s is not a directory", conduitDir),
		}
	}
	if perm := info.Mode().Perm(); perm != 0700 {
		return checkResult{
			name:    "state dir",
			status:  statusWarn,
			message: fmt.Sprintf("%s has mode %o (want 0700)", conduitDir, perm),
			hint:    fmt.Sprintf("run: chmod 700 %s", conduitDir),
		}
	}
	return checkResult{name: "state dir", status: statusOK, message: fmt.Sprintf("%s (0700)", conduitDir)}
}

func checkInstalledBinary(conduitDir string) checkResult {
	target := filepath.Join(conduitDir, "bin", "conduitd")
	if _, err := os.Stat(target); err != nil {
		return checkResult{
			name:    "installed binary",
			status:  statusWarn,
			message: fmt.Sprintf("%s missing", target),
			hint:    "run: conduitd install",
		}
	}
	return checkResult{name: "installed binary", status: statusOK, message: target}
}

func checkPolicy(conduitDir string) checkResult {
	path := filepath.Join(conduitDir, policy.GlobalPolicyFile)
	if _, err := os.Stat(path); err != nil {
		return checkResult{
			name:    "policy",
			status:  statusWarn,
			message: "policy.yaml absent (default-ask only)",
			hint:    "create ~/.conduit/policy.yaml to customize rules",
		}
	}
	doc, err := policy.LoadFile(path)
	if err != nil {
		return checkResult{
			name:     "policy",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("policy.yaml parse error: %v", err),
			hint:     "fix YAML syntax in ~/.conduit/policy.yaml",
		}
	}
	return checkResult{
		name:    "policy",
		status:  statusOK,
		message: fmt.Sprintf("policy.yaml parses (default=%s, %d rules)", doc.Default, len(doc.Rules)),
	}
}

func checkResidentDaemon(conduitDir string, dial dialFunc) checkResult {
	sock := filepath.Join(conduitDir, socketFileName)
	if _, err := os.Stat(sock); err != nil {
		return checkResult{
			name:    "resident daemon",
			status:  statusWarn,
			message: "not running (socket absent)",
			hint:    "run: conduitd daemon",
		}
	}
	conn, err := dial("unix", sock, 500*time.Millisecond)
	if err != nil {
		return checkResult{
			name:    "resident daemon",
			status:  statusWarn,
			message: fmt.Sprintf("socket present but dial failed: %v", err),
			hint:    "run: conduitd daemon",
		}
	}
	conn.Close()
	return checkResult{name: "resident daemon", status: statusOK, message: "resident daemon reachable"}
}

func checkAgentCLIs(look lookPathFunc) checkResult {
	agents := []string{"claude", "codex", "opencode"}
	var found []string
	for _, a := range agents {
		if _, err := look(a); err == nil {
			found = append(found, a)
		}
	}
	if len(found) == 0 {
		return checkResult{
			name:    "agent CLIs",
			status:  statusWarn,
			message: "none of claude/codex/opencode on PATH",
			hint:    "install at least one agent CLI",
		}
	}
	return checkResult{name: "agent CLIs", status: statusOK, message: fmt.Sprintf("found: %s", joinComma(found))}
}

func checkPython(look lookPathFunc) checkResult {
	if _, err := look("python3"); err != nil {
		return checkResult{
			name:    "python3",
			status:  statusWarn,
			message: "python3 not on PATH (PreToolUse hook parser needs it)",
			hint:    "install python3",
		}
	}
	return checkResult{name: "python3", status: statusOK, message: "python3 on PATH"}
}

// checkHooks verifies the Claude PreToolUse hook is BOTH dropped as a script AND
// wired into ~/.claude/settings.json. The script alone is a false positive: if
// settings.json does not register the command, Claude Code never calls it and the
// interactive approval path silently never fires (Finding #10).
func checkHooks(home string) checkResult {
	scriptPath := claudeHookScriptPath(home)
	settingsPath := claudeSettingsPath(home)
	scriptPresent := false
	if _, err := os.Stat(scriptPath); err == nil {
		scriptPresent = true
	}
	wired := claudeHookWired(settingsPath)

	switch {
	case scriptPresent && wired:
		return checkResult{name: "hooks", status: statusOK, message: "claude PreToolUse hook installed and wired"}
	case !scriptPresent && !wired:
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "Claude hook not installed (script + settings.json wiring both missing)",
			hint:    "run: conduitd install",
		}
	case scriptPresent && !wired:
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "Claude hook script present but NOT wired in settings.json — Claude Code never calls it",
			hint:    "run: conduitd install (merges hooks.PreToolUse into ~/.claude/settings.json)",
		}
	default: // wired but script missing
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "settings.json references the hook but the script is missing",
			hint:    "run: conduitd install (rewrites ~/.claude/hooks/conduit-hook.sh)",
		}
	}
}

func checkAuditLog(conduitDir string) checkResult {
	path := filepath.Join(conduitDir, "audit.log")
	if _, err := os.Stat(path); err != nil {
		return checkResult{name: "audit.log", status: statusOK, message: "absent (created on first event)"}
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return checkResult{
			name:    "audit.log",
			status:  statusWarn,
			message: fmt.Sprintf("not writable: %v", err),
			hint:    fmt.Sprintf("run: chmod 600 %s", path),
		}
	}
	f.Close()
	return checkResult{name: "audit.log", status: statusOK, message: "present and writable"}
}

func checkQueue(conduitDir string) checkResult {
	path := filepath.Join(conduitDir, queueFileName)
	data, err := os.ReadFile(path)
	if err != nil {
		return checkResult{name: "queue.json", status: statusOK, message: "absent (no pending approvals)"}
	}
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(data, &obj); err != nil {
		return checkResult{
			name:    "queue.json",
			status:  statusWarn,
			message: fmt.Sprintf("corrupt: %v", err),
			hint:    "remove ~/.conduit/queue.json to reset the pending queue",
		}
	}
	return checkResult{name: "queue.json", status: statusOK, message: fmt.Sprintf("parses (%d entries)", len(obj))}
}

func checkOSArch() checkResult {
	return checkResult{name: "platform", status: statusOK, message: fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)}
}

func checkRelayPairing(conduitDir string) checkResult {
	path := filepath.Join(conduitDir, "relay-pairing.json")
	if _, err := os.Stat(path); err != nil {
		return checkResult{
			name:    "relay pairing",
			status:  statusWarn,
			message: "relay-pairing.json absent (not yet paired)",
			hint:    "run: conduitd pair",
		}
	}
	var cfg relayPairConfig
	data, err := os.ReadFile(path)
	if err != nil {
		return checkResult{
			name:    "relay pairing",
			status:  statusWarn,
			message: fmt.Sprintf("cannot read: %v", err),
		}
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return checkResult{
			name:    "relay pairing",
			status:  statusFail,
			critical: true,
			message: fmt.Sprintf("corrupt: %v", err),
			hint:    "remove relay-pairing.json and re-pair",
		}
	}
	if cfg.RelayURL == "" || cfg.Code == "" || cfg.PrivateKey == "" || cfg.PublicKey == "" {
		return checkResult{
			name:    "relay pairing",
			status:  statusFail,
			critical: true,
			message: "incomplete relay pairing config",
			hint:    "re-run: conduitd pair",
		}
	}
	return checkResult{
		name:    "relay pairing",
		status:  statusOK,
		message: fmt.Sprintf("paired with relay %s", cfg.RelayURL),
	}
}

func joinComma(items []string) string {
	out := ""
	for i, s := range items {
		if i > 0 {
			out += ", "
		}
		out += s
	}
	return out
}

func printDoctorReport(w *os.File, results []checkResult) {
	fmt.Fprintln(w, "conduitd doctor — setup & health self-check")
	fmt.Fprintln(w, "")

	width := 0
	for _, r := range results {
		if len(r.name) > width {
			width = len(r.name)
		}
	}

	var ok, warn, fail int
	for _, r := range results {
		switch r.status {
		case statusOK:
			ok++
		case statusWarn:
			warn++
		default:
			fail++
		}
		fmt.Fprintf(w, "  %s  %-*s  %s\n", r.status.symbol(), width, r.name, r.message)
		if r.hint != "" && r.status != statusOK {
			fmt.Fprintf(w, "     %*s  ↳ %s\n", width, "", r.hint)
		}
	}

	fmt.Fprintln(w, "")
	fmt.Fprintf(w, "%d ok, %d warnings, %d failures\n", ok, warn, fail)
}

// checkShimWrapper verifies that PATH `claude` resolves to the Conduit shim
// under ~/.conduit/bin. Warn if claude resolves elsewhere (shim not first on
// PATH); fail if claude is not found at all.
func checkShimWrapper(home string, look lookPathFunc) checkResult {
	p, err := look("claude")
	if err != nil {
		return checkResult{
			name:    "shim wrapper",
			status:  statusFail,
			message: "claude not on PATH",
			hint:    "run: conduitd install",
		}
	}
	if filepath.Dir(p) == filepath.Join(home, ".conduit", "bin") {
		return checkResult{name: "shim wrapper", status: statusOK, message: p}
	}
	return checkResult{
		name:    "shim wrapper",
		status:  statusWarn,
		message: "claude resolves to " + p + " (shim not first on PATH)",
		hint:    "run: conduitd install (shim PATH coverage)",
	}
}
