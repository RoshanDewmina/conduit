import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Conduit",
  description: "Conduit privacy policy. Your data stays on your device.",
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
          Last updated: June 2026. Bundle ID:{" "}
          <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
            dev.conduit.mobile
          </code>
        </p>

        <div className="space-y-10">
          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              overview<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit is a phone-first approval and audit layer for AI coding
              agents. The application connects directly from your device to
              servers you own or control. Conduit Inc. does not operate relay
              servers that see your SSH sessions, and does not store personal
              data beyond what is strictly necessary for push notification
              delivery and crash reporting.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              bring-your-own host<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              You supply your own SSH server address, username, and credentials.
              Conduit makes a direct connection from your device to that server.
              No Conduit server sits in the middle of your SSH session. We do
              not own, operate, or store any servers on your behalf.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              SSH credentials<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              SSH private keys are stored in the iOS Keychain with the
              protection class{" "}
              <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
              </code>
              . This means keys are:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-3 list-none pl-4 border-l border-line">
              <li>Never synced to iCloud or any cloud service.</li>
              <li>Not accessible when the device is locked.</li>
              <li>Never transmitted to Conduit servers.</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              SSH passwords are prompted at connect time and are never written to
              disk or stored in the Keychain.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              AI API keys<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              AI provider API keys (for example, Anthropic or OpenAI keys) are
              stored exclusively in the iOS Keychain on your device. They are
              used only to authenticate requests sent directly from your device
              to the AI provider over SSH. Conduit never receives, stores, or
              transmits your AI API keys.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              no account required<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit does not require you to create an account. There is no
              Conduit user registration, no email address collected for access,
              and no Conduit backend that stores personal profile data.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              push notifications<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              If you enable push notifications, your Apple Push Notification
              service (APNs) device token is stored on our push backend server
              hosted on Google Cloud Run. This token is used solely to deliver
              notifications (such as agent approval requests) to your device. It
              is not shared with third parties, not linked to a user identity,
              and can be revoked at any time by disabling notifications in iOS
              Settings.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              crash reporting<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              The app may use Sentry to collect anonymized crash reports and
              error diagnostics. Crash reports may include device model, OS
              version, and a stack trace. They do not include SSH session
              content, credentials, or personal identifiers. You can opt out of
              crash reporting in the app settings.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              analytics<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit does not use any behavioral analytics, advertising
              networks, or tracking SDKs. The only telemetry collected is the
              crash reporting described above.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              subscription billing<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              If you purchase a subscription, payment is processed by Stripe.
              Conduit receives only a subscription status confirmation from
              Stripe. We do not store your payment card details. Stripe&apos;s
              own privacy policy governs how your payment data is handled.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              data retention and deletion<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              APNs device tokens are deleted from our push backend when you
              disable notifications or uninstall the app. All other app data
              (Keychain entries, session history) is stored locally on your
              device and is deleted when you uninstall the app or clear the app
              data from iOS Settings.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              children<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit is not directed at children under 13. We do not knowingly
              collect any personal information from children.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              changes to this policy<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Material changes to this policy will be reflected with an updated
              date above and, where appropriate, notified via app release notes.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              contact<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Questions about this policy can be directed to{" "}
              <a
                href="mailto:privacy@conduit.dev"
                className="text-accent hover:text-accent/80 underline underline-offset-2"
              >
                privacy@conduit.dev
              </a>
              .
            </p>
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
            <Link href="/" className="hover:text-dim transition-colors">
              Home
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
