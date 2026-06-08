import Link from "next/link"

const SECTIONS = [
  {
    title: "Agent Inbox",
    description: "How the main notification list looks and feels",
    variants: [
      { label: "A — Ops Center", sub: "Dense linear list, max information density", href: "/inbox/a" },
      { label: "B — Feed", sub: "Spacious cards with rich preview content", href: "/inbox/b" },
      { label: "C — Dashboard", sub: "Split pane: fleet list + agent event timeline", href: "/inbox/c" },
    ],
  },
  {
    title: "Checkpoint / Ask",
    description: "When an agent needs a human decision",
    variants: [
      { label: "A — Risk Card", sub: "Full-screen with blast-radius meter", href: "/checkpoint/a" },
      { label: "B — Sheet", sub: "Bottom sheet with context + quick actions", href: "/checkpoint/b" },
    ],
  },
  {
    title: "Loop Progress",
    description: "Multi-step loop status while running",
    variants: [
      { label: "A — Timeline", sub: "Vertical step list with status icons", href: "/loop/a" },
      { label: "B — Gauge", sub: "Circular progress + compact step log", href: "/loop/b" },
    ],
  },
  {
    title: "Report Card",
    description: "Structured completion card shown when a task finishes",
    variants: [
      { label: "A — Audit", sub: "Technical: diff view, file list, test output", href: "/report/a" },
      { label: "B — Summary", sub: "Clean: goal + stats + expandable risks", href: "/report/b" },
    ],
  },
]

export default function Home() {
  return (
    <main className="min-h-screen bg-[#050810] px-8 py-16">
      <div className="max-w-3xl mx-auto">
        <div className="mb-12">
          <p
            className="text-xs tracking-widest text-blue-400 mb-3 uppercase"
            style={{ fontFamily: "var(--font-geist-mono)" }}
          >
            Design Prototype
          </p>
          <h1 className="text-4xl font-bold text-white mb-3">Conduit UI</h1>
          <p className="text-white/50 text-base">
            Review these variants and give feedback before we write Swift code.
            Each screen has 2–3 distinct design directions.
          </p>
        </div>

        <div className="flex flex-col gap-10">
          {SECTIONS.map((section) => (
            <div key={section.title}>
              <div className="mb-4">
                <h2 className="text-sm font-semibold text-white/80">{section.title}</h2>
                <p className="text-xs text-white/40 mt-0.5">{section.description}</p>
              </div>
              <div className="grid grid-cols-1 gap-2">
                {section.variants.map((v) => (
                  <Link
                    key={v.href}
                    href={v.href}
                    className="group flex items-center justify-between px-4 py-3 rounded-xl border border-white/[0.06] bg-white/[0.02] hover:bg-white/[0.05] hover:border-blue-500/30 transition-all"
                  >
                    <div>
                      <span className="text-sm font-medium text-white/90 group-hover:text-white">
                        {v.label}
                      </span>
                      <p className="text-xs text-white/40 mt-0.5">{v.sub}</p>
                    </div>
                    <span className="text-white/20 group-hover:text-blue-400 transition-colors text-sm">→</span>
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </main>
  )
}
