import type { ReactNode } from "react"

/** Siri / Spotlight / Shortcuts overlay chrome. Per Apple's own design rules
 * (WWDC26 "Design interactive snippets"): snippets "always appear clearly at
 * the top of the screen, overlaying other content" — never bottom-anchored
 * like a Live Activity banner, never full-screen. Background is a generic
 * blurred backdrop (whatever app/screen was open), not a specific Spotlight
 * recreation — we don't have real reference screenshots to match pixel-for-
 * pixel, and the backdrop's exact look isn't the point being tested here. */
export function SiriSnippetFrame({
  children,
  dialog,
  label,
}: {
  children: ReactNode
  dialog?: string
  label?: string
}) {
  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className="relative w-[300px] rounded-[40px] overflow-hidden border border-black/10"
        style={{
          height: "620px",
          background: "linear-gradient(160deg, #dcdad3 0%, #c9c7c0 55%, #b8b6ae 100%)",
        }}
      >
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-24 h-6 bg-black rounded-b-2xl z-20" />

        {/* Blurred backdrop content — implies "something was already open" */}
        <div className="absolute inset-0 backdrop-blur-md opacity-40">
          <div className="pt-20 px-6 flex flex-col gap-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-12 rounded-2xl bg-white/50" />
            ))}
          </div>
        </div>

        {/* Siri indicator + spoken dialog — separate channel from the snippet view itself */}
        {dialog && (
          <div className="absolute top-9 left-4 right-4 z-10 flex items-start gap-2">
            <div
              className="mt-0.5 size-5 shrink-0 rounded-full"
              style={{ background: "conic-gradient(from 45deg, #8b6fb0, #b08fce, #6f5a96, #9d7fc0)" }}
            />
            <p className="text-[11px] leading-snug text-black/60 italic" style={{ fontFamily: "var(--font-geist-sans)" }}>
              {dialog}
            </p>
          </div>
        )}

        {/* The snippet itself — top-anchored, overlaying the backdrop */}
        <div className="absolute left-3 right-3 z-20" style={{ top: dialog ? 70 : 44 }}>
          {children}
        </div>
      </div>
      {label && (
        <span className="text-xs text-white/40" style={{ fontFamily: "var(--font-geist-mono)" }}>
          {label}
        </span>
      )}
    </div>
  )
}
