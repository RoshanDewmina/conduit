import { PhoneFrame } from "@/components/phone-frame"

export default function OnboardingCurrent() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-white/40 font-mono uppercase tracking-widest mb-1">Current — shipped</p>
        <h2 className="text-lg font-bold text-white">Onboarding · Value + Pair</h2>
        <p className="text-xs text-white/40 mt-1 max-w-[360px] mx-auto">
          Rough wireframe of what&apos;s live today (see the real screenshot at
          docs/design-audit/screenshots/current/onboarding-valuepair_unified-chrome_iphone-17-pro_dark.png)
        </p>
      </div>

      <PhoneFrame label="onboarding/current — abstract value rows">
        <div className="flex flex-col h-full bg-[#050810]">
          {/* Step dots */}
          <div className="flex justify-end gap-1.5 px-6 pt-2">
            <span className="w-5 h-1.5 rounded-full bg-orange-400" />
            <span className="w-1.5 h-1.5 rounded-full bg-white/15" />
            <span className="w-1.5 h-1.5 rounded-full bg-white/15" />
          </div>

          {/* Hero — terracotta gradient card, abstract kicker/title only */}
          <div
            className="mx-0 px-6 pt-6 pb-8 rounded-b-[28px]"
            style={{ background: "linear-gradient(135deg, #f0a878 0%, #e8946a 100%)" }}
          >
            <div className="w-11 h-11 rounded-xl bg-purple-300/70 border border-white/40 mb-4" />
            <p className="italic text-white/90 text-sm">your machines,</p>
            <h1 className="text-3xl font-bold text-white leading-tight">in your pocket.</h1>
            <p className="text-xs text-white/85 mt-2 leading-snug">
              Lancer is mission control for the coding agents running on your own
              machines. Here&apos;s what you get:
            </p>
          </div>

          {/* Abstract value rows — no real product shown */}
          <div className="flex-1 px-6 pt-5 flex flex-col gap-4 overflow-y-auto">
            {[
              { icon: "✓", title: "Approve actions from afar", sub: "Allow or deny risky steps in a tap" },
              { icon: ">_", title: "Watch the terminal stream live", sub: "Every command, as it runs" },
              { icon: "🛡", title: "Policy guardrails per machine", sub: "Rules apply to every machine" },
            ].map((row) => (
              <div key={row.title} className="flex items-start gap-3">
                <div className="w-9 h-9 shrink-0 rounded-lg bg-white/[0.06] flex items-center justify-center text-orange-300 text-xs">
                  {row.icon}
                </div>
                <div>
                  <p className="text-[13px] font-semibold text-white">{row.title}</p>
                  <p className="text-[11px] text-white/40">{row.sub}</p>
                </div>
              </div>
            ))}

            <div className="mt-2">
              <p className="text-[10px] font-mono uppercase tracking-widest text-white/30">
                On your desktop, run <span className="text-white/50">lancerd pair</span>
              </p>
              <div className="mt-2 border border-orange-400/50 rounded-xl py-3 text-center text-white/70 tracking-[6px] font-mono">
                000000
              </div>
              <p className="text-[10px] text-white/30 text-center mt-2">
                This code expires in a few minutes and works once — don&apos;t share it.
              </p>
            </div>
          </div>

          {/* Fixed CTA — always advances, never checks pairingState */}
          <div className="px-6 pb-6 pt-3 border-t border-white/[0.06]">
            <div className="rounded-xl bg-orange-400 text-center py-3.5 text-sm font-semibold text-[#1a1006]">
              Pair &amp; continue
            </div>
          </div>
        </div>
      </PhoneFrame>

      <div className="max-w-[390px] w-full rounded-xl border border-red-500/25 bg-red-500/5 px-4 py-3">
        <p className="text-[11px] font-mono uppercase tracking-widest text-red-400 mb-1">Issues (fixed as bugs, redesign untouched)</p>
        <ul className="text-[12px] text-white/60 leading-relaxed list-disc list-inside">
          <li>Value rows are abstract — user never sees the real product before trusting it</li>
          <li>CTA advanced unconditionally regardless of pairing state (now fixed: warns first)</li>
        </ul>
      </div>
    </div>
  )
}
