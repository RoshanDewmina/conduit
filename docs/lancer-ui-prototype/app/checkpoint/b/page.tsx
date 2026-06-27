import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX, MOCK_CHECKPOINT } from "@/lib/mock-data"

export default function CheckpointVariantB() {
  const cp = MOCK_CHECKPOINT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Bottom Sheet</h2>
        <p className="text-xs text-white/40 mt-1">Sheet slides up from inbox — compact + contextual</p>
      </div>

      <PhoneFrame label="checkpoint/b — sheet">
        <div className="relative flex flex-col h-full bg-[#050810]">
          {/* Background: dimmed inbox */}
          <div className="absolute inset-0 flex flex-col opacity-30 pointer-events-none">
            <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
              <h1 className="text-[15px] font-bold text-white">Inbox</h1>
            </div>
            {MOCK_INBOX.slice(1).map((item) => (
              <div key={item.id} className="flex gap-3 px-4 py-3 border-b border-white/[0.04]">
                <StatusDot status={item.status} />
                <div className="flex-1 min-w-0">
                  <p className="text-[11px] font-mono text-blue-400 mb-0.5">{item.agentName}</p>
                  <p className="text-[12px] text-white/70 line-clamp-1">{item.message}</p>
                </div>
              </div>
            ))}
          </div>

          {/* Overlay backdrop */}
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

          {/* Bottom sheet */}
          <div className="absolute bottom-0 left-0 right-0 bg-[#0d1420] border-t border-white/[0.08] rounded-t-3xl px-5 pt-3 pb-6">
            {/* Drag handle */}
            <div className="w-10 h-1 bg-white/20 rounded-full mx-auto mb-4" />

            {/* Agent line */}
            <p className="text-[11px] font-mono text-white/30 mb-3">
              {cp.agentName} · {cp.repo} · {cp.permissionMode} mode
            </p>

            {/* Question */}
            <h3 className="text-[16px] font-bold text-white leading-snug mb-3">
              {cp.question}
            </h3>

            {/* Context quote */}
            <div className="border-l-2 border-amber-500/40 pl-3 mb-4">
              <p className="text-[12px] text-white/50 leading-relaxed line-clamp-3">
                {cp.context}
              </p>
            </div>

            {/* Actions */}
            <div className="flex gap-2">
              <button className="flex-1 py-3.5 rounded-2xl text-[13px] font-bold bg-green-500/15 text-green-400 border border-green-500/30">
                ✓ Approve
              </button>
              <button className="flex-1 py-3.5 rounded-2xl text-[13px] font-bold bg-red-500/10 text-red-400 border border-red-500/20">
                ✕ Deny
              </button>
            </div>
            <button className="w-full mt-2 py-2.5 text-[12px] text-white/40 hover:text-white/60">
              Edit response before sending
            </button>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
