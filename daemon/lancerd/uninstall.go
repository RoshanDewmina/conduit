package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// runUninstall reverses runInstall: it tears down the service unit, the shim
// wrappers, and the installed binary. It is best-effort and idempotent — a
// missing file is not an error, so it is safe to run repeatedly or after a
// partial install. User data (~/.lancer config, pairings, Keychain entries) and
// the Claude hook are left intact by design; the function prints how to remove
// those by hand so an uninstall never silently discards credentials or rules.
func runUninstall() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	binDir := filepath.Join(home, ".lancer", "bin")

	switch runtime.GOOS {
	case "darwin":
		uninstallLaunchd(home)
	case "linux":
		uninstallSystemd(home)
	default:
		fmt.Fprintf(os.Stderr, "No service unit to remove on %s.\n", runtime.GOOS)
	}

	// Shim wrappers (one per intercepted agent) and the installed binary.
	var removed []string
	for _, agent := range shimAgents {
		if removeIfExists(filepath.Join(binDir, agent)) {
			removed = append(removed, agent)
		}
	}
	if len(removed) > 0 {
		fmt.Fprintf(os.Stderr, "Removed shim wrappers for: %v\n", removed)
	}
	if removeIfExists(filepath.Join(binDir, "lancerd")) {
		fmt.Fprintf(os.Stderr, "Removed %s\n", filepath.Join(binDir, "lancerd"))
	}

	fmt.Fprintln(os.Stderr, "Lancer service uninstalled.")
	fmt.Fprintln(os.Stderr, "Left intact (remove by hand if you want a full wipe):")
	fmt.Fprintf(os.Stderr, "  config + pairings:  rm -rf %s\n", filepath.Join(home, ".lancer"))
	fmt.Fprintf(os.Stderr, "  Claude hook:        see %s and remove the Lancer PreToolUse block\n", claudeSettingsPath(home))
	fmt.Fprintln(os.Stderr, "  Keychain keys:      removed via the Lancer app's Trust settings, not here")
	return nil
}

// launchdPlistPath is the per-user LaunchAgent written by installLaunchd. Kept
// here next to its consumer; mirrors the literal in installLaunchd.
func launchdPlistPath(home string) string {
	return filepath.Join(home, "Library", "LaunchAgents", "dev.lancer.lancerd.plist")
}

func uninstallLaunchd(home string) {
	plistPath := launchdPlistPath(home)
	if _, err := os.Stat(plistPath); err != nil {
		fmt.Fprintln(os.Stderr, "No launchd unit installed.")
		return
	}
	// Stop it before removing the plist so launchd doesn't keep the old job.
	if _, err := exec.LookPath("launchctl"); err == nil {
		_ = exec.Command("launchctl", "unload", plistPath).Run()
	}
	if removeIfExists(plistPath) {
		fmt.Fprintf(os.Stderr, "Removed %s\n", plistPath)
	}
}

func uninstallSystemd(home string) {
	unitPath := filepath.Join(home, ".config", "systemd", "user", "lancerd.service")
	if _, err := os.Stat(unitPath); err != nil {
		fmt.Fprintln(os.Stderr, "No systemd unit installed.")
		return
	}
	if _, err := exec.LookPath("systemctl"); err == nil {
		_ = exec.Command("systemctl", "--user", "disable", "--now", "lancerd.service").Run()
	}
	if removeIfExists(unitPath) {
		fmt.Fprintf(os.Stderr, "Removed %s\n", unitPath)
	}
	if _, err := exec.LookPath("systemctl"); err == nil {
		_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	}
}

// removeIfExists deletes path, reporting whether it was actually there. A
// not-exist is treated as "nothing to do" (returns false, no error) so callers
// can stay idempotent.
func removeIfExists(path string) bool {
	if _, err := os.Stat(path); err != nil {
		return false
	}
	if err := os.Remove(path); err != nil {
		fmt.Fprintf(os.Stderr, "warning: could not remove %s: %v\n", path, err)
		return false
	}
	return true
}
