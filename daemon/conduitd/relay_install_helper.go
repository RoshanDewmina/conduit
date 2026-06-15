package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"strings"

	qrcode "github.com/skip2/go-qrcode"
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

// qrPairingPayload matches the iOS QRPairingPayload Codable struct so the
// phone can scan the QR shown by conduitd pair and extract the relay URL,
// pairing code, and the daemon's ephemeral public key.
type qrPairingPayload struct {
	V     int    `json:"v"`
	Relay string `json:"relay"`
	Code  string `json:"code"`
	PK    string `json:"pk"`
}

func printRelayInstructions() {
	code, err := generatePairingCode()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating code: %v\n", err)
		return
	}

	relayURL := resolveRelayURL()

	// Generate an ephemeral X25519 keypair so the QR carries the daemon's
	// public key — the phone uses it to derive the shared session key.
	priv, pub, err := generateKeyPair()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating keypair: %v\n", err)
		return
	}
	_ = priv // retained until the relay session starts; the pair subcommand
	// is ephemeral (it prints once and exits), so the key is scoped to the

	payload := qrPairingPayload{
		V:     1,
		Relay: relayURL,
		Code:  code,
		PK:    base64URLEncode(pub[:]),
	}
	qrData, err := json.Marshal(payload)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error marshalling QR payload: %v\n", err)
		return
	}

	qr, err := qrcode.New(string(qrData), qrcode.Medium)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating QR code: %v\n", err)
		return
	}

	// ANSI QR (inverted for dark terminals).
	ansiQR := qr.ToString(true)

	fmt.Printf(`
╔══════════════════════════════════════════╗
║         Conduit E2E Relay Pairing       ║
╠══════════════════════════════════════════╣
║                                          ║
║   Scan this QR code with Conduit:        ║
║                                          ║
`)
	for _, line := range strings.Split(ansiQR, "\n") {
		trimmed := strings.TrimRight(line, " ")
		if trimmed == "" {
			continue
		}
		fmt.Printf("║   %s   ║\n", trimmed)
	}
	fmt.Printf(`║                                          ║
║   Or enter the code manually:             ║
║       ┌──────────────────┐               ║
║       │    %s    │               ║
║       └──────────────────┘               ║
║                                          ║
║   Relay server: %s  ║
║                                          ║
║   Open Conduit on your phone, tap        ║
║   "Relay Pairing" and scan this QR.      ║
║                                          ║
╚══════════════════════════════════════════╝

`, code, relayURL)
}