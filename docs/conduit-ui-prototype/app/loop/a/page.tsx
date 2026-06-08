import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_LOOPS } from "@/lib/mock-data"

const STEP_ICONS: Record<string, string> = {
  ok: "✓",
  failed: "✕",
  blocked: "●",
  skipped: "○",
}

const STEP_COLORS: Record<string, string> = {
  ok: "text-green-400",
  failed: "text-red-400",
  blocked: "text-amber-400",
  skipped: "text-white/30",
}

export default function LoopVariantA() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Timeline</h2>
        <p className="text-xs text-white/40 mt-1">Vertical step list with status + all active loops</p>
      </div>

      <PhoneFrame label="loop/a — timeline">
        <div className="flex flex-col h-full bg-[#050810]">
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <h1 className="text-[15px] font-bold text-white">Fleet Status</h1>
            <p className="text-[11px] text-white/30">{MOCK_LOOPS.length} active loops</p>
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
            {MOCK_LOOPS.map((l) => {
              const pct = Math.round((l.currentStep / l.totalSteps) * 100)
              const dotStatus =
                l.status === "completed" ? "done" :
                l.status === "blocked" ? "blocked" :
                l.status === "failed" ? "failed" : "running"
              return (
                <div key={l.id} className="px-4 py-4">
                  {/* Loop header */}
                  <div className="flex items-center gap-2 mb-2">
                    <StatusDot status={dotStatus} />
                    <span className="text-[13px] font-semibold text-white/90 flex-1">{l.name}</span>
                    <span className="text-[10px] font-mono text-white/30">{l.startedAt}</span>
                  </div>

                  {/* Progress bar */}
                  <div className="h-1 bg-white/[0.06] rounded-full mb-2 overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all ${
                        l.status === "completed" ? "bg-green-400" :
                        l.status === "blocked" || l.status === "failed" ? "bg-amber-400" :
                        "bg-blue-400"
                      }`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>

                  <div className="flex justify-between items-center mb-3">
                    <span className="text-[10px] font-mono text-white/30">
                      {l.agentName} · {l.repo}
                    </span>
                    <span className="text-[10px] font-mono text-white/40">
                      step {l.currentStep}/{l.totalSteps}
                    </span>
                  </div>

                  {/* Steps */}
                  <div className="flex flex-col gap-1">
                    {l.steps.map((step) => (
                      <div key={step.step} className="flex items-center gap-2">
                        <span className={`text-[12px] w-4 text-center font-mono font-bold ${STEP_COLORS[step.status]}`}>
                          {STEP_ICONS[step.status]}
                        </span>
                        <span className={`text-[11px] ${step.status !== "ok" ? "text-white/80" : "text-white/40"}`}>
                          {step.summary}
                        </span>
                      </div>
                    ))}
                    {/* Pending steps */}
                    {Array.from({ length: l.totalSteps - l.steps.length }).map((_, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <span className="text-[12px] w-4 text-center font-mono text-white/20">○</span>
                        <span className="text-[11px] text-white/20">pending</span>
                      </div>
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
