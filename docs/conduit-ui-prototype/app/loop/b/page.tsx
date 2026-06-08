import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_LOOPS } from "@/lib/mock-data"

export default function LoopVariantB() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Gauge</h2>
        <p className="text-xs text-white/40 mt-1">Circular progress ring — at-a-glance</p>
      </div>

      <PhoneFrame label="loop/b — gauge">
        <div className="flex flex-col h-full bg-[#050810] overflow-y-auto">
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <h1 className="text-[15px] font-bold text-white">Fleet Status</h1>
          </div>

          <div className="flex flex-col gap-4 px-4 py-4">
            {MOCK_LOOPS.map((loop) => {
              const pct = loop.currentStep / loop.totalSteps
              const r = 28
              const circ = 2 * Math.PI * r
              const strokeDash = circ * pct

              const ringColor =
                loop.status === "completed" ? "#4ade80" :
                loop.status === "blocked" || loop.status === "failed" ? "#fbbf24" :
                "#3b82f6"

              return (
                <div
                  key={loop.id}
                  className="rounded-2xl border border-white/[0.06] bg-white/[0.02] px-4 py-4 flex items-center gap-4"
                >
                  {/* Gauge ring */}
                  <div className="relative shrink-0">
                    <svg width="72" height="72" viewBox="0 0 72 72" className="-rotate-90">
                      <circle cx="36" cy="36" r={r} fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth="4" />
                      <circle
                        cx="36" cy="36" r={r}
                        fill="none"
                        stroke={ringColor}
                        strokeWidth="4"
                        strokeDasharray={`${strokeDash} ${circ}`}
                        strokeLinecap="round"
                      />
                    </svg>
                    <div className="absolute inset-0 flex flex-col items-center justify-center">
                      <span className="text-[14px] font-bold text-white leading-none">
                        {loop.currentStep}
                      </span>
                      <span className="text-[9px] text-white/30 font-mono">/{loop.totalSteps}</span>
                    </div>
                  </div>

                  {/* Content */}
                  <div className="flex-1 min-w-0">
                    <p className="text-[13px] font-bold text-white mb-0.5 truncate">{loop.name}</p>
                    <p className="text-[10px] font-mono text-white/30 mb-2">
                      {loop.agentName} · {loop.startedAt}
                    </p>

                    {/* Last 2 steps */}
                    <div className="flex flex-col gap-1">
                      {loop.steps.slice(-2).map((step) => (
                        <div key={step.step} className="flex items-center gap-1.5">
                          <span className={`text-[10px] font-mono ${
                            step.status === "ok" ? "text-green-400" :
                            step.status === "blocked" ? "text-amber-400" : "text-red-400"
                          }`}>
                            {step.status === "ok" ? "✓" : step.status === "blocked" ? "●" : "✕"}
                          </span>
                          <span className="text-[10px] text-white/50 truncate">{step.summary}</span>
                        </div>
                      ))}
                    </div>

                    {/* Status chip */}
                    <span className={`inline-block mt-2 text-[9px] px-2 py-0.5 rounded-md border font-mono ${
                      loop.status === "completed" ? "bg-green-500/10 text-green-400 border-green-500/20" :
                      loop.status === "blocked" ? "bg-amber-500/10 text-amber-400 border-amber-500/20" :
                      loop.status === "running" ? "bg-blue-500/10 text-blue-400 border-blue-500/20" :
                      "bg-red-500/10 text-red-400 border-red-500/20"
                    }`}>
                      {loop.status}
                    </span>
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
