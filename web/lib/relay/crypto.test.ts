import { test, expect } from "bun:test";
import vectors from "./__fixtures__/vectors.json";
import { deriveSessionKey, encryptFrame, decryptFrame, b64uEncode, b64uDecode, textEncode, textDecode } from "./crypto";

test("session key matches Go daemon", () => {
  const key = deriveSessionKey(b64uDecode(vectors.phonePrivB64), vectors.daemonPubB64, vectors.phonePubB64);
  expect(b64uEncode(key)).toBe(vectors.sessionKeyB64);
});

test("AEAD ciphertext+tag match Go daemon (fixed nonce)", () => {
  const key = b64uDecode(vectors.sessionKeyB64);
  const pt = decryptFrame({ version: 1, nonce: vectors.frame.nonceB64, ciphertext: vectors.frame.ciphertextB64, tag: vectors.frame.tagB64 }, key);
  expect(textDecode(pt)).toBe(vectors.frame.plaintext);
  const rt = encryptFrame(textEncode("hello-conduit"), key);
  expect(textDecode(decryptFrame(rt, key))).toBe("hello-conduit");
});
