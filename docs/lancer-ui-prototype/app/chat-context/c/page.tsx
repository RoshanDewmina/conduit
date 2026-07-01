"use client"

import { useState } from "react"
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_MACHINES, MOCK_WORKSPACES, MOCK_MODELS, CURRENT_SELECTION } from "@/lib/mock-chat-context"

type Segment = "machine" | "workspace" | "model" | null

export default function ChatContextVariantC() {
  const [openSegment, setOpenSegment] = useState<Segment>(null)
  const [machine, setMachine] = useState(CURRENT_SELECTION.machine)
  const [workspace, setWorkspace] = useState(CURRENT_SELECTION.workspace)
  const [model, setModel] = useState(CURRENT_SELECTION.model)

  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2 max-w-md">
        <p className="text-xs text-orange-400 font-mono uppercase tracking-widest mb-1">Variant C</p>
        <h2 className="text-lg font-bold text-white">Breadcrumb context bar</h2>
        <p className="text-xs text-white/40 mt-1">
          A slim always-visible breadcrumb above the composer. Tap any segment to jump straight to
          changing just that level — no need to open a full sheet for a one-thing swap. Try tapping
          each word below.
        </p>
      </div>

      <PhoneFrame label="chat-context/c — breadcrumb bar">
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

          {/* Breadcrumb */}
          <div className="px-5 pt-1 pb-2 flex items-center gap-1 text-[11px] font-mono">
            <Crumb label={machine.name} onClick={() => setOpenSegment("machine")} active={openSegment === "machine"} />
            <span className="text-white/20">/</span>
            <Crumb label={workspace.label} onClick={() => setOpenSegment("workspace")} active={openSegment === "workspace"} />
            <span className="text-white/20">/</span>
            <Crumb label={model.label} onClick={() => setOpenSegment("model")} active={openSegment === "model"} />
          </div>

          {/* Idle landing */}
          <div className="flex-1 flex flex-col items-center justify-center px-8 text-center gap-3">
            <span className="text-2xl">✨</span>
            <h1 className="text-2xl font-bold text-white">New chat</h1>
            <p className="text-[13px] text-white/40 leading-snug max-w-[240px]">
              Describe the work. Lancer routes it through policy before anything runs.
            </p>
          </div>

          {/* Composer — existing pills stay as fallback */}
          <div className="px-4 pb-4">
            <div className="rounded-3xl bg-white/[0.04] border border-white/[0.08] px-4 pt-4 pb-3">
              <p className="text-[14px] text-white/30 mb-4">Message — / for commands, @ for files…</p>
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] text-white/25 font-mono">same pills as today, unchanged ↓</span>
                <div className="flex-1" />
                <div className="w-8 h-8 rounded-full bg-orange-500 flex items-center justify-center shrink-0">
                  <span className="text-white text-xs">↑</span>
                </div>
              </div>
            </div>
          </div>

          {/* Sheet for whichever segment is open */}
          {openSegment && (
            <>
              <div className="absolute inset-0 bg-black/60 z-10" onClick={() => setOpenSegment(null)} />
              <div className="absolute bottom-0 left-0 right-0 bg-[#141020] border-t border-white/10 rounded-t-3xl z-20 max-h-[60%] overflow-y-auto">
                <div className="w-10 h-1 rounded-full bg-white/20 mx-auto mt-3 mb-1" />
                <div className="px-5 pt-3 pb-6 flex flex-col gap-1.5">
                  <p className="text-[10px] font-mono uppercase tracking-widest text-white/30 mb-1">
                    {openSegment === "machine" ? "Machine" : openSegment === "workspace" ? "Workspace" : "Model / harness"}
                  </p>
                  {openSegment === "machine" &&
                    MOCK_MACHINES.map((m) => (
                      <Row key={m.id} selected={m.id === machine.id} onClick={() => { setMachine(m); setOpenSegment(null) }} icon="🖥️" label={m.name} sub={`${m.agentCount} agents`} dim={!m.online} />
                    ))}
                  {openSegment === "workspace" &&
                    MOCK_WORKSPACES.map((w) => (
                      <Row key={w.path} selected={w.path === workspace.path} onClick={() => { setWorkspace(w); setOpenSegment(null) }} icon="📁" label={w.label} sub={w.path} />
                    ))}
                  {openSegment === "model" &&
                    MOCK_MODELS.map((mo) => (
                      <Row key={mo.id} selected={mo.id === model.id} onClick={() => { setModel(mo); setOpenSegment(null) }} icon="🧠" label={mo.label} sub={mo.vendorLabel} />
                    ))}
                </div>
              </div>
            </>
          )}
        </div>
      </PhoneFrame>
    </div>
  )
}

function Crumb({ label, onClick, active }: { label: string; onClick: () => void; active: boolean }) {
  return (
    <button
      onClick={onClick}
      className={`px-1.5 py-0.5 rounded transition-colors ${active ? "bg-orange-500/20 text-orange-400" : "text-white/60 hover:text-white/90"}`}
    >
      {label}
    </button>
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
        selected ? "bg-orange-500/15 border-orange-500/40" : "bg-white/[0.03] border-white/[0.06] hover:bg-white/[0.06]"
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
