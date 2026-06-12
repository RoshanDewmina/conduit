package main

import (
	"crypto/rand"
	"encoding/base64"
)

// generateRelayToken mints a per-session capability secret: 32 bytes from
// crypto/rand, base64url-encoded without padding (43 chars). It is the token the
// app and conduitd present as `Authorization: Bearer <relayToken>` on the
// decision-relay endpoints. TREAT AS A SECRET — never log it.
func generateRelayToken() (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b[:]), nil
}
