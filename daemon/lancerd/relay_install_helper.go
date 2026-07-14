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

// defaultRelayURL is the fallback blind-relay endpoint used when LANCER_RELAY_URL
// is unset. This is the live hosted relay (Fly.io) the iOS app ships pointed at
// (project.yml LANCER_PUSH_BACKEND_URL), so testers pair out of the box with no
// extra config. Self-hosters override it via LANCER_RELAY_URL to point at their
// own relay (e.g. a Tailscale Funnel hostname or a GCP VM). See daemon/push-backend/DEPLOY.md.
const (
	retiredHostedRelayURL = "wss://conduit-push-y4wpy6zeva-ts.a.run.app"
	defaultRelayURL       = "wss://conduit-push.fly.dev"
)

// resolveRelayURL returns the relay base URL: LANCER_RELAY_URL when set
// (trimmed), otherwise defaultRelayURL. The single source of truth for the relay
// endpoint across lancerd — every relay consumer must call this rather than
// reading the env var or the literal directly.
func resolveRelayURL() string {
	if v := strings.TrimSpace(os.Getenv("LANCER_RELAY_URL")); v != "" {
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
// phone can scan the QR shown by lancerd pair and extract the relay URL,
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
	if backendURL := strings.TrimSpace(os.Getenv("LANCER_ACCOUNT_BACKEND_URL")); backendURL != "" {
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
	// Explicit `lancerd pair` is intentional re-onboarding — may replace a
	// confirmed pairing (and orphan phones on the previous code).
	if err := writeRelayPairingReplacing(&relayPairConfig{
		RelayURL:   relayURL,
		Code:       code,
		PrivateKey: privB64,
		PublicKey:  pubB64,
	}); err != nil {
		fmt.Fprintf(os.Stderr, "warning: failed to persist relay pairing: %v\n", err)
	}

	// ANSI QR uses terminal block characters by design; keep the surrounding
	// instructions plain so they render cleanly in any terminal or log capture.
	ansiQR := qr.ToString(true)

	fmt.Println("Lancer relay pairing")
	fmt.Println("1. Open Lancer on your phone and choose Add a machine > Pair over relay.")
	fmt.Println("2. Scan this QR code, or enter the six-digit code below.")
	fmt.Println()
	fmt.Println(ansiQR)
	fmt.Printf("Pairing code: %s\n", code)
	fmt.Printf("Relay: %s\n", relayURL)
	fmt.Println("3. Pairing completes automatically after the phone connects.")
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
