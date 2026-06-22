package main

import ("os/exec"; "strings")

func countRunningProcesses(processName string, argvContains []string) int {
	pattern := processName
	if len(argvContains) > 0 { pattern = argvContains[0] }
	out, err := exec.Command("pgrep", "-f", pattern).Output()
	if err != nil { return 0 }
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) == 1 && lines[0] == "" { return 0 }
	return len(lines)
}
