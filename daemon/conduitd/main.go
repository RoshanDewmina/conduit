package main

import (
	"fmt"
	"os"
)

// version is overridable at build time via -ldflags "-X main.version=<v>"
// (see scripts/release-conduitd.sh). A var, not a const, so release builds
// report the real version instead of a misleading hardcoded default.
var version = "0.1.0-dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "version", "--version", "-v":
		fmt.Println(version)

	case "daemon":
		if err := runDaemon(); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd daemon:", err)
			os.Exit(1)
		}

	case "serve":
		if err := runServe(); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd serve:", err)
			os.Exit(1)
		}

	case "install":
		if err := runInstall(); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd install:", err)
			os.Exit(1)
		}

	case "agent-hook":
		if err := runAgentHook(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd agent-hook:", err)
			os.Exit(1)
		}

	case "relay":
		if err := runRelay(); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd relay:", err)
			os.Exit(1)
		}

	case "pair":
		printRelayInstructions()

	case "relay-attach":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: conduitd relay-attach <pairing-code>")
			os.Exit(1)
		}
		code := os.Args[2]
		relayURL := resolveRelayURL()
		priv, pub, err := generateKeyPair()
		if err != nil {
			fmt.Fprintf(os.Stderr, "error generating keypair: %v\n", err)
			os.Exit(1)
		}
		if err := writeRelayPairing(&relayPairConfig{
			RelayURL:   relayURL,
			Code:       code,
			PrivateKey: base64URLEncode(priv[:]),
			PublicKey:  base64URLEncode(pub[:]),
		}); err != nil {
			fmt.Fprintf(os.Stderr, "error writing relay pairing: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "Relay pairing saved for code %s at %s.\n", code, relayURL)
		fmt.Fprintf(os.Stderr, "Restart conduitd daemon (or it will auto-detect within 5s).\n")

	case "doctor":
		if err := runDoctor(); err != nil {
			os.Exit(1)
		}

	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func runRelay() error {
	relayURL := resolveRelayURL()
	pairingCode := os.Getenv("CONDUIT_PAIRING_CODE")
	if pairingCode == "" {
		return fmt.Errorf("CONDUIT_PAIRING_CODE required")
	}

	// Build a server so incoming approvalResponse messages route through the same
	// applyDecision chokepoint as every other delivery path.
	srv := newServer(serverHome())

	// The router is installed on the client as its messageHandler via
	// newE2ERouter, so the initial handler here is only a placeholder until the
	// router replaces it on construction.
	client := newE2ERelayClient(relayURL, pairingCode, nil)
	if client == nil {
		return fmt.Errorf("failed to create relay client")
	}

	router := newE2ERouter(client, srv)
	srv.setE2ERouter(router)

	client.start()

	select {}
}

func usage() {
	fmt.Fprintln(os.Stderr, `conduitd - Conduit remote daemon

Usage:
  conduitd daemon          Run resident bridge (Unix socket, persistent queue)
  conduitd serve           Attach to resident; relay JSON-RPC over stdio
  conduitd install         Install binary + launchd/systemd unit for daemon
  conduitd relay           Connect to push-backend relay for E2E messaging
  conduitd pair            Generate a pairing code for relay setup instructions
  conduitd relay-attach    Save an existing pairing code for the resident daemon
  conduitd agent-hook ...  Send approval event from agent pre-tool hook
  conduitd doctor          Run setup/health self-check (✓/⚠/✗ checklist)
  conduitd version         Print version`)
}
