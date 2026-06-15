package main

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"os"
	"strings"
)

// defaultRelayURL is the fallback blind-relay endpoint used when CONDUIT_RELAY_URL
// is unset. Self-hosters point CONDUIT_RELAY_URL at their own relay (e.g. a
// Tailscale Funnel hostname: wss://<host>.<tailnet>.ts.net/ws/relay base, or a
// GCP VM). See daemon/push-backend/DEPLOY.md.
const defaultRelayURL = "wss://relay.conduit.dev"

// resolveRelayURL returns the relay base URL: CONDUIT_RELAY_URL when set
// (trimmed), otherwise defaultRelayURL. The single source of truth for the relay
// endpoint across conduitd — every relay consumer must call this rather than
// reading the env var or the literal directly.
func resolveRelayURL() string {
	if v := strings.TrimSpace(os.Getenv("CONDUIT_RELAY_URL")); v != "" {
		return v
	}
	return defaultRelayURL
}

func generatePairingCode() (string, error) {
	code := make([]byte, 6)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		code[i] = byte('0') + byte(n.Int64())
	}
	return string(code), nil
}

func printRelayInstructions() {
	code, err := generatePairingCode()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating code: %v\n", err)
		return
	}

	relayURL := resolveRelayURL()

	fmt.Printf(`
╔══════════════════════════════════════════╗
║         Conduit E2E Relay Pairing       ║
╠══════════════════════════════════════════╣
║                                          ║
║   Your pairing code:                     ║
║                                          ║
║       ┌──────────────────┐               ║
║       │    %s    │               ║
║       └──────────────────┘               ║
║                                          ║
║   Relay server: %s  ║
║                                          ║
║   Open Conduit on your phone, tap        ║
║   "Relay Pairing" and enter this code.   ║
║                                          ║
╚══════════════════════════════════════════╝

`, code, relayURL)
}
