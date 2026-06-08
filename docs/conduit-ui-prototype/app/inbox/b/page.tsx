import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX } from "@/lib/mock-data"

export default function InboxVariantB() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Feed</h2>
        <p className="text-xs text-white/40 mt-1">Rich cards with context preview — spacious</p>
      </div>

      <PhoneFrame label="inbox/b — feed">
        <div className="flex flex-col h-full bg-[#070b12]">
          {/* Header */}
          <div className="px-5 pt-3 pb-3">
            <div className="flex items-center justify-between mb-1">
              <h1 className="text-[17px] font-bold text-white">Agent Inbox</h1>
              <div className="size-7 rounded-full bg-blue-500/20 border border-blue-500/30 flex items-center justify-center">
                <span className="text-[11px] font-mono text-blue-400">3</span>
              </div>
            </div>
            <p className="text-[11px] text-white/30">3 need attention</p>
          </div>

          {/* Cards */}
          <div className="flex-1 overflow-y-auto px-4 flex flex-col gap-3 pb-20">
            {MOCK_INBOX.map((item) => (
              <div
                key={item.id}
                className="rounded-2xl border border-white/[0.06] bg-white/[0.03] overflow-hidden"
              >
                {/* Card header */}
                <div className="px-4 pt-3 pb-2 border-b border-white/[0.04] flex items-center gap-2">
                  <StatusDot status={item.status} />
                  <div className="flex-1 min-w-0">
                    <span
                      className="text-[11px] font-semibold text-blue-300"
                      style={{ fontFamily: "var(--font-geist-mono)" }}
                    >
                      {item.agentName}
                    </span>
                    <span className="text-[10px] text-white/30 font-mono ml-2">
                      {item.repo}
                    </span>
                  </div>
                  <span className="text-[10px] text-white/30 font-mono shrink-0">{item.timeAgo}</span>
                </div>

                {/* Card body */}
                <div className="px-4 py-3">
                  <p className="text-[13px] text-white/90 leading-relaxed font-medium">
                    {item.message}
                  </p>
                  {item.context && (
                    <p className="text-[11px] text-white/40 mt-2 leading-relaxed line-clamp-2">
                      {item.context}
                    </p>
                  )}
                </div>

                {/* Card footer — actions for decision/proof items */}
                {item.tag === "decision" && (
                  <div className="px-4 pb-3 flex gap-2">
                    <button className="flex-1 py-2 rounded-xl text-[12px] font-semibold bg-green-500/10 text-green-400 border border-green-500/20 hover:bg-green-500/20 transition-colors">
                      Approve
                    </button>
                    <button className="flex-1 py-2 rounded-xl text-[12px] font-semibold bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 transition-colors">
                      Deny
                    </button>
                  </div>
                )}
                {item.tag === "proof" && (
                  <div className="px-4 pb-3">
                    <button className="w-full py-2 rounded-xl text-[12px] font-semibold bg-blue-500/10 text-blue-400 border border-blue-500/20 hover:bg-blue-500/20 transition-colors">
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
