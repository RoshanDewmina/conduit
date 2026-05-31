import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Conduit",
  description: "Conduit privacy policy. Your data stays on your device.",
};

export default function PrivacyPage() {
  return (
    <div className="flex flex-col min-h-screen">
      <header className="border-b border-zinc-800 px-6 py-4">
        <nav className="max-w-3xl mx-auto flex items-center justify-between">
          <Link
            href="/"
            className="font-mono text-sm font-semibold tracking-tight text-zinc-100"
          >
            conduit
          </Link>
        </nav>
      </header>

      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-16">
        <h1 className="text-3xl font-bold text-zinc-50 mb-2">Privacy Policy</h1>
        <p className="text-sm text-zinc-500 mb-10">
          Last updated: June 2026. Bundle ID:{" "}
          <code className="font-mono text-zinc-400">dev.conduit.mobile</code>
        </p>

        <div className="prose prose-invert prose-zinc max-w-none space-y-10 text-zinc-300">
          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Overview
            </h2>
            <p>
              Conduit is a bring-your-own-host SSH terminal for iOS. The
              application connects directly from your device to servers you own
              or control. Conduit Inc. does not operate relay servers, does not
              see your SSH sessions, and does not store personal data beyond what
              is strictly necessary for push notification delivery and crash
              reporting.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Bring-your-own host
            </h2>
            <p>
              You supply your own SSH server address, username, and credentials.
              Conduit makes a direct connection from your device to that server.
              No Conduit server sits in the middle of your SSH session. We do
              not own, operate, or store any servers on your behalf.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              SSH credentials
            </h2>
            <p>
              SSH private keys are stored in the iOS Keychain with the
              protection class{" "}
              <code className="font-mono text-zinc-400">
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
              </code>
              . This means keys are:
            </p>
            <ul className="list-disc list-inside space-y-1 mt-2">
              <li>Never synced to iCloud or any cloud service.</li>
              <li>Not accessible when the device is locked.</li>
              <li>Never transmitted to Conduit servers.</li>
            </ul>
            <p className="mt-3">
              SSH passwords are prompted at connect time and are never written to
              disk or stored in the Keychain.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              AI API keys
            </h2>
            <p>
              AI provider API keys (for example, Anthropic or OpenAI keys) are
              stored exclusively in the iOS Keychain on your device. They are
              used only to authenticate requests sent directly from your device
              to the AI provider over SSH. Conduit never receives, stores, or
              transmits your AI API keys.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              No account required
            </h2>
            <p>
              Conduit does not require you to create an account. There is no
              Conduit user registration, no email address collected for access,
              and no Conduit backend that stores personal profile data.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Push notifications
            </h2>
            <p>
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
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Crash reporting
            </h2>
            <p>
              The app may use Sentry to collect anonymized crash reports and
              error diagnostics. Crash reports may include device model, OS
              version, and a stack trace. They do not include SSH session
              content, credentials, or personal identifiers. You can opt out of
              crash reporting in the app settings.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Analytics
            </h2>
            <p>
              Conduit does not use any behavioral analytics, advertising
              networks, or tracking SDKs. The only telemetry collected is the
              crash reporting described above.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Subscription billing
            </h2>
            <p>
              If you purchase a subscription, payment is processed by Stripe.
              Conduit receives only a subscription status confirmation from
              Stripe. We do not store your payment card details. Stripe's own
              privacy policy governs how your payment data is handled.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Data retention and deletion
            </h2>
            <p>
              APNs device tokens are deleted from our push backend when you
              disable notifications or uninstall the app. All other app data
              (Keychain entries, session history) is stored locally on your
              device and is deleted when you uninstall the app or clear the app
              data from iOS Settings.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Children
            </h2>
            <p>
              Conduit is not directed at children under 13. We do not knowingly
              collect any personal information from children.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Changes to this policy
            </h2>
            <p>
              Material changes to this policy will be reflected with an updated
              date above and, where appropriate, notified via app release notes.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-zinc-100 mb-3">
              Contact
            </h2>
            <p>
              Questions about this policy can be directed to{" "}
              <a
                href="mailto:privacy@conduit.dev"
                className="text-emerald-400 hover:text-emerald-300 underline underline-offset-2"
              >
                privacy@conduit.dev
              </a>
              .
            </p>
          </section>
        </div>
      </main>

      <footer className="border-t border-zinc-800 px-6 py-8">
        <div className="max-w-3xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-zinc-500">
          <span className="font-mono">conduit.dev</span>
          <Link href="/" className="hover:text-zinc-300 transition-colors">
            Back to home
          </Link>
        </div>
      </footer>
    </div>
  );
}
