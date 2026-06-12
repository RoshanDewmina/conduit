"use client";

import Link from "next/link";
import Button from "@/components/ui/button";

const links = [
  { label: "Product", href: "/product" },
  { label: "Trust", href: "/trust" },
  { label: "Pricing", href: "/pricing" },
  { label: "Docs", href: "/docs" },
];

export default function SiteNav() {
  return (
    <div className="sticky top-0 z-50">
      {/* Announce bar */}
      <div className="bg-raised border-b border-line px-6 py-2 text-center">
        <p className="font-mono text-[11px] text-dim">
          Now in TestFlight beta — governed approvals for Claude Code, Codex &amp; opencode.
        </p>
      </div>

      {/* Nav */}
      <header className="bg-bg/85 backdrop-blur-md border-b border-line">
        <nav className="max-w-[1152px] mx-auto px-6 md:px-8 h-12 flex items-center justify-between gap-6">
          <Link
            href="/"
            className="font-display font-bold text-base tracking-tight text-fg shrink-0"
          >
            conduit<span className="text-accent">_</span>
          </Link>

          <div className="hidden md:flex items-center gap-6">
            {links.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className="font-display text-xs font-semibold tracking-[.05em] uppercase text-dim hover:text-fg transition-colors"
              >
                {l.label}
              </Link>
            ))}
          </div>

          <Button href="/download" variant="primary" className="shrink-0 text-xs px-4 py-2">
            Get the app
          </Button>
        </nav>

        {/* Spectrum hairline */}
        <div className="spectrum-line h-[1px] w-full" />
      </header>
    </div>
  );
}
