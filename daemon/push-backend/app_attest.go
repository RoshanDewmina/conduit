package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/fxamacker/cbor/v2"
)

// App Attest hardens the device-binding flow: the QR challenge secret proves
// the phone SAW this daemon's QR, but on its own a leaked/phished secret plus
// any signed-in session could bind the daemon. Requiring a verified App Attest
// attestation at bind time additionally proves the binding request came from a
// genuine, unmodified Lancer app on real Apple hardware. Verification follows
// Apple's "Validating apps that connect to your server" steps 1-9:
// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server

// Fetched 2026-07-04 from
// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
const appleAppAttestRootCAPEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`

var appAttestNonceOID = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}

type appAttestConfig struct {
	TeamID   string
	BundleID string
	// Env selects the expected aaguid: "production" (default) or "development"
	// (dev-signed builds attest with the appattestdevelop aaguid).
	Env string
}

func (c appAttestConfig) enabled() bool { return c.TeamID != "" && c.BundleID != "" }

func (c appAttestConfig) appID() string { return c.TeamID + "." + c.BundleID }

func (c appAttestConfig) expectedAAGUID() []byte {
	if c.Env == "development" {
		return []byte("appattestdevelop")
	}
	return append([]byte("appattest"), 0, 0, 0, 0, 0, 0, 0)
}

func loadAppAttestConfig() appAttestConfig {
	env := strings.TrimSpace(os.Getenv("APP_ATTEST_ENV"))
	if env == "" {
		env = "production"
	}
	return appAttestConfig{
		TeamID:   strings.TrimSpace(os.Getenv("APP_ATTEST_TEAM_ID")),
		BundleID: strings.TrimSpace(os.Getenv("APP_ATTEST_BUNDLE_ID")),
		Env:      env,
	}
}

var activeAppAttestConfig = loadAppAttestConfig()

func setAppAttestConfigForTest(cfg appAttestConfig) { activeAppAttestConfig = cfg }

// appAttestStartupCheck mirrors relaySecretStartupCheck: refusing to serve an
// unattested binding endpoint in production is the fail-closed default; local
// dev (and the simulator, which cannot attest at all) warns and continues.
func appAttestStartupCheck(enabled, isProd bool) (fatal, warn string) {
	if enabled {
		return "", ""
	}
	if isProd {
		return "SECURITY: APP_ATTEST_TEAM_ID/APP_ATTEST_BUNDLE_ID are unset in a production deployment. " +
			"POST /v1/devices/bind would accept a QR challenge secret plus any signed-in session with no " +
			"proof the request came from a genuine Lancer app — set both (and APP_ATTEST_ENV if not production) " +
			"or the binding trust boundary is weaker than documented.", ""
	}
	return "", "SECURITY WARNING: App Attest is not configured (APP_ATTEST_TEAM_ID/APP_ATTEST_BUNDLE_ID unset) — " +
		"device binding will accept requests without hardware attestation. Fine for local dev/simulator; " +
		"required in production."
}

func warnIfAppAttestDisabled() {
	fatal, warn := appAttestStartupCheck(activeAppAttestConfig.enabled(), relayProductionDeployment())
	if fatal != "" {
		log.Fatal(fatal)
	}
	if warn != "" {
		log.Printf("%s", warn)
	}
}

// attestChallengeStore mints single-use, per-user server nonces the app folds
// into its attestation (clientDataHash), so a captured attestation object
// cannot be replayed against a later bind.
type attestChallengeStore struct {
	mu         sync.Mutex
	challenges map[string]attestChallenge
}

type attestChallenge struct {
	UserID    string
	Challenge []byte
	ExpiresAt time.Time
}

var activeAttestChallengeStore = &attestChallengeStore{challenges: map[string]attestChallenge{}}

func (s *attestChallengeStore) mint(userID string, now time.Time) (id string, challenge []byte, err error) {
	idBytes := make([]byte, 16)
	if _, err := rand.Read(idBytes); err != nil {
		return "", nil, err
	}
	challenge = make([]byte, 32)
	if _, err := rand.Read(challenge); err != nil {
		return "", nil, err
	}
	id = fmt.Sprintf("%x", idBytes)
	s.mu.Lock()
	defer s.mu.Unlock()
	for key, c := range s.challenges {
		if now.After(c.ExpiresAt) {
			delete(s.challenges, key)
		}
	}
	s.challenges[id] = attestChallenge{UserID: userID, Challenge: challenge, ExpiresAt: now.Add(5 * time.Minute)}
	return id, challenge, nil
}

// consume removes and returns the challenge — single-use whether or not the
// subsequent verification succeeds, so a failed attempt burns the nonce.
func (s *attestChallengeStore) consume(id, userID string, now time.Time) ([]byte, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.challenges[id]
	if !ok {
		return nil, false
	}
	delete(s.challenges, id)
	if c.UserID != userID || now.After(c.ExpiresAt) {
		return nil, false
	}
	return c.Challenge, true
}

// verifyAppAttestation validates an App Attest attestation object against the
// server challenge, per Apple's documented steps. Any failure is terminal for
// the bind — there is no partial credit.
func verifyAppAttestation(attestationB64, keyIDB64 string, challenge []byte, cfg appAttestConfig, now time.Time) error {
	attData, err := base64.StdEncoding.DecodeString(attestationB64)
	if err != nil {
		return fmt.Errorf("attestation not base64: %w", err)
	}
	keyID, err := base64.StdEncoding.DecodeString(keyIDB64)
	if err != nil || len(keyID) != 32 {
		return errors.New("keyId must be the base64 of a 32-byte key identifier")
	}

	var obj struct {
		Fmt     string `cbor:"fmt"`
		AttStmt struct {
			X5C     [][]byte `cbor:"x5c"`
			Receipt []byte   `cbor:"receipt"`
		} `cbor:"attStmt"`
		AuthData []byte `cbor:"authData"`
	}
	if err := cbor.Unmarshal(attData, &obj); err != nil {
		return fmt.Errorf("attestation CBOR decode: %w", err)
	}
	if obj.Fmt != "apple-appattest" {
		return fmt.Errorf("unexpected attestation format %q", obj.Fmt)
	}
	if len(obj.AttStmt.X5C) < 2 {
		return errors.New("attestation certificate chain too short")
	}

	// 1. Chain the credential certificate up to Apple's App Attest root.
	leaf, err := x509.ParseCertificate(obj.AttStmt.X5C[0])
	if err != nil {
		return fmt.Errorf("parse credential certificate: %w", err)
	}
	intermediates := x509.NewCertPool()
	for _, der := range obj.AttStmt.X5C[1:] {
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			return fmt.Errorf("parse intermediate certificate: %w", err)
		}
		intermediates.AddCert(cert)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM([]byte(appleAppAttestRootCAPEM)) {
		return errors.New("embedded Apple root CA failed to load")
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots:         roots,
		Intermediates: intermediates,
		CurrentTime:   now,
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return fmt.Errorf("certificate chain does not verify to Apple App Attest root: %w", err)
	}

	// 2-4. Recompute the nonce and compare it to the credential certificate's
	// 1.2.840.113635.100.8.2 extension.
	clientDataHash := sha256.Sum256(challenge)
	nonceInput := append(append([]byte{}, obj.AuthData...), clientDataHash[:]...)
	expectedNonce := sha256.Sum256(nonceInput)
	certNonce, err := appAttestNonceFromCert(leaf)
	if err != nil {
		return err
	}
	if !bytes.Equal(certNonce, expectedNonce[:]) {
		return errors.New("attestation nonce does not match the server challenge")
	}

	// 5. The key identifier is the SHA-256 of the attested public key.
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return errors.New("credential certificate does not hold an ECDSA key")
	}
	pubBytes := elliptic.Marshal(pub.Curve, pub.X, pub.Y)
	pubHash := sha256.Sum256(pubBytes)
	if !bytes.Equal(pubHash[:], keyID) {
		return errors.New("keyId does not match the attested public key")
	}

	// 6-9. Authenticator data: correct App ID, fresh counter, correct
	// environment, and a credential ID equal to the key identifier.
	if len(obj.AuthData) < 55 {
		return errors.New("authenticator data truncated")
	}
	appIDHash := sha256.Sum256([]byte(cfg.appID()))
	if !bytes.Equal(obj.AuthData[:32], appIDHash[:]) {
		return errors.New("attestation was generated for a different app")
	}
	if counter := binary.BigEndian.Uint32(obj.AuthData[33:37]); counter != 0 {
		return fmt.Errorf("attestation counter must be 0, got %d", counter)
	}
	if !bytes.Equal(obj.AuthData[37:53], cfg.expectedAAGUID()) {
		return errors.New("attestation environment (aaguid) mismatch")
	}
	credIDLen := int(binary.BigEndian.Uint16(obj.AuthData[53:55]))
	if len(obj.AuthData) < 55+credIDLen {
		return errors.New("authenticator data truncated (credential id)")
	}
	if credIDLen != len(keyID) || !bytes.Equal(obj.AuthData[55:55+credIDLen], keyID) {
		return errors.New("credential id does not match keyId")
	}
	return nil
}

// appAttestNonceFromCert extracts the expected-nonce octets from the
// credential certificate's App Attest extension: an OCTET STRING wrapping
// DER `SEQUENCE { [1] { OCTET STRING nonce } }`.
func appAttestNonceFromCert(cert *x509.Certificate) ([]byte, error) {
	for _, ext := range cert.Extensions {
		if !ext.Id.Equal(appAttestNonceOID) {
			continue
		}
		var seq asn1.RawValue
		if _, err := asn1.Unmarshal(ext.Value, &seq); err != nil {
			return nil, fmt.Errorf("attestation nonce extension: %w", err)
		}
		var ctx asn1.RawValue
		if _, err := asn1.Unmarshal(seq.Bytes, &ctx); err != nil {
			return nil, fmt.Errorf("attestation nonce extension inner: %w", err)
		}
		var raw asn1.RawValue
		if _, err := asn1.Unmarshal(ctx.Bytes, &raw); err != nil || raw.Tag != asn1.TagOctetString || len(raw.Bytes) == 0 {
			return nil, errors.New("attestation nonce extension has no octet string")
		}
		return raw.Bytes, nil
	}
	return nil, errors.New("credential certificate is missing the App Attest nonce extension")
}
