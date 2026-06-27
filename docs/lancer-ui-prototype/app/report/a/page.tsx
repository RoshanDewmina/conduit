import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_REPORT } from "@/lib/mock-data"

export default function ReportVariantA() {
  const r = MOCK_REPORT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Audit Card</h2>
        <p className="text-xs text-white/40 mt-1">Technical view — diff, files, commands, risks</p>
      </div>

      <PhoneFrame label="report/a — audit">
        <div className="flex flex-col h-full bg-[#050810] overflow-y-auto">
          {/* Header */}
          <div className="px-4 pt-3 pb-3 border-b border-white/[0.06]">
            <p className="text-[10px] font-mono text-blue-400/60 mb-1">
              {r.agentName} · {r.repo}/{r.branch} · {r.permissionMode} mode
            </p>
            <h2 className="text-[15px] font-bold text-white leading-tight">{r.goal}</h2>
          </div>

          {/* Stats row */}
          <div className="grid grid-cols-3 divide-x divide-white/[0.06] border-b border-white/[0.06]">
            {[
              { label: "Tests", value: r.testStatus, color: r.testStatus === "passed" ? "text-green-400" : "text-red-400" },
              { label: "Files", value: `${r.changedFiles.length}`, color: "text-white" },
              { label: "Cmds", value: `${r.commandsRun.length}`, color: "text-white" },
            ].map((s) => (
              <div key={s.label} className="flex flex-col items-center py-3">
                <span className={`text-[13px] font-bold font-mono ${s.color}`}>{s.value}</span>
                <span className="text-[10px] text-white/30 mt-0.5">{s.label}</span>
              </div>
            ))}
          </div>

          <div className="flex flex-col divide-y divide-white/[0.04] pb-4">
            {/* Diff summary */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-1">Diff summary</p>
              <p className="text-[12px] text-white/70 leading-relaxed">{r.diffSummary}</p>
            </div>

            {/* Files */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Changed files</p>
              {r.changedFiles.map((f) => (
                <p key={f} className="text-[11px] font-mono text-blue-300/70 leading-relaxed">+ {f}</p>
              ))}
            </div>

            {/* Commands */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Commands run</p>
              {r.commandsRun.map((c) => (
                <p key={c} className="text-[11px] font-mono text-white/50 leading-relaxed">$ {c}</p>
              ))}
            </div>

            {/* Risks */}
            {r.risks.length > 0 && (
              <div className="px-4 py-3">
                <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Risks</p>
                <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 p-3">
                  {r.risks.map((risk) => (
                    <p key={risk} className="text-[11px] text-amber-300/80 leading-relaxed">⚠ {risk}</p>
                  ))}
                </div>
              </div>
            )}

            {/* Actions */}
            <div className="px-4 pt-3 flex gap-2">
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-bold bg-green-500/15 text-green-400 border border-green-500/30">
                ✓ Approve PR
              </button>
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-bold bg-red-500/10 text-red-400 border border-red-500/20">
                ✕ Reject
              </button>
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
