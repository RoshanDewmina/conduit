import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Security Architecture — Conduit",
  description:
    "Conduit security architecture, threat model, and cryptographic design for SSH-based agent approval.",
};

export default function SecurityPage() {
  return (
    <div className="flex flex-col min-h-screen bg-bg text-fg">
      <header className="border-b border-line px-6 py-4">
        <nav className="max-w-3xl mx-auto flex items-center justify-between">
          <Link
            href="/"
            className="font-display text-sm font-semibold tracking-tight text-fg"
          >
            conduit<span className="text-accent">_</span>
          </Link>
        </nav>
        <div className="spectrum-line h-px w-full mt-4" />
      </header>

      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-16">
        <h1 className="font-display text-3xl font-bold text-fg mb-2 leading-none">
          security architecture<span className="text-accent">_</span>
        </h1>
        <p className="font-mono text-sm text-faint mb-10">
          Last updated: <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">{`{{DATE}}`}</code>. Bundle ID:{" "}
          <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
            dev.conduit.mobile
          </code>
        </p>

        <p className="font-mono text-sm text-dim leading-relaxed mb-10 italic border-l border-line pl-4">
          Audience: Security researchers, system administrators, and technically
          sophisticated users evaluating Conduit&rsquo;s threat model.
        </p>

        <div className="space-y-10">
          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              1. overview<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit is an iOS approval-cockpit for AI coding agents (Claude
              Code, Codex, opencode) that run on the user&rsquo;s own computer
              or server. The security model relies on three principles:
            </p>
            <ol className="font-mono text-sm text-dim space-y-2 mt-3 list-decimal pl-5">
              <li>
                <strong className="text-fg">No cloud escrow.</strong> SSH keys
                and pairing secrets live on your devices. Conduit operates no
                infrastructure that can decrypt your agent traffic.
              </li>
              <li>
                <strong className="text-fg">Defense in depth.</strong> On-device
                Keychain + SSH transport encryption + optional end-to-end
                encryption through the push relay.
              </li>
              <li>
                <strong className="text-fg">User sovereignty.</strong> You
                choose which relay (Conduit&rsquo;s default or self-hosted),
                which hosts to pair with, and when to approve.
              </li>
            </ol>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              2. pairing (device-to-host)<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.1 The pairing flow
            </h3>
            <pre className="font-mono text-xs bg-input border border-line text-fg px-4 py-3 rounded overflow-x-auto leading-relaxed whitespace-pre">
{`┌──────────────────┐                ┌─────────────────────┐
│   iOS Device     │                │  Mac / Linux Host   │
│                  │                │                     │
│  1. Scan QR code │◄─── QR ────── │  2. conduitd pair   │
│                  │    (contains  │     generates QR     │
│  3. Parse QR     │     host +    │     containing:      │
│     extract      │     key info) │     - host address   │
│     host info    │                │     - X25519 pubkey  │
│     + pubkey     │                │                     │
│                  │                │                     │
│  4. Generate     │                │                     │
│     X25519 key   │                │                     │
│     pair         │                │                     │
│                  │                │                     │
│  5. Compute      │◄─── SSH ───── │  6. conduitd         │
│     shared       │    (encrypted │     receives client  │
│     secret via   │     transport)│     pubkey, computes │
│     ECDH         │                │     shared secret    │
└──────────────────┘                └─────────────────────┘`}
            </pre>
            <p className="font-mono text-sm text-dim leading-relaxed mt-4">
              Steps:
            </p>
            <ol className="font-mono text-sm text-dim space-y-1 mt-2 list-decimal pl-5">
              <li>
                The user runs <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">conduitd pair</code>{" "}
                on their host. The daemon generates an X25519 key pair and
                displays a QR code containing the host address, the X25519
                public key, and a one-time nonce.
              </li>
              <li>
                The user scans the QR code with the iOS app (camera permission
                required).
              </li>
              <li>
                The iOS app generates its own X25519 key pair.
              </li>
              <li>
                Both sides compute the shared secret using X25519 ECDH
                (Elliptic Curve Diffie-Hellman).
              </li>
              <li>
                The shared secret is used to derive a session key via HKDF
                (SHA-256).
              </li>
              <li>
                The X25519 private key is stored in the iOS Keychain with{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                  kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                </code>{" "}
                and{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                  kSecAttrSynchronizable: false
                </code>{" "}
                &mdash; it never leaves the device.
              </li>
            </ol>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.2 Security properties
            </h3>
            <ul className="font-mono text-sm text-dim space-y-2 list-none pl-4 border-l border-line">
              <li>
                <strong className="text-fg">QR code is single-use.</strong> Once
                scanned, <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">conduitd</code>{" "}
                invalidates the pairing nonce. An intercepted QR code cannot be
                replayed.
              </li>
              <li>
                <strong className="text-fg">The QR does not contain SSH
                credentials.</strong> It only contains the host&rsquo;s X25519
                public key and addressing info. A compromised QR code reveals
                no SSH secrets.
              </li>
              <li>
                <strong className="text-fg">The SSH connection is authenticated
                separately</strong> using the user&rsquo;s own SSH keys. Conduit
                never sends SSH private keys over the network.
              </li>
              <li>
                <strong className="text-fg">MITM resistance:</strong> The QR
                code is displayed on the host&rsquo;s screen and scanned in
                person (or via a trusted video call). A network attacker
                intercepting the later SSH connection cannot forge the X25519
                key exchange because the host&rsquo;s public key was
                communicated out-of-band via the QR code.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              3. session keys<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              After pairing, both sides derive session keys:
            </p>
            <pre className="font-mono text-xs bg-input border border-line text-fg px-4 py-3 rounded overflow-x-auto leading-relaxed whitespace-pre my-4">
{`shared_secret = X25519(ios_private, host_public)
                = X25519(host_private, ios_public)

session_key = HKDF-SHA256(
    ikm:  shared_secret,
    salt: pairing_nonce || epoch,
    info: "conduit-v1-session-key",
    len:  32
)`}
            </pre>
            <ul className="font-mono text-sm text-dim space-y-1 list-none pl-4 border-l border-line">
              <li>
                The session key is used as the symmetric key for encrypting
                approval request payloads (see &sect;4).
              </li>
              <li>
                Session keys are ephemeral &mdash; a new HKDF derivation runs
                each session using a fresh epoch nonce.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              4. payload encryption<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.1 Direct SSH path (default)
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              When the phone is on the same network as the host (or reachable
              via the internet), all approval traffic travels over the{" "}
              <strong className="text-fg">existing SSH connection</strong>. SSH
              provides its own encryption (AES-256-GCM or ChaCha20-Poly1305 per
              negotiated cipher). The SSH tunnel is the sole transport
              &mdash; Conduit&rsquo;s relay is not involved.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.2 Push relay path (end-to-end encrypted)
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              When the phone is offline or on a different network,
              notifications can be delivered via Conduit&rsquo;s push relay.
              The payload is encrypted <strong className="text-fg">before</strong>{" "}
              it leaves either endpoint:
            </p>
            <pre className="font-mono text-xs bg-input border border-line text-fg px-4 py-3 rounded overflow-x-auto leading-relaxed whitespace-pre my-4">
{`Encryption (iOS → Host decision):
  1. Generate random 12-byte nonce
  2. ciphertext = ChaCha20-Poly1305_Encrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "conduit-relay-v1",
       plaintext: decision_bytes
     )
  3. Transmit: nonce || ciphertext || tag

Decryption (Host receives):
  1. Parse nonce, ciphertext, tag
  2. plaintext = ChaCha20-Poly1305_Decrypt(
       key:   session_key,
       nonce: nonce,
       aad:   "conduit-relay-v1",
       ciphertext: ciphertext
     )`}
            </pre>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.3 What the relay sees
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              The push relay (hosted on Fly.io) has access to:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li><strong className="text-fg">Source and destination routing metadata</strong> (which host identifier should receive this blob)</li>
              <li><strong className="text-fg">Opaque ciphertext</strong> &mdash; the payload is indistinguishable from random bytes</li>
              <li><strong className="text-fg">Timestamps</strong> of when blobs pass through</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              The relay does <strong className="text-fg">not</strong> have
              access to:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>SSH keys, hostnames, usernames, or passwords</li>
              <li>Agent commands, file contents, source code, or terminal output</li>
              <li>Session key material (X25519 keys never reach the relay)</li>
              <li>Any identifying user information (Conduit has no account system)</li>
              <li>IP addresses beyond standard HTTP access logs (retained 14 days)</li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              5. on-device key storage<span className="text-accent">_</span>
            </h2>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Secret</th>
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Storage mechanism</th>
                    <th className="text-left py-2 font-semibold text-fg">Exportable?</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">SSH private keys</td>
                    <td className="py-2 pr-3 text-dim">iOS Keychain, <code className="font-mono text-xs bg-input border border-line text-fg px-1 py-0.5">whenUnlockedThisDeviceOnly</code></td>
                    <td className="py-2 text-dim">Never exported &mdash; used only for SSH auth</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">X25519 key pair</td>
                    <td className="py-2 pr-3 text-dim">iOS Keychain, <code className="font-mono text-xs bg-input border border-line text-fg px-1 py-0.5">whenUnlockedThisDeviceOnly</code></td>
                    <td className="py-2 text-dim">Never exported</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Session history</td>
                    <td className="py-2 pr-3 text-dim">Encrypted SQLite database (local)</td>
                    <td className="py-2 text-dim">Via app UI only (user-initiated export)</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">APNs device token</td>
                    <td className="py-2 pr-3 text-dim">Forwarded to push relay (via HTTPS)</td>
                    <td className="py-2 text-dim">&mdash;</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p className="font-mono text-sm text-dim leading-relaxed">
              All Keychain items have{" "}
              <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                kSecAttrSynchronizable: false
              </code>{" "}
              &mdash; they never sync to iCloud.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              6. network security<span className="text-accent">_</span>
            </h2>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Channel</th>
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Encryption</th>
                    <th className="text-left py-2 font-semibold text-fg">Notes</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">SSH (to your host)</td>
                    <td className="py-2 pr-3 text-dim">Per-negotiated cipher (AES-256-GCM, ChaCha20-Poly1305, etc.)</td>
                    <td className="py-2 text-dim">You control the server and cipher policy</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Push relay &rarr; APNs</td>
                    <td className="py-2 pr-3 text-dim">TLS (Apple&rsquo;s push infrastructure)</td>
                    <td className="py-2 text-dim">Apple delivers the notification</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">iOS app &rarr; push relay</td>
                    <td className="py-2 pr-3 text-dim">HTTPS (TLS 1.3)</td>
                    <td className="py-2 text-dim">Fly.io edge terminates TLS</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">CloudKit sync (optional)</td>
                    <td className="py-2 pr-3 text-dim">Apple-managed encryption</td>
                    <td className="py-2 text-dim">Governed by Apple security</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <ul className="font-mono text-sm text-dim space-y-1 list-none pl-4 border-l border-line">
              <li>
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">NSAppTransportSecurity</code>{" "}
                is set to the default (strict) &mdash; all network connections
                require TLS 1.2+.
              </li>
              <li>
                The push relay uses{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">force_https = true</code>{" "}
                at the Fly.io edge &mdash; HTTP requests are rejected.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              7. offline behavior<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-sm text-dim space-y-2 list-none pl-4 border-l border-line">
              <li>
                <strong className="text-fg">Notifications cannot be
                delivered</strong> when the phone is offline (no network
                connectivity). The agent on the host waits for a configurable
                timeout, then either retries or proceeds with a default policy
                (configurable in{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">policy.yaml</code>).
              </li>
              <li>
                <strong className="text-fg">Session history remains
                viewable</strong> offline &mdash; the encrypted local database
                is always accessible on-device.
              </li>
              <li>
                <strong className="text-fg">SSH connections</strong> that drop
                due to network change are handled by the SSH library&rsquo;s
                reconnection logic. No user data is lost.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              8. key rotation<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-sm text-dim space-y-2 list-none pl-4 border-l border-line">
              <li>
                <strong className="text-fg">SSH keys:</strong> Rotated
                independently by the user on their host. Conduit stores
                whatever private key the user imports.
              </li>
              <li>
                <strong className="text-fg">X25519 pairing keys:</strong> A new
                QR pairing generates fresh X25519 keys on both sides. Old keys
                are discarded from the Keychain.
              </li>
              <li>
                <strong className="text-fg">Session keys</strong> are derived
                fresh each session (HKDF with a new epoch nonce). Past session
                keys cannot be recovered from Keychain material.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              9. self-host relay option<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Users who prefer not to use Conduit&rsquo;s default relay can
              self-host:
            </p>
            <ol className="font-mono text-sm text-dim space-y-1 mt-2 list-decimal pl-5">
              <li>Clone the push backend repository.</li>
              <li>
                Deploy to Fly.io (or any Docker-compatible host) using the
                provided Dockerfile.
              </li>
              <li>
                Set the environment variable in the iOS app under Settings
                &rarr; Advanced &rarr; Relay URL.
              </li>
            </ol>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              All encryption is unchanged &mdash; the self-hosted relay still
              sees only opaque ciphertext. The benefit is network-level
              privacy: the relay operator&rsquo;s TLS termination and HTTP logs
              are under your control.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              10. threat model summary<span className="text-accent">_</span>
            </h2>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Threat</th>
                    <th className="text-left py-2 font-semibold text-fg">Mitigation</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Attacker steals QR code</td>
                    <td className="py-2 text-dim">Single-use nonce; no SSH credentials in QR</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Attacker MiTM SSH connection</td>
                    <td className="py-2 text-dim">SSH key authentication; X25519 key bindings verified out-of-band</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Relay is compromised</td>
                    <td className="py-2 text-dim">Relay sees only ciphertext &mdash; key material stays on device and host</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Phone is lost or stolen</td>
                    <td className="py-2 text-dim">Face ID / device passcode gate Keychain access; <code className="font-mono text-xs bg-input border border-line text-fg px-1 py-0.5">whenUnlockedThisDeviceOnly</code> prevents iCloud sync</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Host is compromised</td>
                    <td className="py-2 text-dim">Conduit cannot prevent this &mdash; attack is outside the threat model; user is responsible for host security</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Malicious push from relay</td>
                    <td className="py-2 text-dim">Payloads require valid ChaCha20-Poly1305 decryption with session key; relay cannot forge valid payloads</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Traffic analysis</td>
                    <td className="py-2 text-dim">Relay sees routing IDs and timing &mdash; metadata is not encrypted; self-host relay to reduce exposure</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              11. assumptions and caveats<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-sm text-dim space-y-2 list-none pl-4 border-l border-line">
              <li>
                <strong className="text-fg">You trust your SSH host.</strong>{" "}
                Conduit protects the transport and relay channels, but the host
                running your agents has full access to your code and data.
              </li>
              <li>
                <strong className="text-fg">You are responsible for your SSH
                key security.</strong> If an attacker obtains your SSH private
                key, they can connect to your host directly.
              </li>
              <li>
                <strong className="text-fg">Notifications are
                best-effort.</strong> Push notifications from the relay are
                delivered by Apple&rsquo;s APNs &mdash; Conduit cannot
                guarantee delivery timing.
              </li>
              <li>
                <strong className="text-fg">Export compliance.</strong> The App
                declares{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                  ITSAppUsesNonExemptEncryption: false
                </code>{" "}
                &mdash; the encryption used (SSH protocol, Apple CryptoKit,
                CommonCrypto) is exempt from U.S. export reporting requirements.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              12. responsible disclosure<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              If you discover a security vulnerability in Conduit, conduitd, or
              the push relay, please report it privately:
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-2">
              <strong className="text-fg">
                [security@conduit.dev &mdash; placeholder]
              </strong>
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              We will acknowledge receipt within 72 hours and work toward a fix
              before public disclosure. We do not currently operate a bounty
              program.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              sources<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-xs text-faint space-y-1.5 list-none pl-4 border-l border-line">
              <li>
                Apple CryptoKit documentation:{" "}
                <a href="https://developer.apple.com/documentation/cryptokit" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  developer.apple.com/documentation/cryptokit
                </a>
              </li>
              <li>
                Apple Keychain Services:{" "}
                <a href="https://developer.apple.com/documentation/security/keychain_services" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  developer.apple.com/documentation/security/keychain_services
                </a>
              </li>
              <li>
                IETF RFC 7748 (Elliptic Curves for Security &mdash; X25519):{" "}
                <a href="https://datatracker.ietf.org/doc/html/rfc7748" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  datatracker.ietf.org/doc/html/rfc7748
                </a>
              </li>
              <li>
                IETF RFC 8439 (ChaCha20-Poly1305):{" "}
                <a href="https://datatracker.ietf.org/doc/html/rfc8439" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  datatracker.ietf.org/doc/html/rfc8439
                </a>
              </li>
              <li>
                IETF RFC 5869 (HKDF):{" "}
                <a href="https://datatracker.ietf.org/doc/html/rfc5869" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  datatracker.ietf.org/doc/html/rfc5869
                </a>
              </li>
              <li>
                Apple ITSAppUsesNonExemptEncryption guidance:{" "}
                <a href="https://developer.apple.com/documentation/security/export-compliance/self-classifying-a-build" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  developer.apple.com/documentation/security/export-compliance/self-classifying-a-build
                </a>
              </li>
            </ul>
          </section>
        </div>
      </main>

      <footer className="border-t border-line px-6 py-8">
        <div className="max-w-3xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <span className="font-mono text-sm text-faint">conduit.dev</span>
          <div className="flex gap-6 font-mono text-sm text-faint">
            <Link href="/privacy" className="hover:text-dim transition-colors">
              Privacy
            </Link>
            <Link href="/terms" className="hover:text-dim transition-colors">
              Terms
            </Link>
            <Link href="/security" className="hover:text-dim transition-colors">
              Security
            </Link>
            <Link href="/" className="hover:text-dim transition-colors">
              Home
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
