import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_CHECKPOINT } from "@/lib/mock-data"

const BLAST_LABELS: Record<string, string> = {
  "repo-only": "repo only",
  "private-infra": "private infra",
  "none": "none",
  "deployed": "deployed",
  "easy-rollback": "easy rollback",
  "staging": "staging",
}

const BLAST_COLORS: Record<string, string> = {
  "repo-only": "text-green-400 bg-green-500/10 border-green-500/20",
  "private-infra": "text-amber-400 bg-amber-500/10 border-amber-500/20",
  "none": "text-green-400 bg-green-500/10 border-green-500/20",
  "deployed": "text-red-400 bg-red-500/10 border-red-500/20",
  "easy-rollback": "text-green-400 bg-green-500/10 border-green-500/20",
  "staging": "text-amber-400 bg-amber-500/10 border-amber-500/20",
}

export default function CheckpointVariantA() {
  const cp = MOCK_CHECKPOINT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Risk Card</h2>
        <p className="text-xs text-white/40 mt-1">Full-screen decision with blast-radius breakdown</p>
      </div>

      <PhoneFrame label="checkpoint/a — risk card">
        <div className="flex flex-col h-full bg-[#050810] px-5 py-4 overflow-y-auto">
          {/* Agent identity */}
          <div className="text-[11px] font-mono text-white/30 mb-4">
            {cp.agentName} · {cp.repo}/{cp.branch} · {cp.host}
          </div>

          {/* Risk level indicator */}
          <div
            className={`text-[10px] font-bold uppercase tracking-widest mb-3 px-2 py-1 rounded self-start border ${
              cp.riskLevel === "high"
                ? "text-red-400 bg-red-500/10 border-red-500/30"
                : "text-amber-400 bg-amber-500/10 border-amber-500/30"
            }`}
            style={{ fontFamily: "var(--font-geist-mono)" }}
          >
            {cp.riskLevel} risk
          </div>

          {/* Question */}
          <h2 className="text-[18px] font-bold text-white leading-snug mb-3">
            {cp.question}
          </h2>

          {/* Context */}
          <div className="rounded-xl border border-white/[0.06] bg-white/[0.02] p-3 mb-4">
            <p className="text-[12px] text-white/60 leading-relaxed">{cp.context}</p>
          </div>

          {/* Blast radius */}
          <div className="mb-5">
            <p className="text-[10px] font-mono text-white/30 uppercase tracking-widest mb-2">
              Blast radius
            </p>
            <div className="grid grid-cols-2 gap-1.5">
              {Object.entries(cp.blastRadius).map(([key, val]) => (
                <div
                  key={key}
                  className={`flex items-center justify-between px-2 py-1.5 rounded-lg border text-[10px] ${BLAST_COLORS[val] ?? "text-white/40 bg-white/[0.02] border-white/[0.06]"}`}
                >
                  <span className="text-white/40 capitalize">{key.replace(/_/g, " ")}</span>
                  <span className="font-mono font-semibold">{BLAST_LABELS[val] ?? val}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Actions */}
          <div className="mt-auto flex flex-col gap-2 pb-2">
            <button className="w-full py-3.5 rounded-2xl text-[14px] font-bold bg-green-500/15 text-green-400 border border-green-500/30 hover:bg-green-500/25 transition-colors">
              ✓ Approve — Roll Back
            </button>
            <div className="flex gap-2">
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-semibold bg-blue-500/10 text-blue-400 border border-blue-500/20">
                Retry Instead
              </button>
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-semibold bg-red-500/10 text-red-400 border border-red-500/20">
                Deny / Pause
              </button>
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
