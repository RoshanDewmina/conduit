package main

import "encoding/json"

// pairBeginParams are the optional params for agent.pair.begin. RelayURL lets
// a GUI client override the relay endpoint; when empty resolveRelayURL's
// default/env resolution (LANCER_RELAY_URL) applies, matching the CLI.
type pairBeginParams struct {
	RelayURL string `json:"relayURL,omitempty"`
	Force    bool   `json:"force,omitempty"`
}

// pairBeginResult is the agent.pair.begin RPC result. Field names/shapes are
// fixed — Lancer for Mac is built against this exact contract. qrPayload is
// the qrPairingPayload marshaled to a JSON string (not a nested object) so
// the client can hand it straight to a QR renderer the same way the phone
// scans the CLI's printed QR code.
type pairBeginResult struct {
	Relay     string `json:"relay"`
	Code      string `json:"code"`
	PublicKey string `json:"publicKey"`
	QRPayload string `json:"qrPayload"`
}

// beginPairing generates a fresh pairing code + X25519 keypair, persists the
// relay pairing config (so the resident's relay watcher picks it up and
// connects), and returns the data a GUI client needs to render the same QR /
// code the `lancerd pair` CLI prints. It reuses the exact helpers
// printRelayInstructions uses rather than re-deriving any crypto.
func beginPairing(params pairBeginParams) (*pairBeginResult, error) {
	code, err := generatePairingCode()
	if err != nil {
		return nil, err
	}

	relayURL := params.RelayURL
	if relayURL == "" {
		relayURL = resolveRelayURL()
	}

	priv, pub, err := generateKeyPair()
	if err != nil {
		return nil, err
	}

	pubB64 := base64URLEncode(pub[:])
	privB64 := base64URLEncode(priv[:])

	payload := qrPairingPayload{
		V:     1,
		Relay: relayURL,
		Code:  code,
		PK:    pubB64,
	}
	qrData, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	if err := writeRelayPairingAllowReplace(&relayPairConfig{
		RelayURL:   relayURL,
		Code:       code,
		PrivateKey: privB64,
		PublicKey:  pubB64,
	}, params.Force); err != nil {
		return nil, err
	}

	return &pairBeginResult{
		Relay:     relayURL,
		Code:      code,
		PublicKey: pubB64,
		QRPayload: string(qrData),
	}, nil
}
