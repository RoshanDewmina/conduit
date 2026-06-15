import Link from "next/link";
import SpectrumBar from "@/components/viz/spectrum-bar";

const columns = [
  {
    heading: "Product",
    links: [
      { label: "Features", href: "/#features" },
      { label: "How it works", href: "/#how-it-works" },
      { label: "Pricing", href: "/#pricing" },
      { label: "Trust", href: "/#trust" },
    ],
  },
  {
    heading: "Legal",
    links: [
      { label: "Privacy", href: "/privacy" },
      { label: "Terms", href: "/terms" },
      { label: "Security", href: "/#trust" },
    ],
  },
  {
    heading: "Community",
    links: [
      { label: "GitHub", href: "https://github.com/conduit" },
      { label: "Discord", href: "https://discord.gg/conduit" },
    ],
  },
];

export default function SiteFooter() {
  return (
    <footer className="border-t border-line">
      <SpectrumBar behavior="subtle" state="idle" motion="balanced" height={2} />

      <div className="max-w-[1152px] mx-auto px-6 md:px-8 py-14 grid grid-cols-1 md:grid-cols-3 gap-10">
        <div>
          <p className="font-display font-bold text-base text-fg mb-2">
            conduit<span className="text-accent">_</span>
          </p>
          <p className="font-mono text-[11px] text-faint leading-relaxed">
            approve your agents · keep your code
          </p>
        </div>

        <div className="md:col-span-2 grid grid-cols-2 md:grid-cols-3 gap-8">
          {columns.map((col) => (
            <div key={col.heading}>
              <p className="font-display text-[10px] tracking-[0.2em] uppercase text-faint mb-3">
                {col.heading}
              </p>
              <ul className="space-y-2">
                {col.links.map((l) => {
                  const isExternal = l.href.startsWith("http") || l.href.startsWith("https");
                  const label = l.label;
                  if (isExternal) {
                    return (
                      <li key={l.href}>
                        <a
                          href={l.href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="font-mono text-xs text-dim hover:text-fg transition-colors"
                        >
                          {label}
                        </a>
                      </li>
                    );
                  }
                  return (
                    <li key={l.href}>
                      <Link
                        href={l.href}
                        className="font-mono text-xs text-dim hover:text-fg transition-colors"
                      >
                        {label}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      </div>

      <div className="border-t border-line max-w-[1152px] mx-auto px-6 md:px-8 py-5 flex flex-col sm:flex-row items-center justify-between gap-2">
        <p className="font-mono text-[11px] text-ghost">
          © 2026 conduit.dev · Your code stays on your machine.
        </p>
        <p className="font-mono text-[11px] text-ghost">
          TestFlight beta · App Store [PLANNED]
        </p>
      </div>
    </footer>
  );
}
