import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX } from "@/lib/mock-data"

export default function InboxVariantB() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Compact Cards</h2>
        <p className="text-xs text-white/40 mt-1">Card structure with dense spacing</p>
      </div>

      <PhoneFrame label="inbox/b — compact cards">
        <div className="flex flex-col h-full bg-[#070b12]">
          {/* Header */}
          <div className="px-4 pt-3 pb-2 border-b border-white/[0.06]">
            <div className="flex items-center justify-between">
              <h1 className="text-[15px] font-bold text-white">Inbox</h1>
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] font-mono text-white/30">3 pending</span>
                <div className="size-5 rounded-full bg-blue-500/20 border border-blue-500/30 flex items-center justify-center">
                  <span className="text-[10px] font-mono text-blue-400">3</span>
                </div>
              </div>
            </div>
          </div>

          {/* Cards */}
          <div className="flex-1 overflow-y-auto px-3 flex flex-col gap-1.5 pt-2 pb-16">
            {MOCK_INBOX.map((item) => (
              <div
                key={item.id}
                className="rounded-xl border border-white/[0.06] bg-white/[0.03] overflow-hidden"
              >
                {/* Card header */}
                <div className="px-3 pt-2 pb-1.5 border-b border-white/[0.04] flex items-center gap-2">
                  <StatusDot status={item.status} />
                  <div className="flex-1 min-w-0 flex items-center gap-1.5">
                    <span
                      className="text-[11px] font-semibold text-blue-300 shrink-0"
                      style={{ fontFamily: "var(--font-geist-mono)" }}
                    >
                      {item.agentName}
                    </span>
                    <span className="text-[10px] text-white/30 font-mono truncate">
                      {item.repo}/{item.branch}
                    </span>
                  </div>
                  <span className="text-[10px] text-white/30 font-mono shrink-0">{item.timeAgo}</span>
                </div>

                {/* Card body */}
                <div className="px-3 py-2">
                  <p className="text-[12px] text-white/80 leading-snug">
                    {item.message}
                  </p>
                  {item.context && (
                    <p className="text-[10px] text-white/35 mt-1 leading-snug line-clamp-1">
                      {item.context}
                    </p>
                  )}
                </div>

                {/* Card footer — actions for decision/proof items */}
                {item.tag === "decision" && (
                  <div className="px-3 pb-2 flex gap-1.5">
                    <button className="flex-1 py-1.5 rounded-lg text-[11px] font-semibold bg-green-500/10 text-green-400 border border-green-500/20 hover:bg-green-500/20 transition-colors">
                      Approve
                    </button>
                    <button className="flex-1 py-1.5 rounded-lg text-[11px] font-semibold bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 transition-colors">
                      Deny
                    </button>
                  </div>
                )}
                {item.tag === "proof" && (
                  <div className="px-3 pb-2">
                    <button className="w-full py-1.5 rounded-lg text-[11px] font-semibold bg-blue-500/10 text-blue-400 border border-blue-500/20 hover:bg-blue-500/20 transition-colors">
                      Review Report →
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Tab bar */}
          <div className="absolute bottom-0 left-0 right-0 border-t border-white/[0.06] bg-[#070b12]/95 backdrop-blur-sm px-6 py-3 flex justify-around">
            {["Inbox", "Fleet", "Settings"].map((tab) => (
              <span key={tab} className={`text-[11px] ${tab === "Inbox" ? "text-blue-400" : "text-white/30"}`}>
                {tab}
              </span>
            ))}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
