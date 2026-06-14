package main

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"os"
)

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

	relayURL := os.Getenv("CONDUIT_RELAY_URL")
	if relayURL == "" {
		relayURL = "wss://relay.conduit.dev"
	}

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
