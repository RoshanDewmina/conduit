# Lancer UI Prototype — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **⚠️ BRAINSTORMING PROTOCOL — READ BEFORE STARTING:**
> This plan has mandatory PAUSE tasks (Tasks 5, 8, 10, 12). At each pause you MUST:
> 1. Take screenshots of all variants built so far
> 2. Show them to the user with `SendUserFile`
> 3. Ask for feedback before proceeding
> 4. Iterate on any screen the user wants changed
> 5. Only continue to the next section after explicit user approval
>
> The purpose of this prototype is to make design decisions BEFORE writing iOS Swift code.
> Building it all then showing it at the end defeats the purpose.

**Goal:** Build an interactive Next.js web prototype at `docs/lancer-ui-prototype/` showing 3 design variants of the Agent Inbox and 2 variants each of Checkpoint/Ask, Loop Progress, and Report Card — so the user can give feedback on UI direction before any iOS implementation begins.

**Architecture:** Standalone Next.js 15 (App Router) in `docs/lancer-ui-prototype/`. All screens are server components with a `PhoneFrame` wrapper that simulates iOS dimensions (390×844). A top `VariantNav` lets you switch between variants without reloading. All data is mocked in `lib/mock-data.ts`. No backend needed.

**Tech Stack:** Next.js 15 (App Router), shadcn/ui (nova preset), Tailwind CSS v4, Lucide React, Geist font (via `next/font/google`).

**Aesthetic Direction — "Terminal Glass":**
- Background: `#050810` (near black with a blue tint)
- Cards: `bg-white/[0.03]` with `backdrop-blur-sm` and `border border-white/[0.06]`
- Accent: `#3b82f6` electric blue; status: red/amber/green
- Typography: Geist Sans for UI text, Geist Mono for agent IDs/code
- Animations: subtle `animate-pulse` on active states, `transition-all` on interactions
- No gradients on white. No purple. No rounded-2xl everything — mix radii intentionally.

---

## File Structure

| File | Responsibility |
|---|---|
| `docs/lancer-ui-prototype/package.json` | Next.js 15 app config |
| `docs/lancer-ui-prototype/app/layout.tsx` | Root layout with Geist font + dark body |
| `docs/lancer-ui-prototype/app/globals.css` | shadcn CSS vars, custom design tokens |
| `docs/lancer-ui-prototype/app/page.tsx` | Variant selector home — visual nav to all screens |
| `docs/lancer-ui-prototype/app/inbox/[variant]/page.tsx` | Inbox variants A, B, C |
| `docs/lancer-ui-prototype/app/checkpoint/[variant]/page.tsx` | Checkpoint variants A, B |
| `docs/lancer-ui-prototype/app/loop/[variant]/page.tsx` | Loop progress variants A, B |
| `docs/lancer-ui-prototype/app/report/[variant]/page.tsx` | Report card variants A, B |
| `docs/lancer-ui-prototype/components/phone-frame.tsx` | CSS iOS phone mockup (390×844) |
| `docs/lancer-ui-prototype/components/variant-nav.tsx` | Top bar with variant switcher |
| `docs/lancer-ui-prototype/components/status-dot.tsx` | Animated status indicator |
| `docs/lancer-ui-prototype/lib/mock-data.ts` | Shared fake inbox/loop/report data |

---

## Task 1: Scaffold Next.js + shadcn

**Files:**
- Create: `docs/lancer-ui-prototype/` (entire Next.js app)

- [ ] **Step 1: Scaffold the Next.js app**

```bash
cd docs
npx create-next-app@latest lancer-ui-prototype \
  --typescript --tailwind --eslint --app \
  --no-src-dir --import-alias "@/*"
cd lancer-ui-prototype
```

- [ ] **Step 2: Init shadcn with nova preset**

```bash
npx shadcn@latest init --preset base-nova --defaults
```

When prompted for style: select **Nova**. When prompted for base color: **Zinc** or **Slate** (darkest option).

- [ ] **Step 3: Add required shadcn components**

```bash
npx shadcn@latest add badge card separator sheet progress avatar button scroll-area
```

- [ ] **Step 4: Add Geist fonts and update layout**

Replace `docs/lancer-ui-prototype/app/layout.tsx`:

```tsx
import type { Metadata } from "next"
import { GeistSans } from "geist/font/sans"
import { GeistMono } from "geist/font/mono"
import "./globals.css"

export const metadata: Metadata = {
  title: "Lancer UI Prototype",
  description: "Design variants for review",
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${GeistSans.variable} ${GeistMono.variable} bg-[#050810] text-white antialiased`}
        style={{ fontFamily: "var(--font-geist-sans)" }}
      >
        {children}
      </body>
    </html>
  )
}
```

Install geist:

```bash
npm install geist
```

- [ ] **Step 5: Add design tokens to globals.css**

Append to `docs/lancer-ui-prototype/app/globals.css`:

```css
:root {
  --lancer-bg: #050810;
  --lancer-surface: rgba(255, 255, 255, 0.03);
  --lancer-border: rgba(255, 255, 255, 0.06);
  --lancer-blue: #3b82f6;
  --lancer-green: #4ade80;
  --lancer-amber: #fbbf24;
  --lancer-red: #f87171;
  --lancer-muted: #6b7280;
  --lancer-mono: var(--font-geist-mono, monospace);
}

.phone-glow {
  box-shadow: 0 0 0 1px rgba(59, 130, 246, 0.1),
              0 40px 80px rgba(0, 0, 0, 0.8),
              inset 0 1px 0 rgba(255, 255, 255, 0.04);
}
```

- [ ] **Step 6: Verify it runs**

```bash
npm run dev
```

Open `http://localhost:3000`. Expected: Next.js default page loads with dark background.

- [ ] **Step 7: Commit**

```bash
git add docs/lancer-ui-prototype
git commit -m "feat(prototype): scaffold Next.js + shadcn nova for UI prototype"
```

---

## Task 2: PhoneFrame + MockData + VariantNav

**Files:**
- Create: `docs/lancer-ui-prototype/components/phone-frame.tsx`
- Create: `docs/lancer-ui-prototype/components/variant-nav.tsx`
- Create: `docs/lancer-ui-prototype/components/status-dot.tsx`
- Create: `docs/lancer-ui-prototype/lib/mock-data.ts`

- [ ] **Step 1: Create PhoneFrame component**

Create `docs/lancer-ui-prototype/components/phone-frame.tsx`:

```tsx
import { cn } from "@/lib/utils"

interface PhoneFrameProps {
  children: React.ReactNode
  className?: string
  label?: string
}

export function PhoneFrame({ children, className, label }: PhoneFrameProps) {
  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className={cn(
          "relative w-[390px] rounded-[44px] phone-glow",
          "bg-[#0a0e16] border border-white/10",
          "overflow-hidden",
          className
        )}
        style={{ height: "844px" }}
      >
        {/* Notch */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-28 h-7 bg-[#0a0e16] rounded-b-2xl border-x border-b border-white/10 z-10" />

        {/* Status bar */}
        <div className="flex justify-between items-center px-8 pt-3 pb-1 text-[11px] text-white/40 relative z-10">
          <span style={{ fontFamily: "var(--font-geist-mono)" }}>9:41</span>
          <div className="flex gap-1 items-center">
            <span>●●●</span>
            <span>▲</span>
            <span>⬛</span>
          </div>
        </div>

        {/* Screen content */}
        <div className="h-full overflow-hidden">{children}</div>

        {/* Home indicator */}
        <div className="absolute bottom-2 left-1/2 -translate-x-1/2 w-32 h-1 bg-white/20 rounded-full" />
      </div>
      {label && (
        <span
          className="text-xs text-white/40"
          style={{ fontFamily: "var(--font-geist-mono)" }}
        >
          {label}
        </span>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Create StatusDot component**

Create `docs/lancer-ui-prototype/components/status-dot.tsx`:

```tsx
import { cn } from "@/lib/utils"

type Status = "decision" | "blocked" | "running" | "done" | "failed" | "idle"

const statusConfig: Record<Status, { color: string; pulse: boolean }> = {
  decision: { color: "bg-[var(--lancer-red)]", pulse: true },
  blocked: { color: "bg-[var(--lancer-amber)]", pulse: true },
  running: { color: "bg-[var(--lancer-blue)]", pulse: true },
  done: { color: "bg-[var(--lancer-green)]", pulse: false },
  failed: { color: "bg-[var(--lancer-red)]", pulse: false },
  idle: { color: "bg-white/20", pulse: false },
}

export function StatusDot({ status }: { status: Status }) {
  const { color, pulse } = statusConfig[status]
  return (
    <span className="relative flex size-2">
      {pulse && (
        <span
          className={cn("animate-ping absolute inline-flex size-full rounded-full opacity-75", color)}
        />
      )}
      <span className={cn("relative inline-flex rounded-full size-2", color)} />
    </span>
  )
}
```

- [ ] **Step 3: Create VariantNav**

Create `docs/lancer-ui-prototype/components/variant-nav.tsx`:

```tsx
"use client"
import Link from "next/link"
import { usePathname } from "next/navigation"
import { cn } from "@/lib/utils"

const SCREENS = [
  {
    label: "Inbox",
    variants: [
      { label: "A — Ops Center", href: "/inbox/a" },
      { label: "B — Feed", href: "/inbox/b" },
      { label: "C — Dashboard", href: "/inbox/c" },
    ],
  },
  {
    label: "Checkpoint",
    variants: [
      { label: "A — Risk Card", href: "/checkpoint/a" },
      { label: "B — Sheet", href: "/checkpoint/b" },
    ],
  },
  {
    label: "Loop",
    variants: [
      { label: "A — Timeline", href: "/loop/a" },
      { label: "B — Gauge", href: "/loop/b" },
    ],
  },
  {
    label: "Report",
    variants: [
      { label: "A — Audit", href: "/report/a" },
      { label: "B — Summary", href: "/report/b" },
    ],
  },
]

export function VariantNav() {
  const path = usePathname()
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-white/[0.06] bg-[#050810]/90 backdrop-blur-sm">
      <div className="max-w-7xl mx-auto px-6 py-3 flex items-center gap-6 overflow-x-auto">
        <Link href="/" className="text-sm font-bold text-white/90 shrink-0">
          ⬡ Lancer
        </Link>
        <div className="flex gap-1 flex-wrap">
          {SCREENS.map((screen) =>
            screen.variants.map((v) => (
              <Link
                key={v.href}
                href={v.href}
                className={cn(
                  "px-3 py-1 rounded-md text-xs whitespace-nowrap transition-all",
                  path === v.href
                    ? "bg-blue-500/20 text-blue-400 border border-blue-500/30"
                    : "text-white/40 hover:text-white/70 hover:bg-white/5"
                )}
              >
                {screen.label} {v.label}
              </Link>
            ))
          )}
        </div>
      </div>
    </nav>
  )
}
```

- [ ] **Step 4: Create mock data**

Create `docs/lancer-ui-prototype/lib/mock-data.ts`:

```ts
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
```

- [ ] **Step 5: Verify build**

```bash
npm run build 2>&1 | tail -5
```

Expected: `✓ Compiled successfully` with no TypeScript errors.

- [ ] **Step 6: Commit**

```bash
git add docs/lancer-ui-prototype
git commit -m "feat(prototype): PhoneFrame, VariantNav, StatusDot, mock data"
```

---

## Task 3: Home Page — Variant Selector

**Files:**
- Create: `docs/lancer-ui-prototype/app/page.tsx`
- Create: `docs/lancer-ui-prototype/app/inbox/[variant]/layout.tsx` (shared layout with nav)

- [ ] **Step 1: Create shared screen layout**

Create `docs/lancer-ui-prototype/app/inbox/[variant]/layout.tsx`:

```tsx
import { VariantNav } from "@/components/variant-nav"

export default function ScreenLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <VariantNav />
      <main className="pt-14 min-h-screen flex items-center justify-center bg-[#050810]">
        {children}
      </main>
    </>
  )
}
```

Create the same layout for each screen group. Run:

```bash
mkdir -p app/inbox/a app/inbox/b app/inbox/c
mkdir -p app/checkpoint/a app/checkpoint/b
mkdir -p app/loop/a app/loop/b
mkdir -p app/report/a app/report/b
```

Copy the layout file to `app/checkpoint/[variant]/layout.tsx`, `app/loop/[variant]/layout.tsx`, `app/report/[variant]/layout.tsx` — they are all identical.

- [ ] **Step 2: Create home page**

Replace `docs/lancer-ui-prototype/app/page.tsx`:

```tsx
import Link from "next/link"

const SECTIONS = [
  {
    title: "Agent Inbox",
    description: "How the main notification list looks and feels",
    variants: [
      { label: "A — Ops Center", sub: "Dense linear list, max information density", href: "/inbox/a" },
      { label: "B — Feed", sub: "Spacious cards with rich preview content", href: "/inbox/b" },
      { label: "C — Dashboard", sub: "Split pane: fleet list + agent event timeline", href: "/inbox/c" },
    ],
  },
  {
    title: "Checkpoint / Ask",
    description: "When an agent needs a human decision",
    variants: [
      { label: "A — Risk Card", sub: "Full-screen with blast-radius meter", href: "/checkpoint/a" },
      { label: "B — Sheet", sub: "Bottom sheet with context + quick actions", href: "/checkpoint/b" },
    ],
  },
  {
    title: "Loop Progress",
    description: "Multi-step loop status while running",
    variants: [
      { label: "A — Timeline", sub: "Vertical step list with status icons", href: "/loop/a" },
      { label: "B — Gauge", sub: "Circular progress + compact step log", href: "/loop/b" },
    ],
  },
  {
    title: "Report Card",
    description: "Structured completion card shown when a task finishes",
    variants: [
      { label: "A — Audit", sub: "Technical: diff view, file list, test output", href: "/report/a" },
      { label: "B — Summary", sub: "Clean: goal + stats + expandable risks", href: "/report/b" },
    ],
  },
]

export default function Home() {
  return (
    <main className="min-h-screen bg-[#050810] px-8 py-16">
      <div className="max-w-3xl mx-auto">
        <div className="mb-12">
          <p
            className="text-xs tracking-widest text-blue-400 mb-3 uppercase"
            style={{ fontFamily: "var(--font-geist-mono)" }}
          >
            Design Prototype
          </p>
          <h1 className="text-4xl font-bold text-white mb-3">Lancer UI</h1>
          <p className="text-white/50 text-base">
            Review these variants and give feedback before we write Swift code.
            Each screen has 2–3 distinct design directions.
          </p>
        </div>

        <div className="flex flex-col gap-10">
          {SECTIONS.map((section) => (
            <div key={section.title}>
              <div className="mb-4">
                <h2 className="text-sm font-semibold text-white/80">{section.title}</h2>
                <p className="text-xs text-white/40 mt-0.5">{section.description}</p>
              </div>
              <div className="grid grid-cols-1 gap-2">
                {section.variants.map((v) => (
                  <Link
                    key={v.href}
                    href={v.href}
                    className="group flex items-center justify-between px-4 py-3 rounded-xl border border-white/[0.06] bg-white/[0.02] hover:bg-white/[0.05] hover:border-blue-500/30 transition-all"
                  >
                    <div>
                      <span className="text-sm font-medium text-white/90 group-hover:text-white">
                        {v.label}
                      </span>
                      <p className="text-xs text-white/40 mt-0.5">{v.sub}</p>
                    </div>
                    <span className="text-white/20 group-hover:text-blue-400 transition-colors text-sm">→</span>
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </main>
  )
}
```

- [ ] **Step 3: Verify home page loads**

```bash
npm run dev
```

Open `http://localhost:3000`. Expected: a clean dark home page listing all variant links.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat(prototype): home page variant selector"
```

---

## Task 4: Inbox Variants A, B, C

**Files:**
- Create: `docs/lancer-ui-prototype/app/inbox/a/page.tsx` (Ops Center — dense list)
- Create: `docs/lancer-ui-prototype/app/inbox/b/page.tsx` (Feed — rich cards)
- Create: `docs/lancer-ui-prototype/app/inbox/c/page.tsx` (Dashboard — split pane)

- [ ] **Step 1: Create Inbox Variant A — Ops Center**

Create `docs/lancer-ui-prototype/app/inbox/a/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { Badge } from "@/components/ui/badge"
import { MOCK_INBOX } from "@/lib/mock-data"

const TAG_STYLES = {
  decision: "border-red-500/30 bg-red-500/10 text-red-400",
  proof: "border-green-500/30 bg-green-500/10 text-green-400",
  blocked: "border-amber-500/30 bg-amber-500/10 text-amber-400",
  failed: "border-red-500/30 bg-red-900/20 text-red-300",
}

export default function InboxVariantA() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Ops Center</h2>
        <p className="text-xs text-white/40 mt-1">Dense linear list — maximum information per row</p>
      </div>

      <PhoneFrame label="inbox/a — ops center">
        <div className="flex flex-col h-full bg-[#050810]">
          {/* Header */}
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <div className="flex items-center justify-between">
              <h1 className="text-[15px] font-bold text-white">Inbox</h1>
              <span className="text-[11px] font-mono text-white/40">3 pending</span>
            </div>
          </div>

          {/* Item list */}
          <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
            {MOCK_INBOX.map((item) => (
              <div
                key={item.id}
                className="flex gap-3 px-4 py-3 hover:bg-white/[0.02] transition-colors"
              >
                {/* Left gutter: status color bar */}
                <div className="flex flex-col items-center gap-1.5 pt-1">
                  <StatusDot status={item.status} />
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 mb-0.5">
                    <span
                      className="text-[11px] font-semibold text-blue-400 truncate"
                      style={{ fontFamily: "var(--font-geist-mono)" }}
                    >
                      {item.agentName}
                    </span>
                    <span className="text-[10px] text-white/30 font-mono truncate">
                      {item.repo}/{item.branch}
                    </span>
                  </div>
                  <p className="text-[12px] text-white/80 leading-snug line-clamp-2">
                    {item.message}
                  </p>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-white/30 font-mono">{item.timeAgo}</span>
                    {item.tag && (
                      <span
                        className={`text-[9px] px-1.5 py-0.5 rounded border ${TAG_STYLES[item.tag]}`}
                      >
                        {item.tag}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Tab bar */}
          <div className="border-t border-white/[0.06] px-4 py-3 flex justify-around">
            {["Inbox", "Fleet", "Settings"].map((tab) => (
              <span
                key={tab}
                className={`text-[11px] ${tab === "Inbox" ? "text-blue-400" : "text-white/30"}`}
              >
                {tab}
              </span>
            ))}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 2: Create Inbox Variant B — Feed**

Create `docs/lancer-ui-prototype/app/inbox/b/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX } from "@/lib/mock-data"

const TAG_COLORS = {
  decision: { bg: "bg-red-500/10", text: "text-red-400", border: "border-red-500/20" },
  proof: { bg: "bg-green-500/10", text: "text-green-400", border: "border-green-500/20" },
  blocked: { bg: "bg-amber-500/10", text: "text-amber-400", border: "border-amber-500/20" },
  failed: { bg: "bg-red-900/20", text: "text-red-300", border: "border-red-500/10" },
}

export default function InboxVariantB() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Feed</h2>
        <p className="text-xs text-white/40 mt-1">Rich cards with context preview — spacious</p>
      </div>

      <PhoneFrame label="inbox/b — feed">
        <div className="flex flex-col h-full bg-[#070b12]">
          {/* Header */}
          <div className="px-5 pt-3 pb-3">
            <div className="flex items-center justify-between mb-1">
              <h1 className="text-[17px] font-bold text-white">Agent Inbox</h1>
              <div className="size-7 rounded-full bg-blue-500/20 border border-blue-500/30 flex items-center justify-center">
                <span className="text-[11px] font-mono text-blue-400">3</span>
              </div>
            </div>
            <p className="text-[11px] text-white/30">3 need attention</p>
          </div>

          {/* Cards */}
          <div className="flex-1 overflow-y-auto px-4 flex flex-col gap-3 pb-20">
            {MOCK_INBOX.map((item) => (
              <div
                key={item.id}
                className="rounded-2xl border border-white/[0.06] bg-white/[0.03] overflow-hidden"
              >
                {/* Card header */}
                <div className="px-4 pt-3 pb-2 border-b border-white/[0.04] flex items-center gap-2">
                  <StatusDot status={item.status} />
                  <div className="flex-1 min-w-0">
                    <span
                      className="text-[11px] font-semibold text-blue-300"
                      style={{ fontFamily: "var(--font-geist-mono)" }}
                    >
                      {item.agentName}
                    </span>
                    <span className="text-[10px] text-white/30 font-mono ml-2">
                      {item.repo}
                    </span>
                  </div>
                  <span className="text-[10px] text-white/30 font-mono shrink-0">{item.timeAgo}</span>
                </div>

                {/* Card body */}
                <div className="px-4 py-3">
                  <p className="text-[13px] text-white/90 leading-relaxed font-medium">
                    {item.message}
                  </p>
                  {item.context && (
                    <p className="text-[11px] text-white/40 mt-2 leading-relaxed line-clamp-2">
                      {item.context}
                    </p>
                  )}
                </div>

                {/* Card footer */}
                {item.tag && (
                  <div className="px-4 pb-3 flex gap-2">
                    {item.tag === "decision" && (
                      <>
                        <button className="flex-1 py-2 rounded-xl text-[12px] font-semibold bg-green-500/10 text-green-400 border border-green-500/20 hover:bg-green-500/20 transition-colors">
                          Approve
                        </button>
                        <button className="flex-1 py-2 rounded-xl text-[12px] font-semibold bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 transition-colors">
                          Deny
                        </button>
                      </>
                    )}
                    {item.tag === "proof" && (
                      <button className="flex-1 py-2 rounded-xl text-[12px] font-semibold bg-blue-500/10 text-blue-400 border border-blue-500/20 hover:bg-blue-500/20 transition-colors">
                        Review Report →
                      </button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Tab bar */}
          <div className="absolute bottom-0 left-0 right-0 border-t border-white/[0.06] bg-[#070b12]/95 backdrop-blur-sm px-6 py-3 flex justify-around">
            {["Inbox", "Fleet", "Settings"].map((tab) => (
              <span key={tab} className={`text-[11px] ${tab === "Inbox" ? "text-blue-400" : "text-white/30"}`}>
                {tab}
              </span>
            ))}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 3: Create Inbox Variant C — Dashboard**

Create `docs/lancer-ui-prototype/app/inbox/c/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_INBOX, MOCK_LOOPS } from "@/lib/mock-data"

const AGENTS = [
  { name: "DeployBot", status: "blocked" as const, events: 2, model: "custom" },
  { name: "ClaudeCode", status: "done" as const, events: 1, model: "claude-code" },
  { name: "ResearchBot", status: "blocked" as const, events: 1, model: "custom" },
  { name: "CodexAgent", status: "running" as const, events: 0, model: "codex" },
]

export default function InboxVariantC() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant C</p>
        <h2 className="text-lg font-bold text-white">Dashboard</h2>
        <p className="text-xs text-white/40 mt-1">Fleet list + selected agent events — two-column</p>
      </div>

      <PhoneFrame label="inbox/c — dashboard">
        <div className="flex h-full bg-[#050810]">
          {/* Left: Agent fleet column */}
          <div className="w-[120px] shrink-0 border-r border-white/[0.06] flex flex-col">
            <div className="px-3 pt-3 pb-2 border-b border-white/[0.04]">
              <span className="text-[10px] font-mono text-white/30 uppercase tracking-wide">Fleet</span>
            </div>
            <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
              {AGENTS.map((agent, i) => (
                <div
                  key={agent.name}
                  className={`px-3 py-3 flex flex-col gap-1 cursor-pointer transition-colors ${
                    i === 0 ? "bg-blue-500/10 border-l-2 border-blue-500" : "hover:bg-white/[0.02]"
                  }`}
                >
                  <div className="flex items-center gap-1.5">
                    <StatusDot status={agent.status} />
                    {agent.events > 0 && (
                      <span className="ml-auto text-[9px] bg-red-500 text-white rounded-full size-4 flex items-center justify-center font-bold">
                        {agent.events}
                      </span>
                    )}
                  </div>
                  <span className="text-[11px] font-semibold text-white/80 leading-tight truncate">
                    {agent.name}
                  </span>
                  <span
                    className="text-[9px] text-white/30 truncate"
                    style={{ fontFamily: "var(--font-geist-mono)" }}
                  >
                    {agent.model}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Right: Selected agent events */}
          <div className="flex-1 flex flex-col min-w-0">
            <div className="px-4 pt-3 pb-2 border-b border-white/[0.06]">
              <p className="text-[13px] font-bold text-white">DeployBot</p>
              <p className="text-[10px] font-mono text-white/30">command-center · mac-mini-prod</p>
            </div>
            <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
              {MOCK_INBOX.filter((i) => i.agentName === "DeployBot").map((item) => (
                <div key={item.id} className="px-4 py-3">
                  <div className="flex items-center gap-1.5 mb-1">
                    <StatusDot status={item.status} />
                    <span className="text-[10px] font-mono text-white/30">{item.timeAgo}</span>
                  </div>
                  <p className="text-[12px] text-white/80 leading-snug">{item.message}</p>
                  {item.tag === "decision" && (
                    <div className="flex gap-2 mt-2">
                      <button className="px-3 py-1 rounded-lg text-[11px] bg-green-500/10 text-green-400 border border-green-500/20">
                        Approve
                      </button>
                      <button className="px-3 py-1 rounded-lg text-[11px] bg-red-500/10 text-red-400 border border-red-500/20">
                        Deny
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 4: Verify all three inbox variants load**

```bash
npm run dev
```

Open:
- `http://localhost:3000/inbox/a` — dense list
- `http://localhost:3000/inbox/b` — feed cards
- `http://localhost:3000/inbox/c` — split dashboard

All three should render inside a phone frame with real mock data.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(prototype): inbox variants A (ops-center), B (feed), C (dashboard)"
```

---

## ⏸️ Task 5: PAUSE — Inbox Variants Review

**This is a mandatory brainstorming checkpoint. Do NOT proceed to Task 6 until the user has reviewed and responded.**

- [ ] **Step 1: Take screenshots of all three inbox variants**

```bash
# In a separate terminal, start the dev server if not running
npm run dev &
sleep 3

# Screenshot each variant (requires screencapture or use the browser manually)
open http://localhost:3000/inbox/a
open http://localhost:3000/inbox/b
open http://localhost:3000/inbox/c
```

Take screenshots of each page showing the phone mockup. Save them:

```bash
screencapture -T 2 /tmp/inbox-a.png
# Switch to /inbox/b in browser, then:
screencapture -T 2 /tmp/inbox-b.png
# Switch to /inbox/c, then:
screencapture -T 2 /tmp/inbox-c.png
```

- [ ] **Step 2: Send screenshots to user**

Use `SendUserFile` to share the three screenshots. Include this message:

> "Here are three inbox design variants for Lancer. Each represents a different information density and layout philosophy:
>
> **A — Ops Center**: Maximum density, linear list. Best if users want to scan many agents quickly.
> **B — Feed**: Spacious cards with inline actions. Best if each notification deserves focus.
> **C — Dashboard**: Split-pane fleet + events. Best if users primarily think in terms of 'which agent?' rather than 'what happened?'
>
> Which direction feels right? Or is there a hybrid you'd like to explore? Also: does the 'Terminal Glass' dark aesthetic work, or should we try a different visual direction?"

- [ ] **Step 3: STOP. Wait for user feedback.**

Do not proceed to Task 6 until the user has:
1. Indicated which inbox variant(s) they prefer (or want modified)
2. Given any feedback on the overall aesthetic
3. Said it's okay to continue

If the user wants changes to any variant, make them in the relevant page file, rebuild, re-screenshot, and repeat this task.

---

## Task 6: Checkpoint Variants A + B

**Files:**
- Create: `docs/lancer-ui-prototype/app/checkpoint/a/page.tsx`
- Create: `docs/lancer-ui-prototype/app/checkpoint/b/page.tsx`

- [ ] **Step 1: Create Checkpoint Variant A — Risk Card (full screen)**

Create `docs/lancer-ui-prototype/app/checkpoint/a/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_CHECKPOINT } from "@/lib/mock-data"

const BLAST_LABELS: Record<string, string> = {
  "repo-only": "repo only",
  "private-infra": "private infra",
  "none": "none",
  "deployed": "deployed",
  "easy-rollback": "easy rollback",
  "staging": "staging",
}

const BLAST_COLORS: Record<string, string> = {
  "repo-only": "text-green-400 bg-green-500/10 border-green-500/20",
  "private-infra": "text-amber-400 bg-amber-500/10 border-amber-500/20",
  "none": "text-green-400 bg-green-500/10 border-green-500/20",
  "deployed": "text-red-400 bg-red-500/10 border-red-500/20",
  "easy-rollback": "text-green-400 bg-green-500/10 border-green-500/20",
  "staging": "text-amber-400 bg-amber-500/10 border-amber-500/20",
}

export default function CheckpointVariantA() {
  const cp = MOCK_CHECKPOINT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Risk Card</h2>
        <p className="text-xs text-white/40 mt-1">Full-screen decision with blast-radius breakdown</p>
      </div>

      <PhoneFrame label="checkpoint/a — risk card">
        <div className="flex flex-col h-full bg-[#050810] px-5 py-4">
          {/* Agent identity */}
          <div
            className="text-[11px] font-mono text-white/30 mb-4"
          >
            {cp.agentName} · {cp.repo}/{cp.branch} · {cp.host}
          </div>

          {/* Risk level indicator */}
          <div
            className={`text-[10px] font-bold uppercase tracking-widest mb-3 px-2 py-1 rounded self-start border ${
              cp.riskLevel === "high"
                ? "text-red-400 bg-red-500/10 border-red-500/30"
                : "text-amber-400 bg-amber-500/10 border-amber-500/30"
            }`}
            style={{ fontFamily: "var(--font-geist-mono)" }}
          >
            {cp.riskLevel} risk
          </div>

          {/* Question */}
          <h2 className="text-[18px] font-bold text-white leading-snug mb-3">
            {cp.question}
          </h2>

          {/* Context */}
          <div className="rounded-xl border border-white/[0.06] bg-white/[0.02] p-3 mb-4">
            <p className="text-[12px] text-white/60 leading-relaxed">{cp.context}</p>
          </div>

          {/* Blast radius */}
          <div className="mb-5">
            <p className="text-[10px] font-mono text-white/30 uppercase tracking-widest mb-2">
              Blast radius
            </p>
            <div className="grid grid-cols-2 gap-1.5">
              {Object.entries(cp.blastRadius).map(([key, val]) => (
                <div
                  key={key}
                  className={`flex items-center justify-between px-2 py-1.5 rounded-lg border text-[10px] ${BLAST_COLORS[val] || "text-white/40 bg-white/[0.02] border-white/[0.06]"}`}
                >
                  <span className="text-white/40 capitalize">{key.replace(/_/g, " ")}</span>
                  <span className="font-mono font-semibold">{BLAST_LABELS[val] || val}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Actions */}
          <div className="mt-auto flex flex-col gap-2">
            <button className="w-full py-3.5 rounded-2xl text-[14px] font-bold bg-green-500/15 text-green-400 border border-green-500/30 hover:bg-green-500/25 transition-colors">
              ✓ Approve — Roll Back
            </button>
            <div className="flex gap-2">
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-semibold bg-blue-500/10 text-blue-400 border border-blue-500/20">
                Retry Instead
              </button>
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-semibold bg-red-500/10 text-red-400 border border-red-500/20">
                Deny / Pause
              </button>
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 2: Create Checkpoint Variant B — Bottom Sheet**

Create `docs/lancer-ui-prototype/app/checkpoint/b/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_INBOX, MOCK_CHECKPOINT } from "@/lib/mock-data"
import { StatusDot } from "@/components/status-dot"

export default function CheckpointVariantB() {
  const cp = MOCK_CHECKPOINT
  // Show inbox in the background to show context of sheet sliding up
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Bottom Sheet</h2>
        <p className="text-xs text-white/40 mt-1">Sheet slides up from inbox — compact + contextual</p>
      </div>

      <PhoneFrame label="checkpoint/b — sheet">
        <div className="relative flex flex-col h-full bg-[#050810]">
          {/* Background: dimmed inbox */}
          <div className="absolute inset-0 flex flex-col opacity-30 pointer-events-none">
            <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
              <h1 className="text-[15px] font-bold text-white">Inbox</h1>
            </div>
            {MOCK_INBOX.slice(1).map((item) => (
              <div key={item.id} className="flex gap-3 px-4 py-3 border-b border-white/[0.04]">
                <StatusDot status={item.status} />
                <div className="flex-1 min-w-0">
                  <p className="text-[11px] font-mono text-blue-400 mb-0.5">{item.agentName}</p>
                  <p className="text-[12px] text-white/70 line-clamp-1">{item.message}</p>
                </div>
              </div>
            ))}
          </div>

          {/* Overlay backdrop */}
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

          {/* Bottom sheet */}
          <div className="absolute bottom-0 left-0 right-0 bg-[#0d1420] border-t border-white/[0.08] rounded-t-3xl px-5 pt-3 pb-6">
            {/* Drag handle */}
            <div className="w-10 h-1 bg-white/20 rounded-full mx-auto mb-4" />

            {/* Agent line */}
            <p className="text-[11px] font-mono text-white/30 mb-3">
              {cp.agentName} · {cp.repo} · {cp.permissionMode} mode
            </p>

            {/* Question */}
            <h3 className="text-[16px] font-bold text-white leading-snug mb-3">
              {cp.question}
            </h3>

            {/* Context quote */}
            <div className="border-l-2 border-amber-500/40 pl-3 mb-4">
              <p className="text-[12px] text-white/50 leading-relaxed line-clamp-3">
                {cp.context}
              </p>
            </div>

            {/* Actions */}
            <div className="flex gap-2">
              <button className="flex-1 py-3.5 rounded-2xl text-[13px] font-bold bg-green-500/15 text-green-400 border border-green-500/30">
                ✓ Approve
              </button>
              <button className="flex-1 py-3.5 rounded-2xl text-[13px] font-bold bg-red-500/10 text-red-400 border border-red-500/20">
                ✕ Deny
              </button>
            </div>
            <button className="w-full mt-2 py-2.5 text-[12px] text-white/40 hover:text-white/60">
              Edit response before sending
            </button>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 3: Verify both checkpoint variants**

```bash
npm run dev
```

Open `http://localhost:3000/checkpoint/a` and `http://localhost:3000/checkpoint/b`.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat(prototype): checkpoint variants A (risk-card) and B (sheet)"
```

---

## Task 7: Loop + Report Variants

**Files:**
- Create: `docs/lancer-ui-prototype/app/loop/a/page.tsx`
- Create: `docs/lancer-ui-prototype/app/loop/b/page.tsx`
- Create: `docs/lancer-ui-prototype/app/report/a/page.tsx`
- Create: `docs/lancer-ui-prototype/app/report/b/page.tsx`

- [ ] **Step 1: Create Loop Variant A — Timeline**

Create `docs/lancer-ui-prototype/app/loop/a/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { StatusDot } from "@/components/status-dot"
import { MOCK_LOOPS } from "@/lib/mock-data"

const STEP_ICONS: Record<string, string> = {
  ok: "✓",
  failed: "✕",
  blocked: "●",
  skipped: "○",
}

const STEP_COLORS: Record<string, string> = {
  ok: "text-green-400",
  failed: "text-red-400",
  blocked: "text-amber-400",
  skipped: "text-white/30",
}

export default function LoopVariantA() {
  const loop = MOCK_LOOPS[0] // Deploy Loop — blocked at step 5
  const pct = Math.round((loop.currentStep / loop.totalSteps) * 100)

  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Timeline</h2>
        <p className="text-xs text-white/40 mt-1">Vertical step list with status + all active loops</p>
      </div>

      <PhoneFrame label="loop/a — timeline">
        <div className="flex flex-col h-full bg-[#050810]">
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <h1 className="text-[15px] font-bold text-white">Fleet Status</h1>
            <p className="text-[11px] text-white/30">{MOCK_LOOPS.length} active loops</p>
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-white/[0.04]">
            {MOCK_LOOPS.map((l) => {
              const pct = Math.round((l.currentStep / l.totalSteps) * 100)
              return (
                <div key={l.id} className="px-4 py-4">
                  {/* Loop header */}
                  <div className="flex items-center gap-2 mb-2">
                    <StatusDot status={l.status === "completed" ? "done" : l.status === "blocked" ? "blocked" : "running"} />
                    <span className="text-[13px] font-semibold text-white/90 flex-1">{l.name}</span>
                    <span className="text-[10px] font-mono text-white/30">{l.startedAt}</span>
                  </div>

                  {/* Progress bar */}
                  <div className="h-1 bg-white/[0.06] rounded-full mb-2 overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all ${
                        l.status === "completed" ? "bg-green-400" :
                        l.status === "blocked" || l.status === "failed" ? "bg-amber-400" :
                        "bg-blue-400"
                      }`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>

                  <div className="flex justify-between items-center mb-3">
                    <span className="text-[10px] font-mono text-white/30">
                      {l.agentName} · {l.repo}
                    </span>
                    <span className="text-[10px] font-mono text-white/40">
                      step {l.currentStep}/{l.totalSteps}
                    </span>
                  </div>

                  {/* Steps */}
                  <div className="flex flex-col gap-1">
                    {l.steps.map((step) => (
                      <div key={step.step} className="flex items-center gap-2">
                        <span
                          className={`text-[12px] w-4 text-center font-mono font-bold ${STEP_COLORS[step.status]}`}
                        >
                          {STEP_ICONS[step.status]}
                        </span>
                        <span className={`text-[11px] ${step.status !== "ok" ? "text-white/80" : "text-white/40"}`}>
                          {step.summary}
                        </span>
                      </div>
                    ))}
                    {/* Pending steps */}
                    {Array.from({ length: l.totalSteps - l.steps.length }).map((_, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <span className="text-[12px] w-4 text-center font-mono text-white/20">○</span>
                        <span className="text-[11px] text-white/20">pending</span>
                      </div>
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 2: Create Loop Variant B — Gauge**

Create `docs/lancer-ui-prototype/app/loop/b/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_LOOPS } from "@/lib/mock-data"

export default function LoopVariantB() {
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Gauge</h2>
        <p className="text-xs text-white/40 mt-1">Circular progress ring — at-a-glance</p>
      </div>

      <PhoneFrame label="loop/b — gauge">
        <div className="flex flex-col h-full bg-[#050810] overflow-y-auto">
          <div className="px-5 pt-3 pb-2 border-b border-white/[0.06]">
            <h1 className="text-[15px] font-bold text-white">Fleet Status</h1>
          </div>

          <div className="flex flex-col gap-4 px-4 py-4">
            {MOCK_LOOPS.map((loop) => {
              const pct = loop.currentStep / loop.totalSteps
              const r = 28
              const circ = 2 * Math.PI * r
              const strokeDash = circ * pct

              const ringColor =
                loop.status === "completed" ? "#4ade80" :
                loop.status === "blocked" || loop.status === "failed" ? "#fbbf24" :
                "#3b82f6"

              return (
                <div
                  key={loop.id}
                  className="rounded-2xl border border-white/[0.06] bg-white/[0.02] px-4 py-4 flex items-center gap-4"
                >
                  {/* Gauge ring */}
                  <div className="relative shrink-0">
                    <svg width="72" height="72" viewBox="0 0 72 72" className="-rotate-90">
                      <circle cx="36" cy="36" r={r} fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth="4" />
                      <circle
                        cx="36" cy="36" r={r}
                        fill="none"
                        stroke={ringColor}
                        strokeWidth="4"
                        strokeDasharray={`${strokeDash} ${circ}`}
                        strokeLinecap="round"
                      />
                    </svg>
                    <div className="absolute inset-0 flex flex-col items-center justify-center">
                      <span className="text-[14px] font-bold text-white leading-none">
                        {loop.currentStep}
                      </span>
                      <span className="text-[9px] text-white/30 font-mono">/{loop.totalSteps}</span>
                    </div>
                  </div>

                  {/* Content */}
                  <div className="flex-1 min-w-0">
                    <p className="text-[13px] font-bold text-white mb-0.5 truncate">{loop.name}</p>
                    <p className="text-[10px] font-mono text-white/30 mb-2">
                      {loop.agentName} · {loop.startedAt}
                    </p>

                    {/* Last 2 steps */}
                    <div className="flex flex-col gap-1">
                      {loop.steps.slice(-2).map((step) => (
                        <div key={step.step} className="flex items-center gap-1.5">
                          <span className={`text-[10px] font-mono ${
                            step.status === "ok" ? "text-green-400" :
                            step.status === "blocked" ? "text-amber-400" : "text-red-400"
                          }`}>
                            {step.status === "ok" ? "✓" : step.status === "blocked" ? "●" : "✕"}
                          </span>
                          <span className="text-[10px] text-white/50 truncate">{step.summary}</span>
                        </div>
                      ))}
                    </div>

                    {/* Status chip */}
                    <span className={`inline-block mt-2 text-[9px] px-2 py-0.5 rounded-md border font-mono ${
                      loop.status === "completed" ? "bg-green-500/10 text-green-400 border-green-500/20" :
                      loop.status === "blocked" ? "bg-amber-500/10 text-amber-400 border-amber-500/20" :
                      loop.status === "running" ? "bg-blue-500/10 text-blue-400 border-blue-500/20" :
                      "bg-red-500/10 text-red-400 border-red-500/20"
                    }`}>
                      {loop.status}
                    </span>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 3: Create Report Variant A — Audit**

Create `docs/lancer-ui-prototype/app/report/a/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_REPORT } from "@/lib/mock-data"

export default function ReportVariantA() {
  const r = MOCK_REPORT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant A</p>
        <h2 className="text-lg font-bold text-white">Audit Card</h2>
        <p className="text-xs text-white/40 mt-1">Technical view — diff, files, commands, risks</p>
      </div>

      <PhoneFrame label="report/a — audit">
        <div className="flex flex-col h-full bg-[#050810] overflow-y-auto">
          {/* Header */}
          <div className="px-4 pt-3 pb-3 border-b border-white/[0.06]">
            <p className="text-[10px] font-mono text-blue-400/60 mb-1">
              {r.agentName} · {r.repo}/{r.branch} · {r.permissionMode} mode
            </p>
            <h2 className="text-[15px] font-bold text-white leading-tight">{r.goal}</h2>
          </div>

          {/* Stats row */}
          <div className="grid grid-cols-3 divide-x divide-white/[0.06] border-b border-white/[0.06]">
            {[
              { label: "Tests", value: r.testStatus, color: r.testStatus === "passed" ? "text-green-400" : "text-red-400" },
              { label: "Files", value: `${r.changedFiles.length}`, color: "text-white" },
              { label: "Cmds", value: `${r.commandsRun.length}`, color: "text-white" },
            ].map((s) => (
              <div key={s.label} className="flex flex-col items-center py-3">
                <span className={`text-[13px] font-bold font-mono ${s.color}`}>{s.value}</span>
                <span className="text-[10px] text-white/30 mt-0.5">{s.label}</span>
              </div>
            ))}
          </div>

          <div className="flex flex-col divide-y divide-white/[0.04] pb-4">
            {/* Diff summary */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-1">Diff summary</p>
              <p className="text-[12px] text-white/70 leading-relaxed">{r.diffSummary}</p>
            </div>

            {/* Files */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Changed files</p>
              {r.changedFiles.map((f) => (
                <p key={f} className="text-[11px] font-mono text-blue-300/70 leading-relaxed">+ {f}</p>
              ))}
            </div>

            {/* Commands */}
            <div className="px-4 py-3">
              <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Commands run</p>
              {r.commandsRun.map((c) => (
                <p key={c} className="text-[11px] font-mono text-white/50 leading-relaxed">$ {c}</p>
              ))}
            </div>

            {/* Risks */}
            {r.risks.length > 0 && (
              <div className="px-4 py-3">
                <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">Risks</p>
                <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 p-3">
                  {r.risks.map((risk) => (
                    <p key={risk} className="text-[11px] text-amber-300/80 leading-relaxed">⚠ {risk}</p>
                  ))}
                </div>
              </div>
            )}

            {/* Actions */}
            <div className="px-4 pt-3 flex gap-2">
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-bold bg-green-500/15 text-green-400 border border-green-500/30">
                ✓ Approve PR
              </button>
              <button className="flex-1 py-3 rounded-2xl text-[13px] font-bold bg-red-500/10 text-red-400 border border-red-500/20">
                ✕ Reject
              </button>
            </div>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 4: Create Report Variant B — Summary**

Create `docs/lancer-ui-prototype/app/report/b/page.tsx`:

```tsx
import { PhoneFrame } from "@/components/phone-frame"
import { MOCK_REPORT } from "@/lib/mock-data"

export default function ReportVariantB() {
  const r = MOCK_REPORT
  return (
    <div className="py-12 flex flex-col items-center gap-6">
      <div className="text-center mb-2">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Variant B</p>
        <h2 className="text-lg font-bold text-white">Summary Card</h2>
        <p className="text-xs text-white/40 mt-1">Clean summary with expandable detail</p>
      </div>

      <PhoneFrame label="report/b — summary">
        <div className="flex flex-col h-full bg-[#070b12]">
          {/* Top */}
          <div className="px-5 pt-4 pb-4">
            <div
              className="text-[10px] font-mono text-white/30 mb-3"
            >
              {r.agentName} · {r.repo} · {r.permissionMode}
            </div>

            <div className="flex items-start justify-between gap-3 mb-3">
              <h2 className="text-[16px] font-bold text-white leading-snug flex-1">
                {r.goal}
              </h2>
              <span
                className={`mt-0.5 shrink-0 text-[11px] px-2.5 py-1 rounded-xl font-bold border ${
                  r.testStatus === "passed"
                    ? "bg-green-500/15 text-green-400 border-green-500/30"
                    : "bg-red-500/15 text-red-400 border-red-500/30"
                }`}
              >
                {r.testStatus}
              </span>
            </div>

            <p className="text-[13px] text-white/60 leading-relaxed">{r.diffSummary}</p>
          </div>

          {/* Stats pills */}
          <div className="px-5 pb-4 flex gap-2 flex-wrap">
            {[
              { label: `${r.changedFiles.length} files`, color: "text-blue-400 bg-blue-500/10 border-blue-500/20" },
              { label: `${r.commandsRun.length} commands`, color: "text-white/60 bg-white/[0.04] border-white/[0.08]" },
              { label: `${r.risks.length} risks`, color: "text-amber-400 bg-amber-500/10 border-amber-500/20" },
            ].map((p) => (
              <span key={p.label} className={`text-[11px] px-2.5 py-1 rounded-xl border ${p.color}`}>
                {p.label}
              </span>
            ))}
          </div>

          {/* Divider */}
          <div className="border-t border-white/[0.06] mx-5" />

          {/* Unverified */}
          <div className="px-5 py-4 flex-1">
            <p className="text-[10px] font-mono text-white/30 uppercase tracking-wide mb-2">
              Not verified
            </p>
            {r.unverified.map((u) => (
              <div key={u} className="flex items-start gap-2 mb-1.5">
                <span className="text-white/20 mt-0.5 text-[11px]">○</span>
                <p className="text-[12px] text-white/50">{u}</p>
              </div>
            ))}
          </div>

          {/* Action */}
          <div className="px-5 pb-6">
            <button className="w-full py-4 rounded-2xl text-[14px] font-bold bg-blue-500/15 text-blue-300 border border-blue-500/25 hover:bg-blue-500/25 transition-colors">
              Approve PR →
            </button>
            <button className="w-full mt-2 py-3 text-[12px] text-white/30">
              See full audit details
            </button>
          </div>
        </div>
      </PhoneFrame>
    </div>
  )
}
```

- [ ] **Step 5: Verify all new screens**

```bash
npm run dev
```

Open and verify:
- `http://localhost:3000/loop/a`
- `http://localhost:3000/loop/b`
- `http://localhost:3000/report/a`
- `http://localhost:3000/report/b`

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "feat(prototype): loop variants A/B, report variants A/B"
```

---

## ⏸️ Task 8: PAUSE — Checkpoint + Loop + Report Review

**Mandatory brainstorming checkpoint. Do NOT proceed until user approves.**

- [ ] **Step 1: Screenshot all remaining variants**

Take screenshots of:
- `/checkpoint/a` and `/checkpoint/b`
- `/loop/a` and `/loop/b`
- `/report/a` and `/report/b`

- [ ] **Step 2: Send all screenshots with context**

Use `SendUserFile` to share. Message:

> "Here are the remaining screens:
>
> **Checkpoint A (Risk Card)** — Full-screen decision with blast-radius grid. Slows you down intentionally for high-risk actions.
> **Checkpoint B (Sheet)** — Slides up over the inbox. Compact, good for quick decisions.
>
> **Loop A (Timeline)** — Shows every step with status icon. Good for transparency, dense.
> **Loop B (Gauge)** — Circular ring + summary. Glanceable, better for checking status quickly.
>
> **Report A (Audit)** — Technical view: diff, files, commands. Feels like a code review.
> **Report B (Summary)** — Clean card with stats pills. Better for quick approve/reject.
>
> Which variants should we move forward with, or what should change?"

- [ ] **Step 3: STOP. Wait for user feedback.**

Do not proceed to Task 9 until the user has reviewed and given explicit approval.

---

## Task 9: Polish Pass — Apply Feedback

**This task is driven entirely by the user's feedback from Tasks 5 and 8. Do not start it until feedback is collected.**

- [ ] **Step 1: Review all feedback notes from Tasks 5 and 8**

Summarise the user's decisions:
- Which inbox variant is preferred?
- Which checkpoint style is preferred?
- Which loop display is preferred?
- Which report card is preferred?
- Any colour / typography / aesthetic changes requested?

- [ ] **Step 2: Apply feedback to each preferred variant**

For each screen the user wants changed, edit the relevant page file. Common polish items:

- Adjust font sizes if text feels too small on the phone frame
- Swap colour accents if the blue feels too cold (try `#6366f1` indigo or `#8b5cf6` violet)
- Add `transition-all` to interactive elements if they feel static
- Fix spacing if items feel cramped or too spread out
- Rename labels if wording doesn't match what the user expects

- [ ] **Step 3: Add a "final cut" index route showing the chosen variants**

After feedback, add a `/final` page that shows the chosen variant for each screen side by side in a grid, so the user has one reference page to approve before iOS implementation begins.

- [ ] **Step 4: Verify final build**

```bash
npm run build 2>&1 | tail -10
```

Expected: `✓ Compiled successfully`, zero TypeScript errors.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(prototype): polish pass based on design feedback"
```

---

## ⏸️ Task 10: PAUSE — Final Approval Before iOS

**This is the final gate. Do not begin any iOS (Swift/SwiftUI) implementation until the user explicitly says "approved" or "looks good, start iOS."**

- [ ] **Step 1: Open the final reference page**

```bash
open http://localhost:3000/final
```

- [ ] **Step 2: Send screenshots of all chosen variants**

Send one screenshot per chosen screen to the user.

- [ ] **Step 3: Ask for final sign-off**

> "This is the complete UI design for the Lancer iOS app based on all the feedback.
> If this looks good, the next step is Plan 2 (iOS Inbox) — implementing these screens in SwiftUI using the Lancer design system.
> Are you happy to move forward, or are there any last changes?"

- [ ] **Step 4: STOP until approved.**

---

## Self-Review Checklist

**Spec coverage:**
- [x] 3 Inbox variants — Tasks 4, 5
- [x] 2 Checkpoint variants — Tasks 6, 8
- [x] 2 Loop Progress variants — Tasks 7, 8
- [x] 2 Report Card variants — Tasks 7, 8
- [x] Variant navigator — Task 3
- [x] Brainstorming pause after each screen group — Tasks 5, 8, 10
- [x] Polish pass driven by feedback — Task 9
- [x] Final approval gate before iOS — Task 10

**Placeholder scan:** No TBDs. All component code is complete. Task 9 is intentionally variable — it runs on feedback, which is the point.

**Type consistency:** All mock data types defined in `lib/mock-data.ts` and used consistently. `LoopItem.status` values match `StatusDot` status prop.

**What this plan does NOT cover (Plan 3 — iOS Implementation):**
- SwiftUI screens
- iOS design system mapping from this prototype
- Real data binding to push-backend API
