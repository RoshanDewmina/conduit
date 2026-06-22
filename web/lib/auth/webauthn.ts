const LS_KEY = "lancer.webauthn.credId";
const RP_NAME = "Lancer";

function bufToB64u(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64uToBuf(s: string): ArrayBuffer {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4 === 0 ? 0 : 4 - (s.length % 4);
  const bin = atob(s + "=".repeat(pad));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

export async function isWebAuthnAvailable(): Promise<boolean> {
  if (typeof window === "undefined" || !window.PublicKeyCredential) return false;
  try {
    return await window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
  } catch {
    return false;
  }
}

async function randomChallenge(): Promise<Uint8Array<ArrayBuffer>> {
  return crypto.getRandomValues(new Uint8Array(32));
}

export async function ensureCredential(): Promise<string> {
  const existing = localStorage.getItem(LS_KEY);
  if (existing) return existing;
  const challenge = await randomChallenge();
  const userId = crypto.getRandomValues(new Uint8Array(16));
  const cred = (await navigator.credentials.create({
    publicKey: {
      challenge,
      rp: { name: RP_NAME, id: window.location.hostname },
      user: { id: userId, name: "lancer-operator", displayName: "Lancer Operator" },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 },
        { type: "public-key", alg: -257 },
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        userVerification: "required",
        residentKey: "preferred",
      },
      timeout: 60000,
      attestation: "none",
    },
  })) as PublicKeyCredential | null;
  if (!cred) throw new Error("credential creation returned null");
  const id = bufToB64u(cred.rawId);
  localStorage.setItem(LS_KEY, id);
  return id;
}

export async function verifyPresence(): Promise<void> {
  const id = await ensureCredential();
  const challenge = await randomChallenge();
  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge,
      allowCredentials: [{ type: "public-key", id: b64uToBuf(id) }],
      userVerification: "required",
      timeout: 60000,
    },
  });
  if (!assertion) throw new Error("verification cancelled");
}
