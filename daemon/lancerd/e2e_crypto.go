package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
)

const frameVersion = 1
const nonceByteCount = 12
const frameAAD = "lancer-frame-v1"

func generateKeyPair() (privateKey [32]byte, publicKey [32]byte, err error) {
	if _, err := rand.Read(privateKey[:]); err != nil {
		return privateKey, publicKey, err
	}
	privateKey[0] &= 248
	privateKey[31] &= 127
	privateKey[31] |= 64

	pk, err := curve25519.X25519(privateKey[:], curve25519.Basepoint)
	if err != nil {
		return privateKey, publicKey, err
	}
	copy(publicKey[:], pk)
	return privateKey, publicKey, nil
}

func deriveSessionKey(privateKey [32]byte, peerPublicKeyB64 string, helperID string, helperKeyB64 string, appKeyB64 string) ([]byte, error) {
	peerKey, err := base64.RawURLEncoding.DecodeString(peerPublicKeyB64)
	if err != nil {
		return nil, err
	}

	shared, err := curve25519.X25519(privateKey[:], peerKey)
	if err != nil {
		return nil, err
	}

	saltSeed := sha256.Sum256([]byte("lancer-pairing:" + helperID))
	info := []byte("lancer-v1:" + helperKeyB64 + ":" + appKeyB64)

	hkdf := hkdf.New(sha256.New, shared, saltSeed[:], info)
	key := make([]byte, 32)
	if _, err := io.ReadFull(hkdf, key); err != nil {
		return nil, err
	}
	return key, nil
}

type encryptedFrame struct {
	Version    int    `json:"version"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	Tag        string `json:"tag"`
}

func encryptFrame(plaintext []byte, key []byte) (*encryptedFrame, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, err
	}

	nonce := make([]byte, nonceByteCount)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}

	ciphertext := aead.Seal(nil, nonce, plaintext, []byte(frameAAD))

	tag := ciphertext[len(ciphertext)-aead.Overhead():]
	ct := ciphertext[:len(ciphertext)-aead.Overhead()]

	return &encryptedFrame{
		Version:    frameVersion,
		Nonce:      base64.RawURLEncoding.EncodeToString(nonce),
		Ciphertext: base64.RawURLEncoding.EncodeToString(ct),
		Tag:        base64.RawURLEncoding.EncodeToString(tag),
	}, nil
}

func decryptFrame(frame *encryptedFrame, key []byte) ([]byte, error) {
	if frame.Version != frameVersion {
		return nil, fmt.Errorf("unsupported frame version %d", frame.Version)
	}

	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, err
	}

	nonce, err := base64.RawURLEncoding.DecodeString(frame.Nonce)
	if err != nil {
		return nil, err
	}

	ct, err := base64.RawURLEncoding.DecodeString(frame.Ciphertext)
	if err != nil {
		return nil, err
	}

	tag, err := base64.RawURLEncoding.DecodeString(frame.Tag)
	if err != nil {
		return nil, err
	}

	sealed := append(ct, tag...)

	plaintext, err := aead.Open(nil, nonce, sealed, []byte(frameAAD))
	if err != nil {
		return nil, err
	}

	return plaintext, nil
}

func base64URLEncode(data []byte) string {
	return base64.RawURLEncoding.EncodeToString(data)
}

func base64URLDecode(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

// seqFrame wraps a relay message body with a monotonically increasing
// per-direction sequence number BEFORE encryption, so the counter is covered
// by the AEAD tag but never visible to the relay itself — a relay-side
// attacker who can't decrypt still can't selectively drop-and-replay based on
// a visible sequence. Gen (optional, base64url) tags which reconnect
// "generation" of the sender minted this counter — see replaySequencer below
// for why this closes the stuck-Working/Retry-after-reconnect bug. A frame
// with no "gen" field is from a peer that hasn't upgraded yet; omitempty keeps
// the wire format byte-for-byte compatible with that peer.
type seqFrame struct {
	Seq  uint64          `json:"seq"`
	Gen  string          `json:"gen,omitempty"`
	Body json.RawMessage `json:"body"`
}

// wrapSeq wraps a frame with no generation tag — used by legacy/back-compat
// callers and tests that simulate a not-yet-upgraded peer. Real traffic from
// an upgraded sender goes through wrapSeqGen.
func wrapSeq(seq uint64, body []byte) ([]byte, error) {
	return json.Marshal(seqFrame{Seq: seq, Body: body})
}

// wrapSeqGen wraps a frame tagged with the sender's current generation id
// (minted fresh every time the sender resets its send counter — see
// newGeneration and its call sites in e2e_client.go).
func wrapSeqGen(seq uint64, gen string, body []byte) ([]byte, error) {
	return json.Marshal(seqFrame{Seq: seq, Gen: gen, Body: body})
}

func unwrapSeq(plaintext []byte) (seq uint64, gen string, body []byte, err error) {
	var f seqFrame
	if err := json.Unmarshal(plaintext, &f); err != nil {
		return 0, "", nil, err
	}
	return f.Seq, f.Gen, f.Body, nil
}

// newGeneration mints a fresh random per-generation tag: 16 random bytes,
// base64url-encoded. Minted at every point the sender resets its send
// counter to 0 (peer_joined / reconnect), so a stale in-flight frame from a
// PREVIOUS generation can never be mistaken for the first frame of a new one.
func newGeneration() (string, error) {
	buf := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// maxTrackedGenerations bounds replaySequencer.seenGens — a reconnect storm
// shouldn't grow this without limit. 32 is generous headroom for any
// realistic reconnect burst; oldest entries are evicted FIFO.
const maxTrackedGenerations = 32

// replayAccept classifies the outcome of replaySequencer.accept, so callers
// can log a stale-generation rejection (expected, harmless residue from a
// prior reconnect) distinctly from a true in-generation replay (the
// property this whole mechanism exists to catch).
type replayAccept int

const (
	replayAccepted replayAccept = iota
	replayRejectedReplay
	replayRejectedStaleGeneration
)

// replaySequencer is the fix for the stuck-Working/Retry-after-reconnect bug
// (5 prior sessions, 5 failed fixes): a bare monotonic counter (the original
// design) accepts ANY seq greater than the last one it saw, with no notion of
// WHICH reconnect generation that seq belongs to. reset() on peer_joined used
// to clear last/initialized outright — but a stale in-flight frame from the
// PREVIOUS generation (still decryptable: deriveSessionKey's inputs are the
// static pairing keys, so the session key never changes across reconnects)
// could arrive AFTER reset() and get accepted, poisoning `last` to its high
// seq — after which every legitimate new-generation frame (seq starting at 0)
// was rejected as "out of order" until the next peer_joined reset it again.
// That is exactly the P0 bug: one direction of the channel goes deaf for
// minutes after any reconnect.
//
// The fix tags every frame with the sender's generation id (see seqFrame.Gen
// / newGeneration) and tracks three things instead of one bare counter:
//   - currentGen: the generation the bare seq counter (last) belongs to.
//   - seenGens: a bounded set of RETIRED generations — frames tagged with one
//     of these are stale residue from before the last reconnect and must be
//     rejected without touching currentGen/last, no matter their seq.
//   - last/initialized: the monotonic counter for currentGen, exactly as
//     before.
//
// accept()'s rules, in order (gen == "" means the sender hasn't upgraded —
// this collapses to the original bare-counter behavior with no regression):
//  1. gen == currentGen: require seq > last (the original check).
//  2. gen != "" and gen is a retired generation (in seenGens): reject WITHOUT
//     touching currentGen/last — this is the line that kills the poisoning.
//  3. otherwise (a genuinely new generation, or the very first frame ever
//     seen): retire the old currentGen into seenGens and adopt the new one
//     unconditionally — the first frame of a new generation is always
//     accepted regardless of its seq value.
//
// reset() (called on every peer_joined) migrates the current generation into
// seenGens and clears last/initialized/currentGen — mirroring the original
// reset semantics for a not-yet-upgraded peer (rule 1 with gen == "" == "")
// while ensuring any frame still in flight from the JUST-retired generation
// hits rule 2, not rule 3, once accept() next sees it.
type replaySequencer struct {
	mu          sync.Mutex
	currentGen  string
	last        uint64
	initialized bool
	seenGens    []string
	seenGensSet map[string]struct{}
}

func (r *replaySequencer) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.currentGen != "" {
		r.rememberGenLocked(r.currentGen)
	}
	r.currentGen = ""
	r.last = 0
	r.initialized = false
}

// rememberGenLocked adds gen to the bounded seenGens set. Caller must hold mu.
func (r *replaySequencer) rememberGenLocked(gen string) {
	if r.seenGensSet == nil {
		r.seenGensSet = make(map[string]struct{})
	}
	if _, ok := r.seenGensSet[gen]; ok {
		return
	}
	r.seenGens = append(r.seenGens, gen)
	r.seenGensSet[gen] = struct{}{}
	if len(r.seenGens) > maxTrackedGenerations {
		oldest := r.seenGens[0]
		r.seenGens = r.seenGens[1:]
		delete(r.seenGensSet, oldest)
	}
}

func (r *replaySequencer) accept(gen string, seq uint64) replayAccept {
	r.mu.Lock()
	defer r.mu.Unlock()

	if gen == r.currentGen {
		if r.initialized && seq <= r.last {
			return replayRejectedReplay
		}
		r.last = seq
		r.initialized = true
		return replayAccepted
	}

	if gen != "" {
		if _, stale := r.seenGensSet[gen]; stale {
			return replayRejectedStaleGeneration
		}
	}

	if r.currentGen != "" {
		r.rememberGenLocked(r.currentGen)
	}
	r.currentGen = gen
	r.last = seq
	r.initialized = true
	return replayAccepted
}
