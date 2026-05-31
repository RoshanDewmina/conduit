import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Get Conduit — SSH Agent Terminal for iOS",
  description:
    "Download Conduit for iPhone. Join the TestFlight beta or get it on the App Store.",
};

// TestFlight link — replace PLACEHOLDER with the real join code once the build is live.
const TESTFLIGHT_URL = "https://testflight.apple.com/join/PLACEHOLDER";

// Bundle ID for reference
const BUNDLE_ID = "dev.conduit.mobile";

export default function DownloadPage() {
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

      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-24 flex flex-col items-center text-center gap-12">
        <div>
          <h1 className="text-4xl font-bold text-zinc-50 mb-4">
            Get Conduit
          </h1>
          <p className="text-lg text-zinc-400 max-w-xl mx-auto leading-relaxed">
            Run AI agents over SSH from your iPhone. BYO host, BYO API key.
            No account required.
          </p>
          <p className="mt-3 font-mono text-xs text-zinc-600">{BUNDLE_ID}</p>
        </div>

        <div className="flex flex-col sm:flex-row gap-6 w-full max-w-md justify-center">
          {/* TestFlight */}
          <a
            href={TESTFLIGHT_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 flex flex-col items-center justify-center gap-2 px-8 py-5 rounded-xl border border-zinc-700 hover:border-zinc-500 hover:bg-zinc-900 transition-colors"
          >
            <span className="text-sm font-mono text-emerald-400 uppercase tracking-widest">
              Beta
            </span>
            <span className="text-base font-semibold text-zinc-100">
              Join TestFlight
            </span>
            <span className="text-xs text-zinc-500">
              Available now
            </span>
          </a>

          {/* App Store placeholder */}
          <div className="flex-1 flex flex-col items-center justify-center gap-2 px-8 py-5 rounded-xl border border-zinc-800 opacity-50 cursor-not-allowed select-none">
            <span className="text-sm font-mono text-zinc-500 uppercase tracking-widest">
              App Store
            </span>
            <span className="text-base font-semibold text-zinc-400">
              Coming soon
            </span>
            <span className="text-xs text-zinc-600">
              Pending review
            </span>
          </div>
        </div>

        <div className="border-t border-zinc-800 w-full pt-10">
          <h2 className="text-sm font-semibold text-zinc-400 mb-6 uppercase tracking-widest">
            Requirements
          </h2>
          <ul className="text-sm text-zinc-400 space-y-2">
            <li>iOS 17 or later</li>
            <li>An SSH-accessible server you control</li>
            <li>An AI API key from a supported provider (optional)</li>
          </ul>
        </div>

        <div className="text-sm text-zinc-500 max-w-md">
          Questions?{" "}
          <a
            href="mailto:hello@conduit.dev"
            className="text-emerald-400 hover:text-emerald-300 underline underline-offset-2"
          >
            hello@conduit.dev
          </a>
        </div>
      </main>

      <footer className="border-t border-zinc-800 px-6 py-8">
        <div className="max-w-3xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-zinc-500">
          <span className="font-mono">conduit.dev</span>
          <div className="flex gap-6">
            <Link href="/privacy" className="hover:text-zinc-300 transition-colors">
              Privacy Policy
            </Link>
            <Link href="/" className="hover:text-zinc-300 transition-colors">
              Home
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
