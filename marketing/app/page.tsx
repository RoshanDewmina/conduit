import Link from "next/link";

export default function Home() {
  return (
    <div className="flex flex-col min-h-screen">
      {/* Nav */}
      <header className="border-b border-zinc-800 px-6 py-4">
        <nav className="max-w-5xl mx-auto flex items-center justify-between">
          <span className="font-mono text-sm font-semibold tracking-tight text-zinc-100">
            conduit
          </span>
          <div className="flex items-center gap-6 text-sm text-zinc-400">
            <Link href="/privacy" className="hover:text-zinc-100 transition-colors">
              Privacy
            </Link>
            <Link
              href="/download"
              className="px-4 py-1.5 rounded-md bg-zinc-100 text-zinc-900 font-medium hover:bg-white transition-colors"
            >
              Get the app
            </Link>
          </div>
        </nav>
      </header>

      <main className="flex-1">
        {/* Hero */}
        <section className="max-w-5xl mx-auto px-6 pt-24 pb-20">
          <p className="font-mono text-xs text-emerald-400 tracking-widest uppercase mb-4">
            SSH Agent Terminal for iOS
          </p>
          <h1 className="text-4xl sm:text-5xl font-bold tracking-tight text-zinc-50 leading-tight max-w-3xl">
            Run AI agents over SSH.
            <br />
            Your infrastructure. Your keys.
          </h1>
          <p className="mt-6 text-lg text-zinc-400 max-w-2xl leading-relaxed">
            Conduit brings Warp-style agent blocks to your iPhone. Connect to
            your own server, run Claude or Codex over SSH, and review every
            action before it executes — all without giving a third-party access
            to your infrastructure.
          </p>
          <div className="mt-10 flex flex-wrap gap-4">
            <Link
              href="/download"
              className="px-6 py-3 rounded-lg bg-zinc-100 text-zinc-900 font-semibold hover:bg-white transition-colors"
            >
              Download for iPhone
            </Link>
            <Link
              href="/subscribe?plan=monthly"
              className="px-6 py-3 rounded-lg border border-zinc-700 text-zinc-300 font-semibold hover:border-zinc-500 hover:text-zinc-100 transition-colors"
            >
              Subscribe
            </Link>
          </div>
        </section>

        {/* Feature rows */}
        <section className="border-t border-zinc-800">
          <div className="max-w-5xl mx-auto px-6 py-20 grid sm:grid-cols-3 gap-12">
            <div>
              <div className="font-mono text-xs text-emerald-400 uppercase tracking-widest mb-3">
                OSC-133 blocks
              </div>
              <h2 className="text-lg font-semibold text-zinc-100 mb-2">
                Warp-style agent blocks
              </h2>
              <p className="text-zinc-400 text-sm leading-relaxed">
                Every shell command and AI output renders as a discrete block
                with its own status gutter. Scan a session at a glance, not a
                wall of scrollback.
              </p>
            </div>

            <div>
              <div className="font-mono text-xs text-emerald-400 uppercase tracking-widest mb-3">
                Inbox approvals
              </div>
              <h2 className="text-lg font-semibold text-zinc-100 mb-2">
                Approve before agents act
              </h2>
              <p className="text-zinc-400 text-sm leading-relaxed">
                When an agent needs to write a file or run a command, it pauses
                and surfaces the action to your Inbox. One tap to approve or
                deny — no surprises.
              </p>
            </div>

            <div>
              <div className="font-mono text-xs text-emerald-400 uppercase tracking-widest mb-3">
                BYO host, no account
              </div>
              <h2 className="text-lg font-semibold text-zinc-100 mb-2">
                No Conduit servers in the loop
              </h2>
              <p className="text-zinc-400 text-sm leading-relaxed">
                SSH directly to your own server. AI API keys stay in your iOS
                Keychain. Conduit never sees your credentials, your code, or
                your agent output.
              </p>
            </div>
          </div>
        </section>

        {/* CTA strip */}
        <section className="border-t border-zinc-800 bg-zinc-900">
          <div className="max-w-5xl mx-auto px-6 py-16 flex flex-col sm:flex-row items-center justify-between gap-6">
            <div>
              <h2 className="text-2xl font-bold text-zinc-50">
                Ready to run agents from your phone?
              </h2>
              <p className="mt-2 text-zinc-400">
                Join the TestFlight beta. No account required.
              </p>
            </div>
            <Link
              href="/download"
              className="shrink-0 px-8 py-3 rounded-lg bg-zinc-100 text-zinc-900 font-semibold hover:bg-white transition-colors"
            >
              Get Conduit
            </Link>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-zinc-800 px-6 py-8">
        <div className="max-w-5xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-zinc-500">
          <span className="font-mono">conduit.dev</span>
          <div className="flex gap-6">
            <Link href="/privacy" className="hover:text-zinc-300 transition-colors">
              Privacy Policy
            </Link>
            <Link href="/download" className="hover:text-zinc-300 transition-colors">
              Download
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
