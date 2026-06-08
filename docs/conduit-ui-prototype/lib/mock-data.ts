export type InboxItem = {
  id: string
  agentName: string
  agentType: "claude-code" | "codex" | "custom"
  repo: string
  branch: string
  host: string
  permissionMode: "cautious" | "auto" | "bypass"
  status: "decision" | "blocked" | "running" | "done" | "failed" | "idle"
  message: string
  context?: string
  timeAgo: string
  tag?: "decision" | "proof" | "blocked" | "failed"
}

export type LoopItem = {
  id: string
  name: string
  agentName: string
  repo: string
  totalSteps: number
  currentStep: number
  status: "running" | "blocked" | "completed" | "failed"
  steps: { step: number; status: "ok" | "failed" | "blocked" | "skipped"; summary: string }[]
  startedAt: string
}

export const MOCK_INBOX: InboxItem[] = [
  {
    id: "1",
    agentName: "DeployBot",
    agentType: "custom",
    repo: "command-center",
    branch: "feat/mcp",
    host: "mac-mini-prod",
    permissionMode: "cautious",
    status: "decision",
    message: "Health check failed twice — roll back or retry?",
    context: "2 of 3 pods unhealthy after deploy. Rollback = safe, retry = faster if transient.",
    timeAgo: "now",
    tag: "decision",
  },
  {
    id: "2",
    agentName: "ClaudeCode",
    agentType: "claude-code",
    repo: "command-center",
    branch: "fix/auth",
    host: "macbook-pro",
    permissionMode: "cautious",
    status: "done",
    message: "Fixed failing login test — 2 files changed, tests passed",
    timeAgo: "2m",
    tag: "proof",
  },
  {
    id: "3",
    agentName: "ResearchBot",
    agentType: "custom",
    repo: "—",
    branch: "—",
    host: "vps-prod",
    permissionMode: "auto",
    status: "blocked",
    message: "Loop blocked — rate limited on news API (429)",
    timeAgo: "7m",
    tag: "blocked",
  },
  {
    id: "4",
    agentName: "CodexAgent",
    agentType: "codex",
    repo: "command-center",
    branch: "refactor/api",
    host: "devbox",
    permissionMode: "auto",
    status: "running",
    message: "Step 6/8 — running integration tests",
    timeAgo: "12m",
  },
  {
    id: "5",
    agentName: "DeployBot",
    agentType: "custom",
    repo: "command-center",
    branch: "main",
    host: "mac-mini-prod",
    permissionMode: "cautious",
    status: "done",
    message: "Staging deploy complete — health checks green",
    timeAgo: "34m",
    tag: "proof",
  },
  {
    id: "6",
    agentName: "ClaudeCode",
    agentType: "claude-code",
    repo: "billing-service",
    branch: "fix/invoice",
    host: "macbook-pro",
    permissionMode: "cautious",
    status: "failed",
    message: "Build failed — TypeScript error in invoice.ts:42",
    timeAgo: "1h",
    tag: "failed",
  },
]

export const MOCK_LOOPS: LoopItem[] = [
  {
    id: "loop-1",
    name: "Deploy Loop",
    agentName: "DeployBot",
    repo: "command-center",
    totalSteps: 8,
    currentStep: 5,
    status: "blocked",
    startedAt: "14:32",
    steps: [
      { step: 1, status: "ok", summary: "Build passed" },
      { step: 2, status: "ok", summary: "Unit tests: 142/142" },
      { step: 3, status: "ok", summary: "Lint passed" },
      { step: 4, status: "ok", summary: "Staging deploy" },
      { step: 5, status: "blocked", summary: "Health check: 2/3 pods unhealthy" },
    ],
  },
  {
    id: "loop-2",
    name: "Bug Fix Loop",
    agentName: "ClaudeCode",
    repo: "command-center",
    totalSteps: 6,
    currentStep: 6,
    status: "completed",
    startedAt: "13:55",
    steps: [
      { step: 1, status: "ok", summary: "Reproduce bug confirmed" },
      { step: 2, status: "ok", summary: "Root cause: token refresh race" },
      { step: 3, status: "ok", summary: "Fix applied" },
      { step: 4, status: "ok", summary: "Tests passing" },
      { step: 5, status: "ok", summary: "PR created" },
      { step: 6, status: "ok", summary: "PR approved + merged" },
    ],
  },
  {
    id: "loop-3",
    name: "Research Loop",
    agentName: "ResearchBot",
    repo: "—",
    totalSteps: 6,
    currentStep: 2,
    status: "blocked",
    startedAt: "14:01",
    steps: [
      { step: 1, status: "ok", summary: "Sources identified" },
      { step: 2, status: "blocked", summary: "Rate limited on news API" },
    ],
  },
]

export const MOCK_REPORT = {
  id: "report-1",
  agentName: "ClaudeCode",
  repo: "command-center",
  branch: "fix/auth",
  host: "macbook-pro",
  permissionMode: "cautious" as const,
  goal: "Fix failing login test after token refresh change",
  changedFiles: ["src/auth/session.ts", "tests/auth.test.ts"],
  commandsRun: ["npm test", "npm run lint", "npm run typecheck"],
  testStatus: "passed" as const,
  diffSummary: "Fixed token refresh race condition — added mutex around the refresh-token exchange to prevent two concurrent requests from both triggering a refresh.",
  risks: ["Did not manually test Safari OAuth flow", "Redis session TTL not updated"],
  unverified: ["Production OAuth provider response times", "Safari WebKit session cookie behavior"],
  recommendedNextAction: "approve_pr",
  loopId: "loop-2",
}

export const MOCK_CHECKPOINT = {
  id: "cp-1",
  agentName: "DeployBot",
  repo: "command-center",
  branch: "feat/mcp",
  host: "mac-mini-prod",
  permissionMode: "cautious" as const,
  question: "Health check failed twice. Roll back or retry?",
  context: "2 of 3 pods unhealthy after deploy. Error: ECONNREFUSED :3001. Last deploy was 4 minutes ago. Rollback takes ~90s and is safe. Retry may work if the issue is transient startup time.",
  blastRadius: {
    filesystem: "repo-only",
    network: "private-infra",
    secrets: "none",
    persistence: "deployed",
    reversibility: "easy-rollback",
    impact: "staging",
  },
  riskLevel: "high" as "low" | "medium" | "high",
}
