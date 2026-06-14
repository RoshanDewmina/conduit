package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
)

const frameVersion = 1
const nonceByteCount = 12
const frameAAD = "conduit-frame-v1"

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

	saltSeed := sha256.Sum256([]byte("conduit-pairing:" + helperID))
	info := []byte("conduit-v1:" + helperKeyB64 + ":" + appKeyB64)

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
