"use client"

const CHOSEN = [
  {
    screen: "Agent Inbox",
    variant: "B — Compact Cards",
    href: "/inbox/b",
    rationale: "Card structure with dense spacing and inline actions",
  },
  {
    screen: "Checkpoint / Ask",
    variant: "B — Bottom Sheet",
    href: "/checkpoint/b",
    rationale: "Slides up over inbox context, compact approve/deny",
  },
  {
    screen: "Loop Progress",
    variant: "A — Timeline",
    href: "/loop/a",
    rationale: "All steps visible with status icons and progress bar",
  },
  {
    screen: "Report Card",
    variant: "A — Audit",
    href: "/report/a",
    rationale: "Technical view with diff, files, commands, and risks",
  },
]

export default function FinalPage() {
  return (
    <main className="min-h-screen bg-[#050810] px-8 py-10">
      <div className="mb-8 flex items-end justify-between">
        <div>
          <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">
            Final Design Reference
          </p>
          <h1 className="text-2xl font-bold text-white">Chosen Variants</h1>
          <p className="text-white/40 text-sm mt-1">
            Approved directions for iOS implementation
          </p>
        </div>
        <div className="text-right">
          <p className="text-[10px] font-mono text-white/20 uppercase tracking-widest">Next step</p>
          <p className="text-xs text-blue-400 font-mono">Plan 2 — SwiftUI screens</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-10">
        {CHOSEN.map((s) => (
          <div key={s.href} className="flex flex-col gap-3">
            <div>
              <div className="flex items-center gap-2 mb-0.5">
                <span className="text-[10px] font-mono text-white/30 uppercase tracking-widest">
                  {s.screen}
                </span>
                <span className="text-[10px] px-1.5 py-0.5 rounded border border-blue-500/30 bg-blue-500/10 text-blue-400 font-mono">
                  chosen
                </span>
              </div>
              <p className="text-sm font-semibold text-white/80">{s.variant}</p>
              <p className="text-[11px] text-white/35 mt-0.5">{s.rationale}</p>
            </div>
            <iframe
              src={s.href}
              className="w-full rounded-2xl border border-white/[0.06]"
              style={{ height: 760, background: "#050810", colorScheme: "dark" }}
            />
          </div>
        ))}
      </div>
    </main>
  )
}
