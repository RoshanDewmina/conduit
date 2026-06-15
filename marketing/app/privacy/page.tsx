import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Conduit",
  description:
    "Conduit does not use analytics, advertising SDKs, or tracking. Your SSH credentials, API keys, and host configurations stay on your device.",
};

export default function PrivacyPage() {
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
          privacy policy<span className="text-accent">_</span>
        </h1>
        <p className="font-mono text-sm text-faint mb-10">
          Last updated: <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">{`{{DATE}}`}</code>. Bundle ID:{" "}
          <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
            dev.conduit.mobile
          </code>
        </p>

        <div className="space-y-10">
          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              1. introduction<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit (the &ldquo;App&rdquo;) is an iOS application that lets
              you approve, deny, and review actions initiated by AI coding
              agents (Claude Code, Codex, opencode) running on your own
              computer or server. The App is published by{" "}
              <strong className="text-fg">
                [Legal entity name &mdash; placeholder: insert company/individual
                name here]
              </strong>
              .
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              This Privacy Policy explains what data the App collects, how it
              is used, and your rights over your data. It applies to all users
              of the App worldwide.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3 font-semibold text-fg">
              Conduit does not use analytics SDKs, advertising networks, or
              third-party tracking of any kind. We do not sell your data.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              2. data we collect<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.1 Data stored exclusively on your device
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed mb-4">
              The following data never leaves your iPhone or iPad unless you
              explicitly transmit it (see &sect;3):
            </p>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Data</th>
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Where stored</th>
                    <th className="text-left py-2 font-semibold text-fg">Purpose</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">SSH private keys (Ed25519, ECDSA, RSA)</td>
                    <td className="py-2 pr-3 text-dim">iOS Keychain (<code className="font-mono text-xs bg-input border border-line text-fg px-1 py-0.5">kSecAttrAccessibleWhenUnlockedThisDeviceOnly</code>)</td>
                    <td className="py-2 text-dim">Authentication to your remote hosts</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Host configurations (hostname, port, username)</td>
                    <td className="py-2 pr-3 text-dim">Local encrypted database</td>
                    <td className="py-2 text-dim">Connecting to your hosts</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">X25519 pairing key material</td>
                    <td className="py-2 pr-3 text-dim">iOS Keychain</td>
                    <td className="py-2 text-dim">End-to-end encryption of relayed approval blobs</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Session history / block transcripts</td>
                    <td className="py-2 pr-3 text-dim">Local encrypted SQLite database</td>
                    <td className="py-2 text-dim">Offline review of past agent activity</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">App preferences</td>
                    <td className="py-2 pr-3 text-dim"><code className="font-mono text-xs bg-input border border-line text-fg px-1 py-0.5">UserDefaults</code> (local)</td>
                    <td className="py-2 text-dim">UI state and user settings</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.2 Data transmitted to Apple
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              <strong className="text-fg">APNs device token.</strong> When you
              opt in to push notifications for remote approval alerts, the App
              registers a device token with Apple Push Notification service
              (APNs). This token is a random identifier that Apple assigns to
              your device &mdash; Conduit does not read or store it as raw
              text; we forward it to our push relay so Apple can deliver
              notifications to your device.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              <strong className="text-fg">CloudKit sync (optional).</strong>{" "}
              If you enable iCloud sync, your host list and snippets are stored
              in your personal Apple CloudKit container. Conduit does not have
              access to your CloudKit data &mdash; it is governed by
              Apple&rsquo;s privacy policy.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.3 Data transmitted to Conduit&rsquo;s push relay
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              When you enable remote approval alerts, your app sends the
              following to Conduit&rsquo;s push notification relay (hosted on
              Fly.io):
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-3 list-none pl-4 border-l border-line">
              <li><strong className="text-fg">APNs device token</strong> (forwarded from Apple &mdash; see &sect;2.2)</li>
              <li><strong className="text-fg">An app-generated session identifier</strong> (a UUID scoped to the pairing between your phone and a specific host)</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              The relay does <strong className="text-fg">not</strong> receive:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>Your SSH keys, hostnames, usernames, or passwords</li>
              <li>Your command output, source code, or file contents</li>
              <li>Your IP address beyond standard HTTP server logs (see &sect;3.2)</li>
            </ul>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.4 Data transmitted through the relay (end-to-end encrypted)
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Approval requests and your decisions (approve / deny / edit) are
              sent as encrypted blobs through the relay. The encryption uses
              X25519 ECDH key agreement with ChaCha20-Poly1305 symmetric
              encryption. The relay <strong className="text-fg">cannot
              read</strong> the contents of these blobs &mdash; it sees only
              opaque ciphertext and routing metadata (destination host
              identifier).
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              2.5 Purchase data (if applicable)
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              If you purchase Conduit Pro (a one-time in-app purchase) or a
              future subscription, Apple processes the transaction. Conduit
              receives only a receipt token from StoreKit that confirms the
              purchase &mdash; we never see your payment card details.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              3. how we use data<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              3.1 Primary purposes
            </h3>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Data</th>
                    <th className="text-left py-2 font-semibold text-fg">Purpose</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">SSH keys</td>
                    <td className="py-2 text-dim">Authenticate to your remote host (only sent over the SSH connection you initiate)</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">APNs token</td>
                    <td className="py-2 text-dim">Deliver push notifications when an agent needs your approval</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Session identifier</td>
                    <td className="py-2 text-dim">Route notifications to the correct paired host</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">X25519 keys</td>
                    <td className="py-2 text-dim">Establish end-to-end encrypted channel between your device and your host</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Purchase receipt</td>
                    <td className="py-2 text-dim">Unlock Pro features</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              3.2 Standard server logs
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Our push relay infrastructure (Fly.io) records standard HTTP
              access logs that may include the originating IP address, request
              timestamp, and User-Agent string. These logs are retained for{" "}
              <strong className="text-fg">14 days</strong> for operational
              troubleshooting and then deleted. We do not correlate these logs
              with any other data.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              4. data sharing<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              We do <strong className="text-fg">not</strong> share your personal
              data with third parties, except:
            </p>
            <ol className="font-mono text-sm text-dim space-y-2 mt-3 list-decimal pl-5">
              <li>
                <strong className="text-fg">Apple</strong> &mdash; for push
                notification delivery (APNs) and optional CloudKit sync,
                governed by Apple&rsquo;s privacy policy.
              </li>
              <li>
                <strong className="text-fg">Fly.io</strong> &mdash; as our
                hosting provider for the push relay. Fly.io processes data
                solely on our instructions and is contractually prohibited from
                using it for any other purpose.
              </li>
              <li>
                <strong className="text-fg">Law enforcement</strong> &mdash;
                only if required by applicable law and accompanied by valid
                legal process. We will notify you unless legally prohibited.
              </li>
            </ol>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              We do <strong className="text-fg">not</strong> share data with
              analytics providers, advertising networks, data brokers, or AI
              model providers.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              5. data retention and deletion<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              5.1 Data on your device
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              All SSH keys, host configurations, session history, and
              preferences are stored locally. Deleting the App from your device
              removes all local data.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              5.2 Data on Conduit&rsquo;s push relay
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              APNs device tokens and session identifiers are retained for as
              long as your session is registered with the relay. You can
              unregister at any time from within the App&rsquo;s settings.
              After unregistration, tokens are deleted within{" "}
              <strong className="text-fg">30 days</strong>.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              5.3 No account = no server-side personal data
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit does not operate a user account system. There is no
              registration, login, or profile stored on our servers.
              Consequently, there is no server-side personal data to delete
              beyond the push tokens described above.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              5.4 Requesting deletion
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              To request deletion of any data held by Conduit&rsquo;s services,
              contact{" "}
              <strong className="text-fg">
                [privacy@conduit.dev &mdash; placeholder: insert support email]
              </strong>
              . We will respond within 30 days.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              6. security<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-sm text-dim space-y-2 list-none pl-4 border-l border-line">
              <li>
                SSH keys and X25519 pairing keys are stored in the iOS Keychain
                with accessibility set to{" "}
                <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                  whenUnlockedThisDeviceOnly
                </code>{" "}
                and synchronization disabled. They never leave the device
                except over the SSH connection you explicitly initiate.
              </li>
              <li>
                Approval relay traffic is end-to-end encrypted (X25519 +
                ChaCha20-Poly1305) so that the relay cannot read the contents.
              </li>
              <li>
                Communication with the push relay is over HTTPS (TLS).
              </li>
              <li>
                Face ID / Touch ID can be enabled to gate access to stored
                keys.
              </li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              <strong className="text-fg">Conduit is not a backup
              service.</strong> We cannot recover your SSH keys, host
              configurations, or session history if you lose your device.
              Maintain independent backups of your SSH credentials.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              7. children<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit is not directed at children under 13 and does not
              knowingly collect personal information from children. If you
              believe a child has provided personal data, contact{" "}
              <strong className="text-fg">[privacy@conduit.dev]</strong>.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              8. your rights<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Depending on your jurisdiction, you may have rights under GDPR
              (EU/EEA), CCPA (California), or similar laws:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-3 list-none pl-4 border-l border-line">
              <li><strong className="text-fg">Right to know</strong> what data is collected and how it is used (this policy)</li>
              <li><strong className="text-fg">Right to access</strong> your data</li>
              <li><strong className="text-fg">Right to deletion</strong> (see &sect;5.4)</li>
              <li><strong className="text-fg">Right to withdraw consent</strong> for push notifications (via iOS Settings)</li>
              <li><strong className="text-fg">Right to non-discrimination</strong> for exercising your rights</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              To exercise any of these rights, contact{" "}
              <strong className="text-fg">[privacy@conduit.dev]</strong>.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              9. changes to this policy<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              We may update this Privacy Policy to reflect changes in our
              practices or legal requirements. Material changes will be
              notified through the App or at the privacy URL listed in App
              Store Connect.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              10. contact<span className="text-accent">_</span>
            </h2>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Role</th>
                    <th className="text-left py-2 font-semibold text-fg">Contact</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Privacy inquiries</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[privacy@conduit.dev &mdash; placeholder]</strong></td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Legal inquiries</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[legal@conduit.dev &mdash; placeholder]</strong></td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Responsible disclosure</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[security@conduit.dev &mdash; placeholder]</strong></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              sources<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-xs text-faint space-y-1.5 list-none pl-4 border-l border-line">
              <li>Apple App Store Review Guidelines &sect;5.1.1 (Privacy):{" "}
                <a href="https://developer.apple.com/app-store/review/guidelines/" className="text-accent hover:text-accent/80 underline underline-offset-2">developer.apple.com/app-store/review/guidelines/</a>
              </li>
              <li>Apple App Privacy Details:{" "}
                <a href="https://developer.apple.com/app-store/app-privacy-details/" className="text-accent hover:text-accent/80 underline underline-offset-2">developer.apple.com/app-store/app-privacy-details/</a>
              </li>
              <li>Apple SDK minimum requirements (April 28, 2026):{" "}
                <a href="https://developer.apple.com/news/upcoming-requirements/?id=02032026a" className="text-accent hover:text-accent/80 underline underline-offset-2">developer.apple.com/news/upcoming-requirements/?id=02032026a</a>
              </li>
              <li>Apple Account Deletion requirement:{" "}
                <a href="https://developer.apple.com/support/offering-account-deletion-in-your-app/" className="text-accent hover:text-accent/80 underline underline-offset-2">developer.apple.com/support/offering-account-deletion-in-your-app/</a>
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
