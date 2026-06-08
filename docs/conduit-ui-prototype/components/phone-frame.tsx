import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

interface PhoneFrameProps {
  children: ReactNode
  className?: string
  label?: string
}

export function PhoneFrame({ children, className, label }: PhoneFrameProps) {
  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className={cn(
          "relative w-[390px] rounded-[44px] phone-glow",
          "bg-[#0a0e16] border border-white/10",
          "overflow-hidden",
          className
        )}
        style={{ height: "844px" }}
      >
        {/* Notch */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-28 h-7 bg-[#0a0e16] rounded-b-2xl border-x border-b border-white/10 z-10" />

        {/* Status bar */}
        <div className="flex justify-between items-center px-8 pt-3 pb-1 text-[11px] text-white/40 relative z-10">
          <span style={{ fontFamily: "var(--font-geist-mono)" }}>9:41</span>
          <div className="flex gap-1 items-center">
            <span>●●●</span>
            <span>▲</span>
            <span>⬛</span>
          </div>
        </div>

        {/* Screen content — pb-6 clears the absolute home indicator */}
        <div className="h-full overflow-hidden pb-6">{children}</div>

        {/* Home indicator */}
        <div className="absolute bottom-2 left-1/2 -translate-x-1/2 w-32 h-1 bg-white/20 rounded-full" />
      </div>
      {label && (
        <span
          className="text-xs text-white/40"
          style={{ fontFamily: "var(--font-geist-mono)" }}
        >
          {label}
        </span>
      )}
    </div>
  )
}
