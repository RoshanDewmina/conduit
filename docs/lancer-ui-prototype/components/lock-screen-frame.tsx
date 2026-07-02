import type { ReactNode } from "react"
import { Flashlight, Camera } from "lucide-react"
import { cn } from "@/lib/utils"

interface LockScreenFrameProps {
  children: ReactNode
  className?: string
  label?: string
}

/** iOS lock-screen chrome, sized to host a Live Activity banner near the bottom — matches
 * the real placement (above the flashlight/camera row), not a full app screen like PhoneFrame. */
export function LockScreenFrame({ children, className, label }: LockScreenFrameProps) {
  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className={cn(
          "relative w-[300px] rounded-[40px] overflow-hidden border border-white/10",
          className
        )}
        style={{
          height: "620px",
          // Warmed to the brand's own terminal-ink tone (--term-bg/--term-bg-2)
          // instead of a generic blue-gray wallpaper — ties the OS chrome back
          // to Conduit's "Editorial · Sand" palette even though Live Activities
          // are always dark, never warm paper.
          background: "linear-gradient(160deg, #2b241c 0%, #1d1a17 55%, #0d0c0b 100%)",
        }}
      >
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-24 h-6 bg-black rounded-b-2xl z-20" />

        <div className="pt-16 flex flex-col items-center text-white">
          <span className="text-[12px] text-white/60 font-medium">Wednesday, 1 July</span>
          <span className="text-[54px] font-semibold leading-none mt-1 tabular-nums">9:41</span>
        </div>

        <div className="absolute left-3 right-3 bottom-[76px]">{children}</div>

        <div className="absolute bottom-6 left-0 right-0 flex justify-between px-8">
          <div className="w-9 h-9 rounded-full bg-white/15 flex items-center justify-center text-white/70">
            <Flashlight className="size-4" />
          </div>
          <div className="w-9 h-9 rounded-full bg-white/15 flex items-center justify-center text-white/70">
            <Camera className="size-4" />
          </div>
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
