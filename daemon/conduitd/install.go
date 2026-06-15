package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func runInstall() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	binDir := filepath.Join(home, ".conduit", "bin")
	if err := os.MkdirAll(binDir, 0700); err != nil {
		return err
	}
	target := filepath.Join(binDir, "conduitd")
	if exe != target {
		data, err := os.ReadFile(exe)
		if err != nil {
			return fmt.Errorf("read binary: %w", err)
		}
		if err := os.WriteFile(target, data, 0755); err != nil {
			return fmt.Errorf("install binary: %w", err)
		}
		fmt.Fprintf(os.Stderr, "Installed %s\n", target)
	}

	if err := installClaudeHook(home); err != nil {
		// Hook wiring is best-effort: a failure here must not abort the daemon
		// install. Surface it so the owner can wire the hook by hand.
		fmt.Fprintf(os.Stderr, "warning: could not wire Claude PreToolUse hook: %v\n", err)
		fmt.Fprintln(os.Stderr, "  wire it manually — see docs/claude-settings-hook.json")
	}
	// TODO(opencode): wire the OpenCode PreToolUse hook (docs/opencode-hooks.json,
	// ~/.config/opencode/hooks/conduit-hook.sh) the same way once OpenCode
	// settings-merge is in scope. Finding #10 covers the Claude path above.

	switch runtime.GOOS {
	case "darwin":
		return installLaunchd(target, home)
	case "linux":
		return installSystemd(target, home)
	default:
		fmt.Fprintf(os.Stderr, "Unsupported OS %s — install binary only.\n", runtime.GOOS)
		return nil
	}
}

// installClaudeHook drops the PreToolUse hook script to ~/.claude/hooks and
// idempotently wires it into ~/.claude/settings.json so Claude Code actually
// calls it. Without the settings wiring the interactive approval path never
// fires (Finding #10).
func installClaudeHook(home string) error {
	scriptPath := claudeHookScriptPath(home)
	if err := os.MkdirAll(filepath.Dir(scriptPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(scriptPath, []byte(claudeHookScript), 0755); err != nil {
		return fmt.Errorf("write hook script: %w", err)
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", scriptPath)

	changed, err := wireClaudeHookSettings(home)
	if err != nil {
		return err
	}
	if changed {
		fmt.Fprintf(os.Stderr, "Wired PreToolUse hook into %s\n", claudeSettingsPath(home))
	} else {
		fmt.Fprintf(os.Stderr, "PreToolUse hook already wired in %s\n", claudeSettingsPath(home))
	}
	return nil
}

func installLaunchd(binary, home string) error {
	plistPath := filepath.Join(home, "Library", "LaunchAgents", "dev.conduit.conduitd.plist")
	if err := os.MkdirAll(filepath.Dir(plistPath), 0755); err != nil {
		return err
	}
	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.conduit.conduitd</string>
  <key>ProgramArguments</key>
  <array>
    <string>%s</string>
    <string>daemon</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>%s</string>
  <key>StandardErrorPath</key><string>%s</string>
</dict>
</plist>
`, binary, filepath.Join(home, ".conduit", "conduitd.stdout.log"), filepath.Join(home, ".conduit", "conduitd.stderr.log"))
	if err := os.WriteFile(plistPath, []byte(plist), 0644); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", plistPath)
	fmt.Fprintln(os.Stderr, "Owner steps:")
	fmt.Fprintf(os.Stderr, "  launchctl unload %s 2>/dev/null || true\n", plistPath)
	fmt.Fprintf(os.Stderr, "  launchctl load %s\n", plistPath)
	return nil
}

func installSystemd(binary, home string) error {
	unitDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(unitDir, 0755); err != nil {
		return err
	}
	unitPath := filepath.Join(unitDir, "conduitd.service")
	unit := fmt.Sprintf(`[Unit]
Description=Conduit resident bridge daemon

[Service]
ExecStart=%s daemon
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
`, binary)
	if err := os.WriteFile(unitPath, []byte(unit), 0644); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", unitPath)
	fmt.Fprintln(os.Stderr, "Owner steps:")
	fmt.Fprintln(os.Stderr, "  systemctl --user daemon-reload")
	fmt.Fprintln(os.Stderr, "  systemctl --user enable --now conduitd.service")
	if _, err := exec.LookPath("systemctl"); err == nil {
		_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	}
	return nil
}
