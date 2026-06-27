import { x25519 } from "@noble/curves/ed25519.js";
import { hkdf } from "@noble/hashes/hkdf.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { chacha20poly1305 } from "@noble/ciphers/chacha.js";
import type { EncryptedFrame } from "./types";

const enc = new TextEncoder();
const dec = new TextDecoder();

export function b64uEncode(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
export function b64uDecode(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4 === 0 ? 0 : 4 - (s.length % 4);
  const bin = atob(s + "=".repeat(pad));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function generateKeyPair(): { priv: Uint8Array; pub: Uint8Array } {
  const priv = x25519.utils.randomSecretKey();
  const pub = x25519.getPublicKey(priv);
  return { priv, pub };
}

/** Phone(web)-side derivation. helperKeyB64 = daemon key, appKeyB64 = own(phone) key. */
export function deriveSessionKey(ownPriv: Uint8Array, daemonPubB64: string, ownPubB64: string): Uint8Array {
  const daemonPub = b64uDecode(daemonPubB64);
  const shared = x25519.getSharedSecret(ownPriv, daemonPub);
  const salt = sha256(enc.encode("lancer-pairing:lancer-relay"));
  const info = enc.encode("lancer-v1:" + daemonPubB64 + ":" + ownPubB64);
  return hkdf(sha256, shared, salt, info, 32);
}

const AAD = enc.encode("lancer-frame-v1");

export function encryptFrame(plaintext: Uint8Array, key: Uint8Array): EncryptedFrame {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const sealed = chacha20poly1305(key, nonce, AAD).encrypt(plaintext);
  const ct = sealed.slice(0, sealed.length - 16);
  const tag = sealed.slice(sealed.length - 16);
  return { version: 1, nonce: b64uEncode(nonce), ciphertext: b64uEncode(ct), tag: b64uEncode(tag) };
}

export function decryptFrame(frame: EncryptedFrame, key: Uint8Array): Uint8Array {
  if (frame.version !== 1) throw new Error("unsupported frame version " + frame.version);
  const nonce = b64uDecode(frame.nonce);
  const ct = b64uDecode(frame.ciphertext);
  const tag = b64uDecode(frame.tag);
  const sealed = new Uint8Array(ct.length + tag.length);
  sealed.set(ct, 0); sealed.set(tag, ct.length);
  return chacha20poly1305(key, nonce, AAD).decrypt(sealed);
}

export const textEncode = (s: string) => enc.encode(s);
export const textDecode = (b: Uint8Array) => dec.decode(b);
