import { PhoneFrame } from "@/components/phone-frame"
import { CURRENT_SELECTION } from "@/lib/mock-chat-context"

export default function ChatContextVariantA() {
  const { machine, workspace, model } = CURRENT_SELECTION

  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2 max-w-md">
        <p className="text-xs text-orange-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Promoted pills</h2>
        <p className="text-xs text-white/40 mt-1">
          Same layout as today — Machine / Workspace / Model become three always-visible pills in the
          composer&apos;s control row, each tapping straight into its existing picker sheet. No new screens.
        </p>
      </div>

      <PhoneFrame label="chat-context/a — promoted pills">
        <div className="flex flex-col h-full bg-[#0c0a14]">
          {/* Header */}
          <div className="px-5 pt-2 pb-3 flex items-center justify-between">
            <div className="w-9 h-9 rounded-full bg-white/[0.06] flex items-center justify-center">
              <span className="text-white/60 text-sm">☰</span>
            </div>
            <div className="w-9 h-9 rounded-full bg-orange-500 flex items-center justify-center shadow-lg shadow-orange-500/30">
              <span className="text-white text-lg leading-none">+</span>
            </div>
          </div>

          {/* Idle landing */}
          <div className="flex-1 flex flex-col items-center justify-center px-8 text-center gap-3">
            <span className="text-2xl">✨</span>
            <h1 className="text-2xl font-bold text-white">New chat</h1>
            <p className="text-[13px] text-white/40 leading-snug max-w-[240px]">
              Describe the work. Lancer routes it through policy before anything runs.
            </p>
            <div className="mt-2 text-[11px] font-mono text-white/25 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              resumed from last session
            </div>
          </div>

          {/* Composer */}
          <div className="px-4 pb-4">
            <div className="rounded-3xl bg-white/[0.04] border border-white/[0.08] px-4 pt-4 pb-3">
              <p className="text-[14px] text-white/30 mb-4">Message — / for commands, @ for files…</p>

              <div className="flex items-center gap-1.5 flex-wrap">
                <Pill icon="🖥️" label={machine.name} tone={machine.online ? "ok" : "off"} />
                <Pill icon="📁" label={workspace.label} />
                <Pill icon="🧠" label={`${model.vendorLabel} · ${model.label}`} />
                <div className="flex-1" />
                <div className="w-8 h-8 rounded-full bg-orange-500 flex items-center justify-center shrink-0">
                  <span className="text-white text-xs">↑</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}

function Pill({ icon, label, tone }: { icon: string; label: string; tone?: "ok" | "off" }) {
  return (
    <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-full bg-white/[0.06] border border-white/[0.08] max-w-[120px]">
      {tone && (
        <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${tone === "ok" ? "bg-emerald-400" : "bg-white/20"}`} />
      )}
      <span className="text-[10px] shrink-0">{icon}</span>
      <span className="text-[11px] text-white/70 font-mono truncate">{label}</span>
    </div>
  )
}
