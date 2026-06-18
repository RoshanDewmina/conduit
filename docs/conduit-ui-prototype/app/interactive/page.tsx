"use client"

import type { ChangeEvent, ReactNode } from "react"
import { useMemo, useState } from "react"
import {
  AlertTriangle,
  CheckCircle2,
  ChevronRight,
  Clock3,
  FileDiff,
  Menu,
  MoreHorizontal,
  PanelLeftClose,
  PanelLeftOpen,
  PlayCircle,
  Plus,
  Search,
  Send,
  Server,
  ShieldCheck,
  X,
  type LucideIcon,
} from "lucide-react"
import { cn } from "@/lib/utils"
import {
  ARTIFACT_ICONS,
  ATTENTION_ITEMS,
  CHAT_CONTEXT,
  DIFF_PREVIEW_LINES,
  FILE_PREVIEW,
  FLEET_AGENTS,
  NAV_ICONS,
  SIDEBAR_VARIANTS,
  STATE_ICONS,
  THREADS,
  type AttentionItem,
  type ChatArtifact,
  type ChatMessage,
  type ChatThread,
  type FleetAgent,
  type SidebarVariant,
  type SidebarVariantID,
} from "@/lib/sidebar-chat-data"

const riskClass = {
  low: "border-[#36c26b]/35 bg-[#36c26b]/10 text-[#6fea9a]",
  medium: "border-[#f0a93b]/35 bg-[#f0a93b]/10 text-[#f5c469]",
  high: "border-[#5a68ff]/45 bg-[#2f43ff]/14 text-[#91a0ff]",
  critical: "border-[#e0533f]/45 bg-[#e0533f]/12 text-[#ff897c]",
}

const stateClass = {
  running: "bg-[#36c26b] text-[#9ef2bd]",
  "needs-you": "bg-[#f0a93b] text-[#ffd98a]",
  done: "bg-[#5a68ff] text-[#aeb7ff]",
  paused: "bg-[#8a8d96] text-[#c8cad0]",
  idle: "bg-[#565963] text-[#c8cad0]",
  offline: "bg-[#34373e] text-[#8a8d96]",
}

const artifactClass = {
  blue: "border-[#5a68ff]/35 bg-[#2f43ff]/12 text-[#aeb7ff]",
  green: "border-[#36c26b]/35 bg-[#36c26b]/10 text-[#9ef2bd]",
  amber: "border-[#f0a93b]/35 bg-[#f0a93b]/10 text-[#ffd98a]",
  red: "border-[#e0533f]/35 bg-[#e0533f]/10 text-[#ff897c]",
  neutral: "border-white/[0.1] bg-white/[0.035] text-[#d6d3cc]",
}

export default function InteractivePage() {
  const [variantID, setVariantID] = useState<SidebarVariantID>("chat")
  const [threads, setThreads] = useState<ChatThread[]>(THREADS)
  const [attention, setAttention] = useState<AttentionItem[]>(ATTENTION_ITEMS)
  const [selectedThreadID, setSelectedThreadID] = useState(THREADS[0].id)
  const [searchText, setSearchText] = useState("")
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [composer, setComposer] = useState("")
  const [activeArtifact, setActiveArtifact] = useState<ChatArtifact | null>(THREADS[0].messages[1].artifacts?.[0] ?? null)
  const [model, setModel] = useState(THREADS[0].model)
  const [host, setHost] = useState(THREADS[0].host)
  const [budget, setBudget] = useState(THREADS[0].budget)

  const variant = SIDEBAR_VARIANTS.find((item) => item.id === variantID) ?? SIDEBAR_VARIANTS[0]
  const selectedThread = threads.find((thread) => thread.id === selectedThreadID) ?? threads[0]

  const filteredThreads = useMemo(() => {
    const q = searchText.trim().toLowerCase()
    if (!q) return threads
    return threads.filter((thread) => {
      const haystack = [
        thread.title,
        thread.agent,
        thread.host,
        thread.cwd,
        thread.summary,
        ...thread.messages.map((message) => message.body),
        ...thread.messages.flatMap((message) => message.artifacts?.map((artifact) => `${artifact.label} ${artifact.detail}`) ?? []),
      ].join(" ").toLowerCase()
      return haystack.includes(q)
    })
  }, [searchText, threads])

  function selectVariant(next: SidebarVariantID) {
    setVariantID(next)
    setSidebarOpen(true)
  }

  function selectThread(threadID: string) {
    const next = threads.find((thread) => thread.id === threadID)
    if (!next) return
    setSelectedThreadID(threadID)
    setModel(next.model)
    setHost(next.host)
    setBudget(next.budget)
    setActiveArtifact(next.messages.flatMap((message) => message.artifacts ?? [])[0] ?? null)
    setSidebarOpen(false)
  }

  function createThread() {
    const id = `thread-new-${Date.now()}`
    const newThread: ChatThread = {
      id,
      title: "New agent chat",
      agent: "Codex",
      agentKey: "CX",
      host: "This Mac",
      cwd: "/Users/roshansilva/Documents/command-center",
      model: "gpt-5-codex",
      budget: "$4 cap",
      status: "running",
      lastActive: "now",
      summary: "Fresh conversation ready to continue from the phone.",
      messages: [
        {
          id: `${id}-system`,
          role: "system",
          body: "New thread created. Choose an agent context, write a prompt, and Conduit will keep the conversation in history.",
          time: "now",
          status: "complete",
        },
      ],
    }
    setThreads((current) => [newThread, ...current])
    setSelectedThreadID(id)
    setSearchText("")
    setModel(newThread.model)
    setHost(newThread.host)
    setBudget(newThread.budget)
    setActiveArtifact(null)
    setSidebarOpen(false)
  }

  function sendFollowUp() {
    const trimmed = composer.trim()
    if (!trimmed) return
    const userMessage: ChatMessage = {
      id: `user-${Date.now()}`,
      role: "user",
      body: trimmed,
      time: "now",
    }
    const assistantMessage: ChatMessage = {
      id: `assistant-${Date.now()}`,
      role: "assistant",
      body: "Follow-up accepted. Conduit continues this thread with a fresh runId, keeps the prior turns visible, and streams new artifacts into the same conversation.",
      time: "now",
      status: "streaming",
      artifacts: [
        { id: `tests-${Date.now()}`, kind: "tests", label: "Tests", detail: "queued after update", tone: "green" },
      ],
    }
    setThreads((current) =>
      current.map((thread) =>
        thread.id === selectedThreadID
          ? {
              ...thread,
              status: "running",
              lastActive: "now",
              summary: trimmed,
              messages: [...thread.messages, userMessage, assistantMessage],
            }
          : thread
      )
    )
    setComposer("")
  }

  function continueThread(threadID: string) {
    selectThread(threadID)
    setComposer("Continue from the last result and explain the next step.")
  }

  function decide(item: AttentionItem, state: "approved" | "rejected") {
    setAttention((current) => current.map((entry) => (entry.id === item.id ? { ...entry, state } : entry)))
    const message: ChatMessage = {
      id: `decision-${item.id}-${Date.now()}`,
      role: "system",
      body: state === "approved" ? `${item.action} approved. The agent can continue in this thread.` : `${item.action} rejected. The agent is paused for edits.`,
      time: "now",
      status: "complete",
      artifacts: [
        { id: `approval-${item.id}`, kind: "approval", label: "Approval", detail: state, tone: state === "approved" ? "green" : "red" },
      ],
    }
    setThreads((current) =>
      current.map((thread) =>
        thread.id === item.threadId
          ? {
              ...thread,
              status: state === "approved" ? "running" : "paused",
              lastActive: "now",
              messages: [...thread.messages, message],
            }
          : thread
      )
    )
    selectThread(item.threadId)
  }

  function openFleetAgent(agent: FleetAgent) {
    selectThread(agent.threadId)
  }

  return (
    <main className="min-h-screen overflow-hidden bg-[#050810] text-[#ecebe5]">
      <div className="flex h-screen">
        <Sidebar
          open={sidebarOpen}
          variant={variant}
          activeVariantID={variantID}
          threads={filteredThreads}
          allThreads={threads}
          attention={attention}
          fleet={FLEET_AGENTS}
          selectedThreadID={selectedThread.id}
          searchText={searchText}
          onSearchChange={setSearchText}
          onToggle={() => setSidebarOpen((open) => !open)}
          onVariantChange={selectVariant}
          onCreateThread={createThread}
          onSelectThread={selectThread}
          onContinueThread={continueThread}
          onDecision={decide}
          onOpenFleetAgent={openFleetAgent}
        />

        {sidebarOpen && (
          <button
            type="button"
            aria-label="Close sidebar overlay"
            className="fixed inset-0 z-30 bg-black/55 md:hidden"
            onClick={() => setSidebarOpen(false)}
          />
        )}

        <section className="flex min-w-0 flex-1 flex-col">
          <TopBar
            variant={variant}
            thread={selectedThread}
            sidebarOpen={sidebarOpen}
            onToggleSidebar={() => setSidebarOpen((open) => !open)}
          />

          <div
            className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_320px] gap-0 max-[1120px]:grid-cols-1"
            data-testid={`variant-screen-${variant.id}`}
          >
            <ChatDetail
              thread={selectedThread}
              attention={attention}
              activeArtifact={activeArtifact}
              model={model}
              host={host}
              budget={budget}
              composer={composer}
              onModelChange={setModel}
              onHostChange={setHost}
              onBudgetChange={setBudget}
              onComposerChange={setComposer}
              onSend={sendFollowUp}
              onArtifactOpen={setActiveArtifact}
              onDecision={decide}
            />
            <ContextPanel
              thread={selectedThread}
              artifact={activeArtifact}
              attention={attention}
              fleet={FLEET_AGENTS}
              onArtifactOpen={setActiveArtifact}
              onOpenFleetAgent={openFleetAgent}
            />
          </div>
        </section>
      </div>
    </main>
  )
}

function Sidebar(props: {
  open: boolean
  variant: SidebarVariant
  activeVariantID: SidebarVariantID
  threads: ChatThread[]
  allThreads: ChatThread[]
  attention: AttentionItem[]
  fleet: FleetAgent[]
  selectedThreadID: string
  searchText: string
  onSearchChange: (value: string) => void
  onToggle: () => void
  onVariantChange: (id: SidebarVariantID) => void
  onCreateThread: () => void
  onSelectThread: (id: string) => void
  onContinueThread: (id: string) => void
  onDecision: (item: AttentionItem, state: "approved" | "rejected") => void
  onOpenFleetAgent: (agent: FleetAgent) => void
}) {
  return (
    <aside
      data-testid="sidebar-panel"
      className={cn(
        "z-40 flex h-screen shrink-0 flex-col border-r border-white/[0.08] bg-[#090b10]/98 transition-all duration-300",
        props.open ? "w-[360px]" : "w-[74px]",
        "max-md:fixed max-md:inset-y-0 max-md:left-0 max-md:w-[88vw] max-md:max-w-[390px]",
        props.open ? "max-md:translate-x-0" : "max-md:-translate-x-full md:translate-x-0"
      )}
    >
      <div className="flex h-[72px] items-center gap-3 border-b border-white/[0.08] px-4">
        <PixelMark label="C" />
        {props.open && (
          <div className="min-w-0 flex-1">
            <p className="font-mono text-[10px] uppercase tracking-[0.28em] text-[#5a68ff]">Conduit</p>
            <h1 className="truncate text-[17px] font-black leading-none text-white">Sidebar chat</h1>
          </div>
        )}
        <button
          type="button"
          data-testid="sidebar-toggle"
          onClick={props.onToggle}
          className="grid size-10 place-items-center border border-white/[0.1] bg-white/[0.03] text-[#c8cad0] transition hover:border-[#5a68ff]/45 hover:text-white"
          aria-label={props.open ? "Collapse sidebar" : "Open sidebar"}
        >
          {props.open ? <PanelLeftClose className="size-4" /> : <PanelLeftOpen className="size-4" />}
        </button>
      </div>

      <VariantSwitcher
        open={props.open}
        activeVariantID={props.activeVariantID}
        onVariantChange={props.onVariantChange}
      />

      <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3">
        {props.variant.navOrder.map((section) => (
          <SidebarSection key={section} icon={NAV_ICONS[section]} label={sectionLabel(section)} open={props.open}>
            {section === "new" && <NewChatButton open={props.open} onCreateThread={props.onCreateThread} />}
            {section === "search" && (
              <SearchBlock open={props.open} value={props.searchText} onChange={props.onSearchChange} />
            )}
            {section === "threads" && (
              <ThreadList
                open={props.open}
                threads={props.threads}
                selectedThreadID={props.selectedThreadID}
                searchActive={props.searchText.trim().length > 0}
                onSelectThread={props.onSelectThread}
                onContinueThread={props.onContinueThread}
              />
            )}
            {section === "attention" && (
              <AttentionList open={props.open} items={props.attention} onDecision={props.onDecision} onSelectThread={props.onSelectThread} />
            )}
            {section === "fleet" && <FleetList open={props.open} agents={props.fleet} onOpenFleetAgent={props.onOpenFleetAgent} />}
            {section === "settings" && <SettingsList open={props.open} />}
          </SidebarSection>
        ))}
      </div>

      {props.open && (
        <div className="border-t border-white/[0.08] p-3">
          <div className="border border-[#36c26b]/25 bg-[#36c26b]/10 p-3">
            <div className="flex items-center gap-2">
              <ShieldCheck className="size-4 text-[#6fea9a]" />
              <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#9ef2bd]">Governed remote control</span>
            </div>
            <p className="mt-2 text-[12px] leading-relaxed text-[#c8cad0]">
              Chat remains the main surface, while policy, approvals, and fleet status stay one tap away.
            </p>
          </div>
        </div>
      )}
    </aside>
  )
}

function VariantSwitcher(props: {
  open: boolean
  activeVariantID: SidebarVariantID
  onVariantChange: (id: SidebarVariantID) => void
}) {
  return (
    <div className={cn("border-b border-white/[0.08] p-3", !props.open && "px-2")}>
      {props.open ? (
        <div className="grid gap-1">
          {SIDEBAR_VARIANTS.map((variant) => {
            const Icon = variant.primaryIcon
            const active = props.activeVariantID === variant.id
            return (
              <button
                type="button"
                key={variant.id}
                data-testid={`variant-${variant.id}`}
                onClick={() => props.onVariantChange(variant.id)}
                className={cn(
                  "flex w-full min-w-0 items-center gap-3 border px-3 py-2 text-left transition",
                  active ? "border-[#5a68ff]/60 bg-[#2f43ff]/16 text-white" : "border-transparent text-[#8a8d96] hover:border-white/[0.08] hover:bg-white/[0.03]"
                )}
              >
                <Icon className="size-4 shrink-0" />
                <div className="min-w-0 flex-1">
                  <p className="font-mono text-[11px] font-bold uppercase tracking-[0.12em]">{variant.label}</p>
                  <p className="mt-0.5 truncate text-[11px] text-[#6f737c]">{variant.premise}</p>
                </div>
              </button>
            )
          })}
        </div>
      ) : (
        <div className="grid gap-2">
          {SIDEBAR_VARIANTS.map((variant) => {
            const Icon = variant.primaryIcon
            return (
              <button
                type="button"
                key={variant.id}
                data-testid={`variant-${variant.id}`}
                onClick={() => props.onVariantChange(variant.id)}
                className={cn(
                  "grid size-11 place-items-center border transition",
                  props.activeVariantID === variant.id ? "border-[#5a68ff]/60 bg-[#2f43ff]/16 text-white" : "border-white/[0.08] bg-white/[0.025] text-[#8a8d96]"
                )}
                aria-label={variant.label}
              >
                <Icon className="size-4" />
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

function SidebarSection(props: {
  icon: LucideIcon
  label: string
  open: boolean
  children: ReactNode
}) {
  const Icon = props.icon
  return (
    <section className="mb-3">
      <div className={cn("mb-2 flex items-center gap-2 px-1", !props.open && "justify-center")}>
        <Icon className="size-3.5 text-[#5a68ff]" />
        {props.open && <h2 className="font-mono text-[10px] font-bold uppercase tracking-[0.18em] text-[#70747d]">{props.label}</h2>}
      </div>
      {props.children}
    </section>
  )
}

function NewChatButton(props: { open: boolean; onCreateThread: () => void }) {
  return (
    <button
      type="button"
      data-testid="new-chat"
      onClick={props.onCreateThread}
      className={cn(
        "flex w-full items-center justify-center gap-2 border border-[#5a68ff]/45 bg-[#2f43ff]/18 text-white transition hover:bg-[#2f43ff]/25",
        props.open ? "px-3 py-3 text-left" : "size-11"
      )}
    >
      <Plus className="size-4" />
      {props.open && <span className="font-mono text-[11px] font-bold uppercase tracking-[0.14em]">New chat</span>}
    </button>
  )
}

function SearchBlock(props: {
  open: boolean
  value: string
  onChange: (value: string) => void
}) {
  if (!props.open) {
    return (
      <div className="grid size-11 place-items-center border border-white/[0.08] bg-white/[0.025] text-[#8a8d96]">
        <Search className="size-4" />
      </div>
    )
  }
  return (
    <label className="flex items-center gap-2 border border-white/[0.08] bg-[#0e1016] px-3 py-2">
      <Search className="size-4 text-[#70747d]" />
      <input
        data-testid="thread-search"
        value={props.value}
        onChange={(event: ChangeEvent<HTMLInputElement>) => props.onChange(event.target.value)}
        placeholder="Search threads, messages, artifacts"
        className="min-w-0 flex-1 bg-transparent font-mono text-[12px] text-white outline-none placeholder:text-[#565963]"
      />
      {props.value && (
        <button type="button" onClick={() => props.onChange("")} aria-label="Clear search">
          <X className="size-4 text-[#70747d]" />
        </button>
      )}
    </label>
  )
}

function ThreadList(props: {
  open: boolean
  threads: ChatThread[]
  selectedThreadID: string
  searchActive: boolean
  onSelectThread: (id: string) => void
  onContinueThread: (id: string) => void
}) {
  if (!props.open) {
    return (
      <div className="grid gap-2">
        {props.threads.slice(0, 4).map((thread) => (
          <button
            key={thread.id}
            type="button"
            onClick={() => props.onSelectThread(thread.id)}
            className={cn("grid size-11 place-items-center border font-mono text-[11px]", props.selectedThreadID === thread.id ? "border-[#5a68ff]/55 bg-[#2f43ff]/16 text-white" : "border-white/[0.08] bg-white/[0.025] text-[#8a8d96]")}
          >
            {thread.agentKey}
          </button>
        ))}
      </div>
    )
  }
  return (
    <div className="grid gap-2" data-testid="thread-results">
      {props.searchActive && (
        <p className="px-1 font-mono text-[10px] uppercase tracking-[0.14em] text-[#70747d]">{props.threads.length} matching threads</p>
      )}
      {props.threads.map((thread) => (
        <article
          key={thread.id}
          data-testid={`thread-row-${thread.id}`}
          className={cn("border bg-[#0e1016] transition", props.selectedThreadID === thread.id ? "border-[#5a68ff]/50" : "border-white/[0.07] hover:border-white/[0.14]")}
        >
          <button type="button" onClick={() => props.onSelectThread(thread.id)} className="w-full p-3 text-left">
            <div className="flex items-center gap-2">
              <AgentBadge thread={thread} />
              <StatePill state={thread.status} />
              <span className="ml-auto font-mono text-[10px] text-[#565963]">{thread.lastActive}</span>
            </div>
            <h3 className="mt-2 line-clamp-1 text-[14px] font-bold leading-tight text-white">{thread.title}</h3>
            <p className="mt-1 line-clamp-2 text-[12px] leading-relaxed text-[#8a8d96]">{thread.summary}</p>
          </button>
          <div className="flex border-t border-white/[0.06]">
            <button
              type="button"
              data-testid={`continue-${thread.id}`}
              onClick={() => props.onContinueThread(thread.id)}
              className="flex flex-1 items-center justify-center gap-2 px-3 py-2 font-mono text-[10px] uppercase tracking-[0.12em] text-[#aeb7ff] hover:bg-white/[0.04]"
            >
              <PlayCircle className="size-3.5" />
              Continue
            </button>
          </div>
        </article>
      ))}
    </div>
  )
}

function AttentionList(props: {
  open: boolean
  items: AttentionItem[]
  onDecision: (item: AttentionItem, state: "approved" | "rejected") => void
  onSelectThread: (id: string) => void
}) {
  const pending = props.items.filter((item) => item.state === "pending")
  if (!props.open) {
    return (
      <button
        type="button"
        className="relative grid size-11 place-items-center border border-[#f0a93b]/35 bg-[#f0a93b]/10 text-[#ffd98a]"
        onClick={() => pending[0] && props.onSelectThread(pending[0].threadId)}
        aria-label="Needs attention"
      >
        <AlertTriangle className="size-4" />
        {pending.length > 0 && <span className="absolute -right-1 -top-1 grid size-5 place-items-center bg-[#e0533f] font-mono text-[10px] text-white">{pending.length}</span>}
      </button>
    )
  }
  return (
    <div className="grid gap-2">
      {props.items.map((item) => (
        <article key={item.id} className="border border-white/[0.08] bg-[#0e1016] p-3">
          <div className="flex items-center gap-2">
            <span className={cn("border px-2 py-1 font-mono text-[10px] uppercase tracking-[0.12em]", riskClass[item.risk])}>{item.risk}</span>
            <span className="ml-auto font-mono text-[10px] uppercase tracking-[0.12em] text-[#70747d]">{item.state}</span>
          </div>
          <button type="button" onClick={() => props.onSelectThread(item.threadId)} className="mt-2 w-full text-left">
            <h3 className="text-[13px] font-bold text-white">{item.title}</h3>
            <p className="mt-1 text-[12px] leading-relaxed text-[#8a8d96]">{item.detail}</p>
          </button>
          {item.state === "pending" && (
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button
                type="button"
                data-testid={`reject-${item.id}`}
                onClick={() => props.onDecision(item, "rejected")}
                className="border border-white/[0.08] px-3 py-2 font-mono text-[10px] uppercase tracking-[0.12em] text-[#c8cad0] hover:bg-white/[0.04]"
              >
                Reject
              </button>
              <button
                type="button"
                data-testid={`approve-${item.id}`}
                onClick={() => props.onDecision(item, "approved")}
                className="border border-[#36c26b]/40 bg-[#36c26b]/12 px-3 py-2 font-mono text-[10px] uppercase tracking-[0.12em] text-[#9ef2bd] hover:bg-[#36c26b]/18"
              >
                Approve
              </button>
            </div>
          )}
        </article>
      ))}
    </div>
  )
}

function FleetList(props: {
  open: boolean
  agents: FleetAgent[]
  onOpenFleetAgent: (agent: FleetAgent) => void
}) {
  if (!props.open) {
    return (
      <div className="grid gap-2">
        {props.agents.slice(0, 3).map((agent) => (
          <button
            key={agent.id}
            type="button"
            onClick={() => props.onOpenFleetAgent(agent)}
            className="grid size-11 place-items-center border border-white/[0.08] bg-white/[0.025] text-[#8a8d96]"
            aria-label={agent.agent}
          >
            <Server className="size-4" />
          </button>
        ))}
      </div>
    )
  }
  return (
    <div className="grid gap-2">
      {props.agents.map((agent) => (
        <button
          type="button"
          key={agent.id}
          data-testid={`fleet-agent-${agent.id}`}
          onClick={() => props.onOpenFleetAgent(agent)}
          className="border border-white/[0.08] bg-[#0e1016] p-3 text-left transition hover:border-[#36c26b]/40"
        >
          <div className="flex items-center gap-2">
            <Server className="size-4 text-[#6fea9a]" />
            <span className="font-mono text-[11px] font-bold uppercase tracking-[0.12em] text-white">{agent.host}</span>
            <span className="ml-auto font-mono text-[10px] text-[#70747d]">{agent.spend}</span>
          </div>
          <p className="mt-2 text-[13px] font-semibold text-[#d6d3cc]">{agent.agent} - {agent.model}</p>
          <p className="mt-1 truncate font-mono text-[11px] text-[#70747d]">{agent.branch}</p>
        </button>
      ))}
    </div>
  )
}

function SettingsList(props: { open: boolean }) {
  const rows = ["Policy and approvals", "Models and budgets", "Hosts and relay"]
  if (!props.open) {
    return (
      <div className="grid size-11 place-items-center border border-white/[0.08] bg-white/[0.025] text-[#8a8d96]">
        <MoreHorizontal className="size-4" />
      </div>
    )
  }
  return (
    <div className="grid gap-1">
      {rows.map((row) => (
        <button key={row} type="button" className="flex items-center justify-between border border-white/[0.06] bg-white/[0.02] px-3 py-2 text-left text-[12px] text-[#c8cad0]">
          {row}
          <ChevronRight className="size-3.5 text-[#565963]" />
        </button>
      ))}
    </div>
  )
}

function TopBar(props: {
  variant: SidebarVariant
  thread: ChatThread
  sidebarOpen: boolean
  onToggleSidebar: () => void
}) {
  const Icon = props.variant.primaryIcon
  return (
    <header className="flex h-[72px] items-center gap-3 border-b border-white/[0.08] bg-[#0a0d14]/96 px-4">
      <button
        type="button"
        className="grid size-11 place-items-center border border-white/[0.1] bg-white/[0.03] text-[#c8cad0] md:hidden"
        onClick={props.onToggleSidebar}
        aria-label="Open sidebar"
      >
        <Menu className="size-5" />
      </button>
      <button
        type="button"
        className="hidden size-11 place-items-center border border-white/[0.1] bg-white/[0.03] text-[#c8cad0] md:grid"
        onClick={props.onToggleSidebar}
        aria-label={props.sidebarOpen ? "Collapse sidebar" : "Open sidebar"}
      >
        {props.sidebarOpen ? <PanelLeftClose className="size-4" /> : <PanelLeftOpen className="size-4" />}
      </button>
      <div className="grid size-11 place-items-center border border-[#5a68ff]/35 bg-[#2f43ff]/12">
        <Icon className="size-5 text-[#aeb7ff]" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex min-w-0 items-center gap-2">
          <h2 className="truncate text-[18px] font-black text-white">{props.thread.title}</h2>
          <StatePill state={props.thread.status} />
        </div>
        <p className="truncate font-mono text-[11px] text-[#70747d]">{props.variant.label} - {props.variant.premise}</p>
      </div>
      <div className="hidden items-center gap-2 lg:flex">
        <TinyMetric label="threads" value="history" />
        <TinyMetric label="search" value="global" />
        <TinyMetric label="fleet" value="context" />
      </div>
    </header>
  )
}

function ChatDetail(props: {
  thread: ChatThread
  attention: AttentionItem[]
  activeArtifact: ChatArtifact | null
  model: string
  host: string
  budget: string
  composer: string
  onModelChange: (value: string) => void
  onHostChange: (value: string) => void
  onBudgetChange: (value: string) => void
  onComposerChange: (value: string) => void
  onSend: () => void
  onArtifactOpen: (artifact: ChatArtifact) => void
  onDecision: (item: AttentionItem, state: "approved" | "rejected") => void
}) {
  const pendingForThread = props.attention.filter((item) => item.threadId === props.thread.id && item.state === "pending")
  return (
    <section className="flex min-h-0 flex-col bg-[#050810]">
      <div className="border-b border-white/[0.08] bg-[#080b12] px-5 py-4">
        <div className="flex flex-wrap items-center gap-2">
          <AgentBadge thread={props.thread} />
          <ContextSelect
            testId="host-select"
            label="Host"
            value={props.host}
            options={["This Mac", "Dev VPS", "Staging"]}
            onChange={props.onHostChange}
          />
          <ContextSelect
            testId="model-select"
            label="Model"
            value={props.model}
            options={["gpt-5-codex", "sonnet 4.5", "deepseek-v4-flash", "kimi-k2"]}
            onChange={props.onModelChange}
          />
          <label className="flex h-9 items-center gap-2 border border-white/[0.08] bg-white/[0.025] px-3">
            <span className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#70747d]">Budget</span>
            <input
              data-testid="budget-input"
              value={props.budget}
              onChange={(event) => props.onBudgetChange(event.target.value)}
              className="w-20 bg-transparent font-mono text-[11px] text-white outline-none"
            />
          </label>
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5">
        <div className="mx-auto flex max-w-[860px] flex-col gap-5">
          <ThreadSummary thread={props.thread} />

          {pendingForThread.map((item) => (
            <InlineApproval key={item.id} item={item} onDecision={props.onDecision} />
          ))}

          {props.thread.messages.map((message) => (
            <MessageBubble
              key={message.id}
              message={message}
              agentKey={props.thread.agentKey}
              onArtifactOpen={props.onArtifactOpen}
            />
          ))}

          <div className="hidden max-[1120px]:block">
            <ArtifactPreview artifact={props.activeArtifact} testId="artifact-preview-mobile" />
          </div>
        </div>
      </div>

      <div className="border-t border-white/[0.08] bg-[#080b12] p-4">
        <div className="mx-auto flex max-w-[860px] items-end gap-3">
          <label className="min-w-0 flex-1 border border-white/[0.1] bg-[#10131b] p-3 focus-within:border-[#5a68ff]/50">
            <span className="mb-2 block font-mono text-[10px] uppercase tracking-[0.16em] text-[#70747d]">Continue this thread</span>
            <textarea
              data-testid="composer-input"
              value={props.composer}
              onChange={(event) => props.onComposerChange(event.target.value)}
              placeholder="Send a follow-up, request changes, or ask for status..."
              rows={2}
              className="max-h-32 min-h-12 w-full resize-none bg-transparent text-[14px] leading-relaxed text-white outline-none placeholder:text-[#565963]"
            />
          </label>
          <button
            type="button"
            data-testid="send-follow-up"
            onClick={props.onSend}
            disabled={!props.composer.trim()}
            className="grid size-14 place-items-center border border-[#5a68ff]/45 bg-[#2f43ff]/18 text-white transition enabled:hover:bg-[#2f43ff]/26 disabled:border-white/[0.08] disabled:bg-white/[0.02] disabled:text-[#565963]"
            aria-label="Send follow-up"
          >
            <Send className="size-5" />
          </button>
        </div>
      </div>
    </section>
  )
}

function ContextPanel(props: {
  thread: ChatThread
  artifact: ChatArtifact | null
  attention: AttentionItem[]
  fleet: FleetAgent[]
  onArtifactOpen: (artifact: ChatArtifact) => void
  onOpenFleetAgent: (agent: FleetAgent) => void
}) {
  const relatedFleet = props.fleet.find((agent) => agent.threadId === props.thread.id)
  const artifacts = props.thread.messages.flatMap((message) => message.artifacts ?? [])
  return (
    <aside className="min-h-0 overflow-y-auto border-l border-white/[0.08] bg-[#090b10] p-4 max-[1120px]:hidden">
      <PanelSection title="Thread must-haves" count={CHAT_CONTEXT.length}>
        <div className="grid gap-2">
          {CHAT_CONTEXT.map((item) => {
            const Icon = item.icon
            return (
              <div key={item.label} className="flex items-center gap-3 border border-white/[0.06] bg-white/[0.025] p-3">
                <Icon className="size-4 text-[#aeb7ff]" />
                <div>
                  <p className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#c8cad0]">{item.label}</p>
                  <p className="text-[12px] text-[#70747d]">{item.value}</p>
                </div>
              </div>
            )
          })}
        </div>
      </PanelSection>

      <PanelSection title="Artifacts" count={artifacts.length}>
        <div className="grid gap-2">
          {artifacts.map((artifact) => {
            const Icon = ARTIFACT_ICONS[artifact.kind]
            return (
              <button
                key={artifact.id}
                type="button"
                data-testid={`artifact-${artifact.kind}`}
                onClick={() => props.onArtifactOpen(artifact)}
                className={cn("flex items-center gap-3 border p-3 text-left transition hover:bg-white/[0.055]", artifactClass[artifact.tone])}
              >
                <Icon className="size-4" />
                <div>
                  <p className="font-mono text-[10px] uppercase tracking-[0.12em]">{artifact.label}</p>
                  <p className="text-[12px] opacity-80">{artifact.detail}</p>
                </div>
              </button>
            )
          })}
        </div>
      </PanelSection>

      <ArtifactPreview artifact={props.artifact} testId="artifact-preview" />

      {relatedFleet && (
        <PanelSection title="Fleet context" count={1}>
          <button
            type="button"
            onClick={() => props.onOpenFleetAgent(relatedFleet)}
            className="w-full border border-[#36c26b]/25 bg-[#36c26b]/10 p-3 text-left"
          >
            <div className="flex items-center gap-2">
              <Server className="size-4 text-[#9ef2bd]" />
              <span className="font-mono text-[11px] uppercase tracking-[0.12em] text-[#9ef2bd]">{relatedFleet.host}</span>
            </div>
            <p className="mt-2 text-[13px] font-semibold text-white">{relatedFleet.agent} - {relatedFleet.branch}</p>
            <p className="mt-1 font-mono text-[11px] text-[#70747d]">{relatedFleet.cwd}</p>
          </button>
        </PanelSection>
      )}
    </aside>
  )
}

function ArtifactPreview(props: { artifact: ChatArtifact | null; testId: string }) {
  if (!props.artifact) {
    return (
      <PanelSection title="Preview" count={0}>
        <div className="border border-white/[0.06] bg-white/[0.02] p-4 text-[12px] leading-relaxed text-[#70747d]">
          Select a diff, file list, test result, or approval artifact to inspect it beside the chat.
        </div>
      </PanelSection>
    )
  }

  return (
    <PanelSection title={`${props.artifact.label} preview`} count={1}>
      <div className="border border-white/[0.08] bg-[#0d1017] p-3" data-testid={props.testId}>
        <p className="font-mono text-[10px] uppercase tracking-[0.14em] text-[#70747d]">{props.artifact.detail}</p>
        {props.artifact.kind === "diff" && (
          <div className="mt-3 overflow-hidden border border-white/[0.06] bg-black/30 font-mono text-[11px]">
            {DIFF_PREVIEW_LINES.map((line) => (
              <div
                key={line.text}
                className={cn(
                  "px-3 py-1.5",
                  line.kind === "add" && "bg-[#36c26b]/10 text-[#9ef2bd]",
                  line.kind === "del" && "bg-[#e0533f]/10 text-[#ff897c]",
                  line.kind === "meta" && "text-[#aeb7ff]"
                )}
              >
                {line.text}
              </div>
            ))}
          </div>
        )}
        {props.artifact.kind === "files" && (
          <div className="mt-3 grid gap-1">
            {FILE_PREVIEW.map((file) => (
              <div key={file} className="flex items-center gap-2 border border-white/[0.06] bg-white/[0.025] px-2 py-2 font-mono text-[11px] text-[#d6d3cc]">
                <FileDiff className="size-3.5 text-[#aeb7ff]" />
                {file}
              </div>
            ))}
          </div>
        )}
        {props.artifact.kind === "tests" && (
          <div className="mt-3 grid grid-cols-2 gap-2">
            <TinyMetric label="lint" value="pass" />
            <TinyMetric label="build" value="pass" />
            <TinyMetric label="e2e" value="queued" />
            <TinyMetric label="console" value="clean" />
          </div>
        )}
        {props.artifact.kind === "approval" && (
          <div className="mt-3 border border-[#f0a93b]/25 bg-[#f0a93b]/10 p-3 text-[12px] leading-relaxed text-[#ffd98a]">
            This is shown inside chat and mirrored in the attention sidebar so the user does not context-switch to a separate tab.
          </div>
        )}
        {props.artifact.kind === "preview" && (
          <div className="mt-3 grid h-36 place-items-center border border-[#36c26b]/25 bg-[#36c26b]/10 text-center">
            <PlayCircle className="mb-2 size-7 text-[#9ef2bd]" />
            <p className="font-mono text-[11px] uppercase tracking-[0.12em] text-[#9ef2bd]">Preview tunnel active</p>
          </div>
        )}
      </div>
    </PanelSection>
  )
}

function ThreadSummary(props: { thread: ChatThread }) {
  return (
    <section className="border border-white/[0.08] bg-[#0c0f16] p-4">
      <div className="flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-[#5a68ff]">Saved conversation</p>
          <h2 data-testid="active-thread-title" className="mt-2 text-[28px] font-black leading-none text-white max-sm:text-[24px]">{props.thread.title}</h2>
          <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-[#a6a8af]">{props.thread.summary}</p>
        </div>
        <div className="grid min-w-[190px] gap-2 font-mono text-[11px] text-[#8a8d96]">
          <MetaRow label="Host" value={props.thread.host} />
          <MetaRow label="CWD" value={props.thread.cwd} />
          <MetaRow label="Model" value={props.thread.model} />
          <MetaRow label="Budget" value={props.thread.budget} />
        </div>
      </div>
    </section>
  )
}

function InlineApproval(props: {
  item: AttentionItem
  onDecision: (item: AttentionItem, state: "approved" | "rejected") => void
}) {
  return (
    <article className="border border-[#f0a93b]/35 bg-[#f0a93b]/10 p-4" data-testid={`inline-approval-${props.item.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        <ShieldCheck className="size-4 text-[#ffd98a]" />
        <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#ffd98a]">Needs approval</span>
        <span className={cn("border px-2 py-1 font-mono text-[10px] uppercase tracking-[0.12em]", riskClass[props.item.risk])}>{props.item.risk}</span>
      </div>
      <h3 className="mt-3 text-[16px] font-bold text-white">{props.item.title}</h3>
      <p className="mt-1 text-[13px] leading-relaxed text-[#d6d3cc]">{props.item.detail}</p>
      <div className="mt-4 flex flex-wrap gap-2">
        <button
          type="button"
          data-testid={`inline-reject-${props.item.id}`}
          onClick={() => props.onDecision(props.item, "rejected")}
          className="border border-white/[0.1] px-4 py-2 font-mono text-[10px] uppercase tracking-[0.12em] text-[#c8cad0]"
        >
          Reject
        </button>
        <button
          type="button"
          data-testid={`inline-approve-${props.item.id}`}
          onClick={() => props.onDecision(props.item, "approved")}
          className="border border-[#36c26b]/40 bg-[#36c26b]/12 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.12em] text-[#9ef2bd]"
        >
          {props.item.action}
        </button>
      </div>
    </article>
  )
}

function MessageBubble(props: {
  message: ChatMessage
  agentKey: string
  onArtifactOpen: (artifact: ChatArtifact) => void
}) {
  const isUser = props.message.role === "user"
  const isSystem = props.message.role === "system"
  return (
    <article className={cn("flex gap-3", isUser && "justify-end")}>
      {!isUser && (
        <div className={cn("grid size-9 shrink-0 place-items-center border font-mono text-[11px]", isSystem ? "border-[#36c26b]/30 bg-[#36c26b]/10 text-[#9ef2bd]" : "border-[#5a68ff]/35 bg-[#2f43ff]/12 text-[#aeb7ff]")}>
          {isSystem ? <ShieldCheck className="size-4" /> : props.agentKey}
        </div>
      )}
      <div className={cn("max-w-[78%] border p-4 max-sm:max-w-[90%]", isUser ? "border-[#5a68ff]/35 bg-[#2f43ff]/16" : "border-white/[0.08] bg-[#0d1017]")}>
        <div className="mb-2 flex items-center gap-2">
          <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-[#70747d]">{props.message.role}</span>
          <span className="font-mono text-[10px] text-[#565963]">{props.message.time}</span>
          {props.message.status && <MessageStatus status={props.message.status} />}
        </div>
        <p className="text-[14px] leading-relaxed text-[#e9e9e2]">{props.message.body}</p>
        {!!props.message.artifacts?.length && (
          <div className="mt-3 flex flex-wrap gap-2">
            {props.message.artifacts.map((artifact) => {
              const Icon = ARTIFACT_ICONS[artifact.kind]
              return (
                <button
                  type="button"
                  key={artifact.id}
                  data-testid={`message-artifact-${artifact.kind}`}
                  onClick={() => props.onArtifactOpen(artifact)}
                  className={cn("flex items-center gap-2 border px-3 py-2 font-mono text-[10px] uppercase tracking-[0.12em]", artifactClass[artifact.tone])}
                >
                  <Icon className="size-3.5" />
                  {artifact.label}
                </button>
              )
            })}
          </div>
        )}
      </div>
    </article>
  )
}

function ContextSelect(props: {
  testId: string
  label: string
  value: string
  options: string[]
  onChange: (value: string) => void
}) {
  return (
    <label className="flex h-9 items-center gap-2 border border-white/[0.08] bg-white/[0.025] px-3">
      <span className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#70747d]">{props.label}</span>
      <select
        data-testid={props.testId}
        value={props.value}
        onChange={(event) => props.onChange(event.target.value)}
        className="bg-[#0d1017] font-mono text-[11px] text-white outline-none"
      >
        {props.options.map((option) => (
          <option key={option}>{option}</option>
        ))}
      </select>
    </label>
  )
}

function PanelSection(props: { title: string; count?: number; children: ReactNode }) {
  return (
    <section className="mb-5">
      <div className="mb-2 flex items-center justify-between">
        <h3 className="font-mono text-[10px] font-bold uppercase tracking-[0.18em] text-[#70747d]">{props.title}</h3>
        {typeof props.count === "number" && <span className="font-mono text-[10px] text-[#565963]">{props.count}</span>}
      </div>
      {props.children}
    </section>
  )
}

function AgentBadge(props: { thread: ChatThread }) {
  return (
    <span className="inline-flex items-center gap-2 border border-white/[0.08] bg-white/[0.035] px-2.5 py-1.5">
      <span className="grid size-5 place-items-center bg-[#5a68ff] font-mono text-[10px] font-black text-white">{props.thread.agentKey}</span>
      <span className="font-mono text-[10px] font-bold uppercase tracking-[0.12em] text-[#d6d3cc]">{props.thread.agent}</span>
    </span>
  )
}

function StatePill(props: { state: ChatThread["status"] | FleetAgent["state"] }) {
  const Icon = STATE_ICONS[props.state]
  return (
    <span className={cn("inline-flex items-center gap-1.5 px-2 py-1 font-mono text-[10px] uppercase tracking-[0.12em]", stateClass[props.state])}>
      <Icon className="size-3" />
      {props.state}
    </span>
  )
}

function MessageStatus(props: { status: NonNullable<ChatMessage["status"]> }) {
  const icon = props.status === "complete" ? <CheckCircle2 className="size-3" /> : props.status === "blocked" ? <AlertTriangle className="size-3" /> : <Clock3 className="size-3" />
  return (
    <span className="inline-flex items-center gap-1 font-mono text-[10px] uppercase tracking-[0.12em] text-[#70747d]">
      {icon}
      {props.status}
    </span>
  )
}

function MetaRow(props: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-[52px_minmax(0,1fr)] gap-2">
      <span className="uppercase tracking-[0.12em] text-[#565963]">{props.label}</span>
      <span className="truncate text-[#d6d3cc]">{props.value}</span>
    </div>
  )
}

function TinyMetric(props: { label: string; value: string }) {
  return (
    <div className="border border-white/[0.08] bg-white/[0.025] px-3 py-2">
      <p className="font-mono text-[9px] uppercase tracking-[0.16em] text-[#565963]">{props.label}</p>
      <p className="mt-1 font-mono text-[12px] text-[#d6d3cc]">{props.value}</p>
    </div>
  )
}

function PixelMark(props: { label: string }) {
  return (
    <div className="grid size-10 grid-cols-2 grid-rows-2 gap-0.5 border border-[#5a68ff]/40 bg-[#2f43ff]/12 p-1">
      <span className="bg-[#5a68ff]" />
      <span className="bg-[#36c26b]" />
      <span className="bg-[#f0a93b]" />
      <span className="grid place-items-center bg-[#111827] font-mono text-[10px] font-black text-white">{props.label}</span>
    </div>
  )
}

function sectionLabel(section: SidebarVariant["navOrder"][number]) {
  switch (section) {
    case "new": return "Start"
    case "search": return "Search"
    case "threads": return "Recent threads"
    case "attention": return "Needs attention"
    case "fleet": return "Fleet"
    case "settings": return "Settings"
  }
}
