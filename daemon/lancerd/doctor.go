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

	"lancer/lancerd/policy"
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
		return "OK"
	case statusWarn:
		return "WARN"
	default:
		return "FAIL"
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

// agentBinaries maps each vendor id (as the phone uses it) to its CLI binary.
var agentBinaries = []struct{ vendor, binary string }{
	{"claudeCode", "claude"},
	{"codex", "codex"},
	{"opencode", "opencode"},
	{"kimi", "kimi"},
}

// installedAgents returns the vendor ids whose CLI is resolvable, so the phone only
// offers agents the user actually has installed (instead of a hardcoded list). It
// searches the SAME augmented dirs the dispatcher uses to launch agents — under
// launchd the daemon's inherited PATH is minimal, so a bare exec.LookPath would
// find nothing even though the CLIs exist (Homebrew, ~/.local/bin, Kimi's bin).
func installedAgents(_ lookPathFunc) []string {
	dirs := []string{"/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs,
			filepath.Join(home, ".local", "bin"),
			filepath.Join(home, ".kimi-code", "bin"),
			filepath.Join(home, ".lancer", "bin"),
		)
	}
	// Also honor the inherited PATH so a non-standard install location still works.
	dirs = append(dirs, filepath.SplitList(os.Getenv("PATH"))...)

	var out []string
	for _, a := range agentBinaries {
		for _, d := range dirs {
			p := filepath.Join(d, a.binary)
			if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
				out = append(out, a.vendor)
				break
			}
		}
	}
	return out
}

// dialFunc mirrors net.DialTimeout so the daemon-reachability check is testable.
type dialFunc func(network, addr string, timeout time.Duration) (net.Conn, error)

func runDoctor() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	lancer := filepath.Join(home, ".lancer")
	if dir := os.Getenv("LANCER_STATE_DIR"); dir != "" {
		lancer = dir
	}

	exe, _ := os.Executable()
	results := collectDoctorResults(lancer, exe, home, exec.LookPath, net.DialTimeout)
	printDoctorReport(os.Stdout, results)

	for _, r := range results {
		if r.critical && r.status == statusFail {
			return fmt.Errorf("critical checks failed")
		}
	}
	return nil
}

func collectDoctorResults(lancerDir, exePath, home string, look lookPathFunc, dial dialFunc) []checkResult {
	return []checkResult{
		checkVersion(exePath),
		checkLancerDir(lancerDir),
		checkInstalledBinary(lancerDir),
		checkPolicy(lancerDir),
		checkResidentDaemon(lancerDir, dial),
		checkAgentCLIs(look),
		checkPython(look),
		checkHooks(home),
		checkAuditLog(lancerDir),
		checkQueue(lancerDir),
		checkOSArch(),
		checkRelayPairing(lancerDir),
		checkShimWrapper(home, look),
	}
}

func checkVersion(exePath string) checkResult {
	msg := fmt.Sprintf("lancerd %s", version)
	if exePath != "" {
		msg = fmt.Sprintf("lancerd %s (%s)", version, exePath)
	}
	return checkResult{name: "version", status: statusOK, message: msg}
}

func checkLancerDir(lancerDir string) checkResult {
	info, err := os.Stat(lancerDir)
	if err != nil {
		return checkResult{
			name:     "state dir",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("%s missing", lancerDir),
			hint:     "run: lancerd install",
		}
	}
	if !info.IsDir() {
		return checkResult{
			name:     "state dir",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("%s is not a directory", lancerDir),
		}
	}
	if perm := info.Mode().Perm(); perm != 0700 {
		return checkResult{
			name:    "state dir",
			status:  statusWarn,
			message: fmt.Sprintf("%s has mode %o (want 0700)", lancerDir, perm),
			hint:    fmt.Sprintf("run: chmod 700 %s", lancerDir),
		}
	}
	return checkResult{name: "state dir", status: statusOK, message: fmt.Sprintf("%s (0700)", lancerDir)}
}

func checkInstalledBinary(lancerDir string) checkResult {
	target := filepath.Join(lancerDir, "bin", "lancerd")
	if _, err := os.Stat(target); err != nil {
		return checkResult{
			name:    "installed binary",
			status:  statusWarn,
			message: fmt.Sprintf("%s missing", target),
			hint:    "run: lancerd install",
		}
	}
	return checkResult{name: "installed binary", status: statusOK, message: target}
}

func checkPolicy(lancerDir string) checkResult {
	path := filepath.Join(lancerDir, policy.GlobalPolicyFile)
	if _, err := os.Stat(path); err != nil {
		return checkResult{
			name:    "policy",
			status:  statusWarn,
			message: "policy.yaml absent (default-ask only)",
			hint:    "create ~/.lancer/policy.yaml to customize rules",
		}
	}
	doc, err := policy.LoadFile(path)
	if err != nil {
		return checkResult{
			name:     "policy",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("policy.yaml parse error: %v", err),
			hint:     "fix YAML syntax in ~/.lancer/policy.yaml",
		}
	}
	return checkResult{
		name:    "policy",
		status:  statusOK,
		message: fmt.Sprintf("policy.yaml parses (default=%s, %d rules)", doc.Default, len(doc.Rules)),
	}
}

func checkResidentDaemon(lancerDir string, dial dialFunc) checkResult {
	sock := filepath.Join(lancerDir, socketFileName)
	if _, err := os.Stat(sock); err != nil {
		return checkResult{
			name:    "resident daemon",
			status:  statusWarn,
			message: "not running (socket absent)",
			hint:    "run: lancerd daemon",
		}
	}
	conn, err := dial("unix", sock, 500*time.Millisecond)
	if err != nil {
		return checkResult{
			name:    "resident daemon",
			status:  statusWarn,
			message: fmt.Sprintf("socket present but dial failed: %v", err),
			hint:    "run: lancerd daemon",
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
		return checkResult{name: "hooks", status: statusOK, message: "Claude approval hook installed (Lancer runs only)"}
	case !scriptPresent && !wired:
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "Claude hook not installed (script + settings.json wiring both missing)",
			hint:    "run: lancerd install",
		}
	case scriptPresent && !wired:
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "Claude hook script present but NOT wired in settings.json — Claude Code never calls it",
			hint:    "run: lancerd install (merges hooks.PreToolUse into ~/.claude/settings.json)",
		}
	default: // wired but script missing
		return checkResult{
			name:    "hooks",
			status:  statusWarn,
			message: "settings.json references the hook but the script is missing",
			hint:    "run: lancerd install (rewrites ~/.claude/hooks/lancer-hook.sh)",
		}
	}
}

func checkAuditLog(lancerDir string) checkResult {
	path := filepath.Join(lancerDir, "audit.log")
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

func checkQueue(lancerDir string) checkResult {
	path := filepath.Join(lancerDir, queueFileName)
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
			hint:    "remove ~/.lancer/queue.json to reset the pending queue",
		}
	}
	return checkResult{name: "queue.json", status: statusOK, message: fmt.Sprintf("parses (%d entries)", len(obj))}
}

func checkOSArch() checkResult {
	return checkResult{name: "platform", status: statusOK, message: fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)}
}

func checkRelayPairing(lancerDir string) checkResult {
	path := filepath.Join(lancerDir, "relay-pairing.json")
	if _, err := os.Stat(path); err != nil {
		return checkResult{
			name:    "relay pairing",
			status:  statusWarn,
			message: "relay-pairing.json absent (not yet paired)",
			hint:    "run: lancerd pair",
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
			name:     "relay pairing",
			status:   statusFail,
			critical: true,
			message:  fmt.Sprintf("corrupt: %v", err),
			hint:     "remove relay-pairing.json and re-pair",
		}
	}
	if cfg.RelayURL == "" || cfg.Code == "" || cfg.PrivateKey == "" || cfg.PublicKey == "" {
		return checkResult{
			name:     "relay pairing",
			status:   statusFail,
			critical: true,
			message:  "incomplete relay pairing config",
			hint:     "re-run: lancerd pair",
		}
	}
	return checkResult{
		name:    "relay pairing",
		status:  statusOK,
		message: fmt.Sprintf("paired with relay %s (%s)", cfg.RelayURL, confirmedState(cfg)),
	}
}

func confirmedState(cfg relayPairConfig) string {
	if cfg.isConfirmed() {
		return "confirmed"
	}
	return "unconfirmed"
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
	fmt.Fprintln(w, "Lancer doctor")
	fmt.Fprintln(w, "Checks the local bridge. Warnings include a direct next step.")
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
		fmt.Fprintf(w, "  %-4s %-*s %s\n", r.status.symbol(), width, r.name, r.message)
		if r.hint != "" && r.status != statusOK {
			fmt.Fprintf(w, "       %-*s Next: %s\n", width, "", r.hint)
		}
	}

	fmt.Fprintln(w, "")
	fmt.Fprintf(w, "Summary: %d OK, %d warnings, %d failures\n", ok, warn, fail)
}

// checkShimWrapper verifies that PATH `claude` resolves to the Lancer shim
// under ~/.lancer/bin. Warn if claude resolves elsewhere (shim not first on
// PATH); fail if claude is not found at all.
func checkShimWrapper(home string, look lookPathFunc) checkResult {
	p, err := look("claude")
	if err != nil {
		return checkResult{
			name:    "shim wrapper",
			status:  statusFail,
			message: "claude not on PATH",
			hint:    "run: lancerd install",
		}
	}
	if filepath.Dir(p) == filepath.Join(home, ".lancer", "bin") {
		return checkResult{name: "shim wrapper", status: statusOK, message: p}
	}
	return checkResult{
		name:    "shim wrapper",
		status:  statusWarn,
		message: "claude resolves to " + p + " (shim not first on PATH)",
		hint:    "run: lancerd install (shim PATH coverage)",
	}
}
