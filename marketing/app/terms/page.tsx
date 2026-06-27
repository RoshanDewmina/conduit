import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Service — Lancer",
  description:
    "Lancer terms of service. By downloading, installing, or using Lancer, you agree to be bound by these Terms.",
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
            lancer<span className="text-accent">_</span>
          </Link>
        </nav>
        <div className="spectrum-line h-px w-full mt-4" />
      </header>

      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-16">
        <h1 className="font-display text-3xl font-bold text-fg mb-2 leading-none">
          terms of service<span className="text-accent">_</span>
        </h1>
        <p className="font-mono text-sm text-faint mb-10">
          Last updated: <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">{`{{DATE}}`}</code>. Bundle ID:{" "}
          <code className="font-mono text-xs bg-input border border-line text-fg px-1.5 py-0.5">
            dev.lancer.mobile
          </code>
        </p>

        <div className="space-y-10">
          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              1. acceptance<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              By downloading, installing, or using Lancer (the &ldquo;App&rdquo;),
              you agree to be bound by these Terms of Service (the
              &ldquo;Terms&rdquo;). If you do not agree, do not use the App.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              The App is published by{" "}
              <strong className="text-fg">
                [Legal entity name &mdash; placeholder: insert company or
                individual name]
              </strong>
              .
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              These Terms supplement the Apple App Store Terms of Service (the
              &ldquo;Apple Terms&rdquo;). To the extent of any conflict, these
              Terms govern your use of the App.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              2. the app&rsquo;s purpose<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Lancer is an iOS approval-firewall and audit interface for AI
              coding agents (Claude Code, Codex, opencode) that run on
              computers you own or control. The App:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-3 list-none pl-4 border-l border-line">
              <li>Connects to your remote host via SSH</li>
              <li>Shows you approval requests from agents running on that host</li>
              <li>Lets you approve, deny, or edit proposed actions</li>
              <li>Displays a running transcript of agent activity</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              <strong className="text-fg">The App does not execute, compile,
              download, or install code on your iOS device.</strong> All code
              execution occurs on your remote host.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              3. license<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Lancer grants you a personal, non-transferable, non-exclusive
              license to use the App on Apple-branded devices that you own or
              control, as permitted by the Apple Terms.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              4. your responsibilities<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.1 Authorized access only
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              You may use Lancer only to connect to:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>Hosts that you own</li>
              <li>Hosts that you are explicitly authorized by the owner to access</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              You are solely responsible for maintaining the security of your
              SSH keys and host credentials.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.2 Your agents, your liability
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              You control what AI coding agents do on your host. Lancer merely
              relays approval decisions. You are responsible for:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>The actions your agents perform</li>
              <li>Compliance with any laws or policies applicable to your code and data</li>
              <li>Ensuring your agents do not introduce vulnerabilities, violate licenses, or expose sensitive information</li>
            </ul>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              4.3 Prohibited uses
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              You must not use Lancer to:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>Access any system without authorization</li>
              <li>Distribute malware, ransomware, or other harmful code</li>
              <li>Conduct denial-of-service attacks or network abuse</li>
              <li>Violate applicable export control or sanctions laws</li>
              <li>Circumvent any technical or legal restriction on the host system</li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              5. accounts<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              <strong className="text-fg">Lancer does not create or manage
              user accounts.</strong> Pairing is device-to-device &mdash; you
              scan a QR code from your host to link your phone. There is no
              login, no profile, and no Lancer-hosted user database.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              If you purchase Lancer Pro via in-app purchase, Apple manages
              the transaction and receipt. Lancer does not create a separate
              account for this purpose.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              6. in-app purchases and pro tier<span className="text-accent">_</span>
            </h2>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              6.1 Current offering
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Lancer Pro is a one-time in-app purchase (non-consumable) that
              unlocks additional features (e.g., multi-host management, advanced
              surfaces). Price and feature set are displayed in the App. Apple
              processes all payments.
            </p>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              6.2 Future subscription (planned &mdash; not yet available)
            </h3>
            <p className="font-mono text-sm text-dim leading-relaxed">
              A subscription-based Pro tier is under development but is{" "}
              <strong className="text-fg">not currently offered</strong>. When
              and if it ships, the following will apply:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>Auto-renewing subscription managed by Apple&rsquo;s StoreKit 2</li>
              <li>Pricing and duration displayed before purchase</li>
              <li>Subscriptions renew unless cancelled at least 24 hours before the period ends</li>
              <li>Manage / cancel via Apple&rsquo;s Subscription settings on your device</li>
              <li>Refunds handled by Apple per their policy</li>
            </ul>

            <h3 className="font-display text-base font-semibold text-fg mt-6 mb-3">
              6.3 General IAP terms
            </h3>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>All purchases are final unless Apple&rsquo;s refund policy applies</li>
              <li>Prices are as displayed in the App and may be updated for future purchases</li>
              <li>Lancer Pro is a single-device purchase (Apple ID bound)</li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              7. third-party services<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              The App interacts with the following third-party services that
              you configure:
            </p>
            <div className="overflow-x-auto my-4">
              <table className="w-full text-sm font-mono border-collapse">
                <thead>
                  <tr className="border-b border-line">
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Service</th>
                    <th className="text-left py-2 pr-3 font-semibold text-fg">Role</th>
                    <th className="text-left py-2 font-semibold text-fg">Provider terms</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Your SSH host (your own machine)</td>
                    <td className="py-2 pr-3 text-dim">Runs your agents</td>
                    <td className="py-2 text-dim">Your own responsibility</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Apple Push Notification service</td>
                    <td className="py-2 pr-3 text-dim">Delivers notifications</td>
                    <td className="py-2 text-dim">Apple Developer Program License Agreement</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Fly.io</td>
                    <td className="py-2 pr-3 text-dim">Hosts the push relay</td>
                    <td className="py-2 text-dim">Fly.io Terms of Service</td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Stripe (if applicable)</td>
                    <td className="py-2 pr-3 text-dim">Payment processing for conduit.dev subscriptions</td>
                    <td className="py-2 text-dim">Stripe Services Agreement</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Lancer is not responsible for the availability, security, or
              policies of these third-party services.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              8. disclaimer of warranties<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed font-semibold text-fg">
              THE APP IS PROVIDED &ldquo;AS IS&rdquo; AND &ldquo;AS
              AVAILABLE,&rdquo; WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
              MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
              NON-INFRINGEMENT.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              Lancer does not warrant that:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>The App will be uninterrupted, timely, secure, or error-free</li>
              <li>The results obtained from the App will be accurate or reliable</li>
              <li>Any errors in the App will be corrected</li>
            </ul>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              <strong className="text-fg">Security tool disclaimer.</strong>{" "}
              Lancer is a tool to assist with agent governance. It does not
              guarantee that your agents will never perform unauthorized or
              harmful actions. You must independently verify agent behavior and
              maintain backups.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              9. limitation of liability<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed font-semibold text-fg">
              TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT
              SHALL{" "}
              <strong className="text-fg">
                [Legal entity name]
              </strong>{" "}
              BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL,
              OR EXEMPLARY DAMAGES, INCLUDING BUT NOT LIMITED TO DAMAGES FOR
              LOSS OF PROFITS, GOODWILL, USE, DATA, OR OTHER INTANGIBLE LOSSES,
              ARISING OUT OF OR IN CONNECTION WITH THE USE OR INABILITY TO USE
              THE APP.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              Our total liability to you shall not exceed the greater of (a)
              the amount you paid for the App (including any in-app purchases)
              in the twelve (12) months preceding the claim, or (b) one hundred
              U.S. dollars ($100.00).
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              10. apple&rsquo;s standard eula<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              Apple&rsquo;s Licensed Application End User License Agreement
              (the &ldquo;Apple EULA&rdquo;) applies to your use of the App as
              downloaded from the App Store. These Terms do not limit any
              rights you have under the Apple EULA.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              11. termination<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              We may terminate or suspend your access to the App at any time,
              without prior notice, for conduct that we believe violates these
              Terms or is harmful to other users, us, or third parties.
            </p>
            <p className="font-mono text-sm text-dim leading-relaxed mt-3">
              Upon termination:
            </p>
            <ul className="font-mono text-sm text-dim space-y-1 mt-2 list-none pl-4 border-l border-line">
              <li>Your license to use the App ends</li>
              <li>You must cease all use and delete the App</li>
              <li>Local data on your device will be removed when you delete the App</li>
            </ul>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              12. changes to these terms<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              We may update these Terms from time to time. Material changes
              will be notified through the App. Your continued use after the
              effective date constitutes acceptance of the updated Terms.
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              13. governing law<span className="text-accent">_</span>
            </h2>
            <p className="font-mono text-sm text-dim leading-relaxed">
              These Terms are governed by the laws of{" "}
              <strong className="text-fg">
                [Jurisdiction &mdash; placeholder: e.g., the State of
                California, USA]
              </strong>
              , without regard to its conflict-of-law provisions. The exclusive
              venue for any dispute shall be the state and federal courts in{" "}
              <strong className="text-fg">
                [County / District &mdash; placeholder]
              </strong>
              .
            </p>
          </section>

          <section>
            <h2 className="font-display text-lg font-semibold text-fg mb-3">
              14. contact<span className="text-accent">_</span>
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
                    <td className="py-2 pr-3 text-dim">General / legal inquiries</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[legal@conduit.dev &mdash; placeholder]</strong></td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">Support</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[support@conduit.dev &mdash; placeholder]</strong></td>
                  </tr>
                  <tr className="border-b border-line/50">
                    <td className="py-2 pr-3 text-dim">DMCA / takedown notices</td>
                    <td className="py-2 text-dim"><strong className="text-fg">[legal@conduit.dev &mdash; placeholder]</strong></td>
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
              <li>
                Apple App Store Review Guidelines &sect;3.1.1 (IAP), &sect;4.2
                (Functionality), &sect;5.1:{" "}
                <a href="https://developer.apple.com/app-store/review/guidelines/" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  developer.apple.com/app-store/review/guidelines/
                </a>
              </li>
              <li>
                Apple Licensed Application End User License Agreement:{" "}
                <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  apple.com/legal/internet-services/itunes/dev/stdeula/
                </a>
              </li>
              <li>
                Apple SDK minimum requirements (April 28, 2026):{" "}
                <a href="https://developer.apple.com/news/upcoming-requirements/?id=02032026a" className="text-accent hover:text-accent/80 underline underline-offset-2">
                  developer.apple.com/news/upcoming-requirements/?id=02032026a
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
