import type { LucideIcon } from "lucide-react"
import {
  AlertTriangle,
  Bot,
  CheckCircle2,
  Clock3,
  Code2,
  FileDiff,
  Files,
  Gauge,
  History,
  Inbox,
  MessageSquarePlus,
  PlayCircle,
  Search,
  Server,
  Settings,
  ShieldCheck,
  Square,
} from "lucide-react"

export type SidebarVariantID = "chat" | "attention" | "fleet"

export type ChatArtifactKind = "diff" | "files" | "tests" | "approval" | "preview"

export type ChatArtifact = {
  id: string
  kind: ChatArtifactKind
  label: string
  detail: string
  tone: "blue" | "green" | "amber" | "red" | "neutral"
}

export type ChatMessage = {
  id: string
  role: "user" | "assistant" | "system"
  body: string
  time: string
  status?: "streaming" | "blocked" | "complete"
  artifacts?: ChatArtifact[]
}

export type ChatThread = {
  id: string
  title: string
  agent: "Claude Code" | "Codex" | "OpenCode" | "Kimi"
  agentKey: string
  host: string
  cwd: string
  model: string
  budget: string
  status: "running" | "needs-you" | "done" | "paused"
  lastActive: string
  summary: string
  messages: ChatMessage[]
}

export type AttentionItem = {
  id: string
  threadId: string
  title: string
  detail: string
  risk: "low" | "medium" | "high" | "critical"
  action: string
  state: "pending" | "approved" | "rejected"
}

export type FleetAgent = {
  id: string
  threadId: string
  host: string
  agent: string
  cwd: string
  model: string
  state: "running" | "needs-you" | "idle" | "offline"
  spend: string
  branch: string
}

export type SidebarVariant = {
  id: SidebarVariantID
  label: string
  shortLabel: string
  premise: string
  primaryIcon: LucideIcon
  navOrder: Array<"new" | "search" | "threads" | "attention" | "fleet" | "settings">
}

export const SIDEBAR_VARIANTS: SidebarVariant[] = [
  {
    id: "chat",
    label: "A. Chat-first",
    shortLabel: "Chat",
    premise: "Start in the conversation. History, search, approvals, and fleet are supporting rails.",
    primaryIcon: MessageSquarePlus,
    navOrder: ["new", "search", "threads", "attention", "fleet", "settings"],
  },
  {
    id: "attention",
    label: "B. Attention-first",
    shortLabel: "Attention",
    premise: "Lead with what needs a human, then resolve decisions inside the related chat thread.",
    primaryIcon: Inbox,
    navOrder: ["attention", "new", "search", "threads", "fleet", "settings"],
  },
  {
    id: "fleet",
    label: "C. Fleet-first",
    shortLabel: "Fleet",
    premise: "Group by host and agent first, but opening an agent still lands in its chat thread.",
    primaryIcon: Server,
    navOrder: ["fleet", "new", "search", "threads", "attention", "settings"],
  },
]

export const THREADS: ChatThread[] = [
  {
    id: "thread-release",
    title: "Ship sidebar chat prototype",
    agent: "Codex",
    agentKey: "CX",
    host: "This Mac",
    cwd: "/Users/roshansilva/Documents/command-center",
    model: "gpt-5-codex",
    budget: "$4 cap",
    status: "running",
    lastActive: "now",
    summary: "Converting the prototype from tab-first to sidebar-first, with searchable history and artifacts.",
    messages: [
      {
        id: "m1",
        role: "user",
        body: "Turn the prototype into a sidebar-first chat app and compare three broad layouts.",
        time: "9:32",
      },
      {
        id: "m2",
        role: "assistant",
        body: "I found the old prototype still compares Approval, Fleet, and Session modes. I am replacing that with chat-first, attention-first, and fleet-first sidebars while keeping the same dark Conduit design language.",
        time: "9:33",
        status: "complete",
        artifacts: [
          { id: "diff", kind: "diff", label: "Diff", detail: "3 files changed", tone: "blue" },
          { id: "tests", kind: "tests", label: "Tests", detail: "lint/build/e2e planned", tone: "green" },
        ],
      },
      {
        id: "m3",
        role: "assistant",
        body: "Waiting on a high-risk file rewrite approval before I update the interactive route.",
        time: "9:36",
        status: "blocked",
        artifacts: [
          { id: "approval", kind: "approval", label: "Approval", detail: "Rewrite prototype route", tone: "amber" },
        ],
      },
    ],
  },
  {
    id: "thread-followup",
    title: "Continue Claude session from phone",
    agent: "Claude Code",
    agentKey: "CC",
    host: "Dev VPS",
    cwd: "/home/ubuntu/conduit",
    model: "sonnet 4.5",
    budget: "$8 cap",
    status: "needs-you",
    lastActive: "2m",
    summary: "Follow-up run started with a new runId; the user needs to approve a build command.",
    messages: [
      {
        id: "m1",
        role: "user",
        body: "Do a second pass and check Codex and Kimi behavior while you are at it.",
        time: "8:54",
      },
      {
        id: "m2",
        role: "assistant",
        body: "Claude and opencode continue paths are wired. Codex is guarded behind an unsupported response until the headless continue smoke check is done.",
        time: "8:57",
        status: "complete",
        artifacts: [
          { id: "files", kind: "files", label: "Files", detail: "dispatch.go, AppRoot.swift", tone: "neutral" },
        ],
      },
    ],
  },
  {
    id: "thread-diff",
    title: "Review mobile diff flow",
    agent: "OpenCode",
    agentKey: "OC",
    host: "Staging",
    cwd: "/srv/conduit",
    model: "deepseek-v4-flash",
    budget: "no cap",
    status: "done",
    lastActive: "18m",
    summary: "Unified diff review is ready for a phone-sized approval pass.",
    messages: [
      {
        id: "m1",
        role: "user",
        body: "Show the changed files before approval and make it readable on a phone.",
        time: "8:12",
      },
      {
        id: "m2",
        role: "assistant",
        body: "The side-by-side diff was replaced by a single-column unified diff with file chips and an approve-and-continue action.",
        time: "8:18",
        status: "complete",
        artifacts: [
          { id: "diff", kind: "diff", label: "Diff", detail: "auth/session.ts + tests", tone: "blue" },
          { id: "preview", kind: "preview", label: "Preview", detail: "localhost:3000", tone: "green" },
        ],
      },
    ],
  },
]

export const ATTENTION_ITEMS: AttentionItem[] = [
  {
    id: "att-approval",
    threadId: "thread-release",
    title: "Approve prototype route rewrite",
    detail: "Codex wants to replace the old interactive mode comparison.",
    risk: "high",
    action: "Approve rewrite",
    state: "pending",
  },
  {
    id: "att-build",
    threadId: "thread-followup",
    title: "Run app-target build",
    detail: "Claude needs permission to launch the simulator build verification.",
    risk: "medium",
    action: "Approve build",
    state: "pending",
  },
]

export const FLEET_AGENTS: FleetAgent[] = [
  {
    id: "fleet-mac-codex",
    threadId: "thread-release",
    host: "This Mac",
    agent: "Codex",
    cwd: "/Users/roshansilva/Documents/command-center",
    model: "gpt-5-codex",
    state: "running",
    spend: "$1.18",
    branch: "opencode/onboarding-redesign",
  },
  {
    id: "fleet-vps-claude",
    threadId: "thread-followup",
    host: "Dev VPS",
    agent: "Claude Code",
    cwd: "/home/ubuntu/conduit",
    model: "sonnet 4.5",
    state: "needs-you",
    spend: "$2.47",
    branch: "resume-followup-mvp",
  },
  {
    id: "fleet-staging-opencode",
    threadId: "thread-diff",
    host: "Staging",
    agent: "OpenCode",
    cwd: "/srv/conduit",
    model: "deepseek-v4-flash",
    state: "idle",
    spend: "$0.31",
    branch: "mobile-diff-review",
  },
]

export const NAV_ICONS: Record<SidebarVariant["navOrder"][number], LucideIcon> = {
  new: MessageSquarePlus,
  search: Search,
  threads: History,
  attention: Inbox,
  fleet: Server,
  settings: Settings,
}

export const ARTIFACT_ICONS: Record<ChatArtifactKind, LucideIcon> = {
  diff: FileDiff,
  files: Files,
  tests: CheckCircle2,
  approval: ShieldCheck,
  preview: PlayCircle,
}

export const STATE_ICONS = {
  running: Clock3,
  "needs-you": AlertTriangle,
  done: CheckCircle2,
  paused: Square,
  idle: Gauge,
  offline: Server,
} as const

export const CHAT_CONTEXT = [
  { label: "History", value: "3 saved threads", icon: History },
  { label: "Search", value: "messages + artifacts", icon: Search },
  { label: "Continue", value: "new runId per turn", icon: Bot },
  { label: "Artifacts", value: "diffs, files, tests", icon: Code2 },
  { label: "Governance", value: "Inbox decisions inline", icon: ShieldCheck },
  { label: "Fleet", value: "host + spend context", icon: Server },
]

export const DIFF_PREVIEW_LINES = [
  { kind: "meta", text: "app/interactive/page.tsx" },
  { kind: "del", text: "- DESIGN_MODES: Approval Core / Fleet Control / Session Cockpit" },
  { kind: "add", text: "+ SIDEBAR_VARIANTS: Chat-first / Attention-first / Fleet-first" },
  { kind: "add", text: "+ Searchable thread history, continuation, artifacts, inline approvals" },
]

export const FILE_PREVIEW = [
  "lib/sidebar-chat-data.ts",
  "app/interactive/page.tsx",
  "tests/sidebar-chat.spec.ts",
  "playwright.config.ts",
]
