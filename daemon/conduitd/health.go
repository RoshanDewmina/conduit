package main

import (
	"net"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

type hostHealth struct {
	Hostname            string          `json:"hostname"`
	Status              string          `json:"status"`
	IsAsleep            *bool           `json:"isAsleep,omitempty"`
	IsOnBattery         *bool           `json:"isOnBattery,omitempty"`
	BatteryPercent      *int            `json:"batteryPercent,omitempty"`
	IsPluggedIn         *bool           `json:"isPluggedIn,omitempty"`
	LidClosed           *bool           `json:"lidClosed,omitempty"`
	NetworkReachable    bool            `json:"networkReachable"`
	InterfaceType       *string         `json:"interfaceType,omitempty"`
	DaemonVersion       string          `json:"daemonVersion"`
	Uptime              float64         `json:"uptime"`
	LastPhoneContact    *time.Time      `json:"lastPhoneContact,omitempty"`
	ApnsTokenFresh      bool            `json:"apnsTokenFresh"`
	HooksInstalled      bool            `json:"hooksInstalled"`
	LocalModelEndpoints []modelEndpoint `json:"localModelEndpoints"`
}

type modelEndpoint struct {
	Name      string `json:"name"`
	URL       string `json:"url"`
	Reachable bool   `json:"reachable"`
}

var daemonStartTime = time.Now()

func collectHostHealth() hostHealth {
	h := hostHealth{
		DaemonVersion:      version,
		NetworkReachable:   true,
		ApnsTokenFresh:     true,
		HooksInstalled:     checkHooksInstalled(),
		LocalModelEndpoints: probeLocalModels(),
	}

	if name, err := os.Hostname(); err == nil {
		h.Hostname = name
	}

	if runtime.GOOS == "darwin" {
		collectMacHealth(&h)
	}

	h.Uptime = time.Since(daemonStartTime).Seconds()

	if h.IsAsleep != nil && *h.IsAsleep {
		h.Status = "sleeping"
	} else if !h.NetworkReachable {
		h.Status = "unreachable"
	} else if h.IsOnBattery != nil && *h.IsOnBattery && h.BatteryPercent != nil && *h.BatteryPercent < 20 {
		h.Status = "degraded"
	} else {
		h.Status = "healthy"
	}

	return h
}

func collectMacHealth(h *hostHealth) {
	if out, err := execCommand("pmset", "-g", "batt"); err == nil {
		lines := strings.Split(out, "\n")
		for _, line := range lines {
			if strings.Contains(line, "%") {
				h.IsOnBattery = boolPtr(!strings.Contains(line, "charging"))
				h.IsPluggedIn = boolPtr(strings.Contains(line, "charging") || strings.Contains(line, "charged"))
				if idx := strings.Index(line, "%"); idx > 0 {
					start := idx - 1
					for start > 0 && line[start-1] >= '0' && line[start-1] <= '9' {
						start--
					}
					if pct := parseIntSafe(line[start:idx]); pct > 0 {
						h.BatteryPercent = &pct
					}
				}
			}
		}
	}

	if out, err := execCommand("pmset", "-g", "assertions"); err == nil {
		// A running process can't observe actual sleep, so the meaningful signal is
		// sleep *eligibility*: idle-sleep is permitted (no PreventUserIdleSystemSleep
		// wake-lock held) AND the host is on battery, where macOS will idle-sleep and
		// drop the daemon. Plugged-in or wake-locked hosts report IsAsleep=false.
		sleepPrevented := assertionHeld(out, "PreventUserIdleSystemSleep") ||
			assertionHeld(out, "PreventUserIdleDisplaySleep")
		onBattery := h.IsOnBattery != nil && *h.IsOnBattery
		asleep := !sleepPrevented && onBattery
		h.IsAsleep = &asleep
	}
}

// assertionHeld reports whether the named pmset assertion is held with a nonzero
// count. The `pmset -g assertions` summary lists each assertion as
// "<Name>                 <count>", so the name appearing with a count of 0 means
// it is registered but NOT currently asserted.
func assertionHeld(out, name string) bool {
	for _, line := range strings.Split(out, "\n") {
		idx := strings.Index(line, name)
		if idx < 0 {
			continue
		}
		rest := strings.TrimSpace(line[idx+len(name):])
		if rest == "" {
			continue
		}
		return parseIntSafe(rest) > 0
	}
	return false
}

func checkHooksInstalled() bool {
	home, _ := os.UserHomeDir()
	paths := []string{
		home + "/.claude/settings.json",
		home + "/.codex/hooks.json",
		home + "/.config/opencode/hooks.json",
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return true
		}
	}
	return false
}

func probeLocalModels() []modelEndpoint {
	endpoints := []modelEndpoint{
		{Name: "ollama", URL: "http://localhost:11434"},
		{Name: "lm-studio", URL: "http://localhost:1234"},
	}
	for i := range endpoints {
		conn, err := net.DialTimeout("tcp", extractHostPort(endpoints[i].URL), 500*time.Millisecond)
		if err == nil {
			conn.Close()
			endpoints[i].Reachable = true
		}
	}
	return endpoints
}

func execCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	return string(out), err
}

func boolPtr(b bool) *bool { return &b }

func parseIntSafe(s string) int {
	n := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}

func extractHostPort(url string) string {
	url = strings.TrimPrefix(url, "http://")
	url = strings.TrimPrefix(url, "https://")
	if !strings.Contains(url, ":") {
		url = url + ":80"
	}
	return url
}
