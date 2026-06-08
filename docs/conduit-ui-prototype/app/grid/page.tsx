"use client"
import { useEffect, useRef } from "react"

const SCREENS = [
  { label: "Checkpoint A — Risk Card", href: "/checkpoint/a" },
  { label: "Checkpoint B — Bottom Sheet", href: "/checkpoint/b" },
  { label: "Loop A — Timeline", href: "/loop/a" },
  { label: "Loop B — Gauge", href: "/loop/b" },
  { label: "Report A — Audit", href: "/report/a" },
  { label: "Report B — Summary", href: "/report/b" },
]

export default function GridPage() {
  return (
    <main className="min-h-screen bg-[#050810] px-8 py-10">
      <div className="mb-8">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Design Review</p>
        <h1 className="text-2xl font-bold text-white">All Screens</h1>
      </div>
      <div className="grid grid-cols-3 gap-8">
        {SCREENS.map((s) => (
          <div key={s.href} className="flex flex-col gap-2">
            <p className="text-xs text-white/50 font-mono">{s.label}</p>
            <iframe
              src={s.href}
              className="w-full rounded-2xl border border-white/[0.06]"
              style={{ height: 700, background: "#050810", colorScheme: "dark" }}
            />
          </div>
        ))}
      </div>
    </main>
  )
}
