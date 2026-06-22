import type { LucideIcon } from "lucide-react"
import {
  Activity,
  AppWindow,
  Bell,
  Bot,
  CreditCard,
  FileDiff,
  Files,
  Inbox,
  KeyRound,
  Library,
  Lock,
  Radio,
  Server,
  Settings,
  ShieldCheck,
  Terminal,
} from "lucide-react"

export type DesignModeID = "approval" | "fleet" | "session"
export type AppTabID = "inbox" | "fleet" | "session" | "activity" | "settings"
export type SessionSurfaceID = "terminal" | "preview" | "files" | "diff" | "session-inbox"
export type ApprovalDecision = "pending" | "approved" | "approvedAlways" | "rejected"
export type RiskLevel = "low" | "medium" | "high" | "critical"

export type DesignMode = {
  id: DesignModeID
  name: string
  shortName: string
  premise: string
  homeTab: AppTabID
  tabOrder: AppTabID[]
  accent: string
}

export type AppTab = {
  id: AppTabID
  label: string
  icon: LucideIcon
}

export type SessionSurface = {
  id: SessionSurfaceID
  label: string
  icon: LucideIcon
}

export type ApprovalItem = {
  id: string
  agent: "Claude Code" | "Codex" | "OpenCode" | "DeployBot"
  agentKey: string
  kind: "command" | "mcp" | "question" | "patch"
  title: string
  command: string
  cwd: string
  host: string
  time: string
  risk: RiskLevel
  blastRadius: string[]
  decision: ApprovalDecision
  choices?: string[]
}

export type HostSlot = {
  id: string
  name: string
  address: string
  status: "connected" | "reconnecting" | "saved" | "offline"
  agents: {
    name: string
    model: string
    state: "running" | "idle" | "needs-you" | "offline"
    spend: string
  }[]
  cwd: string
}

export type ActivityItem = {
  id: string
  type: "approval" | "connect" | "test" | "preview" | "security"
  title: string
  detail: string
  time: string
  tone: "ok" | "warn" | "danger" | "info"
}

export type TerminalBlock = {
  id: string
  prompt: string
  output: string[]
  exit: 0 | 1 | null
  duration: string
}

export type FileEntry = {
  name: string
  kind: "dir" | "file"
  size: string
  touched: string
}

export type Snippet = {
  name: string
  body: string
  scope: string
}

export const DESIGN_MODES: DesignMode[] = [
  {
    id: "approval",
    name: "Approval Core",
    shortName: "Approvals",
    premise: "Inbox is the product. Every surface is optimized around fast, confident human decisions.",
    homeTab: "inbox",
    tabOrder: ["inbox", "fleet", "session", "activity", "settings"],
    accent: "#2f43ff",
  },
  {
    id: "fleet",
    name: "Fleet Control",
    shortName: "Fleet",
    premise: "The home screen is an operating map for hosts, agents, spend, status, and escalation.",
    homeTab: "fleet",
    tabOrder: ["fleet", "inbox", "activity", "session", "settings"],
    accent: "#36c26b",
  },
  {
    id: "session",
    name: "Session Cockpit",
    shortName: "Session",
    premise: "The terminal is the anchor. Diffs, files, previews, and approvals orbit the live workspace.",
    homeTab: "session",
    tabOrder: ["session", "inbox", "fleet", "activity", "settings"],
    accent: "#f0a93b",
  },
]

export const APP_TABS: Record<AppTabID, AppTab> = {
  inbox: { id: "inbox", label: "Inbox", icon: Inbox },
  fleet: { id: "fleet", label: "Fleet", icon: Server },
  session: { id: "session", label: "Session", icon: Terminal },
  activity: { id: "activity", label: "Activity", icon: Activity },
  settings: { id: "settings", label: "Settings", icon: Settings },
}

export const SESSION_SURFACES: SessionSurface[] = [
  { id: "terminal", label: "Terminal", icon: Terminal },
  { id: "preview", label: "Preview", icon: AppWindow },
  { id: "files", label: "Files", icon: Files },
  { id: "diff", label: "Diff", icon: FileDiff },
  { id: "session-inbox", label: "Inbox", icon: Inbox },
]

export const INITIAL_APPROVALS: ApprovalItem[] = [
  {
    id: "ap-1",
    agent: "Claude Code",
    agentKey: "CC",
    kind: "command",
    title: "Claude Code wants to run a command",
    command: "rm -rf ./dist && npm run build:prod",
    cwd: "/home/ubuntu/myapp",
    host: "Dev VPS",
    time: "7:47 AM",
    risk: "high",
    blastRadius: ["filesystem: repo only", "network: none", "reversibility: easy rollback"],
    decision: "pending",
  },
  {
    id: "ap-2",
    agent: "Codex",
    agentKey: "OX",
    kind: "patch",
    title: "Codex wants to apply a patch",
    command: "src/auth/session.ts + tests/auth.test.ts",
    cwd: "/Users/roshan/command-center",
    host: "This Mac",
    time: "7:45 AM",
    risk: "medium",
    blastRadius: ["files: 2 changed", "tests: 116 passing", "risk: auth flow"],
    decision: "pending",
  },
  {
    id: "ap-3",
    agent: "OpenCode",
    agentKey: "OC",
    kind: "mcp",
    title: "OpenCode wants to call a tool",
    command: "github.create_pull_request({ base: main, draft: true })",
    cwd: "/repo/lancer",
    host: "Staging",
    time: "7:39 AM",
    risk: "low",
    blastRadius: ["remote: GitHub", "visibility: draft PR", "reversible: yes"],
    decision: "approved",
  },
  {
    id: "ap-4",
    agent: "DeployBot",
    agentKey: "DB",
    kind: "question",
    title: "DeployBot needs a release decision",
    command: "Health check failed twice. Roll back or retry?",
    cwd: "/srv/lancer",
    host: "mac-mini-prod",
    time: "7:31 AM",
    risk: "critical",
    blastRadius: ["network: private infra", "impact: staging", "persistence: deployed"],
    decision: "pending",
    choices: ["Roll back", "Retry deploy", "Pause run"],
  },
]

export const HOSTS: HostSlot[] = [
  {
    id: "host-1",
    name: "Dev VPS",
    address: "ubuntu@dev.example.com:22",
    status: "connected",
    cwd: "/home/ubuntu/myapp",
    agents: [
      { name: "Claude Code", model: "sonnet 4.5", state: "needs-you", spend: "$1.42" },
      { name: "Codex", model: "gpt-5-codex", state: "running", spend: "$0.58" },
    ],
  },
  {
    id: "host-2",
    name: "This Mac",
    address: "roshansilva@127.0.0.1:22",
    status: "connected",
    cwd: "/Users/roshansilva/Documents/command-center",
    agents: [
      { name: "Codex", model: "gpt-5", state: "running", spend: "$0.31" },
      { name: "OpenCode", model: "local", state: "idle", spend: "$0.00" },
    ],
  },
  {
    id: "host-3",
    name: "Staging",
    address: "deploy@staging.example.com:22",
    status: "reconnecting",
    cwd: "/srv/lancer",
    agents: [{ name: "DeployBot", model: "custom", state: "offline", spend: "$0.09" }],
  },
  {
    id: "host-4",
    name: "Raspberry Pi",
    address: "pi@192.168.1.42:22",
    status: "saved",
    cwd: "~",
    agents: [],
  },
]

export const ACTIVITY_LOG: ActivityItem[] = [
  {
    id: "ev-1",
    type: "approval",
    title: "Approved Codex patch",
    detail: "2 files changed, 116 tests passing, draft PR ready",
    time: "now",
    tone: "ok",
  },
  {
    id: "ev-2",
    type: "connect",
    title: "Dev VPS reconnected",
    detail: "Wi-Fi to cellular handoff recovered through tmux attach",
    time: "2m",
    tone: "info",
  },
  {
    id: "ev-3",
    type: "test",
    title: "npm run test completed",
    detail: "116 passed, 0 failed, 0 skipped",
    time: "5m",
    tone: "ok",
  },
  {
    id: "ev-4",
    type: "preview",
    title: "Preview detected localhost:3000",
    detail: "Remote app available through SSH proxy",
    time: "8m",
    tone: "info",
  },
  {
    id: "ev-5",
    type: "security",
    title: "High-risk command paused",
    detail: "rm -rf ./dist && npm run build:prod",
    time: "13m",
    tone: "warn",
  },
]

export const INITIAL_BLOCKS: TerminalBlock[] = [
  {
    id: "b-1",
    prompt: "git status --short",
    output: [
      " M Packages/LancerKit/Sources/AppFeature/AppRoot.swift",
      " M Packages/LancerKit/Sources/InboxFeature/InboxView.swift",
      "?? docs/lancer-ui-prototype/app/interactive/",
    ],
    exit: 0,
    duration: "0.12s",
  },
  {
    id: "b-2",
    prompt: "npm run test",
    output: ["PASS src/auth.test.ts", "PASS src/approval.test.ts", "116 tests passed"],
    exit: 0,
    duration: "18.4s",
  },
]

export const FILES: FileEntry[] = [
  { name: "Packages", kind: "dir", size: "12 items", touched: "2m" },
  { name: "Lancer", kind: "dir", size: "9 items", touched: "8m" },
  { name: "docs", kind: "dir", size: "57 items", touched: "now" },
  { name: "project.yml", kind: "file", size: "10.5 KB", touched: "16m" },
  { name: "ARCHITECTURE.md", kind: "file", size: "48.6 KB", touched: "1h" },
]

export const SNIPPETS: Snippet[] = [
  { name: "Run tests", body: "cd Packages/LancerKit && swift test", scope: "repo" },
  { name: "Restart daemon", body: "sudo systemctl restart lancerd", scope: "host" },
  { name: "Preview ports", body: "lsof -iTCP -sTCP:LISTEN -n -P", scope: "session" },
]

export const LIBRARY_CARDS = [
  { label: "Snippets", count: "12", icon: Library, detail: "Reusable terminal actions" },
  { label: "SSH Keys", count: "3", icon: KeyRound, detail: "Secure Enclave backed" },
  { label: "Agents", count: "4", icon: Bot, detail: "Claude, Codex, OpenCode" },
  { label: "Billing", count: "$2.40", icon: CreditCard, detail: "Today across hosts" },
]

export const SETTINGS_GROUPS = [
  { label: "Security", icon: Lock, items: ["Face ID app lock", "Redact saved output", "Audit export"] },
  { label: "Approvals", icon: ShieldCheck, items: ["Always ask", "Allow exact repeat", "Blast radius rules"] },
  { label: "Notifications", icon: Bell, items: ["Push approvals", "Live Activity", "Watch sync"] },
  { label: "Bridge", icon: Radio, items: ["lancerd status", "Relay token", "Device registration"] },
]

export const FEATURE_MAP = [
  "Approvals",
  "Fleet",
  "Activity",
  "Terminal",
  "Preview",
  "Files",
  "Diff",
  "Snippets",
  "Keys",
  "Billing",
  "Watch",
  "Live Activity",
]

export const DIFF_LINES = [
  { kind: "meta", text: "--- a/src/auth/session.ts" },
  { kind: "meta", text: "+++ b/src/auth/session.ts" },
  { kind: "hunk", text: "@@ -42,7 +42,11 @@" },
  { kind: "del", text: "- const token = await refreshToken()" },
  { kind: "add", text: "+ const token = await refreshLock.runExclusive(refreshToken)" },
  { kind: "ctx", text: "  session.update(token)" },
  { kind: "add", text: "+ audit.record('token-refresh', session.id)" },
]

export function statusTone(status: HostSlot["status"] | HostSlot["agents"][number]["state"]) {
  switch (status) {
    case "connected":
    case "running":
      return "ok"
    case "reconnecting":
    case "needs-you":
      return "warn"
    case "offline":
      return "danger"
    default:
      return "off"
  }
}
