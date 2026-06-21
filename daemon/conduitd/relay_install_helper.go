package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"

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
	V                int    `json:"v"`
	Relay            string `json:"relay"`
	Code             string `json:"code"`
	PK               string `json:"pk"`
	AccountBackend   string `json:"accountBackend,omitempty"`
	AccountChallenge string `json:"accountChallenge,omitempty"`
	AccountSecret    string `json:"accountSecret,omitempty"`
}

func printRelayInstructions() {
	code, err := generatePairingCode()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating code: %v\n", err)
		return
	}

	relayURL := resolveRelayURL()

	// Generate an X25519 keypair so the QR carries the daemon's public key —
	// the phone uses it to derive the shared session key. Persist the keypair
	// alongside the code so the resident daemon can connect to the relay with
	// the same identity the phone scanned.
	priv, pub, err := generateKeyPair()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error generating keypair: %v\n", err)
		return
	}

	pubB64 := base64URLEncode(pub[:])
	privB64 := base64URLEncode(priv[:])

	payload := qrPairingPayload{
		V:     1,
		Relay: relayURL,
		Code:  code,
		PK:    pubB64,
	}
	if backendURL := strings.TrimSpace(os.Getenv("CONDUIT_ACCOUNT_BACKEND_URL")); backendURL != "" {
		challenge, err := createAccountDeviceChallenge(backendURL, hostnameForPairing(), publicKeyFingerprint(pubB64))
		if err != nil {
			fmt.Fprintf(os.Stderr, "warning: account device binding unavailable: %v\n", err)
		} else {
			payload.AccountBackend = backendURL
			payload.AccountChallenge = challenge.ID
			payload.AccountSecret = challenge.Secret
		}
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

	// Persist the pairing config so the resident daemon connects to the relay.
	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   relayURL,
		Code:       code,
		PrivateKey: privB64,
		PublicKey:  pubB64,
	}); err != nil {
		fmt.Fprintf(os.Stderr, "warning: failed to persist relay pairing: %v\n", err)
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
║   After scanning, the daemon will        ║
║   connect to the relay automatically.    ║
║                                          ║
╚══════════════════════════════════════════╝

`, code, relayURL)
	if payload.AccountChallenge != "" {
		fmt.Println("This QR also contains a one-time account device-binding challenge.")
		fmt.Println("On a signed-in phone, choose “bind this daemon to my account”.")
		if credential, err := waitForAccountDeviceCredential(payload.AccountBackend, payload.AccountChallenge, payload.AccountSecret, 10*time.Minute); err != nil {
			fmt.Fprintf(os.Stderr, "account device binding not completed: %v\n", err)
		} else if err := writeAccountDeviceCredential(credential); err != nil {
			fmt.Fprintf(os.Stderr, "warning: account device credential was issued but could not be stored: %v\n", err)
		} else {
			fmt.Println("Account device binding complete. No account password was requested.")
		}
	}
}
