import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX } from "@/lib/mock-data"

const AGENTS = [
  { name: "DeployBot", status: "blocked" as const, events: 2, model: "custom" },
  { name: "ClaudeCode", status: "done" as const, events: 1, model: "claude-code" },
  { name: "ResearchBot", status: "blocked" as const, events: 1, model: "custom" },
  { name: "CodexAgent", status: "running" as const, events: 0, model: "codex" },
]

export default function InboxVariantC() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant C</p>
        <h2 className="text-lg font-bold text-white">Dashboard</h2>
        <p className="text-xs text-white/40 mt-1">Fleet list + selected agent events — two-column</p>
      </div>

      <PhoneFrame label="inbox/c — dashboard">
        <div className="flex h-full bg-[#050810]">
          {/* Left: Agent fleet column */}
          <div className="w-[120px] shrink-0 border-r border-white/[0.06] flex flex-col">
            <div className="px-3 pt-3 pb-2 border-b border-white/[0.04]">
              <span className="text-[10px] font-mono text-white/30 uppercase tracking-wide">Fleet</span>
            </div>
            <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
              {AGENTS.map((agent, i) => (
                <div
                  key={agent.name}
                  className={`px-3 py-3 flex flex-col gap-1 cursor-pointer transition-colors ${
                    i === 0 ? "bg-blue-500/10 border-l-2 border-blue-500" : "hover:bg-white/[0.02]"
                  }`}
                >
                  <div className="flex items-center gap-1.5">
                    <StatusDot status={agent.status} />
                    {agent.events > 0 && (
                      <span className="ml-auto text-[9px] bg-red-500 text-white rounded-full size-4 flex items-center justify-center font-bold">
                        {agent.events}
                      </span>
                    )}
                  </div>
                  <span className="text-[11px] font-semibold text-white/80 leading-tight truncate">
                    {agent.name}
                  </span>
                  <span
                    className="text-[9px] text-white/30 truncate"
                    style={{ fontFamily: "var(--font-geist-mono)" }}
                  >
                    {agent.model}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Right: Selected agent events */}
          <div className="flex-1 flex flex-col min-w-0">
            <div className="px-4 pt-3 pb-2 border-b border-white/[0.06]">
              <p className="text-[13px] font-bold text-white">DeployBot</p>
              <p className="text-[10px] font-mono text-white/30">command-center · mac-mini-prod</p>
            </div>
            <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
              {MOCK_INBOX.filter((item) => item.agentName === "DeployBot").map((item) => (
                <div key={item.id} className="px-4 py-3">
                  <div className="flex items-center gap-1.5 mb-1">
                    <StatusDot status={item.status} />
                    <span className="text-[10px] font-mono text-white/30">{item.timeAgo}</span>
                  </div>
                  <p className="text-[12px] text-white/80 leading-snug">{item.message}</p>
                  {item.tag === "decision" && (
                    <div className="flex gap-2 mt-2">
                      <button className="px-3 py-1 rounded-lg text-[11px] bg-green-500/10 text-green-400 border border-green-500/20">
                        Approve
                      </button>
                      <button className="px-3 py-1 rounded-lg text-[11px] bg-red-500/10 text-red-400 border border-red-500/20">
                        Deny
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
