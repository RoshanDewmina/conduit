import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"

export default function OnboardingProposed() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Proposed — not built yet</p>
        <h2 className="text-lg font-bold text-white">Onboarding · Value + Pair</h2>
        <p className="text-xs text-white/40 mt-1 max-w-[360px] mx-auto">
          Direction both audits agreed on: show the real product instead of
          abstract bullets, and put pairing errors right next to the field
        </p>
      </div>

      <PhoneFrame label="onboarding/proposed — real product preview">
        <div className="flex flex-col h-full bg-[#050810]">
          {/* Step dots */}
          <div className="flex justify-end gap-1.5 px-6 pt-2">
            <span className="w-5 h-1.5 rounded-full bg-orange-400" />
            <span className="w-1.5 h-1.5 rounded-full bg-white/15" />
            <span className="w-1.5 h-1.5 rounded-full bg-white/15" />
          </div>

          {/* Hero — SAME terracotta chrome, but the body is now a real product
              preview instead of an italic kicker + abstract title */}
          <div
            className="px-6 pt-5 pb-5 rounded-b-[28px]"
            style={{ background: "linear-gradient(135deg, #f0a878 0%, #e8946a 100%)" }}
          >
            <div className="flex items-center gap-2 mb-3">
              <div className="w-8 h-8 rounded-lg bg-purple-300/70 border border-white/40" />
              <p className="text-white font-bold text-sm">Steer AI coding agents from your phone.</p>
            </div>

            {/* Mini product-preview card: connected machine + 1 pending approval
                + a work-thread excerpt, exactly what the audit asked for */}
            <div className="rounded-2xl bg-[#0a0e16]/95 border border-white/15 p-3 shadow-lg">
              <div className="flex items-center gap-2 mb-2.5">
                <StatusDot status="running" />
                <span className="text-[11px] font-mono text-white/70">hermes-box · connected</span>
              </div>
              <div className="rounded-lg bg-amber-500/10 border border-amber-500/25 px-2.5 py-2 mb-2">
                <p className="text-[10px] font-mono uppercase tracking-wide text-amber-400">Needs you</p>
                <p className="text-[11px] text-white/80 mt-0.5">Approve: apply migration patch</p>
              </div>
              <div className="rounded-lg bg-white/[0.04] px-2.5 py-2">
                <p className="text-[10px] text-white/40 font-mono">Claude Code · fix login redirect</p>
                <p className="text-[11px] text-white/60 mt-0.5 line-clamp-1">→ Read AuthView.swift, 3 files changed</p>
              </div>
            </div>
          </div>

          <div className="flex-1 px-6 pt-5 flex flex-col gap-4 overflow-y-auto">
            <div>
              <p className="text-[10px] font-mono uppercase tracking-widest text-white/30">
                On your desktop, run <span className="text-white/50">lancerd pair</span>
              </p>
              <div className="mt-2 border border-orange-400/50 rounded-xl py-3 text-center text-white/70 tracking-[6px] font-mono">
                000000
              </div>
              <p className="text-[10px] text-white/30 text-center mt-2">
                This code expires in a few minutes and works once — don&apos;t share it.
              </p>

              {/* Field-adjacent error — was a generic centered status line
                  elsewhere; now sits directly under the field it explains */}
              <div className="mt-2 rounded-lg bg-red-500/10 border border-red-500/25 px-3 py-2">
                <p className="text-[11px] text-red-400 font-medium">
                  That code&apos;s expired — get a new one from your machine.
                </p>
              </div>
            </div>
          </div>

          {/* Fixed CTA — unchanged copy, now backed by real gating (already
              shipped as a bug fix: warns before finishing unpaired) */}
          <div className="px-6 pb-6 pt-3 border-t border-white/[0.06]">
            <div className="rounded-xl bg-orange-400 text-center py-3.5 text-sm font-semibold text-[#1a1006]">
              Pair &amp; continue
            </div>
          </div>
        </div>
      </PhoneFrame>

      <div className="max-w-[390px] w-full rounded-xl border border-blue-500/25 bg-blue-500/5 px-4 py-3">
        <p className="text-[11px] font-mono uppercase tracking-widest text-blue-400 mb-1">What changes</p>
        <ul className="text-[12px] text-white/60 leading-relaxed list-disc list-inside">
          <li>3 abstract value rows → one real product-preview card (machine + approval + activity)</li>
          <li>Headline copy locked to a single line: &quot;Steer AI coding agents from your phone.&quot;</li>
          <li>Pairing errors move from a generic status line to directly under the code field</li>
          <li>Static image first; a looping recording is an optional later pass (Reduce Motion fallback required)</li>
        </ul>
      </div>
    </div>
  )
}
