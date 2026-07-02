"use client"

import { Fragment, useState } from "react"
import Link from "next/link"
import { Flashlight, Camera } from "lucide-react"
import { LockScreenFrame } from "@/components/lock-screen-frame"
import { DynamicIslandCompact, DynamicIslandExpanded } from "@/components/dynamic-island-frame"
import {
  display,
  body,
  mono,
  C,
  KEYFRAMES,
  SectionLabel,
  Eyebrow,
  Headline,
  Body,
  Card,
  Badge,
  Chip,
  StatusDot,
  AgentAvatarTile,
  REF_IMG,
} from "@/components/conduit/brand"

// ---------------------------------------------------------------------------
// Section 1 — "What we have today", reproduced exactly, recolored to brand
// ---------------------------------------------------------------------------

interface SessionState {
  status: "connected" | "reconnecting" | "error" | "suspended"
  pendingApprovals: number
  agentName?: string
  isStreaming: boolean
  cost: number | null
  lastDecision: "approved" | "rejected" | null
  risk?: "high" | "low"
}

type Primary =
  | { type: "needsYou"; count: number }
  | { type: "decisionLanded"; approved: boolean }
  | { type: "running" }
  | { type: "idle" }

function resolvePrimary(s: SessionState): Primary {
  if (s.pendingApprovals > 0) return { type: "needsYou", count: s.pendingApprovals }
  if (s.lastDecision) return { type: "decisionLanded", approved: s.lastDecision === "approved" }
  if (s.isStreaming) return { type: "running" }
  return { type: "idle" }
}

function dotSpec(s: SessionState, p: Primary): { tone: "sage" | "amber" | "danger" | "idle"; pulse: boolean } {
  switch (p.type) {
    case "needsYou":
      // High-risk approvals (Rivian's "alarm triggered" pattern) escalate to
      // danger instead of the routine amber — most approvals aren't emergencies.
      return { tone: s.risk === "high" ? "danger" : "amber", pulse: true }
    case "decisionLanded":
      return { tone: p.approved ? "sage" : "danger", pulse: false }
    case "running":
      return { tone: "sage", pulse: true }
    case "idle":
      if (s.status === "reconnecting") return { tone: "amber", pulse: true }
      if (s.status === "error") return { tone: "danger", pulse: false }
      if (s.status === "suspended") return { tone: "idle", pulse: false }
      return { tone: "sage", pulse: false }
  }
}

function statusLabel(s: SessionState, p: Primary): string {
  switch (p.type) {
    case "needsYou":
      return p.count === 1 ? "1 pending" : `${p.count} pending`
    case "decisionLanded":
      return p.approved ? "approved" : "denied"
    case "running":
      return "running"
    case "idle":
      return s.status
  }
}

function formatCost(cost: number): string {
  if (cost < 0.01) return "<$0.01"
  return `$${cost.toFixed(2)}`
}

const SCENARIOS: Record<string, SessionState> = {
  connected: { status: "connected", pendingApprovals: 0, agentName: "Claude Code", isStreaming: false, cost: 0.12, lastDecision: null },
  running: { status: "connected", pendingApprovals: 0, agentName: "Claude Code", isStreaming: true, cost: 0.34, lastDecision: null },
  needsApproval: { status: "connected", pendingApprovals: 1, agentName: "Claude Code", isStreaming: true, cost: 0.51, lastDecision: null, risk: "low" },
  needsApprovalHigh: { status: "connected", pendingApprovals: 1, agentName: "Claude Code", isStreaming: true, cost: 0.51, lastDecision: null, risk: "high" },
  approved: { status: "connected", pendingApprovals: 0, agentName: "Claude Code", isStreaming: true, cost: 0.51, lastDecision: "approved" },
  rejected: { status: "connected", pendingApprovals: 0, agentName: "Claude Code", isStreaming: false, cost: 0.51, lastDecision: "rejected" },
  reconnecting: { status: "reconnecting", pendingApprovals: 0, agentName: undefined, isStreaming: false, cost: null, lastDecision: null },
}

const SCENARIO_LABELS: { key: keyof typeof SCENARIOS; label: string }[] = [
  { key: "connected", label: "Connected" },
  { key: "running", label: "Running" },
  { key: "needsApproval", label: "Needs approval" },
  { key: "needsApprovalHigh", label: "Needs approval — high risk" },
  { key: "approved", label: "Approved" },
  { key: "rejected", label: "Denied" },
  { key: "reconnecting", label: "Reconnecting" },
]

function CurrentBanner({ state }: { state: SessionState }) {
  const p = resolvePrimary(state)
  const dot = dotSpec(state, p)
  const label = statusLabel(state, p)
  const banded = p.type === "needsYou"
  const highRisk = banded && state.risk === "high"

  return (
    <div
      style={{
        borderRadius: 24,
        background: "rgba(13,12,11,.85)",
        backdropFilter: "blur(10px)",
        border: `1px solid ${highRisk ? "rgba(217,122,112,.35)" : "rgba(244,239,230,.08)"}`,
        overflow: "hidden",
      }}
    >
      {/* Banded header — the system's own ApprovalCard pattern: a tinted
          strip clipped inside the same radius. Escalates to danger for
          high-risk actions (Rivian's "alarm triggered" cue) instead of
          treating every approval the same — most aren't emergencies. */}
      {banded && (
        <div style={{ background: highRisk ? "rgba(217,122,112,.2)" : "rgba(224,164,92,.16)", padding: "7px 16px", display: "flex", alignItems: "center", gap: 7 }}>
          <StatusDot tone={highRisk ? "danger" : "amber"} pulse size={6} />
          <span className={mono.className} style={{ fontSize: 10, letterSpacing: ".08em", textTransform: "uppercase", color: highRisk ? "#d97a70" : C.amberOnDark, fontWeight: 500, flex: 1 }}>
            {highRisk ? "High-risk action blocked" : "Needs your approval"}
          </span>
          {highRisk && <Badge tone="high">High risk</Badge>}
        </div>
      )}
      <div style={{ padding: "13px 16px", display: "flex", alignItems: "center", gap: 12 }}>
        <AgentAvatarTile size={30} dot={dot} />
        <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, flex: 1 }}>
          <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.cream, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
            {state.agentName ?? "hermes-box"}
          </span>
          <div className={mono.className} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11 }}>
            <span style={{ color: "rgba(244,239,230,.55)" }}>{label}</span>
            {state.cost !== null && state.cost > 0 && (
              <>
                <span style={{ color: "rgba(244,239,230,.25)" }}>·</span>
                <span style={{ color: "rgba(244,239,230,.55)" }}>{formatCost(state.cost)}</span>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function CurrentIslandCompact({ state }: { state: SessionState }) {
  const p = resolvePrimary(state)
  const dot = dotSpec(state, p)
  return (
    <DynamicIslandCompact
      leading={<AgentAvatarTile size={18} dot={dot} />}
      trailing={
        p.type === "needsYou" ? (
          <span className={mono.className} style={{ fontSize: 11, fontWeight: 600, color: C.amberOnDark }}>{p.count}</span>
        ) : (
          <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.4)" }}>
            {p.type === "decisionLanded" ? "✓" : p.type === "running" ? "..." : state.status.slice(0, 3)}
          </span>
        )
      }
    />
  )
}

function CurrentIslandExpanded({ state }: { state: SessionState }) {
  const p = resolvePrimary(state)
  const dot = dotSpec(state, p)
  return (
    <DynamicIslandExpanded
      leading={<AgentAvatarTile size={24} dot={dot} />}
      trailing={
        p.type === "needsYou" ? (
          <span className={mono.className} style={{ fontSize: 11, fontWeight: 600, color: C.amberOnDark }}>{p.count} pending</span>
        ) : state.cost && state.cost > 0 ? (
          <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.45)" }}>{formatCost(state.cost)}</span>
        ) : null
      }
      center={
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 2 }}>
          <span className={display.className} style={{ fontSize: 13, fontWeight: 700, color: C.cream }}>{state.agentName ?? "hermes-box"}</span>
          <span className={mono.className} style={{ fontSize: 10.5, color: "rgba(244,239,230,.4)" }}>{statusLabel(state, p)}</span>
        </div>
      }
      bottom={
        p.type === "needsYou" ? (
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div className={body.className} style={{ display: "flex", alignItems: "center", borderRadius: 999, border: "1px solid rgba(244,239,230,.22)", padding: "7px 14px", fontSize: 12, fontWeight: 600, color: "rgba(244,239,230,.8)" }}>
              Deny
            </div>
            <div className={body.className} style={{ display: "flex", alignItems: "center", borderRadius: 999, background: C.cream, padding: "7px 14px", fontSize: 12, fontWeight: 600, color: C.ink900 }}>
              Approve
            </div>
          </div>
        ) : (
          state.cost && state.cost > 0 ? (
            <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.4)" }}>{formatCost(state.cost)}</span>
          ) : null
        )
      }
    />
  )
}

function SessionStateDemo() {
  const [key, setKey] = useState<keyof typeof SCENARIOS>("needsApproval")
  const state = SCENARIOS[key]

  return (
    <section>
      <SectionLabel tone="terra">Every state, reproduced exactly</SectionLabel>
      <Headline size={24}>What we ship today</Headline>
      <Body style={{ maxWidth: 640, margin: "10px 0 24px" }}>
        Reproduces <code style={{ color: C.ink700 }}>LiveActivityPresentation.resolve()</code> and the widget&apos;s region
        layout — recolored from the old ad-hoc blue/green/red/amber to the brand&apos;s actual status trio: sage (running,
        online), amber (needs you), danger (denied, blocked). No blue anywhere, per the system. Click a state to see it.
      </Body>

      <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 28 }}>
        {SCENARIO_LABELS.map((s) => (
          <Chip key={s.key} active={key === s.key} onClick={() => setKey(s.key)}>
            {s.label}
          </Chip>
        ))}
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-start", gap: 40 }}>
        <LockScreenFrame label="lock screen">
          <CurrentBanner state={state} />
        </LockScreenFrame>
        <div style={{ display: "flex", flexDirection: "column", gap: 24, paddingTop: 16 }}>
          <div>
            <SectionLabel>Island — compact</SectionLabel>
            <div style={{ marginTop: 8 }}>
              <CurrentIslandCompact state={state} />
            </div>
          </div>
          <div>
            <SectionLabel>Island — expanded</SectionLabel>
            <div style={{ marginTop: 8 }}>
              <CurrentIslandExpanded state={state} />
            </div>
          </div>
        </div>
      </div>

      <Card style={{ marginTop: 32, maxWidth: 640, padding: "14px 16px", background: C.amberTint, border: "none" }}>
        <Body style={{ color: C.amber600, margin: 0 }}>
          <span className={body.className} style={{ fontWeight: 700 }}>Gap vs. iOS 26/27:</span> no{" "}
          <code style={{ color: C.amber600 }}>supplementalActivityFamilies</code> (no real Watch/CarPlay presence — they&apos;d
          get this same cramped compact view), no <code style={{ color: C.amber600 }}>isDynamicIslandLimitedInWidth</code>{" "}
          handling for iPhone 17 Pro landscape, no <code style={{ color: C.amber600 }}>showsWidgetContainerBackground</code>{" "}
          for StandBy&apos;s 200% scaling. Closed further down this page — Watch &amp; CarPlay presence, and
          Landscape &amp; StandBy.
        </Body>
      </Card>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Section 2 — Mobbin references
// ---------------------------------------------------------------------------

interface RefShot {
  app: string
  caption: string
  imageUrl: string
  mobbinUrl: string
}

const REFS: RefShot[] = [
  {
    app: "Granola — AI notetaking",
    caption: "\"Taking notes... 1:39\" + inline camera/End buttons — closest analog to an AI-agent Live Activity with actions.",
    imageUrl: "https://mobbin.com/api/mcp/short/P40PIgD8",
    mobbinUrl: "https://mobbin.com/screens/68a8fed7-ea39-426f-8353-f114d87780dd",
  },
  {
    app: "Flighty — flight tracker",
    caption: "Segmented color-coded bar with a live delta (\"9m early\") — the model for a cost-vs-budget bar with warning/over states.",
    imageUrl: "https://mobbin.com/api/mcp/short/NgixkCkH",
    mobbinUrl: "https://mobbin.com/screens/e885508e-8728-426b-a1a2-7a4be1e4086e",
  },
  {
    app: "DoorDash — delivery",
    caption: "Icon + one-line status + ETA — the glanceable single-sentence pattern our lock-screen banner already follows.",
    imageUrl: "https://mobbin.com/api/mcp/short/Sv7VmCWY",
    mobbinUrl: "https://mobbin.com/screens/6509a2e7-1efb-48cf-a6ff-c9c2d5726316",
  },
  {
    app: "Lyft — rideshare",
    caption: "Progress bar + rating badge sharing one row — proof a bar and a secondary badge (our pending-approval badge) can coexist.",
    imageUrl: "https://mobbin.com/api/mcp/short/vPbh7Obz",
    mobbinUrl: "https://mobbin.com/screens/1e3a6d14-c1be-4da9-957c-898a4902c682",
  },
  {
    app: "Apple Fitness — workout",
    caption: "3-button expanded row (lap / pause / mute) — a model if Lancer ever adds inline controls beyond Approve/Deny.",
    imageUrl: "https://mobbin.com/api/mcp/short/UWLZ0UC6",
    mobbinUrl: "https://mobbin.com/screens/40e562c3-6597-49d2-b326-47038e1e0d49",
  },
  {
    app: "Duolingo — streak",
    caption: "Minimal compact pill: one colored glyph, one checkmark — matches how little our compact/minimal island should ever show.",
    imageUrl: "https://mobbin.com/api/mcp/short/LuJl956K",
    mobbinUrl: "https://mobbin.com/screens/42d0ff92-eb8a-4d68-af91-d41520f1d455",
  },
  {
    app: "Opal — focus timer",
    caption: "Dark, typographic-only pill, no bar. Validates the \"live-incrementing timer, no bar\" fallback when no budget is set.",
    imageUrl: "https://mobbin.com/api/mcp/short/qXASm4w8",
    mobbinUrl: "https://mobbin.com/screens/7c3d9ab1-4295-4652-9cca-e40fe9801fab",
  },
]

function MobbinReferencesSection() {
  return (
    <section>
      <SectionLabel tone="terra">Borrowed with attribution</SectionLabel>
      <Headline size={24}>Reference points</Headline>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))", gap: 20, marginTop: 20 }}>
        {REFS.map((r) => (
          <a key={r.mobbinUrl} href={r.mobbinUrl} target="_blank" rel="noreferrer" style={{ textDecoration: "none" }}>
            <Card style={{ padding: 10, height: "100%" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={r.imageUrl} alt={r.app} className={REF_IMG} style={{ width: "100%" }} />
              <div className={display.className} style={{ fontSize: 13, fontWeight: 700, color: C.ink900, marginTop: 10 }}>
                {r.app} <span style={{ color: C.terra500 }}>↗</span>
              </div>
              <Body style={{ fontSize: 12, color: C.ink350, marginTop: 4, lineHeight: 1.45 }}>{r.caption}</Body>
            </Card>
          </a>
        ))}
      </div>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Section 2b — Second sweep: broader categories, judged good/bad per screen
// rather than just "here's a nice pattern." Some of these directly produced
// the risk-banding change above; others are flagged as ideas, not adopted.
// ---------------------------------------------------------------------------

interface JudgedRef extends RefShot {
  good: string
  bad: string
}

const SECOND_SWEEP: JudgedRef[] = [
  {
    app: "Rivian — alarm triggered",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/dUtEUubq",
    mobbinUrl: "https://mobbin.com/screens/c25ddb40-e4a0-4f77-a9a6-9996a8afa4ed",
    good: "The correct escalation for a truly critical state — full-bleed danger red, one big icon, stacked full-width buttons (easier under stress than side-by-side). Directly produced the high-risk danger band above.",
    bad: "Too aggressive for routine approvals — reserve this tier for genuinely dangerous actions (rm -rf, force push), not every pending decision.",
  },
  {
    app: "sweetgreen — order stepper",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/XTU1R0W9",
    mobbinUrl: "https://mobbin.com/screens/7a147967-210a-46bb-9d51-700d6158a646",
    good: "Labeled dots (Received → Preparing → Complete) make progress legible with zero prior knowledge — better than a bare percentage for multi-phase work.",
    bad: "Needs ~90px of vertical space — too tall for our compact lock-screen banner, and needs a known step count agent loops usually don't have.",
  },
  {
    app: "Gopuff — icon stepper",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/xieQ0BoO",
    mobbinUrl: "https://mobbin.com/screens/111f57d1-be77-440b-b73d-e90380e2df30",
    good: "Icon-only stepper fits the same 4 stages in under half sweetgreen's height — much closer to our real space budget.",
    bad: "Icons alone (lightning/bag/car/house) need prior knowledge to parse — first-time legibility is weak without labels.",
  },
  {
    app: "Tolan — call card",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/b8UotTKL",
    mobbinUrl: "https://mobbin.com/screens/b778d05c-922c-4910-bb05-468faf028d56",
    good: "Circular icon-only mute/end buttons are more compact than our labeled pills and instantly readable from the system Phone app — a \"Stop agent\" action could borrow this exact shape.",
    bad: "The full-bleed colorful gradient is off-brand (no blue/purple, one accent) — borrow the button shape, not the palette.",
  },
  {
    app: "Citizen — Watch My Back",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/kPZp3aOn",
    mobbinUrl: "https://mobbin.com/screens/648b2967-b27b-4f60-86cf-93a7359d7d94",
    good: "Two clearly differentiated CTAs side-by-side with a countdown reads fine at a glance — validates our Approve/Deny pairing shape.",
    bad: "The color pairing (purple label + red + blue) is busy and breaks the one-accent rule — good proof of concept, bad palette to copy.",
  },
  {
    app: "Apple Sports — live score",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/fsS6Lwld",
    mobbinUrl: "https://mobbin.com/screens/83dfa80a-6fae-408e-acbd-f670e7e20e39",
    good: "Proves a Dynamic Island can hold two independent entities side-by-side with a shared center metric — useful if Lancer ever shows 2+ agents in one activity.",
    bad: "Not applicable today — we're one-activity-per-host. Forcing it in would misrepresent the real architecture.",
  },
  {
    app: "Duolingo — streak urgency",
    caption: "",
    imageUrl: "https://mobbin.com/api/mcp/short/BOgStP1x",
    mobbinUrl: "https://mobbin.com/screens/5baab775-2f06-42a5-92bb-bc1f3942affa",
    good: "Escalating color intensity communicates \"time is running out\" without extra copy — could work for \"approval expiring soon.\"",
    bad: "The gamified glaring-mascot execution is the wrong tone entirely for a calm ops tool — borrow the color-escalation idea only.",
  },
]

function SecondSweepSection() {
  return (
    <section>
      <SectionLabel tone="terra">Second pass — judged, not just admired</SectionLabel>
      <Headline size={24}>What&apos;s actually useful here</Headline>
      <Body style={{ maxWidth: 640, margin: "10px 0 24px" }}>
        Broader categories this time — delivery steppers, sports Dynamic Islands, call cards, emergency alerts —
        each judged on what to take and what to leave, not just admired.
      </Body>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 20 }}>
        {SECOND_SWEEP.map((r) => (
          <Card key={r.mobbinUrl} style={{ padding: 10 }}>
            <a href={r.mobbinUrl} target="_blank" rel="noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={r.imageUrl} alt={r.app} className={REF_IMG} style={{ width: "100%" }} />
            </a>
            <div className={display.className} style={{ fontSize: 13, fontWeight: 700, color: C.ink900, marginTop: 10, marginBottom: 8 }}>
              {r.app}
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <div style={{ display: "flex", gap: 6 }}>
                <span style={{ color: C.sage500, fontSize: 12, flexShrink: 0, marginTop: 1 }}>✓</span>
                <Body style={{ fontSize: 11.5, color: C.ink500, lineHeight: 1.4, margin: 0 }}>{r.good}</Body>
              </div>
              <div style={{ display: "flex", gap: 6 }}>
                <span style={{ color: C.danger500, fontSize: 12, flexShrink: 0, marginTop: 1 }}>✕</span>
                <Body style={{ fontSize: 11.5, color: C.ink350, lineHeight: 1.4, margin: 0 }}>{r.bad}</Body>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Section 3 — Approach A/B/C comparison
// ---------------------------------------------------------------------------

interface BudgetPreset {
  key: string
  label: string
  hasBudget: boolean
  pct: number
  fill: string
  textColor: string
  spentLabel: string
  capLabel: string
}

const BUDGET_PRESETS: BudgetPreset[] = [
  { key: "none", label: "No budget set", hasBudget: false, pct: 0, fill: C.sageOnDark, textColor: C.sageOnDark, spentLabel: "3:42", capLabel: "" },
  { key: "normal", label: "Under budget", hasBudget: true, pct: 21, fill: C.sageOnDark, textColor: "rgba(244,239,230,.6)", spentLabel: "$0.42", capLabel: "$2.00 cap" },
  { key: "warning", label: "Near budget", hasBudget: true, pct: 84, fill: C.amberOnDark, textColor: C.amberOnDark, spentLabel: "$1.68", capLabel: "$2.00 cap" },
  { key: "over", label: "Over budget", hasBudget: true, pct: 117, fill: "#d97a70", textColor: "#d97a70", spentLabel: "$2.35", capLabel: "$2.00 cap" },
]

function ApproachABanner({ b }: { b: BudgetPreset }) {
  return (
    <div style={{ borderRadius: 20, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "11px 14px", display: "flex", alignItems: "center", gap: 10, width: 230 }}>
      <AgentAvatarTile size={22} dot={{ tone: "sage", pulse: true }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 4, minWidth: 0, flex: 1 }}>
        <span className={display.className} style={{ fontSize: 12.5, fontWeight: 700, color: C.cream }}>Claude Code</span>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.5)" }}>running</span>
          <span style={{ color: "rgba(244,239,230,.2)", fontSize: 10 }}>·</span>
          {b.hasBudget ? (
            <div style={{ height: 4, width: 48, borderRadius: 999, background: "rgba(244,239,230,.15)", overflow: "hidden" }}>
              <div style={{ height: "100%", borderRadius: 999, width: `${Math.min(100, b.pct)}%`, background: b.fill }} />
            </div>
          ) : (
            <span className={mono.className} style={{ fontSize: 10, color: C.sageOnDark }}>3:42</span>
          )}
        </div>
      </div>
    </div>
  )
}

function ApproachBBanner({ b }: { b: BudgetPreset }) {
  return (
    <div style={{ borderRadius: 20, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "11px 14px", display: "flex", flexDirection: "column", gap: 8, width: 230 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <AgentAvatarTile size={22} dot={{ tone: "sage", pulse: true }} />
        <span className={display.className} style={{ fontSize: 12.5, fontWeight: 700, color: C.cream, flex: 1 }}>Claude Code</span>
        <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.5)" }}>running</span>
      </div>
      {b.hasBudget ? (
        <div>
          <div style={{ height: 6, width: "100%", borderRadius: 999, background: "rgba(244,239,230,.15)", overflow: "hidden" }}>
            <div style={{ height: "100%", borderRadius: 999, width: `${Math.min(100, b.pct)}%`, background: b.fill }} />
          </div>
          <div className={mono.className} style={{ display: "flex", justifyContent: "space-between", marginTop: 4, fontSize: 9, color: "rgba(244,239,230,.35)" }}>
            <span>{b.spentLabel} spent</span>
            <span>{b.capLabel}</span>
          </div>
        </div>
      ) : (
        <span className={mono.className} style={{ fontSize: 10, color: C.sageOnDark }}>3:42 elapsed</span>
      )}
    </div>
  )
}

function ApproachCBanner({ b }: { b: BudgetPreset }) {
  return (
    <div style={{ borderRadius: 20, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", overflow: "hidden", width: 230 }}>
      <div style={{ padding: "11px 14px", display: "flex", alignItems: "center", gap: 10 }}>
        <AgentAvatarTile size={22} dot={{ tone: "sage", pulse: true }} />
        <div style={{ display: "flex", flexDirection: "column", gap: 4, minWidth: 0, flex: 1 }}>
          <span className={display.className} style={{ fontSize: 12.5, fontWeight: 700, color: C.cream }}>Claude Code</span>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.5)" }}>running</span>
            <span style={{ color: "rgba(244,239,230,.2)", fontSize: 10 }}>·</span>
            <span className={mono.className} style={{ fontSize: 10, color: b.hasBudget ? b.textColor : C.sageOnDark }}>{b.hasBudget ? b.spentLabel : "3:42"}</span>
          </div>
        </div>
      </div>
      {b.hasBudget && (
        <div style={{ height: 3, width: "100%", background: "rgba(244,239,230,.1)" }}>
          <div style={{ height: "100%", width: `${Math.min(100, b.pct)}%`, background: b.fill }} />
        </div>
      )}
    </div>
  )
}

const APPROACHES: {
  key: string
  label: string
  recommended?: boolean
  desc: string
  Banner: (props: { b: BudgetPreset }) => React.ReactElement
}[] = [
  {
    key: "a",
    label: "A — Replace the cost slot in place",
    recommended: true,
    desc: "Swaps the existing cost text for a slim bar (or live timer when unbudgeted) in the same spot. Smallest diff, reuses resolve() as-is.",
    Banner: ApproachABanner,
  },
  {
    key: "b",
    label: "B — Dedicated progress row",
    desc: "Flighty-style: a new full-width row with spent/cap labels at each end. More prominent, grows the banner's height.",
    Banner: ApproachBBanner,
  },
  {
    key: "c",
    label: "C — Keep numbers, add a hairline accent",
    desc: "Leaves the existing cost text untouched, adds a 3pt bar under the whole card as a secondary glance signal.",
    Banner: ApproachCBanner,
  },
]

// Approach D — a fourth idea straight out of the sweep (sweetgreen/Gopuff's
// milestone stepper). Not folded into the A/B/C grid above: it needs phase
// data (a known step sequence) that most open-ended agent loops don't have,
// so it's a candidate for phased workflows specifically, not a replacement.
const STEPS = ["Plan", "Edit", "Test", "Review"]

function StepperBanner({ current }: { current: number }) {
  return (
    <div style={{ borderRadius: 20, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "13px 16px", width: 280 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 12 }}>
        <AgentAvatarTile size={22} dot={{ tone: "sage", pulse: true }} />
        <span className={display.className} style={{ fontSize: 12.5, fontWeight: 700, color: C.cream, flex: 1 }}>Claude Code</span>
        <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.5)" }}>step {current + 1}/{STEPS.length}</span>
      </div>
      <div style={{ display: "flex", alignItems: "center" }}>
        {STEPS.map((step, i) => (
          <Fragment key={step}>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
              <span
                style={{
                  width: 9,
                  height: 9,
                  borderRadius: "50%",
                  background: i < current ? C.sageOnDark : i === current ? C.sageOnDark : "rgba(244,239,230,.18)",
                  animation: i === current ? "cds-pulse-sage 2s infinite" : "none",
                }}
              />
              <span className={mono.className} style={{ fontSize: 9, color: i <= current ? "rgba(244,239,230,.6)" : "rgba(244,239,230,.3)" }}>{step}</span>
            </div>
            {i < STEPS.length - 1 && (
              <div style={{ flex: 1, height: 1, background: i < current ? C.sageOnDark : "rgba(244,239,230,.14)", marginBottom: 14 }} />
            )}
          </Fragment>
        ))}
      </div>
    </div>
  )
}

function ApproachesSection() {
  return (
    <section>
      <SectionLabel tone="terra">Same data, three shapes</SectionLabel>
      <Headline size={24}>The progress affordance</Headline>
      <Body style={{ maxWidth: 640, margin: "10px 0 28px" }}>
        Sage bar when <code style={{ color: C.ink700 }}>ChatConversation.budgetUSD</code> is set (amber near cap, dusty-red
        over — no blue), live-incrementing timer (<code style={{ color: C.ink700 }}>Text(timerInterval:)</code>, no extra
        pushes) otherwise. Compare across all four budget states below — pick a row.
      </Body>

      <div style={{ overflowX: "auto" }}>
        <div style={{ minWidth: 800, display: "grid", gridTemplateColumns: "220px repeat(4, 1fr)", columnGap: 24, rowGap: 32 }}>
          <div />
          {BUDGET_PRESETS.map((b) => (
            <SectionLabel key={b.key}>{b.label}</SectionLabel>
          ))}

          {APPROACHES.map((a) => (
            <Fragment key={a.key}>
              <div style={{ display: "flex", flexDirection: "column", justifyContent: "center" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
                  <span className={display.className} style={{ fontSize: 13.5, fontWeight: 700, color: C.ink900 }}>{a.label}</span>
                  {a.recommended && <Badge tone="healthy">Recommended</Badge>}
                </div>
                <Body style={{ fontSize: 12, color: C.ink350, lineHeight: 1.45 }}>{a.desc}</Body>
              </div>
              {BUDGET_PRESETS.map((b) => (
                <div key={`${a.key}-${b.key}`} style={{ display: "flex", alignItems: "center" }}>
                  <a.Banner b={b} />
                </div>
              ))}
            </Fragment>
          ))}
        </div>
      </div>

      <div style={{ marginTop: 40, display: "flex", flexWrap: "wrap", gap: 24, alignItems: "center" }}>
        <div style={{ display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 220 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
            <span className={display.className} style={{ fontSize: 13.5, fontWeight: 700, color: C.ink900 }}>D — Milestone stepper</span>
            <Badge tone="warn">From the sweep</Badge>
          </div>
          <Body style={{ fontSize: 12, color: C.ink350, lineHeight: 1.45 }}>
            sweetgreen/Gopuff-style. Only fits workflows with a known phase sequence — most open-ended agent loops
            don&apos;t have one, so this is a candidate for structured/phased tasks specifically, not a general replacement.
          </Body>
        </div>
        <StepperBanner current={1} />
      </div>

      <Card style={{ marginTop: 24, maxWidth: 640, padding: "14px 16px", background: C.surfaceField }}>
        <Body style={{ margin: 0, color: C.ink500 }}>
          <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Update:</span>{" "}
          Tolan&apos;s circular icon-only mute/end buttons suggested a compact <span style={{ color: C.ink700 }}>Stop agent</span>{" "}
          action next to Approve/Deny — sketched further down this page, now that{" "}
          <code style={{ color: C.ink700 }}>CancellableIntent</code> (WWDC26) gives it a real mechanism instead of
          just a shape to borrow.
        </Body>
      </Card>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Section 4 — Can Live Activities show multiple agents at once?
//
// Two real constraints shape this, not just taste:
//  1. LancerLiveActivityManager.activities is keyed by hostID (one Activity
//     per host) — a second concurrent session on the SAME host today
//     overwrites the first's content rather than getting its own card.
//  2. Even once every host/agent has its own Activity, iOS only shows ONE
//     Live Activity at a time in the Dynamic Island (whichever most
//     recently updated) — multiple Activities only stack on the Lock
//     Screen, never in the Island. So "N agents in one Island" requires a
//     single aggregate Activity, not N individual ones competing for it.
// ---------------------------------------------------------------------------

interface FleetHost {
  name: string
  agent: string
  tone: "sage" | "amber" | "danger"
  label: string
  pending: number
}

const FLEET_SCENARIOS: Record<string, FleetHost[]> = {
  "1": [{ name: "mac-studio", agent: "claude", tone: "sage", label: "running", pending: 0 }],
  "2": [
    { name: "mac-studio", agent: "claude", tone: "sage", label: "running", pending: 0 },
    { name: "vps-fra", agent: "codex", tone: "amber", label: "needs you", pending: 1 },
  ],
  "3": [
    { name: "mac-studio", agent: "claude", tone: "sage", label: "running", pending: 0 },
    { name: "vps-fra", agent: "codex", tone: "amber", label: "needs you", pending: 1 },
    { name: "kimi-box", agent: "kimi", tone: "amber", label: "needs you", pending: 1 },
  ],
}

function FleetBanner({ hosts }: { hosts: FleetHost[] }) {
  const totalPending = hosts.reduce((n, h) => n + h.pending, 0)
  const runningCount = hosts.filter((h) => h.pending === 0).length

  // Single host — no aggregation needed, this IS the per-host card.
  if (hosts.length === 1) {
    const h = hosts[0]
    return (
      <div style={{ borderRadius: 24, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "13px 16px", display: "flex", alignItems: "center", gap: 12 }}>
        <AgentAvatarTile size={30} agent={h.agent} dot={{ tone: h.tone, pulse: true }} />
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.cream }}>{h.name}</span>
          <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.55)" }}>{h.label}</span>
        </div>
      </div>
    )
  }

  // Multiple hosts — aggregate card. Only offer a direct Approve/Deny when
  // there's exactly ONE pending approval fleet-wide (unambiguous which one
  // it acts on); otherwise it's a "Review" deep-link, never a guess.
  return (
    <div style={{ borderRadius: 24, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", overflow: "hidden" }}>
      <div style={{ padding: "13px 16px 4px" }}>
        <span className={mono.className} style={{ fontSize: 10, letterSpacing: ".08em", textTransform: "uppercase", color: "rgba(244,239,230,.4)" }}>
          {runningCount} running · {totalPending} {totalPending === 1 ? "needs" : "need"} you
        </span>
      </div>
      <div style={{ padding: "8px 16px", display: "flex", flexDirection: "column", gap: 10 }}>
        {hosts.slice(0, 3).map((h) => (
          <div key={h.name} style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <AgentAvatarTile size={22} agent={h.agent} dot={{ tone: h.tone, pulse: h.tone !== "sage" }} />
            <span className={display.className} style={{ fontSize: 12.5, fontWeight: 700, color: C.cream, flex: 1 }}>{h.name}</span>
            <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.5)" }}>{h.label}</span>
          </div>
        ))}
      </div>
      <div style={{ padding: "10px 16px 14px" }}>
        {totalPending === 1 ? (
          <div style={{ display: "flex", gap: 10 }}>
            <div className={body.className} style={{ flex: 1, textAlign: "center", borderRadius: 999, border: "1px solid rgba(244,239,230,.22)", padding: "7px 0", fontSize: 12, fontWeight: 600, color: "rgba(244,239,230,.8)" }}>Deny</div>
            <div className={body.className} style={{ flex: 1, textAlign: "center", borderRadius: 999, background: C.cream, padding: "7px 0", fontSize: 12, fontWeight: 600, color: C.ink900 }}>Approve</div>
          </div>
        ) : (
          <div className={body.className} style={{ textAlign: "center", borderRadius: 999, background: "rgba(224,164,92,.16)", padding: "7px 0", fontSize: 12, fontWeight: 600, color: C.amberOnDark }}>
            {totalPending} pending — Review
          </div>
        )}
      </div>
    </div>
  )
}

function FleetIslandCompact({ hosts }: { hosts: FleetHost[] }) {
  const totalPending = hosts.reduce((n, h) => n + h.pending, 0)
  if (hosts.length === 1) {
    return <DynamicIslandCompact leading={<AgentAvatarTile size={18} agent={hosts[0].agent} dot={{ tone: hosts[0].tone, pulse: true }} />} trailing={<span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.4)" }}>...</span>} />
  }
  return (
    <DynamicIslandCompact
      leading={
        <span style={{ display: "flex" }}>
          {hosts.slice(0, 2).map((h, i) => (
            <span key={h.name} style={{ marginLeft: i === 0 ? 0 : -8, border: "2px solid #000", borderRadius: 8, display: "inline-flex" }}>
              <AgentAvatarTile size={16} agent={h.agent} />
            </span>
          ))}
        </span>
      }
      trailing={totalPending > 0 ? <span className={mono.className} style={{ fontSize: 11, fontWeight: 600, color: C.amberOnDark }}>{totalPending}</span> : <span className={mono.className} style={{ fontSize: 10, color: "rgba(244,239,230,.4)" }}>{hosts.length}</span>}
    />
  )
}

function FleetSummaryDemo() {
  const [count, setCount] = useState<"1" | "2" | "3">("2")
  const hosts = FLEET_SCENARIOS[count]

  return (
    <section>
      <SectionLabel tone="terra">Answering a real question, not a hypothetical</SectionLabel>
      <Headline size={24}>Can it show multiple agents?</Headline>
      <Body style={{ maxWidth: 680, margin: "10px 0 20px" }}>
        Two different constraints, two different fixes. <strong style={{ color: C.ink700 }}>Same-host sessions</strong> need a code
        fix — <code style={{ color: C.ink700 }}>activities</code> is keyed by <code style={{ color: C.ink700 }}>hostID</code>, so a
        second concurrent session today overwrites the first instead of getting its own card. <strong style={{ color: C.ink700 }}>Multiple
        hosts</strong> already get separate activities, but the Dynamic Island only ever shows one at a time (an iOS constraint, not
        ours) — showing several agents *in the Island* means one aggregate Activity, not several competing for the same pill.
      </Body>

      <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
        {(["1", "2", "3"] as const).map((n) => (
          <Chip key={n} active={count === n} onClick={() => setCount(n)}>
            {n} host{n === "1" ? "" : "s"}
          </Chip>
        ))}
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-start", gap: 40 }}>
        <LockScreenFrame label="lock screen">
          <FleetBanner hosts={hosts} />
        </LockScreenFrame>
        <div style={{ display: "flex", flexDirection: "column", gap: 8, paddingTop: 16 }}>
          <SectionLabel>Island — compact</SectionLabel>
          <FleetIslandCompact hosts={hosts} />
        </div>
      </div>

      <Card style={{ marginTop: 32, maxWidth: 680, padding: "14px 16px" }}>
        <Body style={{ margin: 0 }}>
          <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>The rule that keeps this honest:</span> the
          card only offers a direct Approve/Deny when exactly <em>one</em>{" "}
          approval is pending fleet-wide — unambiguous which one it acts on. The moment a second approval queues up anywhere, it
          drops to a plain &quot;N pending — Review&quot; deep-link rather than guess. &quot;The thing that needs you comes
          first&quot; only holds if the action is never ambiguous.
        </Body>
      </Card>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Closing the iOS 26/27 platform gaps flagged in "What we ship today":
// .supplementalActivityFamilies (WWDC25, still current — confirmed no WWDC26
// replacement), isDynamicIslandLimitedInWidth + showsWidgetContainerBackground
// (WWDC26 "Live Activities essentials", session 223).
// ---------------------------------------------------------------------------

function WatchTile() {
  return (
    <div style={{ width: 168, height: 168, borderRadius: 34, background: "rgba(13,12,11,.92)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8 }}>
      <AgentAvatarTile size={40} dot={{ tone: "amber", pulse: true }} />
      <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.5)" }}>1 pending</span>
    </div>
  )
}

function CarPlayCard() {
  return (
    <div style={{ width: 360, height: 110, borderRadius: 22, background: "rgba(13,12,11,.92)", display: "flex", alignItems: "center", gap: 18, padding: "0 24px" }}>
      <AgentAvatarTile size={56} dot={{ tone: "amber", pulse: true }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span className={display.className} style={{ fontSize: 22, fontWeight: 700, color: C.cream }}>Needs you</span>
        <span className={mono.className} style={{ fontSize: 13, color: "rgba(244,239,230,.5)" }}>vps-fra</span>
      </div>
    </div>
  )
}

function WatchCarPlaySection() {
  return (
    <section>
      <SectionLabel tone="terra">Closing the iOS 26 gap — WWDC25, still current</SectionLabel>
      <Headline size={24}>Watch &amp; CarPlay presence</Headline>
      <Body style={{ maxWidth: 680, margin: "10px 0 28px" }}>
        Confirmed via a second research pass: no WWDC26 replacement — <code style={{ color: C.ink700 }}>.supplementalActivityFamilies([.small])</code>{" "}
        plus reading the <code style={{ color: C.ink700 }}>activityFamily</code> environment value is still the
        mechanism. &quot;.small&quot; means drastically reduced, not a shrunk copy of the main layout — Apple&apos;s
        own guidance. Watch gets a glanceable tile; CarPlay gets a driving-safe card, one huge word, nothing
        fine-print.
      </Body>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 40, alignItems: "center" }}>
        <div>
          <SectionLabel>Watch — Smart Stack tile</SectionLabel>
          <div style={{ marginTop: 10 }}>
            <WatchTile />
          </div>
        </div>
        <div>
          <SectionLabel>CarPlay — dashboard card</SectionLabel>
          <div style={{ marginTop: 10 }}>
            <CarPlayCard />
          </div>
        </div>
      </div>
    </section>
  )
}

function LandscapeCompact({ limited }: { limited: boolean }) {
  return (
    <DynamicIslandCompact
      leading={<AgentAvatarTile size={18} dot={{ tone: "amber", pulse: true }} />}
      trailing={
        limited ? (
          <span style={{ fontSize: 13 }}>●</span>
        ) : (
          <span className={mono.className} style={{ fontSize: 11, fontWeight: 600, color: C.amberOnDark }}>1</span>
        )
      }
    />
  )
}

function StandByBanner() {
  // No gradient/blur here — showsWidgetContainerBackground is false in
  // StandBy, so the real widget swaps to .activityBackgroundTint() for an
  // edge-to-edge fill instead of the Lock Screen's translucent card.
  return (
    <div style={{ width: 300, height: 160, borderRadius: 28, background: "#3a2410", display: "flex", alignItems: "center", gap: 16, padding: "0 28px" }}>
      <AgentAvatarTile size={44} dot={{ tone: "amber", pulse: true }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <span className={display.className} style={{ fontSize: 24, fontWeight: 700, color: C.cream }}>Claude Code</span>
        <span className={mono.className} style={{ fontSize: 14, color: "rgba(244,239,230,.6)" }}>1 pending · vps-fra</span>
      </div>
    </div>
  )
}

function LandscapeStandBySection() {
  return (
    <section>
      <SectionLabel tone="terra">Closing the iOS 27 gap — WWDC26 session 223, verified this pass</SectionLabel>
      <Headline size={24}>Landscape &amp; StandBy</Headline>
      <Body style={{ maxWidth: 680, margin: "10px 0 28px" }}>
        Two separate environment values, two separate fixes.{" "}
        <code style={{ color: C.ink700 }}>isDynamicIslandLimitedInWidth</code> is true in landscape — compact views
        need an icon-only fallback since there&apos;s no room to grow horizontally.{" "}
        <code style={{ color: C.ink700 }}>showsWidgetContainerBackground</code> is false in StandBy (charging +
        landscape) — the Lock Screen&apos;s translucent card at 200% scale leaves blank space around the edges, so
        StandBy needs <code style={{ color: C.ink700 }}>.activityBackgroundTint()</code> for an edge-to-edge fill
        instead.
      </Body>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 40, alignItems: "flex-start", marginBottom: 32 }}>
        <div>
          <SectionLabel>Portrait compact (unconstrained)</SectionLabel>
          <div style={{ marginTop: 10 }}>
            <LandscapeCompact limited={false} />
          </div>
        </div>
        <div>
          <SectionLabel>Landscape compact — isDynamicIslandLimitedInWidth</SectionLabel>
          <div style={{ marginTop: 10 }}>
            <LandscapeCompact limited={true} />
          </div>
        </div>
      </div>
      <div>
        <SectionLabel>StandBy — 200% scale, edge-to-edge tint, no gradient</SectionLabel>
        <div style={{ marginTop: 10 }}>
          <StandByBanner />
        </div>
      </div>
    </section>
  )
}

// ---------------------------------------------------------------------------
// The parked "Stop agent" idea, now with a real mechanism behind it —
// CancellableIntent (WWDC26 session 345) handles the cleanup, LongRunningIntent
// covers the Siri-initiated case. Tolan's circular icon-only shape, adapted.
// ---------------------------------------------------------------------------

function StopButton() {
  return (
    <span style={{ width: 34, height: 34, borderRadius: 17, background: "rgba(217,122,112,.18)", display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="#d97a70" strokeWidth={2.5} strokeLinecap="round">
        <line x1="6" y1="6" x2="18" y2="18" />
        <line x1="18" y1="6" x2="6" y2="18" />
      </svg>
    </span>
  )
}

function StopActionSection() {
  return (
    <section>
      <SectionLabel tone="terra">Previously parked, now has a mechanism — CancellableIntent</SectionLabel>
      <Headline size={24}>A Stop button, built</Headline>
      <Body style={{ maxWidth: 680, margin: "10px 0 28px" }}>
        Tolan&apos;s circular icon-only end-call button, adapted — sits opposite the agent name on a{" "}
        <em>running</em> card (not just needs-approval), since stopping a runaway agent shouldn&apos;t require
        opening the app.
      </Body>
      <LockScreenFrame label="lock screen — running, stoppable">
        <div style={{ borderRadius: 24, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "13px 16px", display: "flex", alignItems: "center", gap: 12 }}>
          <AgentAvatarTile size={30} dot={{ tone: "sage", pulse: true }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, flex: 1 }}>
            <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.cream }}>Claude Code</span>
            <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.55)" }}>running · $0.34</span>
          </div>
          <StopButton />
        </div>
      </LockScreenFrame>
    </section>
  )
}

// ---------------------------------------------------------------------------

export default function LiveActivityPage() {
  return (
    <div
      className={body.className}
      style={{
        minHeight: "100vh",
        background: `linear-gradient(180deg, ${C.paperGradTop} 0%, ${C.paperGradBot} 100%)`,
        padding: "64px 32px",
      }}
    >
      <style>{KEYFRAMES}</style>
      <div style={{ maxWidth: 1040, margin: "0 auto" }}>
        <Link
          href="/"
          className={mono.className}
          style={{ fontSize: 11, color: C.ink350, textTransform: "uppercase", letterSpacing: ".08em", textDecoration: "none" }}
        >
          ← back to board
        </Link>

        <div style={{ marginTop: 28, marginBottom: 6 }}>
          <SectionLabel tone="terra">Design companion · Live Activity</SectionLabel>
        </div>
        <Eyebrow>an agent keeps working while your phone is locked</Eyebrow>
        <Headline size={38}>Live Activity &amp; Dynamic Island</Headline>
        <Body style={{ maxWidth: 720, marginTop: 14, marginBottom: 56 }}>
          Lancer already ships a push-driven Live Activity (<code style={{ color: C.ink700 }}>LiveActivityManager.swift</code>,{" "}
          <code style={{ color: C.ink700 }}>LancerLiveActivityWidget.swift</code>) with lock-screen + Dynamic Island surfaces,
          Approve/Deny via <code style={{ color: C.ink700 }}>ApprovalActionIntent</code>, and cold-launch push-to-start. The
          cost-vs-budget bar logic in <code style={{ color: C.ink700 }}>LiveActivityPresentation.resolve()</code> exists but is
          never fed the real <code style={{ color: C.ink700 }}>ChatConversation.budgetUSD</code> — this page works through
          fixing that and picking a rendering approach, restyled to the <strong style={{ color: C.ink700 }}>Editorial · Sand</strong>{" "}
          system (warm paper, terracotta, sage/amber/danger — no blue).
        </Body>

        <div style={{ display: "flex", flexDirection: "column", gap: 80 }}>
          <SessionStateDemo />
          <MobbinReferencesSection />
          <SecondSweepSection />
          <ApproachesSection />
          <FleetSummaryDemo />
          <WatchCarPlaySection />
          <LandscapeStandBySection />
          <StopActionSection />
        </div>
      </div>
    </div>
  )
}
