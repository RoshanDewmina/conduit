"use client"

import { useState } from "react"
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_MACHINES, MOCK_WORKSPACES, MOCK_MODELS, CURRENT_SELECTION } from "@/lib/mock-chat-context"

export default function ChatContextVariantB() {
  const [open, setOpen] = useState(false)
  const [machine, setMachine] = useState(CURRENT_SELECTION.machine)
  const [workspace, setWorkspace] = useState(CURRENT_SELECTION.workspace)
  const [model, setModel] = useState(CURRENT_SELECTION.model)

  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2 max-w-md">
        <p className="text-xs text-orange-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">One combined sheet</h2>
        <p className="text-xs text-white/40 mt-1">
          One pill in the composer opens a single sheet with Machine → Workspace → Model as three
          sections you pick in sequence — fewer taps to change more than one thing. Tap the pill below,
          it&apos;s live.
        </p>
      </div>

      <PhoneFrame label="chat-context/b — combined sheet">
        <div className="flex flex-col h-full bg-[#0c0a14] relative">
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
          </div>

          {/* Composer */}
          <div className="px-4 pb-4">
            <div className="rounded-3xl bg-white/[0.04] border border-white/[0.08] px-4 pt-4 pb-3">
              <p className="text-[14px] text-white/30 mb-4">Message — / for commands, @ for files…</p>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setOpen(true)}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/[0.06] border border-white/[0.08] hover:bg-white/[0.09] transition-colors"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                  <span className="text-[11px] text-white/70 font-mono truncate max-w-[160px]">
                    {machine.name} · {workspace.label} · {model.label}
                  </span>
                  <span className="text-white/30 text-[10px]">▾</span>
                </button>
                <div className="flex-1" />
                <div className="w-8 h-8 rounded-full bg-orange-500 flex items-center justify-center shrink-0">
                  <span className="text-white text-xs">↑</span>
                </div>
              </div>
            </div>
          </div>

          {/* Sheet */}
          {open && (
            <>
              <div
                className="absolute inset-0 bg-black/60 z-10"
                onClick={() => setOpen(false)}
              />
              <div className="absolute bottom-0 left-0 right-0 bg-[#141020] border-t border-white/10 rounded-t-3xl z-20 max-h-[70%] overflow-y-auto">
                <div className="w-10 h-1 rounded-full bg-white/20 mx-auto mt-3 mb-1" />
                <div className="px-5 pt-3 pb-6 flex flex-col gap-5">
                  <Section title="Machine">
                    {MOCK_MACHINES.map((m) => (
                      <Row
                        key={m.id}
                        selected={m.id === machine.id}
                        onClick={() => setMachine(m)}
                        icon="🖥️"
                        label={m.name}
                        sub={`${m.agentCount} agent${m.agentCount === 1 ? "" : "s"}`}
                        dim={!m.online}
                      />
                    ))}
                  </Section>
                  <Section title="Workspace">
                    {MOCK_WORKSPACES.map((w) => (
                      <Row
                        key={w.path}
                        selected={w.path === workspace.path}
                        onClick={() => setWorkspace(w)}
                        icon="📁"
                        label={w.label}
                        sub={w.path}
                      />
                    ))}
                  </Section>
                  <Section title="Model / harness">
                    {MOCK_MODELS.map((mo) => (
                      <Row
                        key={mo.id}
                        selected={mo.id === model.id}
                        onClick={() => setModel(mo)}
                        icon="🧠"
                        label={mo.label}
                        sub={mo.vendorLabel}
                      />
                    ))}
                  </Section>
                  <button
                    onClick={() => setOpen(false)}
                    className="mt-1 py-3 rounded-2xl bg-orange-500 text-white text-[13px] font-semibold"
                  >
                    Done
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </PhoneFrame>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-[10px] font-mono uppercase tracking-widest text-white/30">{title}</p>
      <div className="flex flex-col gap-1.5">{children}</div>
    </div>
  )
}

function Row({
  selected,
  onClick,
  icon,
  label,
  sub,
  dim,
}: {
  selected: boolean
  onClick: () => void
  icon: string
  label: string
  sub?: string
  dim?: boolean
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-3 px-3 py-2.5 rounded-2xl border text-left transition-colors ${
        selected
          ? "bg-orange-500/15 border-orange-500/40"
          : "bg-white/[0.03] border-white/[0.06] hover:bg-white/[0.06]"
      }`}
    >
      <span className="text-sm">{icon}</span>
      <div className="flex-1 min-w-0">
        <p className={`text-[13px] font-medium truncate ${dim ? "text-white/40" : "text-white/90"}`}>{label}</p>
        {sub && <p className="text-[10px] text-white/30 font-mono truncate">{sub}</p>}
      </div>
      {selected && <span className="text-orange-400 text-xs">✓</span>}
    </button>
  )
}
