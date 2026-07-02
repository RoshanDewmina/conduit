import type { ReactNode } from "react"

/** Compact Dynamic Island pill — leading/trailing only, matches
 * LancerSessionLiveActivity's compactLeading/compactTrailing regions. */
export function DynamicIslandCompact({
  leading,
  trailing,
}: {
  leading: ReactNode
  trailing: ReactNode
}) {
  return (
    <div className="w-[126px] h-9 rounded-full bg-black flex items-center justify-between px-3.5 mx-auto">
      <div className="flex items-center">{leading}</div>
      <div className="flex items-center">{trailing}</div>
    </div>
  )
}

/** Expanded Dynamic Island — leading/trailing/center/bottom regions, matches
 * LancerSessionLiveActivity's DynamicIslandExpandedRegion layout. */
export function DynamicIslandExpanded({
  leading,
  trailing,
  center,
  bottom,
  label,
}: {
  leading: ReactNode
  trailing: ReactNode
  center: ReactNode
  bottom: ReactNode
  label?: string
}) {
  return (
    <div className="flex flex-col items-center gap-2">
      <div className="w-[340px] rounded-[32px] bg-black px-5 pt-4 pb-4 mx-auto">
        <div className="flex items-start justify-between">
          <div className="flex items-center">{leading}</div>
          <div className="flex items-center">{trailing}</div>
        </div>
        <div className="flex justify-center -mt-1">{center}</div>
        <div className="mt-2 flex justify-center">{bottom}</div>
      </div>
      {label && (
        <span className="text-xs text-white/40" style={{ fontFamily: "var(--font-geist-mono)" }}>
          {label}
        </span>
      )}
    </div>
  )
}
