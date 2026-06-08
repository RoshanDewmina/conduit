import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX } from "@/lib/mock-data"

const TAG_STYLES = {
  decision: "border-red-500/30 bg-red-500/10 text-red-400",
  proof: "border-green-500/30 bg-green-500/10 text-green-400",
  blocked: "border-amber-500/30 bg-amber-500/10 text-amber-400",
  failed: "border-red-500/30 bg-red-900/20 text-red-300",
}

export default function InboxVariantA() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Ops Center</h2>
        <p className="text-xs text-white/40 mt-1">Dense linear list — maximum information per row</p>
      </div>

      <PhoneFrame label="inbox/a — ops center">
        <div className="flex flex-col h-full bg-[#050810]">
          {/* Header */}
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <div className="flex items-center justify-between">
              <h1 className="text-[15px] font-bold text-white">Inbox</h1>
              <span className="text-[11px] font-mono text-white/40">3 pending</span>
            </div>
          </div>

          {/* Item list */}
          <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
            {MOCK_INBOX.map((item) => (
              <div
                key={item.id}
                className="flex gap-3 px-4 py-3 hover:bg-white/[0.02] transition-colors"
              >
                {/* Left gutter: status dot */}
                <div className="flex flex-col items-center gap-1.5 pt-1">
                  <StatusDot status={item.status} />
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 mb-0.5">
                    <span
                      className="text-[11px] font-semibold text-blue-400 truncate"
                      style={{ fontFamily: "var(--font-geist-mono)" }}
                    >
                      {item.agentName}
                    </span>
                    <span className="text-[10px] text-white/30 font-mono truncate">
                      {item.repo}/{item.branch}
                    </span>
                  </div>
                  <p className="text-[12px] text-white/80 leading-snug line-clamp-2">
                    {item.message}
                  </p>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-white/30 font-mono">{item.timeAgo}</span>
                    {item.tag && (
                      <span
                        className={`text-[9px] px-1.5 py-0.5 rounded border ${TAG_STYLES[item.tag]}`}
                      >
                        {item.tag}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Tab bar */}
          <div className="border-t border-white/[0.06] px-4 py-3 flex justify-around">
            {["Inbox", "Fleet", "Settings"].map((tab) => (
              <span
                key={tab}
                className={`text-[11px] ${tab === "Inbox" ? "text-blue-400" : "text-white/30"}`}
              >
                {tab}
              </span>
            ))}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
