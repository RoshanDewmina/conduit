import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_REPORT } from "@/lib/mock-data"

export default function ReportVariantB() {
  const r = MOCK_REPORT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Summary Card</h2>
        <p className="text-xs text-white/40 mt-1">Clean summary with expandable detail</p>
      </div>

      <PhoneFrame label="report/b — summary">
        <div className="flex flex-col h-full bg-[#070b12]">
          {/* Top */}
          <div className="px-5 pt-4 pb-4">
            <div className="text-[10px] font-mono text-white/30 mb-3">
              {r.agentName} · {r.repo} · {r.permissionMode}
            </div>

            <div className="flex items-start justify-between gap-3 mb-3">
              <h2 className="text-[16px] font-bold text-white leading-snug flex-1">
                {r.goal}
              </h2>
              <span
                className={`mt-0.5 shrink-0 text-[11px] px-2.5 py-1 rounded-xl font-bold border ${
                  r.testStatus === "passed"
                    ? "bg-green-500/15 text-green-400 border-green-500/30"
                    : "bg-red-500/15 text-red-400 border-red-500/30"
                }`}
              >
                {r.testStatus}
              </span>
            </div>

            <p className="text-[13px] text-white/60 leading-relaxed">{r.diffSummary}</p>
          </div>

          {/* Stats pills */}
          <div className="px-5 pb-4 flex gap-2 flex-wrap">
            {[
              { label: `${r.changedFiles.length} files`, color: "text-blue-400 bg-blue-500/10 border-blue-500/20" },
              { label: `${r.commandsRun.length} commands`, color: "text-white/60 bg-white/[0.04] border-white/[0.08]" },
              { label: `${r.risks.length} risks`, color: "text-amber-400 bg-amber-500/10 border-amber-500/20" },
            ].map((p) => (
              <span key={p.label} className={`text-[11px] px-2.5 py-1 rounded-xl border ${p.color}`}>
                {p.label}
              </span>
            ))}
          </div>

          {/* Divider */}
          <div className="border-t border-white/[0.06] mx-5" />

          {/* Unverified */}
          <div className="px-5 py-4 flex-1">
            <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">
              Not verified
            </p>
            {r.unverified.map((u) => (
              <div key={u} className="flex items-start gap-2 mb-1.5">
                <span className="text-white/20 mt-0.5 text-[11px]">○</span>
                <p className="text-[12px] text-white/50">{u}</p>
              </div>
            ))}
          </div>

          {/* Action */}
          <div className="px-5 pb-6">
            <button className="w-full py-4 rounded-2xl text-[14px] font-bold bg-blue-500/15 text-blue-300 border border-blue-500/25 hover:bg-blue-500/25 transition-colors">
              Approve PR →
            </button>
            <button className="w-full mt-2 py-3 text-[12px] text-white/30">
              See full audit details
            </button>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
