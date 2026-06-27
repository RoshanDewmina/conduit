import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Get Lancer — Approve your agents. Keep your code.",
  description:
    "Get Lancer for iPhone. Join the TestFlight beta — governed approvals for Claude Code, Codex & opencode. No account required.",
};

const TESTFLIGHT_URL = "https://testflight.apple.com/join/PLACEHOLDER";
const BUNDLE_ID = "dev.lancer.mobile";

export default function DownloadPage() {
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

      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-24 flex flex-col items-center text-center gap-12">
        <div>
          <p className="font-display text-xs uppercase tracking-[0.14em] text-faint mb-4">
            TESTFLIGHT BETA
          </p>
          <h1 className="font-display text-4xl font-bold text-fg mb-4 leading-none">
            get lancer<span className="text-accent">_</span>
          </h1>
          <p className="font-mono text-base text-dim max-w-xl mx-auto leading-relaxed">
            Governed approvals for AI coding agents on your phone. BYO host,
            BYO API key. No account required.
          </p>
          <p className="mt-3 font-mono text-xs text-faint">{BUNDLE_ID}</p>
        </div>

        <div className="flex flex-col sm:flex-row gap-6 w-full max-w-md justify-center">
          <a
            href={TESTFLIGHT_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 flex flex-col items-center justify-center gap-2 px-8 py-5 border border-line hover:border-fg/30 bg-raised hover:bg-input transition-colors"
          >
            <span className="font-display text-xs text-low uppercase tracking-[0.14em]">
              Beta · Available now
            </span>
            <span className="font-display text-base font-semibold text-fg">
              Join TestFlight
            </span>
            <span className="font-mono text-xs text-dim">
              TestFlight beta — no account
            </span>
          </a>

          <div className="flex-1 flex flex-col items-center justify-center gap-2 px-8 py-5 border border-line opacity-40 cursor-not-allowed select-none">
            <span className="font-display text-xs text-faint uppercase tracking-[0.14em]">
              [PLANNED]
            </span>
            <span className="font-display text-base font-semibold text-dim">
              App Store
            </span>
            <span className="font-mono text-xs text-faint">
              coming soon
            </span>
          </div>
        </div>

        <div className="border-t border-line w-full pt-10">
          <h2 className="font-display text-xs uppercase tracking-[0.14em] text-faint mb-6">
            Requirements
          </h2>
          <ul className="font-mono text-sm text-dim space-y-2">
            <li>iOS 17 or later</li>
            <li>An SSH-accessible server you control</li>
            <li>An AI API key from a supported provider (optional)</li>
          </ul>
        </div>

        <div className="font-mono text-sm text-faint max-w-md">
          Questions?{" "}
          <a
            href="mailto:hello@conduit.dev"
            className="text-accent hover:text-accent/80 underline underline-offset-2"
          >
            hello@conduit.dev
          </a>
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
