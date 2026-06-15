import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Service — Conduit",
  description: "Conduit terms of service.",
};

export default function TermsPage() {
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
          terms of service<span className="text-accent">_</span>
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
              draft notice<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              These terms are a placeholder and do not yet constitute a binding
              agreement. Final legal terms will be published before the App Store
              release. In the meantime the{" "}
              <Link href="/privacy" className="text-accent underline underline-offset-2">
                privacy policy
              </Link>{" "}
              governs how your data is handled.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              TODO: Replace with final terms of service before public launch.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              acceptance<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              By using Conduit (&quot;the Service&quot;), you agree to these
              terms. If you do not agree, do not use the Service.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              description<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Conduit is a phone-first approval, policy, and audit layer for AI
              coding agents. The application connects directly from your device
              to servers you own or control. Conduit Inc. does not operate relay
              servers that see your SSH sessions.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              your responsibilities<span className="text-accent">_</span>
            </h2>
            <ul className="font-mono text-sm text-dim space-y-1.5 list-none pl-4 border-l border-line">
              <li>You are responsible for the security of your SSH credentials and API keys.</li>
              <li>You are responsible for any activity that occurs through your use of the Service.</li>
              <li>You must comply with all applicable laws and regulations.</li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              beta disclaimer<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              The Service is provided in beta (&quot;as is&quot;) without
              warranty of any kind. Conduit Inc. disclaims all liability for any
              damages arising from the use of the Service during beta.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              intellectual property<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              The Service and its original content, features, and functionality
              are owned by Conduit Inc. and are protected by applicable
              intellectual property laws.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              termination<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              We may terminate or suspend access to the Service at any time,
              without prior notice, for conduct that we believe violates these
              terms or is harmful to other users, third parties, or us.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              contact<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Questions about these terms can be directed to{" "}
              <a
                href="mailto:legal@conduit.dev"
                className="text-accent hover:text-accent/80 underline underline-offset-2"
              >
                legal@conduit.dev
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
