"use client"

import type { ReactNode } from "react"
import { useMemo, useState } from "react"
import {
  AppWindow,
  Bell,
  Bot,
  ChevronLeft,
  ChevronRight,
  ClipboardList,
  Command,
  Download,
  FileDiff,
  FileText,
  Folder,
  GitPullRequest,
  History,
  Inbox,
  Library,
  Mic,
  MoreHorizontal,
  Radio,
  RefreshCw,
  Send,
  Server,
  ShieldCheck,
  Sparkles,
  Terminal,
  Upload,
  Wifi,
  X,
  Zap,
  type LucideIcon,
} from "lucide-react"
import { cn } from "@/lib/utils"
import {
  ACTIVITY_LOG,
  APP_TABS,
  DESIGN_MODES,
  DIFF_LINES,
  FEATURE_MAP,
  FILES,
  HOSTS,
  INITIAL_APPROVALS,
  INITIAL_BLOCKS,
  LIBRARY_CARDS,
  SESSION_SURFACES,
  SETTINGS_GROUPS,
  SNIPPETS,
  type ActivityItem,
  type AppTabID,
  type ApprovalDecision,
  type ApprovalItem,
  type DesignMode,
  type DesignModeID,
  type HostSlot,
  type SessionSurfaceID,
  type TerminalBlock,
} from "@/lib/interactive-data"

type SettingsState = {
  appLock: boolean
  redact: boolean
  push: boolean
  cloudSync: boolean
}

const TONE_CLASS = {
  ok: "bg-[#36c26b] text-[#36c26b]",
  warn: "bg-[#f0a93b] text-[#f0a93b]",
  danger: "bg-[#e0533f] text-[#e0533f]",
  info: "bg-[#2f43ff] text-[#5a68ff]",
  off: "bg-[#34373e] text-[#8a8d96]",
}

const RISK_CLASS = {
  low: "border-[#36c26b]/35 bg-[#36c26b]/10 text-[#36c26b]",
  medium: "border-[#f0a93b]/35 bg-[#f0a93b]/10 text-[#f0a93b]",
  high: "border-[#2f43ff]/45 bg-[#2f43ff]/12 text-[#7d88ff]",
  critical: "border-[#e0533f]/45 bg-[#e0533f]/12 text-[#e0533f]",
}

export default function InteractivePage() {
  const [modeID, setModeID] = useState<DesignModeID>("approval")
  const mode = DESIGN_MODES.find((item) => item.id === modeID) ?? DESIGN_MODES[0]
  const [activeTab, setActiveTab] = useState<AppTabID>(mode.homeTab)
  const [sessionSurface, setSessionSurface] = useState<SessionSurfaceID>("terminal")
  const [approvals, setApprovals] = useState<ApprovalItem[]>(INITIAL_APPROVALS)
  const [terminalBlocks, setTerminalBlocks] = useState<TerminalBlock[]>(INITIAL_BLOCKS)
  const [commandInput, setCommandInput] = useState("")
  const [selectedHostID, setSelectedHostID] = useState("host-1")
  const [hostStatus, setHostStatus] = useState<Record<string, HostSlot["status"]>>({})
  const [decisionID, setDecisionID] = useState<string | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [showLibrary, setShowLibrary] = useState(false)
  const [toast, setToast] = useState("Live prototype ready")
  const [settings, setSettings] = useState({
    appLock: true,
    redact: false,
    push: true,
    cloudSync: true,
  })

  const pendingCount = approvals.filter((approval) => approval.decision === "pending").length
  const hosts = HOSTS.map((host) => ({ ...host, status: hostStatus[host.id] ?? host.status }))
  const selectedHost = hosts.find((host) => host.id === selectedHostID) ?? hosts[0]
  const activeDecision = approvals.find((approval) => approval.id === decisionID) ?? null

  function selectMode(nextModeID: DesignModeID) {
    const nextMode = DESIGN_MODES.find((item) => item.id === nextModeID) ?? DESIGN_MODES[0]
    setModeID(nextModeID)
    setActiveTab(nextMode.homeTab)
    setToast(`${nextMode.name} direction selected`)
  }

  function setTab(tab: AppTabID) {
    setShowLibrary(false)
    setActiveTab(tab)
  }

  function decide(id: string, decision: ApprovalDecision) {
    setApprovals((items) => items.map((item) => (item.id === id ? { ...item, decision } : item)))
    setDecisionID(null)
    setToast(decision === "rejected" ? "Decision rejected" : "Decision approved and relayed")
  }

  function submitCommand() {
    const prompt = commandInput.trim()
    if (!prompt) return
    const nextBlock: TerminalBlock = {
      id: `b-${Date.now()}`,
      prompt,
      output: commandOutput(prompt),
      exit: prompt.includes("fail") ? 1 : 0,
      duration: prompt.includes("test") ? "18.6s" : "0.42s",
    }
    setTerminalBlocks((blocks) => [...blocks, nextBlock])
    setCommandInput("")
    setToast("Command sent to the active PTY")
  }

  function connectHost(id: string) {
    setHostStatus((items) => ({ ...items, [id]: "connected" }))
    setSelectedHostID(id)
    setActiveTab("session")
    setToast("Host connected and session opened")
  }

  function openSession(hostID: string, surface: SessionSurfaceID = "terminal") {
    setSelectedHostID(hostID)
    setSessionSurface(surface)
    setActiveTab("session")
  }

  function approveFromWatch() {
    const next = approvals.find((approval) => approval.decision === "pending")
    if (next) {
      decide(next.id, "approved")
      setToast("Approved from Apple Watch")
    }
  }

  function decideFromWatch(decision: Extract<ApprovalDecision, "approved" | "rejected">) {
    const next = approvals.find((approval) => approval.decision === "pending")
    if (next) {
      decide(next.id, decision)
      setToast(decision === "rejected" ? "Rejected from Apple Watch" : "Approved from Apple Watch")
    }
  }

  const screen = showLibrary ? (
    <LibraryScreen onBack={() => setShowLibrary(false)} />
  ) : (
    <ScreenRouter
      mode={mode}
      activeTab={activeTab}
      approvals={approvals}
      hosts={hosts}
      selectedHost={selectedHost}
      terminalBlocks={terminalBlocks}
      commandInput={commandInput}
      sessionSurface={sessionSurface}
      settings={settings}
      onSetCommandInput={setCommandInput}
      onSubmitCommand={submitCommand}
      onSetSurface={setSessionSurface}
      onSetTab={setTab}
      onSetDecision={setDecisionID}
      onDecide={decide}
      onConnectHost={connectHost}
      onOpenSession={openSession}
      onOpenLibrary={() => setShowLibrary(true)}
      onToggleSetting={(key) => setSettings((current) => ({ ...current, [key]: !current[key] }))}
    />
  )

  return (
    <main className="min-h-screen overflow-x-hidden bg-[#050810] text-[#e9e9e2]">
      <div className="mx-auto flex min-h-screen max-w-[1120px] flex-col px-5 py-5 max-[560px]:px-3">
        <ReviewHeader
          mode={mode}
          activeTab={activeTab}
          pendingCount={pendingCount}
          onModeChange={selectMode}
          onOpenOnboarding={() => setShowOnboarding(true)}
        />

        <div className="grid flex-1 grid-cols-[minmax(390px,1fr)_300px] gap-6 py-5 max-[980px]:grid-cols-1">
          <section className="sticky top-5 flex h-[calc(100vh-116px)] min-h-[560px] items-center justify-center self-start max-[980px]:static max-[980px]:h-auto max-[980px]:min-h-0">
            <PhoneShell
              mode={mode}
              activeTab={activeTab}
              pendingCount={pendingCount}
              toast={toast}
              onSetTab={setTab}
            >
              {screen}
              {activeDecision && (
                <DecisionSheet
                  approval={activeDecision}
                  onClose={() => setDecisionID(null)}
                  onDecide={decide}
                />
              )}
              {showOnboarding && <OnboardingOverlay onClose={() => setShowOnboarding(false)} />}
            </PhoneShell>
          </section>

          <ActionDock
            mode={mode}
            activeTab={activeTab}
            selectedHost={selectedHost}
            pendingCount={pendingCount}
            approvals={approvals}
            onWatchApprove={approveFromWatch}
            onWatchDecision={decideFromWatch}
            onOpenSession={() => openSession(selectedHost.id)}
            onSetTab={setTab}
          />
        </div>
      </div>
    </main>
  )
}

function ScreenRouter(props: {
  mode: DesignMode
  activeTab: AppTabID
  approvals: ApprovalItem[]
  hosts: HostSlot[]
  selectedHost: HostSlot
  terminalBlocks: TerminalBlock[]
  commandInput: string
  sessionSurface: SessionSurfaceID
  settings: SettingsState
  onSetCommandInput: (value: string) => void
  onSubmitCommand: () => void
  onSetSurface: (surface: SessionSurfaceID) => void
  onSetTab: (tab: AppTabID) => void
  onSetDecision: (id: string) => void
  onDecide: (id: string, decision: ApprovalDecision) => void
  onConnectHost: (id: string) => void
  onOpenSession: (hostID: string, surface?: SessionSurfaceID) => void
  onOpenLibrary: () => void
  onToggleSetting: (key: keyof SettingsState) => void
}) {
  switch (props.activeTab) {
    case "inbox":
      return (
        <InboxScreen
          mode={props.mode}
          approvals={props.approvals}
          onSetDecision={props.onSetDecision}
          onDecide={props.onDecide}
          onViewDiff={() => {
            props.onSetSurface("diff")
            props.onSetTab("session")
          }}
        />
      )
    case "fleet":
      return (
        <FleetScreen
          mode={props.mode}
          hosts={props.hosts}
          onConnectHost={props.onConnectHost}
          onOpenSession={props.onOpenSession}
        />
      )
    case "session":
      return (
        <SessionScreen
          mode={props.mode}
          selectedHost={props.selectedHost}
          approvals={props.approvals}
          terminalBlocks={props.terminalBlocks}
          commandInput={props.commandInput}
          sessionSurface={props.sessionSurface}
          onSetCommandInput={props.onSetCommandInput}
          onSubmitCommand={props.onSubmitCommand}
          onSetSurface={props.onSetSurface}
          onSetDecision={props.onSetDecision}
          onDecide={props.onDecide}
        />
      )
    case "activity":
      return <ActivityScreen />
    case "settings":
      return (
        <SettingsScreen
          settings={props.settings}
          onToggleSetting={props.onToggleSetting}
          onOpenLibrary={props.onOpenLibrary}
        />
      )
  }
}

function ReviewHeader(props: {
  mode: DesignMode
  activeTab: AppTabID
  pendingCount: number
  onModeChange: (mode: DesignModeID) => void
  onOpenOnboarding: () => void
}) {
  return (
    <header className="border border-white/[0.08] bg-[#0a0b0d]/95 px-4 py-3">
      <div className="flex flex-wrap items-center gap-3">
        <div className="mr-auto min-w-[190px]">
          <p className="font-mono text-[10px] uppercase tracking-[0.26em] text-[#5a68ff]">Conduit</p>
          <h1 className="mt-1 text-[22px] font-black leading-none tracking-[-0.02em] text-white">Interactive Prototype</h1>
          <p className="mt-1 font-mono text-[11px] text-[#565963]">
            {APP_TABS[props.activeTab].label} · {props.pendingCount} pending
          </p>
        </div>

        <div className="flex min-w-[320px] flex-1 gap-1 border border-white/[0.08] bg-white/[0.025] p-1 max-[560px]:min-w-0">
          {DESIGN_MODES.map((mode) => (
            <button
              type="button"
              key={mode.id}
              data-testid={`mode-${mode.id}`}
              onClick={() => props.onModeChange(mode.id)}
              title={mode.premise}
              className={cn(
                "min-w-0 flex-1 border px-3 py-2 text-left transition",
                props.mode.id === mode.id
                  ? "border-[#2f43ff]/60 bg-[#2f43ff]/14 text-white"
                  : "border-transparent text-[#8a8d96] hover:border-white/[0.08] hover:bg-white/[0.03]"
              )}
            >
              <span className="block truncate font-mono text-[10px] font-bold uppercase tracking-[0.13em]">{mode.name}</span>
              <span className="mt-2 block h-1.5 w-full" style={{ background: props.mode.id === mode.id ? mode.accent : "#23262d" }} />
            </button>
          ))}
        </div>

        <button
          type="button"
          onClick={props.onOpenOnboarding}
          className="flex h-[54px] items-center justify-center gap-2 border border-white/[0.1] bg-white/[0.03] px-4 font-mono text-[10px] uppercase tracking-[0.14em] text-[#e9e9e2] hover:border-[#2f43ff]/50 max-[560px]:h-11 max-[560px]:w-full"
        >
          <Sparkles className="size-3.5 text-[#2f43ff]" />
          Onboarding
        </button>
      </div>
    </header>
  )
}

function PhoneShell(props: {
  mode: DesignMode
  activeTab: AppTabID
  pendingCount: number
  toast: string
  onSetTab: (tab: AppTabID) => void
  children: ReactNode
}) {
  return (
    <div className="interactive-phone-frame relative h-[844px] w-[390px] overflow-hidden border border-white/[0.14] bg-[#0a0b0d] shadow-[0_50px_120px_rgba(0,0,0,0.65)] max-[520px]:scale-[0.88]">
      <div className="absolute inset-x-0 top-0 z-30 h-[52px] bg-[#0a0b0d]">
        <div className="flex items-center justify-between px-9 pt-4 font-mono text-[12px] text-white">
          <span>9:41</span>
          <div className="flex items-center gap-2">
            <SignalBars />
            <Wifi className="size-4" />
            <div className="flex h-4 w-8 items-center border border-[#36c26b] px-0.5">
              <div className="h-2.5 flex-1 bg-[#36c26b]" />
            </div>
          </div>
        </div>
      </div>
      <div className="absolute left-1/2 top-0 z-40 h-[34px] w-[122px] -translate-x-1/2 rounded-b-[20px] bg-black" />

      <div className="absolute inset-x-0 top-[52px] z-20 border-b border-white/[0.08] bg-[#101320]">
        <button
          type="button"
          onClick={() => props.onSetTab("session")}
          className="flex w-full items-center gap-3 px-4 py-2.5 text-left"
        >
          <PixelGlyph seed={props.mode.shortName} size={36} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="font-mono text-[13px] text-[#8a8d96]">
                {props.pendingCount > 0 ? `${props.pendingCount} pending approvals` : "all sessions clear"}
              </span>
              <StatusLight tone={props.pendingCount > 0 ? "warn" : "ok"} pulse={props.pendingCount > 0} />
            </div>
            <p className="truncate font-mono text-[10px] text-[#565963]">{props.toast}</p>
          </div>
          <ChevronRight className="size-4 text-[#8a8d96]" />
        </button>
      </div>

      <div className="absolute inset-x-0 bottom-[76px] top-[104px] overflow-hidden">{props.children}</div>

      <nav className="absolute inset-x-0 bottom-0 z-30 grid h-[76px] border-t border-white/[0.08] bg-[#111317]/95 backdrop-blur">
        <div
          className="grid h-full"
          style={{ gridTemplateColumns: `repeat(${props.mode.tabOrder.length}, minmax(0, 1fr))` }}
        >
          {props.mode.tabOrder.map((id) => {
            const item = APP_TABS[id]
            const Icon = item.icon
            const active = props.activeTab === id
            return (
              <button
                type="button"
                key={id}
                data-testid={`tab-${id}`}
                onClick={() => props.onSetTab(id)}
                className={cn(
                  "relative flex flex-col items-center justify-center gap-1 font-mono text-[10px] uppercase tracking-[0.12em]",
                  active ? "text-[#2f43ff]" : "text-[#565963]"
                )}
              >
                {active && <span className="absolute top-0 h-[3px] w-8 bg-[#2f43ff]" />}
                <Icon className="size-[20px]" strokeWidth={2.1} />
                <span>{item.label}</span>
              </button>
            )
          })}
        </div>
      </nav>
    </div>
  )
}

function InboxScreen(props: {
  mode: DesignMode
  approvals: ApprovalItem[]
  onSetDecision: (id: string) => void
  onDecide: (id: string, decision: ApprovalDecision) => void
  onViewDiff: () => void
}) {
  const pending = props.approvals.filter((item) => item.decision === "pending")
  const decided = props.approvals.filter((item) => item.decision !== "pending")
  return (
    <ScreenFrame>
      <ScreenHeader
        title="inbox"
        breadcrumb={props.mode.id === "session" ? "active workspace approvals" : "agent approvals"}
        count={pending.length ? `${pending.length} pending` : "clear"}
      />

      {props.mode.id === "approval" && (
        <div className="mx-4 mt-4 border border-[#2f43ff]/25 bg-[#2f43ff]/10 p-3">
          <div className="flex items-center justify-between">
            <span className="font-mono text-[11px] uppercase tracking-[0.16em] text-[#7d88ff]">decision queue</span>
            <Bell className="size-4 text-[#7d88ff]" />
          </div>
          <p className="mt-2 text-[13px] leading-relaxed text-[#d6d3cc]">
            High-risk actions pause here first. Approve, edit, or deny without leaving the active run.
          </p>
        </div>
      )}

      <div className="mt-4 flex-1 overflow-y-auto pb-4">
        {pending.length > 0 && <SectionHead label="pending" count={pending.length} />}
        <div className="space-y-3 px-4">
          {pending.map((approval) => (
            <ApprovalCard
              key={approval.id}
              approval={approval}
              compact={props.mode.id === "fleet"}
              onOpen={() => props.onSetDecision(approval.id)}
              onDecide={props.onDecide}
              onViewDiff={props.onViewDiff}
            />
          ))}
        </div>

        {decided.length > 0 && <SectionHead label="decided" count={decided.length} className="mt-5" />}
        <div className="px-4">
          {decided.map((approval) => (
            <button
              type="button"
              key={approval.id}
              onClick={() => props.onSetDecision(approval.id)}
              className="flex w-full items-center gap-3 border-b border-white/[0.06] py-3 text-left"
            >
              <AgentBadge approval={approval} label={false} />
              <div className="min-w-0 flex-1">
                <p className="truncate font-mono text-[13px] text-[#e9e9e2]">{approval.command}</p>
                <p className="truncate font-mono text-[11px] text-[#565963]">{approval.cwd}</p>
              </div>
              <DecisionPill decision={approval.decision} />
            </button>
          ))}
        </div>
      </div>
    </ScreenFrame>
  )
}

function ApprovalCard(props: {
  approval: ApprovalItem
  compact?: boolean
  onOpen: () => void
  onDecide: (id: string, decision: ApprovalDecision) => void
  onViewDiff: () => void
}) {
  const approval = props.approval
  return (
    <article className="border border-[#23262d] bg-[#0e0f12]">
      <button type="button" onClick={props.onOpen} className="w-full p-3 text-left">
        <div className="flex items-center gap-2">
          <AgentBadge approval={approval} />
          <RiskPill risk={approval.risk} />
          <span className="ml-auto font-mono text-[11px] text-[#565963]">{approval.time}</span>
        </div>
        <p className="mt-3 text-[15px] font-bold leading-tight text-[#e9e9e2]">{approval.title}</p>
        <div className="mt-2 flex items-center gap-2 font-mono text-[11px] text-[#565963]">
          <Server className="size-3.5" />
          <span className="truncate">{approval.cwd}</span>
        </div>
        <CommandBlock command={approval.command} tone={approval.risk} />
        {!props.compact && (
          <div className="mt-3 flex flex-wrap gap-1.5">
            {approval.blastRadius.map((item) => (
              <span key={item} className="border border-white/[0.08] bg-white/[0.03] px-2 py-1 font-mono text-[10px] text-[#8a8d96]">
                {item}
              </span>
            ))}
          </div>
        )}
      </button>

      <div className="flex flex-wrap gap-2 border-t border-white/[0.06] p-3">
        {approval.kind === "patch" && (
          <RectButton tone="info" onClick={props.onViewDiff}>
            View diff
          </RectButton>
        )}
        <RectButton tone="muted" onClick={props.onOpen}>
          Edit & run
        </RectButton>
        <RectButton tone="danger" onClick={() => props.onDecide(approval.id, "rejected")}>
          Deny
        </RectButton>
        <RectButton tone="muted" onClick={() => props.onDecide(approval.id, "approvedAlways")}>
          Always
        </RectButton>
        <RectButton tone="primary" testId={`approve-${approval.id}`} onClick={() => props.onDecide(approval.id, "approved")}>
          Approve
        </RectButton>
      </div>
    </article>
  )
}

function FleetScreen(props: {
  mode: DesignMode
  hosts: HostSlot[]
  onConnectHost: (id: string) => void
  onOpenSession: (id: string, surface?: SessionSurfaceID) => void
}) {
  const connected = props.hosts.filter((host) => host.status === "connected")
  const activeAgents = props.hosts.flatMap((host) => host.agents).filter((agent) => agent.state !== "offline")
  return (
    <ScreenFrame>
      <ScreenHeader
        title="fleet"
        breadcrumb={props.mode.id === "fleet" ? "control room" : "agents & spend"}
        count={`${props.hosts.length} hosts`}
      />

      <div className="mx-4 mt-4 grid grid-cols-3 border border-[#23262d] bg-[#0e0f12]">
        <FleetMetric value={`${activeAgents.length}`} label="vendors" />
        <FleetMetric value={`${connected.length}`} label="sessions" />
        <FleetMetric value="$2.40" label="today" />
      </div>

      {props.mode.id === "fleet" && (
        <div className="mx-4 mt-3 border border-[#36c26b]/25 bg-[#36c26b]/10 p-3">
          <div className="flex items-center gap-2">
            <Radio className="size-4 text-[#36c26b]" />
            <span className="font-mono text-[11px] uppercase tracking-[0.16em] text-[#36c26b]">bridge health</span>
          </div>
          <div className="mt-3 grid grid-cols-4 gap-1">
            {["push", "watch", "conduitd", "tmux"].map((item, index) => (
              <span key={item} className={cn("h-2", index === 2 ? "bg-[#f0a93b]" : "bg-[#36c26b]")} />
            ))}
          </div>
        </div>
      )}

      <div className="mt-4 flex-1 overflow-y-auto pb-4">
        <SectionHead label="live hosts" count={props.hosts.filter((host) => host.status !== "saved").length} />
        <div className="space-y-3 px-4">
          {props.hosts.map((host) => (
            <HostCard
              key={host.id}
              host={host}
              onConnect={() => props.onConnectHost(host.id)}
              onOpenSession={(surface) => props.onOpenSession(host.id, surface)}
            />
          ))}
        </div>
      </div>
    </ScreenFrame>
  )
}

function HostCard(props: {
  host: HostSlot
  onConnect: () => void
  onOpenSession: (surface?: SessionSurfaceID) => void
}) {
  const tone = props.host.status === "connected" ? "ok" : props.host.status === "reconnecting" ? "warn" : "off"
  return (
    <article className="border border-[#23262d] bg-[#0e0f12] p-3">
      <div className="flex items-center gap-3">
        <PixelGlyph seed={props.host.name} size={44} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-[15px] font-bold text-[#e9e9e2]">{props.host.name}</h3>
            <StatusLight tone={tone} pulse={props.host.status === "reconnecting"} />
          </div>
          <p className="truncate font-mono text-[11px] text-[#565963]">{props.host.address}</p>
        </div>
        <button
          type="button"
          onClick={props.host.status === "saved" ? props.onConnect : () => props.onOpenSession()}
          className="grid size-9 place-items-center border border-white/[0.08] text-[#2f43ff]"
          aria-label={props.host.status === "saved" ? "Connect host" : "Open session"}
        >
          {props.host.status === "saved" ? <RefreshCw className="size-4" /> : <Terminal className="size-4" />}
        </button>
      </div>

      {props.host.agents.length > 0 && (
        <div className="mt-3 space-y-2 border-t border-white/[0.06] pt-3">
          {props.host.agents.map((agent) => (
            <div key={agent.name} className="flex items-center gap-2">
              <StatusLight
                tone={agent.state === "needs-you" ? "warn" : agent.state === "running" ? "ok" : agent.state === "idle" ? "info" : "off"}
                pulse={agent.state === "running" || agent.state === "needs-you"}
              />
              <span className="font-mono text-[12px] text-[#d6d3cc]">{agent.name}</span>
              <span className="truncate font-mono text-[10px] text-[#565963]">{agent.model}</span>
              <span className="ml-auto font-mono text-[11px] text-[#8a8d96]">{agent.spend}</span>
            </div>
          ))}
        </div>
      )}

      {props.host.status !== "saved" && (
        <div className="mt-3 grid grid-cols-3 gap-2">
          <TinyButton icon={Terminal} label="shell" onClick={() => props.onOpenSession("terminal")} />
          <TinyButton icon={AppWindow} label="preview" onClick={() => props.onOpenSession("preview")} />
          <TinyButton icon={FileDiff} label="diff" onClick={() => props.onOpenSession("diff")} />
        </div>
      )}
    </article>
  )
}

function SessionScreen(props: {
  mode: DesignMode
  selectedHost: HostSlot
  approvals: ApprovalItem[]
  terminalBlocks: TerminalBlock[]
  commandInput: string
  sessionSurface: SessionSurfaceID
  onSetCommandInput: (value: string) => void
  onSubmitCommand: () => void
  onSetSurface: (surface: SessionSurfaceID) => void
  onSetDecision: (id: string) => void
  onDecide: (id: string, decision: ApprovalDecision) => void
}) {
  return (
    <ScreenFrame className="bg-[#08090c]">
      <div className="border-b border-[#23262d] bg-[#111317] px-4 py-3">
        <div className="flex items-center gap-3">
          <button type="button" className="grid size-10 place-items-center border border-[#2f343c] text-[#8a8d96]">
            <ChevronLeft className="size-5" />
          </button>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h2 className="truncate font-mono text-[15px] font-bold text-[#e9e9e2]">{props.selectedHost.name}</h2>
              <span className="border border-[#36c26b]/25 bg-[#36c26b]/10 px-2 py-1 font-mono text-[11px] text-[#36c26b]">
                Done
              </span>
            </div>
            <p className="truncate font-mono text-[12px] text-[#565963]">
              <span className="text-[#2f43ff]">$</span> {props.selectedHost.cwd}
            </p>
          </div>
          <button type="button" className="grid size-10 place-items-center text-[#8a8d96]" aria-label="More">
            <MoreHorizontal className="size-5" />
          </button>
        </div>
      </div>

      <div className="flex items-center gap-1 overflow-x-auto border-b border-[#23262d] bg-[#0e0f12] px-2 py-2">
        {SESSION_SURFACES.map((surface) => {
          const Icon = surface.icon
          const active = props.sessionSurface === surface.id
          return (
            <button
              type="button"
              key={surface.id}
              data-testid={`surface-${surface.id}`}
              onClick={() => props.onSetSurface(surface.id)}
              className={cn(
                "flex shrink-0 items-center gap-1.5 border px-2.5 py-1.5 font-mono text-[10px] uppercase tracking-[0.08em]",
                active
                  ? "border-[#2f43ff]/55 bg-[#2f43ff]/15 text-[#7d88ff]"
                  : "border-white/[0.06] bg-white/[0.02] text-[#8a8d96]"
              )}
            >
              <Icon className="size-3.5" />
              {surface.label}
            </button>
          )
        })}
      </div>

      <div className="min-h-0 flex-1 overflow-hidden">
        {props.sessionSurface === "terminal" && (
          <TerminalSurface
            blocks={props.terminalBlocks}
            value={props.commandInput}
            onChange={props.onSetCommandInput}
            onSubmit={props.onSubmitCommand}
          />
        )}
        {props.sessionSurface === "preview" && <PreviewSurface />}
        {props.sessionSurface === "files" && <FilesSurface />}
        {props.sessionSurface === "diff" && <DiffSurface />}
        {props.sessionSurface === "session-inbox" && (
          <div className="h-full overflow-y-auto p-4">
            <div className="space-y-3">
              {props.approvals
                .filter((item) => item.decision === "pending")
                .map((approval) => (
                  <ApprovalCard
                    key={approval.id}
                    approval={approval}
                    compact={props.mode.id === "session"}
                    onOpen={() => props.onSetDecision(approval.id)}
                    onDecide={props.onDecide}
                    onViewDiff={() => props.onSetSurface("diff")}
                  />
                ))}
            </div>
          </div>
        )}
      </div>
    </ScreenFrame>
  )
}

function TerminalSurface(props: {
  blocks: TerminalBlock[]
  value: string
  onChange: (value: string) => void
  onSubmit: () => void
}) {
  return (
    <div className="flex h-full flex-col bg-[#08090c]">
      <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3">
        {props.blocks.map((block) => (
          <article
            key={block.id}
            className={cn(
              "mb-3 border bg-[#101217]",
              block.exit === 1 ? "border-[#e0533f]/65" : "border-[#2f343c]"
            )}
          >
            <div className="flex items-center gap-2 border-b border-[#2f343c] bg-[#15171c] px-3 py-2">
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-[#8a8d96]">run</span>
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-[#565963]">command</span>
              <span className="ml-auto font-mono text-[11px] text-[#565963]">{block.duration}</span>
              <span
                className={cn(
                  "px-2 py-1 font-mono text-[11px]",
                  block.exit === 0 ? "bg-[#36c26b]/12 text-[#36c26b]" : "bg-[#e0533f]/12 text-[#e0533f]"
                )}
              >
                exit {block.exit ?? "…"}
              </span>
            </div>
            <div className="p-3 font-mono text-[15px] leading-relaxed">
              <p>
                <span className="text-[#2f43ff]">roshansilva@127.0.0.1</span>
                <span className="text-[#565963]">:/command-center $ </span>
                <span className="text-[#e9e9e2]">{block.prompt}</span>
              </p>
              {block.output.map((line) => (
                <p key={line} className={line.includes("PASS") || line.includes("passed") ? "text-[#36c26b]" : "text-[#55b7ff]"}>
                  {line}
                </p>
              ))}
            </div>
          </article>
        ))}
      </div>

      <div className="border-t border-[#23262d] bg-[#0e0f12]">
        <div className="flex gap-2 overflow-x-auto px-3 py-2">
          {["Esc", "Tab", "Ctrl", "Tmux", "↑", "↓", "←", "→"].map((key) => (
            <button
              type="button"
              key={key}
              className="min-w-14 border border-[#2f343c] bg-[#15171c] px-3 py-3 font-mono text-[14px] text-[#d6d3cc]"
            >
              {key}
            </button>
          ))}
          <button type="button" className="ml-auto grid min-w-12 place-items-center text-[#565963]" aria-label="History">
            <History className="size-6" />
          </button>
        </div>
        <div className="flex items-center gap-2 px-3 pb-3">
          <div className="flex min-w-0 flex-1 items-center gap-2 border border-white/[0.06] bg-[#15171c] px-3 py-3">
            <span className="font-mono text-[#565963]">$</span>
            <input
              value={props.value}
              onChange={(event) => props.onChange(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") props.onSubmit()
              }}
              placeholder="command"
              className="min-w-0 flex-1 bg-transparent font-mono text-[15px] text-[#e9e9e2] outline-none placeholder:text-[#34373e]"
            />
          </div>
          <button type="button" className="grid size-11 place-items-center text-[#565963]" aria-label="Dictate">
            <Mic className="size-5" />
          </button>
          <button
            type="button"
            onClick={props.onSubmit}
            className="grid size-11 place-items-center bg-[#2f43ff] text-white"
            aria-label="Send command"
          >
            <Send className="size-5" />
          </button>
        </div>
      </div>
    </div>
  )
}

function PreviewSurface() {
  const [viewport, setViewport] = useState<"mobile" | "desktop">("mobile")
  return (
    <div className="flex h-full flex-col bg-[#f4f4f2] text-[#14161b]">
      <div className="flex items-center gap-2 border-b border-[#d2d4d0] bg-white px-3 py-2">
        <button type="button" className="border border-[#d2d4d0] px-2 py-1 font-mono text-[11px]">
          :3000
        </button>
        <button type="button" className="border border-[#d2d4d0] px-2 py-1 font-mono text-[11px]">
          Detect
        </button>
        <div className="ml-auto flex border border-[#d2d4d0]">
          {(["mobile", "desktop"] as const).map((item) => (
            <button
              type="button"
              key={item}
              onClick={() => setViewport(item)}
              className={cn(
                "px-2 py-1 font-mono text-[10px] uppercase",
                viewport === item ? "bg-[#2f43ff] text-white" : "text-[#4a4d55]"
              )}
            >
              {item}
            </button>
          ))}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-[#eceef0] p-4">
        <div className={cn("mx-auto min-h-[560px] bg-white shadow-sm", viewport === "mobile" ? "w-[240px]" : "w-[560px]")}>
          <div className="h-40 bg-[#0a0b0d] p-5 text-white">
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-[#5a68ff]">Preview</p>
            <h3 className="mt-3 text-xl font-black">Remote app is live</h3>
            <p className="mt-2 text-sm text-white/55">SSH proxy, hot reload, and WebSocket checks are passing.</p>
          </div>
          <div className="grid grid-cols-2 gap-3 p-4">
            {["Auth flow", "API health", "Visual QA", "Deploy gate"].map((item) => (
              <div key={item} className="border border-[#e2e3e0] p-3">
                <p className="text-sm font-bold">{item}</p>
                <p className="mt-1 text-xs text-[#80838c]">Ready for review</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

function FilesSurface() {
  const [selected, setSelected] = useState("ARCHITECTURE.md")
  return (
    <div className="grid h-full grid-rows-[auto_1fr] bg-[#0a0b0d]">
      <div className="flex items-center gap-2 border-b border-[#23262d] px-3 py-2">
        <Folder className="size-4 text-[#2f43ff]" />
        <span className="truncate font-mono text-[12px] text-[#8a8d96]">/Users/roshan/command-center</span>
        <button type="button" className="ml-auto grid size-8 place-items-center border border-[#2f343c]" aria-label="Upload">
          <Upload className="size-4" />
        </button>
      </div>
      <div className="min-h-0 overflow-y-auto">
        {FILES.map((file) => (
          <button
            type="button"
            key={file.name}
            onClick={() => setSelected(file.name)}
            className={cn(
              "flex w-full items-center gap-3 border-b border-white/[0.05] px-4 py-3 text-left",
              selected === file.name && "bg-[#2f43ff]/10"
            )}
          >
            {file.kind === "dir" ? <Folder className="size-4 text-[#2f43ff]" /> : <FileText className="size-4 text-[#8a8d96]" />}
            <div className="min-w-0 flex-1">
              <p className="truncate font-mono text-[13px] text-[#e9e9e2]">{file.name}</p>
              <p className="font-mono text-[10px] text-[#565963]">{file.size} · {file.touched}</p>
            </div>
            <Download className="size-4 text-[#565963]" />
          </button>
        ))}
      </div>
    </div>
  )
}

function DiffSurface() {
  return (
    <div className="flex h-full flex-col bg-[#0a0b0d]">
      <div className="border-b border-[#23262d] p-3">
        <div className="flex items-center gap-2">
          <GitPullRequest className="size-4 text-[#36c26b]" />
          <span className="font-mono text-[12px] text-[#d6d3cc]">fix/auth-token-refresh</span>
          <span className="ml-auto font-mono text-[11px] text-[#36c26b]">+11</span>
          <span className="font-mono text-[11px] text-[#e0533f]">-4</span>
        </div>
        <p className="mt-2 text-[12px] leading-relaxed text-[#8a8d96]">
          Mutexes the token refresh path and records audit evidence for the agent run.
        </p>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto font-mono text-[12px]">
        {DIFF_LINES.map((line, index) => (
          <div
            key={`${line.text}-${index}`}
            className={cn(
              "flex gap-2 px-3 py-1",
              line.kind === "add" && "bg-[#36c26b]/10 text-[#36c26b]",
              line.kind === "del" && "bg-[#e0533f]/10 text-[#e0533f]",
              line.kind === "meta" && "text-[#5a68ff]",
              line.kind === "hunk" && "bg-white/[0.03] text-[#8a8d96]",
              line.kind === "ctx" && "text-[#8a8d96]"
            )}
          >
            <span className="w-6 text-right text-[#565963]">{index + 1}</span>
            <span className="whitespace-pre-wrap">{line.text}</span>
          </div>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-2 border-t border-[#23262d] p-3">
        <RectButton tone="danger">Reject hunk</RectButton>
        <RectButton tone="primary">Approve patch</RectButton>
      </div>
    </div>
  )
}

function ActivityScreen() {
  const [filter, setFilter] = useState<ActivityItem["type"] | "all">("all")
  const visible = filter === "all" ? ACTIVITY_LOG : ACTIVITY_LOG.filter((item) => item.type === filter)
  return (
    <ScreenFrame>
      <ScreenHeader title="activity" breadcrumb="audit & replay" count={`${visible.length} events`} />
      <div className="mx-4 mt-4 flex gap-2 overflow-x-auto">
        {(["all", "approval", "connect", "test", "preview", "security"] as const).map((item) => (
          <button
            type="button"
            key={item}
            onClick={() => setFilter(item)}
            className={cn(
              "border px-3 py-2 font-mono text-[10px] uppercase tracking-[0.12em]",
              filter === item ? "border-[#2f43ff]/60 bg-[#2f43ff]/15 text-[#7d88ff]" : "border-white/[0.08] text-[#8a8d96]"
            )}
          >
            {item}
          </button>
        ))}
      </div>
      <div className="mt-4 flex-1 overflow-y-auto px-4 pb-4">
        <div className="border border-[#23262d] bg-[#0e0f12]">
          {visible.map((item) => (
            <div key={item.id} className="flex gap-3 border-b border-white/[0.06] p-3 last:border-b-0">
              <StatusLight tone={item.tone} pulse={item.tone === "warn"} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <p className="truncate font-mono text-[13px] text-[#e9e9e2]">{item.title}</p>
                  <span className="ml-auto font-mono text-[10px] text-[#565963]">{item.time}</span>
                </div>
                <p className="mt-1 text-[12px] leading-relaxed text-[#8a8d96]">{item.detail}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </ScreenFrame>
  )
}

function SettingsScreen(props: {
  settings: SettingsState
  onToggleSetting: (key: keyof SettingsState) => void
  onOpenLibrary: () => void
}) {
  return (
    <ScreenFrame>
      <ScreenHeader
        title="settings"
        breadcrumb="device & agent"
        action={<IconButton icon={LibraryIcon} label="Open library" onClick={props.onOpenLibrary} />}
      />
      <div className="flex-1 overflow-y-auto px-4 pb-4">
        <SectionHead label="library" count={LIBRARY_CARDS.length} />
        <div className="grid grid-cols-2 gap-2">
          {LIBRARY_CARDS.map((card) => {
            const Icon = card.icon
            return (
              <button
                type="button"
                key={card.label}
                onClick={props.onOpenLibrary}
                className="border border-[#23262d] bg-[#0e0f12] p-3 text-left"
              >
                <Icon className="size-4 text-[#2f43ff]" />
                <p className="mt-3 font-mono text-[17px] text-[#e9e9e2]">{card.count}</p>
                <p className="font-mono text-[11px] text-[#d6d3cc]">{card.label}</p>
                <p className="mt-1 text-[10px] leading-tight text-[#565963]">{card.detail}</p>
              </button>
            )
          })}
        </div>

        <SectionHead label="controls" className="mt-5" />
        <div className="border border-[#23262d] bg-[#0e0f12]">
          <ToggleRow label="Face ID app lock" active={props.settings.appLock} onToggle={() => props.onToggleSetting("appLock")} />
          <ToggleRow label="Redact saved output" active={props.settings.redact} onToggle={() => props.onToggleSetting("redact")} />
          <ToggleRow label="Push approvals" active={props.settings.push} onToggle={() => props.onToggleSetting("push")} />
          <ToggleRow label="iCloud sync" active={props.settings.cloudSync} onToggle={() => props.onToggleSetting("cloudSync")} />
        </div>

        <SectionHead label="policy" className="mt-5" />
        <div className="space-y-2">
          {SETTINGS_GROUPS.map((group) => {
            const Icon = group.icon
            return (
              <div key={group.label} className="border border-[#23262d] bg-[#0e0f12] p-3">
                <div className="flex items-center gap-2">
                  <Icon className="size-4 text-[#8a8d96]" />
                  <span className="font-mono text-[13px] text-[#e9e9e2]">{group.label}</span>
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {group.items.map((item) => (
                    <span key={item} className="border border-white/[0.08] bg-white/[0.03] px-2 py-1 font-mono text-[10px] text-[#8a8d96]">
                      {item}
                    </span>
                  ))}
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </ScreenFrame>
  )
}

const LibraryIcon = Library

function LibraryScreen(props: { onBack: () => void }) {
  return (
    <ScreenFrame>
      <ScreenHeader
        title="library"
        breadcrumb="your toolkit"
        action={<IconButton icon={ChevronLeft} label="Back" onClick={props.onBack} />}
      />
      <div className="flex-1 overflow-y-auto px-4 pb-4">
        <SectionHead label="snippets" count={SNIPPETS.length} />
        <div className="space-y-2">
          {SNIPPETS.map((snippet) => (
            <div key={snippet.name} className="border border-[#23262d] bg-[#0e0f12] p-3">
              <div className="flex items-center gap-2">
                <Command className="size-4 text-[#2f43ff]" />
                <span className="font-mono text-[13px] font-bold text-[#e9e9e2]">{snippet.name}</span>
                <span className="ml-auto border border-white/[0.08] px-2 py-1 font-mono text-[10px] text-[#8a8d96]">{snippet.scope}</span>
              </div>
              <p className="mt-2 truncate border-l-2 border-[#2f43ff] pl-3 font-mono text-[12px] text-[#8a8d96]">{snippet.body}</p>
            </div>
          ))}
        </div>

        <SectionHead label="keys & agents" className="mt-5" />
        <div className="grid grid-cols-2 gap-2">
          <LibraryTile icon={ShieldCheck} label="Secure keys" value="3" />
          <LibraryTile icon={Bot} label="Agent profiles" value="4" />
          <LibraryTile icon={ClipboardList} label="Policy rules" value="8" />
          <LibraryTile icon={Sparkles} label="Cloud agents" value="2" />
        </div>
      </div>
    </ScreenFrame>
  )
}

function ActionDock(props: {
  mode: DesignMode
  activeTab: AppTabID
  selectedHost: HostSlot
  pendingCount: number
  approvals: ApprovalItem[]
  onWatchApprove: () => void
  onWatchDecision: (decision: Extract<ApprovalDecision, "approved" | "rejected">) => void
  onOpenSession: () => void
  onSetTab: (tab: AppTabID) => void
}) {
  const nextApproval = props.approvals.find((approval) => approval.decision === "pending")
  return (
    <aside className="self-center border border-white/[0.08] bg-[#0a0b0d] max-[980px]:self-stretch">
      <div className="border-b border-white/[0.08] p-4">
        <div className="flex items-center gap-3">
          <span className="h-8 w-1.5" style={{ background: props.mode.accent }} aria-hidden="true" />
          <div className="min-w-0">
            <p className="font-mono text-[10px] uppercase tracking-[0.24em] text-[#565963]">direction</p>
            <h2 className="truncate text-[18px] font-black text-white">{props.mode.name}</h2>
          </div>
        </div>
        <p className="mt-3 text-[13px] leading-relaxed text-[#8a8d96]">{props.mode.premise}</p>
      </div>

      <div className="grid grid-cols-2 border-b border-white/[0.08]">
        <DockStat label="screen" value={APP_TABS[props.activeTab].label} />
        <DockStat label="pending" value={`${props.pendingCount}`} tone={props.pendingCount > 0 ? "warn" : "ok"} />
      </div>

      <div className="p-4">
        <div className="border border-white/[0.08] bg-[#111317] p-3">
          <div className="flex items-center gap-2">
            <Radio className="size-4 text-[#36c26b]" />
            <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-[#8a8d96]">Live Activity</p>
            <StatusLight tone={props.pendingCount > 0 ? "warn" : "ok"} pulse={props.pendingCount > 0} />
          </div>
          <div className="mt-3 flex items-center gap-3">
            <PixelGlyph seed="live" size={32} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-bold text-white">{props.selectedHost.name}</p>
              <p className="truncate font-mono text-[11px] text-[#8a8d96]">
                {nextApproval ? nextApproval.title : "All sessions clear"}
              </p>
            </div>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2">
            <RectButton
              tone="danger"
              testId="watch-reject"
              onClick={() => props.onWatchDecision("rejected")}
            >
              Reject
            </RectButton>
            <RectButton tone="primary" testId="watch-approve" onClick={props.onWatchApprove}>
              Approve
            </RectButton>
          </div>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={props.onOpenSession}
            className="border border-white/[0.08] bg-white/[0.03] px-3 py-3 font-mono text-[10px] uppercase tracking-[0.12em] text-[#e9e9e2] hover:border-[#2f43ff]/50"
          >
            Session
          </button>
          <button
            type="button"
            onClick={() => props.onSetTab("activity")}
            className="border border-white/[0.08] bg-white/[0.03] px-3 py-3 font-mono text-[10px] uppercase tracking-[0.12em] text-[#e9e9e2] hover:border-[#2f43ff]/50"
          >
            Audit
          </button>
        </div>

        <div className="mt-4 flex items-center gap-2 border border-white/[0.08] bg-white/[0.025] px-3 py-2">
          <Zap className="size-4 text-[#f0a93b]" />
          <p className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#8a8d96]">
            {FEATURE_MAP.length} features reachable in phone
          </p>
        </div>
      </div>
    </aside>
  )
}

function DecisionSheet(props: {
  approval: ApprovalItem
  onClose: () => void
  onDecide: (id: string, decision: ApprovalDecision) => void
}) {
  const [choice, setChoice] = useState(0)
  return (
    <div className="absolute inset-0 z-40 bg-black/60 backdrop-blur-sm">
      <div className="absolute inset-x-0 bottom-0 border-t border-white/[0.12] bg-[#111317] p-4 shadow-2xl">
        <div className="mx-auto mb-4 h-1 w-10 bg-white/20" />
        <div className="flex items-start gap-3">
          <AgentBadge approval={props.approval} />
          <button type="button" onClick={props.onClose} className="ml-auto text-[#8a8d96]" aria-label="Close decision sheet">
            <X className="size-5" />
          </button>
        </div>
        <h3 className="mt-3 text-[18px] font-black leading-tight text-[#e9e9e2]">{props.approval.title}</h3>
        <CommandBlock command={props.approval.command} tone={props.approval.risk} />
        {props.approval.choices && (
          <div className="mt-3 grid gap-2">
            {props.approval.choices.map((item, index) => (
              <button
                type="button"
                key={item}
                onClick={() => setChoice(index)}
                className={cn(
                  "flex items-center gap-3 border px-3 py-3 text-left font-mono text-[12px]",
                  choice === index ? "border-[#2f43ff] bg-[#2f43ff]/12 text-[#e9e9e2]" : "border-white/[0.08] text-[#8a8d96]"
                )}
              >
                <span className="grid size-7 place-items-center border border-white/[0.1]">{String.fromCharCode(65 + index)}</span>
                {item}
              </button>
            ))}
          </div>
        )}
        <div className="mt-4 grid grid-cols-3 gap-2">
          <RectButton tone="danger" onClick={() => props.onDecide(props.approval.id, "rejected")}>
            Deny
          </RectButton>
          <RectButton tone="muted" onClick={() => props.onDecide(props.approval.id, "approvedAlways")}>
            Always
          </RectButton>
          <RectButton tone="primary" testId={`sheet-approve-${props.approval.id}`} onClick={() => props.onDecide(props.approval.id, "approved")}>
            Approve
          </RectButton>
        </div>
      </div>
    </div>
  )
}

function OnboardingOverlay(props: { onClose: () => void }) {
  const [step, setStep] = useState(0)
  const steps = [
    {
      title: "agents ask.",
      accent: "you approve.",
      body: "Risky commands, file writes, credentials, and network actions pause on this phone.",
      icon: Inbox,
    },
    {
      title: "remote stays alive.",
      accent: "tmux resumes.",
      body: "The workspace keeps running through network handoffs and foreground changes.",
      icon: Server,
    },
    {
      title: "review the work.",
      accent: "ship safely.",
      body: "Diffs, files, previews, snippets, and reports live beside the terminal.",
      icon: FileDiff,
    },
  ]
  const current = steps[step]
  const Icon = current.icon
  return (
    <div className="absolute inset-0 z-50 bg-[#0a0b0d] p-6">
      <SpectrumBar />
      <div className="mt-8 font-mono text-[10px] uppercase tracking-[0.28em] text-[#565963]">conduit</div>
      <div className="mt-10 grid size-16 place-items-center border border-[#2f43ff]/40 bg-[#2f43ff]/12 text-[#5a68ff]">
        <Icon className="size-8" />
      </div>
      <h2 className="mt-8 text-[38px] font-black leading-[0.98] tracking-[-0.03em]">
        {current.title}
        <br />
        <span className="text-[#8a8d96]">{current.accent}</span>
      </h2>
      <p className="mt-5 max-w-[250px] font-mono text-[12px] leading-loose text-[#8a8d96]">{current.body}</p>
      <div className="absolute inset-x-6 bottom-8">
        <div className="mb-5 flex gap-1.5">
          {steps.map((item, index) => (
            <span key={item.title} className={cn("h-1 flex-1", step === index ? "bg-[#2f43ff]" : "bg-[#23262d]")} />
          ))}
        </div>
        <div className="grid grid-cols-2 gap-2">
          <RectButton tone="muted" onClick={props.onClose}>
            Skip
          </RectButton>
          <RectButton tone="primary" onClick={() => (step === steps.length - 1 ? props.onClose() : setStep(step + 1))}>
            {step === steps.length - 1 ? "Done" : "Continue"}
          </RectButton>
        </div>
      </div>
    </div>
  )
}

function ScreenFrame({ children, className }: { children: ReactNode; className?: string }) {
  return <section className={cn("flex h-full flex-col bg-[#0a0b0d]", className)}>{children}</section>
}

function ScreenHeader(props: { title: string; breadcrumb: string; count?: string; action?: ReactNode }) {
  return (
    <header className="px-4 pt-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="font-black lowercase tracking-[-0.06em] text-[#e9e9e2] text-[42px] leading-none">
            {props.title}
            <span className="text-[#2f43ff]">_</span>
          </h2>
          <div className="mt-3 flex items-center gap-2 font-mono text-[13px] text-[#565963]">
            <span>~/conduit</span>
            <ChevronRight className="size-3 text-[#2f43ff]" />
            <span>{props.breadcrumb}</span>
            {props.count && <span className="ml-auto text-[#8a8d96]">{props.count}</span>}
          </div>
        </div>
        {props.action}
      </div>
      <SpectrumBar className="mt-4" />
    </header>
  )
}

function SpectrumBar({ className }: { className?: string }) {
  return (
    <div className={cn("grid h-2 grid-cols-7 gap-0.5", className)} aria-hidden="true">
      {["#C8423B", "#E2662C", "#F0922E", "#F2C14E", "#C77BA6", "#7E4FB5", "#5460C8"].map((color) => (
        <span key={color} style={{ background: color }} />
      ))}
    </div>
  )
}

function SectionHead({ label, count, className }: { label: string; count?: number; className?: string }) {
  return (
    <div className={cn("px-4 pb-2 pt-1 font-mono text-[12px] uppercase tracking-[0.22em] text-[#565963]", className)}>
      {label}
      {count !== undefined && <span> · {count}</span>}
    </div>
  )
}

function AgentBadge({ approval, label = true }: { approval: ApprovalItem; label?: boolean }) {
  return (
    <span className="inline-flex items-center gap-1.5 border border-[#2f343c] bg-[#15171c] px-1.5 py-1">
      <span className="grid size-5 place-items-center bg-[#d1702f] font-mono text-[10px] font-black text-white">
        {approval.agentKey}
      </span>
      {label && <span className="font-mono text-[12px] text-[#8a8d96]">{approval.agent}</span>}
    </span>
  )
}

function RiskPill({ risk }: { risk: ApprovalItem["risk"] }) {
  return <span className={cn("border px-2 py-1 font-mono text-[11px] font-bold uppercase", RISK_CLASS[risk])}>{risk}</span>
}

function DecisionPill({ decision }: { decision: ApprovalDecision }) {
  const label = decision === "approvedAlways" ? "always" : decision
  const approved = decision === "approved" || decision === "approvedAlways"
  return (
    <span className={cn("px-2 py-1 font-mono text-[11px]", approved ? "bg-[#36c26b]/12 text-[#36c26b]" : "bg-[#e0533f]/12 text-[#e0533f]")}>
      {label}
    </span>
  )
}

function CommandBlock({ command, tone }: { command: string; tone: ApprovalItem["risk"] }) {
  const color = tone === "critical" ? "#e0533f" : tone === "medium" ? "#f0a93b" : "#2f43ff"
  return (
    <div className="mt-3 border-l-4 bg-[#050810] px-3 py-3" style={{ borderColor: color }}>
      <div className="mb-1 flex gap-2 font-mono text-[11px] uppercase tracking-[0.14em] text-[#8a8d96]">
        <span>bash</span>
        <span className="bg-[#23262d] px-1.5">{tone}</span>
      </div>
      <p className="break-words font-mono text-[15px] leading-snug text-[#e9e9e2]">{command}</p>
    </div>
  )
}

function RectButton({
  children,
  tone,
  onClick,
  testId,
}: {
  children: ReactNode
  tone: "primary" | "danger" | "muted" | "info"
  onClick?: () => void
  testId?: string
}) {
  const toneClass = {
    primary: "border-[#2f43ff] bg-[#2f43ff] text-white hover:bg-[#5a68ff]",
    danger: "border-[#e0533f] bg-[#e0533f]/10 text-[#e0533f] hover:bg-[#e0533f]/18",
    muted: "border-[#2f343c] bg-transparent text-[#e9e9e2] hover:bg-white/[0.04]",
    info: "border-[#2f43ff]/45 bg-[#2f43ff]/10 text-[#7d88ff] hover:bg-[#2f43ff]/16",
  }[tone]
  return (
    <button
      type="button"
      data-testid={testId}
      onClick={onClick}
      className={cn("flex min-h-9 flex-1 items-center justify-center px-3 font-mono text-[11px] font-bold uppercase tracking-[0.12em] transition", toneClass)}
    >
      {children}
    </button>
  )
}

function TinyButton({ icon: Icon, label, onClick }: { icon: LucideIcon; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center justify-center gap-1 border border-white/[0.08] bg-white/[0.025] px-2 py-2 font-mono text-[10px] uppercase text-[#8a8d96]"
    >
      <Icon className="size-3.5" />
      {label}
    </button>
  )
}

function ToggleRow({ label, active, onToggle }: { label: string; active: boolean; onToggle: () => void }) {
  return (
    <button type="button" onClick={onToggle} className="flex w-full items-center gap-3 border-b border-white/[0.06] px-3 py-3 text-left last:border-b-0">
      <span className="font-mono text-[13px] text-[#e9e9e2]">{label}</span>
      <span className={cn("ml-auto flex h-6 w-10 items-center border p-0.5 transition", active ? "border-[#2f43ff] bg-[#2f43ff]/20" : "border-[#2f343c] bg-[#15171c]")}>
        <span className={cn("size-4 bg-[#8a8d96] transition", active && "translate-x-4 bg-[#2f43ff]")} />
      </span>
    </button>
  )
}

function IconButton({ icon: Icon, label, onClick }: { icon: LucideIcon; label: string; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="grid size-10 place-items-center border border-white/[0.08] bg-white/[0.025] text-[#8a8d96]" aria-label={label}>
      <Icon className="size-4" />
    </button>
  )
}

function FleetMetric({ value, label }: { value: string; label: string }) {
  return (
    <div className="border-r border-[#23262d] px-2 py-4 text-center last:border-r-0">
      <p className="font-mono text-[22px] text-[#e9e9e2]">{value}</p>
      <p className="mt-1 font-mono text-[11px] text-[#8a8d96]">{label}</p>
    </div>
  )
}

function DockStat({ value, label, tone = "info" }: { value: string; label: string; tone?: "info" | "ok" | "warn" }) {
  const color = tone === "ok" ? "text-[#36c26b]" : tone === "warn" ? "text-[#f0a93b]" : "text-[#7d88ff]"
  return (
    <div className="border-r border-white/[0.08] bg-white/[0.02] p-3 last:border-r-0">
      <p className={cn("truncate font-mono text-[16px]", color)}>{value}</p>
      <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.14em] text-[#565963]">{label}</p>
    </div>
  )
}

function LibraryTile({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="border border-[#23262d] bg-[#0e0f12] p-3">
      <Icon className="size-4 text-[#8a8d96]" />
      <p className="mt-3 font-mono text-[22px] text-[#e9e9e2]">{value}</p>
      <p className="font-mono text-[11px] text-[#8a8d96]">{label}</p>
    </div>
  )
}

function StatusLight({ tone, pulse = false }: { tone: keyof typeof TONE_CLASS; pulse?: boolean }) {
  return (
    <span className="relative inline-flex size-2 shrink-0">
      {pulse && <span className={cn("absolute inline-flex size-full animate-ping opacity-60", TONE_CLASS[tone].split(" ")[0])} />}
      <span className={cn("relative inline-flex size-2", TONE_CLASS[tone].split(" ")[0])} />
    </span>
  )
}

function PixelGlyph({ seed, size }: { seed: string; size: number }) {
  const cells = useMemo(() => {
    const base = seed.split("").reduce((sum, char) => sum + char.charCodeAt(0), 0)
    return Array.from({ length: 16 }, (_, index) => (base + index * 7) % 5)
  }, [seed])
  const colors = ["#2f343c", "#565963", "#8a8d96", "#bda4a8", "#cbd8d4"]
  return (
    <div
      className="grid shrink-0 grid-cols-4 gap-[2px] overflow-hidden border border-white/[0.08] bg-[#15171c] p-[5px]"
      style={{ width: size, height: size }}
      aria-hidden="true"
    >
      {cells.map((cell, index) => (
        <span key={`${seed}-${index}`} style={{ background: colors[cell] }} />
      ))}
    </div>
  )
}

function SignalBars() {
  return (
    <span className="flex h-4 items-end gap-0.5" aria-hidden="true">
      {[6, 9, 12, 15].map((height) => (
        <span key={height} className="w-1 bg-white" style={{ height }} />
      ))}
    </span>
  )
}

function commandOutput(prompt: string) {
  if (prompt.includes("test")) return ["PASS SessionViewModelTests", "PASS ApprovalRelayTests", "116 tests passed"]
  if (prompt.includes("git")) return [" M docs/conduit-ui-prototype/app/interactive/page.tsx", " M docs/conduit-ui-prototype/app/page.tsx"]
  if (prompt.startsWith("#")) return ["Translated natural language into shell command", "npm run lint && npm run build"]
  if (prompt.includes("fail")) return ["fatal: simulated command failure"]
  return ["command accepted", "remote PTY still attached"]
}
