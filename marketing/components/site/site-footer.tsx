import Link from "next/link";
import SpectrumBar from "@/components/viz/spectrum-bar";

const columns = [
  {
    heading: "Product",
    links: [
      { label: "How it works", href: "/product" },
      { label: "Trust & Privacy", href: "/trust" },
      { label: "Pricing", href: "/pricing" },
    ],
  },
  {
    heading: "Docs",
    links: [
      { label: "Documentation", href: "/docs" },
      { label: "Download", href: "/download" },
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
                {col.links.map((l) => (
                  <li key={l.href}>
                    <Link
                      href={l.href}
                      className="font-mono text-xs text-dim hover:text-fg transition-colors"
                    >
                      {l.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}

          <div>
            <p className="font-display text-[10px] tracking-[0.2em] uppercase text-faint mb-3">
              Status
            </p>
            <ul className="space-y-2">
              <li className="font-mono text-xs text-dim">
                TestFlight beta —{" "}
                <span className="text-faint">App Store [PLANNED]</span>
              </li>
              <li className="font-mono text-xs text-faint">
                No Conduit account.
              </li>
              <li className="font-mono text-xs text-faint">
                Your code stays on your machine.
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div className="border-t border-line max-w-[1152px] mx-auto px-6 md:px-8 py-5">
        <p className="font-mono text-[11px] text-ghost">© 2026 conduit.dev</p>
      </div>
    </footer>
  );
}
