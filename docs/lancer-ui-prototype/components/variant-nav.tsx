"use client"
import Link from "next/link"
import { usePathname } from "next/navigation"
import { cn } from "@/lib/utils"

const SCREENS = [
  {
    label: "Monetization",
    variants: [{ label: "Trigger timing", href: "/monetization" }],
  },
  {
    label: "Onboarding",
    variants: [
      { label: "Compare", href: "/onboarding" },
      { label: "Current", href: "/onboarding/current" },
      { label: "Proposed", href: "/onboarding/proposed" },
    ],
  },
  {
    label: "Chat Context",
    variants: [
      { label: "A — Promoted pills", href: "/chat-context/a" },
      { label: "B — Combined sheet", href: "/chat-context/b" },
      { label: "C — Breadcrumb bar", href: "/chat-context/c" },
    ],
  },
  {
    label: "Inbox",
    variants: [
      { label: "A — Ops Center", href: "/inbox/a" },
      { label: "B — Feed", href: "/inbox/b" },
      { label: "C — Dashboard", href: "/inbox/c" },
    ],
  },
  {
    label: "Checkpoint",
    variants: [
      { label: "A — Risk Card", href: "/checkpoint/a" },
      { label: "B — Sheet", href: "/checkpoint/b" },
    ],
  },
  {
    label: "Loop",
    variants: [
      { label: "A — Timeline", href: "/loop/a" },
      { label: "B — Gauge", href: "/loop/b" },
    ],
  },
  {
    label: "Report",
    variants: [
      { label: "A — Audit", href: "/report/a" },
      { label: "B — Summary", href: "/report/b" },
    ],
  },
]

export function VariantNav() {
  const path = usePathname()
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-white/[0.06] bg-[#050810]/90 backdrop-blur-sm">
      <div className="max-w-7xl mx-auto px-6 py-3 flex items-center gap-6 overflow-x-auto">
        <Link href="/" className="text-sm font-bold text-white/90 shrink-0">
          ⬡ Lancer
        </Link>
        <div className="flex gap-1 flex-wrap">
          {SCREENS.flatMap((screen) =>
            screen.variants.map((v) => (
              <Link
                key={v.href}
                href={v.href}
                className={cn(
                  "px-3 py-1 rounded-md text-xs whitespace-nowrap transition-all",
                  path === v.href
                    ? "bg-blue-500/20 text-blue-400 border border-blue-500/30"
                    : "text-white/40 hover:text-white/70 hover:bg-white/5"
                )}
              >
                {screen.label} {v.label}
              </Link>
            ))
          )}
        </div>
      </div>
    </nav>
  )
}
