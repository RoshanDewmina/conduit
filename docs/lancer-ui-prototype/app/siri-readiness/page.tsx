"use client"

import Link from "next/link"
import { display, body, mono, serif, C, SectionLabel, Eyebrow, Headline, Body, Card, Badge, AgentAvatarTile, HostIconTile } from "@/components/conduit/brand"
import { SiriSnippetFrame } from "@/components/siri-snippet-frame"

// ---------------------------------------------------------------------------
// Sourced from WWDC26 (the apple-docs tool only indexes through WWDC25 — this
// was pulled live via WebSearch/WebFetch against developer.apple.com, plus
// the App Schema Domains reference page fetched directly through apple-docs).
// ---------------------------------------------------------------------------

function SourceLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className={mono.className} style={{ fontSize: 10.5, color: C.terra700, textDecoration: "underline", textUnderlineOffset: 2 }}>
      {children} ↗
    </a>
  )
}

function PrimitiveCard({ title, tag, children, sourceHref, sourceLabel }: { title: string; tag: string; children: React.ReactNode; sourceHref: string; sourceLabel: string }) {
  return (
    <Card style={{ padding: 18 }}>
      <Badge tone="warn">{tag}</Badge>
      <div className={display.className} style={{ fontSize: 15, fontWeight: 700, color: C.ink900, marginTop: 10, marginBottom: 6 }}>
        {title}
      </div>
      <Body style={{ fontSize: 13, lineHeight: 1.5, marginBottom: 10 }}>{children}</Body>
      <SourceLink href={sourceHref}>{sourceLabel}</SourceLink>
    </Card>
  )
}

type Status = "not-started" | "foundational" | "sketched"

function StatusPill({ status }: { status: Status }) {
  if (status === "foundational") return <Badge tone="high">Blocks the rest</Badge>
  if (status === "sketched") return <Badge tone="healthy">Sketched above</Badge>
  return <Badge tone="low">Not started</Badge>
}

function PlanRow({ title, status, children }: { title: string; status: Status; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", gap: 14, padding: "14px 0", borderBottom: `1px solid ${C.line}` }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.ink900 }}>{title}</span>
          <StatusPill status={status} />
        </div>
        <Body style={{ fontSize: 12.5, lineHeight: 1.5, margin: 0 }}>{children}</Body>
      </div>
    </div>
  )
}

function SnippetRow({ title, kind, sketched = false, children }: { title: string; kind: "Result" | "Confirmation"; sketched?: boolean; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", gap: 14, padding: "14px 0", borderBottom: `1px solid ${C.line}` }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.ink900 }}>{title}</span>
          <Badge tone={kind === "Confirmation" ? "warn" : "low"}>{kind}</Badge>
          {sketched && <Badge tone="healthy">Sketched above</Badge>}
        </div>
        <Body style={{ fontSize: 12.5, lineHeight: 1.5, margin: 0 }}>{children}</Body>
      </div>
    </div>
  )
}

function OrderStep({ n, title, sketched = false, children }: { n: number; title: string; sketched?: boolean; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", gap: 14 }}>
      <span
        className={display.className}
        style={{
          flexShrink: 0,
          width: 26,
          height: 26,
          borderRadius: 13,
          background: sketched ? C.sage500 : C.ink900,
          color: "#fff",
          fontSize: 12,
          fontWeight: 700,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {sketched ? "✓" : n}
      </span>
      <div style={{ flex: 1, paddingBottom: 24 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.ink900 }}>{title}</span>
          {sketched && <Badge tone="healthy">Sketched</Badge>}
        </div>
        <Body style={{ fontSize: 12.5, lineHeight: 1.5, margin: 0 }}>{children}</Body>
      </div>
    </div>
  )
}

// System-rendered row — the ONLY visual control we have here is title,
// subtitle, and icon. Apple owns the chrome (disambiguation sheet, Spotlight,
// Shortcuts row), so this deliberately does NOT use the brand's warm-paper
// styling — it's a plain approximation of native list-row chrome, styled
// distinctly from our own Card so the contrast with the Snippet reads at a
// glance.
function SystemListRow({ icon, title, subtitle }: { icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "11px 14px", background: "#fff", borderRadius: 10, border: "1px solid #e5e5ea" }}>
      {icon}
      <div style={{ display: "flex", flexDirection: "column", gap: 1, minWidth: 0 }}>
        <span style={{ fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: 15, fontWeight: 600, color: "#000", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
          {title}
        </span>
        <span style={{ fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: 13, color: "#8e8e93" }}>{subtitle}</span>
      </div>
    </div>
  )
}

function EntitySection({ name, note, icon, title, subtitle, snippetTitle, snippetSubtitle }: {
  name: string
  note: string
  icon: React.ReactNode
  title: string
  subtitle: string
  snippetTitle: string
  snippetSubtitle: string
}) {
  return (
    <div style={{ marginBottom: 28 }}>
      <div className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.ink900, marginBottom: 4 }}>{name}</div>
      <Body style={{ fontSize: 12, color: C.ink350, marginBottom: 12 }}>{note}</Body>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        <div>
          <SectionLabel>System-rendered (Spotlight / disambiguation / Shortcuts)</SectionLabel>
          <div style={{ marginTop: 8, padding: 12, background: "#f2f2f7", borderRadius: 14 }}>
            <SystemListRow icon={icon} title={title} subtitle={subtitle} />
          </div>
        </div>
        <div>
          <SectionLabel>Custom Snippet (fully branded)</SectionLabel>
          <div style={{ marginTop: 8, borderRadius: 20, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "13px 16px", display: "flex", alignItems: "center", gap: 12 }}>
            {icon}
            <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
              <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.cream, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {snippetTitle}
              </span>
              <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.55)" }}>{snippetSubtitle}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// Result snippet chrome — rounded, dark, and deliberately larger type than
// the Live Activity cards (Apple's own rule: snippet text sizes above system
// defaults for glanceability at a distance). Single "Done" button, per the
// Result-snippet contract — no follow-up action needed to dismiss it.
function SnippetShell({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ borderRadius: 28, background: "rgba(13,12,11,.94)", boxShadow: "0 12px 30px -10px rgba(0,0,0,.5)", padding: "18px 18px 14px", display: "flex", flexDirection: "column", gap: 14 }}>
      {children}
      <div className={body.className} style={{ textAlign: "center", borderRadius: 999, background: "rgba(244,239,230,.1)", padding: "10px 0", fontSize: 14, fontWeight: 600, color: C.cream }}>
        Done
      </div>
    </div>
  )
}

function AgentStatusQuerySnippetView() {
  const hosts = [
    { name: "mac-studio", agent: "claude", tone: "sage" as const, label: "running" },
    { name: "vps-fra", agent: "codex", tone: "amber" as const, label: "needs you" },
    { name: "kimi-box", agent: "kimi", tone: "amber" as const, label: "needs you" },
  ]
  return (
    <SnippetShell>
      <div>
        <span className={mono.className} style={{ fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase", color: "rgba(244,239,230,.4)" }}>
          1 running · 2 need you
        </span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        {hosts.map((h) => (
          <div key={h.name} style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <AgentAvatarTile size={30} agent={h.agent} dot={{ tone: h.tone, pulse: h.tone !== "sage" }} />
            <span className={display.className} style={{ fontSize: 16, fontWeight: 700, color: C.cream, flex: 1 }}>{h.name}</span>
            <span className={mono.className} style={{ fontSize: 12, color: "rgba(244,239,230,.5)" }}>{h.label}</span>
          </div>
        ))}
      </div>
    </SnippetShell>
  )
}

function PendingApprovalsSnippetView() {
  const approvals = [
    { agent: "codex", host: "vps-fra", action: "git push --force origin main", risk: "danger" as const },
    { agent: "kimi", host: "kimi-box", action: "rm ./node_modules -rf", risk: "amber" as const },
  ]
  return (
    <SnippetShell>
      <div>
        <span className={mono.className} style={{ fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase", color: "rgba(244,239,230,.4)" }}>
          2 pending approvals
        </span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {approvals.map((a) => (
          <div key={a.action} style={{ display: "flex", alignItems: "center", gap: 12, borderRadius: 16, background: "rgba(244,239,230,.05)", padding: "10px 12px" }}>
            <AgentAvatarTile size={26} agent={a.agent} dot={{ tone: a.risk, pulse: false }} />
            <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, flex: 1 }}>
              <span className={mono.className} style={{ fontSize: 13, color: C.cream, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{a.action}</span>
              <span className={mono.className} style={{ fontSize: 10.5, color: "rgba(244,239,230,.4)" }}>{a.host}</span>
            </div>
          </div>
        ))}
      </div>
    </SnippetShell>
  )
}

// Confirmation snippet chrome — two buttons: a secondary dismiss and a
// primary action-verb button, per Apple's rule (the verb makes clear what's
// next: "Stop", "Approve", never a generic "OK"). Mirrors the Live
// Activity's own Approve/Deny pair so the two surfaces feel like one system.
function SnippetShellConfirm({ children, secondaryLabel, primaryLabel, primaryTone = "cream" }: {
  children: React.ReactNode
  secondaryLabel: string
  primaryLabel: string
  primaryTone?: "cream" | "danger"
}) {
  return (
    <div style={{ borderRadius: 28, background: "rgba(13,12,11,.94)", boxShadow: "0 12px 30px -10px rgba(0,0,0,.5)", padding: "18px 18px 14px", display: "flex", flexDirection: "column", gap: 14 }}>
      {children}
      <div style={{ display: "flex", gap: 10 }}>
        <div className={body.className} style={{ flex: 1, textAlign: "center", borderRadius: 999, border: "1px solid rgba(244,239,230,.22)", padding: "10px 0", fontSize: 14, fontWeight: 600, color: "rgba(244,239,230,.8)" }}>
          {secondaryLabel}
        </div>
        <div
          className={body.className}
          style={{
            flex: 1,
            textAlign: "center",
            borderRadius: 999,
            padding: "10px 0",
            fontSize: 14,
            fontWeight: 600,
            background: primaryTone === "danger" ? "#d97a70" : C.cream,
            color: primaryTone === "danger" ? "#2a0f0c" : C.ink900,
          }}
        >
          {primaryLabel}
        </div>
      </div>
    </div>
  )
}

function PauseStopSnippetView({ disambiguate }: { disambiguate: boolean }) {
  const runs = [
    { name: "mac-studio", agent: "claude" },
    { name: "vps-fra", agent: "codex" },
  ]
  if (!disambiguate) {
    return (
      <SnippetShellConfirm secondaryLabel="Cancel" primaryLabel="Stop">
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <AgentAvatarTile size={30} agent="claude" dot={{ tone: "sage", pulse: true }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
            <span className={display.className} style={{ fontSize: 16, fontWeight: 700, color: C.cream }}>Stop Claude Code?</span>
            <span className={mono.className} style={{ fontSize: 12, color: "rgba(244,239,230,.5)" }}>mac-studio · running 4m</span>
          </div>
        </div>
      </SnippetShellConfirm>
    )
  }
  return (
    <div style={{ borderRadius: 28, background: "rgba(13,12,11,.94)", boxShadow: "0 12px 30px -10px rgba(0,0,0,.5)", padding: "18px 18px 14px", display: "flex", flexDirection: "column", gap: 14 }}>
      <span className={display.className} style={{ fontSize: 16, fontWeight: 700, color: C.cream }}>Which one?</span>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {runs.map((r) => (
          <div key={r.name} style={{ display: "flex", alignItems: "center", gap: 12, borderRadius: 16, background: "rgba(244,239,230,.05)", padding: "10px 12px" }}>
            <AgentAvatarTile size={26} agent={r.agent} dot={{ tone: "sage", pulse: true }} />
            <span className={mono.className} style={{ fontSize: 13, color: C.cream, flex: 1 }}>{r.name}</span>
          </div>
        ))}
      </div>
      <div className={body.className} style={{ textAlign: "center", borderRadius: 999, border: "1px solid rgba(244,239,230,.22)", padding: "10px 0", fontSize: 14, fontWeight: 600, color: "rgba(244,239,230,.8)" }}>
        Cancel
      </div>
    </div>
  )
}

// Reuses the Live Activity's own banded-header language (amber = routine,
// danger = high-risk escalation) inside the Confirmation snippet, so the
// same visual vocabulary means the same thing on both surfaces.
function ApproveSnippetView({ highRisk }: { highRisk: boolean }) {
  return (
    <div style={{ borderRadius: 28, background: "rgba(13,12,11,.94)", boxShadow: "0 12px 30px -10px rgba(0,0,0,.5)", overflow: "hidden" }}>
      <div style={{ background: highRisk ? "rgba(217,122,112,.22)" : "rgba(224,164,92,.18)", padding: "9px 18px", display: "flex", alignItems: "center", gap: 8 }}>
        <span className={mono.className} style={{ fontSize: 11, letterSpacing: ".08em", textTransform: "uppercase", color: highRisk ? "#e89a90" : "#E0A45C", fontWeight: 500 }}>
          {highRisk ? "High-risk action" : "Needs your approval"}
        </span>
      </div>
      <div style={{ padding: "16px 18px 14px", display: "flex", flexDirection: "column", gap: 14 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <AgentAvatarTile size={30} agent="codex" dot={{ tone: highRisk ? "danger" : "amber", pulse: false }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
            <span className={mono.className} style={{ fontSize: 14, color: C.cream, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
              git push --force origin main
            </span>
            <span className={mono.className} style={{ fontSize: 11.5, color: "rgba(244,239,230,.5)" }}>vps-fra · Codex</span>
          </div>
        </div>
        <div style={{ display: "flex", gap: 10 }}>
          <div className={body.className} style={{ flex: 1, textAlign: "center", borderRadius: 999, border: "1px solid rgba(244,239,230,.22)", padding: "10px 0", fontSize: 14, fontWeight: 600, color: "rgba(244,239,230,.8)" }}>
            Deny
          </div>
          <div className={body.className} style={{ flex: 1, textAlign: "center", borderRadius: 999, background: C.cream, padding: "10px 0", fontSize: 14, fontWeight: 600, color: C.ink900 }}>
            Approve
          </div>
        </div>
      </div>
    </div>
  )
}

// RelevantEntities surfaces through system chrome (Spotlight's empty-state
// suggestions), not a custom Snippet — same constraint as the entity display
// representations above. Modeled on the "recent/popular before you type"
// pattern several Mobbin references used (Tripadvisor, Uber Eats), the
// closest real analog available since Mobbin has no genuine RelevantEntities
// captures to reference directly.
function SpotlightSuggestedRow() {
  return (
    <div style={{ background: "#fff", borderRadius: 14, border: "1px solid #e5e5ea", overflow: "hidden" }}>
      <div style={{ padding: "10px 14px", borderBottom: "1px solid #e5e5ea" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, background: "#f2f2f7", borderRadius: 10, padding: "8px 12px" }}>
          <span style={{ color: "#8e8e93", fontSize: 14 }}>⌕</span>
          <span style={{ fontFamily: "-apple-system, sans-serif", fontSize: 15, color: "#c7c7cc" }}>Search</span>
        </div>
      </div>
      <div style={{ padding: "10px 14px 4px" }}>
        <span style={{ fontFamily: "-apple-system, sans-serif", fontSize: 11, fontWeight: 600, color: "#8e8e93", textTransform: "uppercase", letterSpacing: ".02em" }}>
          Suggested
        </span>
      </div>
      <div style={{ padding: "6px 14px 12px" }}>
        <SystemListRow icon={<AgentAvatarTile size={30} agent="codex" dot={{ tone: "danger", pulse: false }} />} title="git push --force origin main" subtitle="Lancer · vps-fra · high risk" />
      </div>
    </div>
  )
}

// LongRunningIntent's auto-generated Live Activity is deliberately generic —
// system chrome, not ours — so this comparison is honest about the
// difference rather than implying it inherits our branding for free.
function SystemGeneratedActivity() {
  return (
    <div style={{ borderRadius: 22, background: "#1c1c1e", padding: "14px 16px", display: "flex", alignItems: "center", gap: 12 }}>
      <div style={{ width: 28, height: 28, borderRadius: 14, border: "2px solid rgba(255,255,255,.2)", borderTopColor: "#fff", flexShrink: 0 }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 6, flex: 1 }}>
        <span style={{ fontFamily: "-apple-system, sans-serif", fontSize: 14, fontWeight: 600, color: "#fff" }}>Starting Claude Code…</span>
        <div style={{ height: 4, borderRadius: 2, background: "rgba(255,255,255,.15)", overflow: "hidden" }}>
          <div style={{ height: "100%", width: "35%", borderRadius: 2, background: "#fff" }} />
        </div>
      </div>
      <span style={{ width: 26, height: 26, borderRadius: 13, background: "rgba(255,255,255,.12)", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff", fontSize: 11, flexShrink: 0 }}>✕</span>
    </div>
  )
}

export default function SiriReadinessPage() {
  return (
    <div className={body.className} style={{ minHeight: "100vh", background: `linear-gradient(180deg, ${C.paperGradTop} 0%, ${C.paperGradBot} 100%)`, padding: "64px 32px" }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <Link href="/" className={mono.className} style={{ fontSize: 11, color: C.ink350, textTransform: "uppercase", letterSpacing: ".08em", textDecoration: "none" }}>
          ← back to board
        </Link>

        <div style={{ marginTop: 28, marginBottom: 6 }}>
          <SectionLabel tone="terra">Design companion · Siri &amp; App Intents</SectionLabel>
        </div>
        <Eyebrow>getting ready before Siri AI arrives, not after</Eyebrow>
        <Headline size={38}>Siri readiness — the full plan</Headline>
        <Body style={{ maxWidth: 720, marginTop: 14, marginBottom: 8 }}>
          The <code style={{ color: C.ink700 }}>action-layer / Siri / MCP</code> engineering plan sized{" "}
          <code style={{ color: C.ink700 }}>CommandGateway</code> + broadened AppIntents against the WWDC25-era App
          Intents model. WWDC26 shipped a materially different primitive set — <strong style={{ color: C.ink700 }}>App
          Schemas</strong>, <strong style={{ color: C.ink700 }}>View Annotations</strong>, and{" "}
          <strong style={{ color: C.ink700 }}>OwnershipProvidingEntity</strong> — that changes how much of this is
          &quot;write custom phrase-matching code&quot; vs. &quot;model your data correctly and inherit Siri&apos;s
          understanding for free.&quot; This page is the full inventory before we design any single piece.
        </Body>
        <Body style={{ maxWidth: 720, marginBottom: 56, fontSize: 12.5, color: C.ink350 }}>
          Sourced from WWDC26 sessions 240, 343, 344 and the App Schema Domains reference (the apple-docs tool only
          indexes through WWDC25 — this was pulled live). Not from the apple-docs tool&apos;s indexed archive.
        </Body>

        <div style={{ display: "flex", flexDirection: "column", gap: 64 }}>
          {/* ---------------- What changed ---------------- */}
          <section>
            <SectionLabel tone="terra">Three primitives that change the plan</SectionLabel>
            <Headline size={24}>What WWDC26 actually shipped</Headline>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 16, marginTop: 20 }}>
              <PrimitiveCard title="View Annotations API" tag="On-screen resolution" sourceHref="https://developer.apple.com/videos/play/wwdc2026/343/" sourceLabel="WWDC26 · Session 343">
                <code style={{ color: C.ink700 }}>.appEntityIdentifier(...)</code> on a view (or{" "}
                <code style={{ color: C.ink700 }}>forSelectionType:</code>{" "}
                on a list) tells Siri what&apos;s on screen. Foregrounded + looking at a session → &quot;pause
                this&quot; resolves with zero
                disambiguation. Dissolves most of the plan&apos;s &quot;which host?&quot; AppEntity/EntityQuery
                fiddliness for the common case. Voice-only-while-locked still needs the fallback.
              </PrimitiveCard>
              <PrimitiveCard title="OwnershipProvidingEntity" tag="Safety mechanism" sourceHref="https://developer.apple.com/videos/play/wwdc2026/343/" sourceLabel="WWDC26 · Session 343">
                Siri auto-injects a confirmation step for intents with meaningful side effects on{" "}
                <code style={{ color: C.ink700 }}>.shared</code>/<code style={{ color: C.ink700 }}>.public</code>-owned
                entities. Replaces the plan&apos;s blanket &quot;never expose approve to Siri&quot; with &quot;mark the
                entity so Siri always forces a tap&quot; — same guarantee, less restrictive, matches the tap-to-approve
                decision already made for snippets.
              </PrimitiveCard>
              <PrimitiveCard title="AppIntentsTesting framework" tag="Verification" sourceHref="https://developer.apple.com/videos/play/wwdc2026/240/" sourceLabel="WWDC26 · Session 240">
                Validates the Siri/Shortcuts/Spotlight integration through real system pathways — no UI automation, no
                real device. Weakens (doesn&apos;t eliminate) the plan&apos;s &quot;Siri invocation can&apos;t be
                verified in the simulator&quot; constraint for the business-logic layer specifically.
              </PrimitiveCard>
            </div>
            <Card style={{ marginTop: 16, padding: "14px 16px", background: C.surfaceField }}>
              <Body style={{ margin: 0, fontSize: 12.5 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Also checked:</span>{" "}
                the full App Schema Domain list (Audio, Calendar, Camera, Clock, Files, Mail, Maps, Messages, Notes, Phone,
                Photos, Reminders, System-and-in-app-search, Assistant, Visual-Intelligence, plus several
                Shortcuts-only creative-app domains). None fit &quot;pause/resume/cancel a process&quot; or
                &quot;approve/deny a request&quot; — confirms those stay custom App Intents, not domain-adopting ones,
                exactly as the original plan assumed. One domain fit fell out: <code style={{ color: C.ink700 }}>.system.searchInApp</code>{" "}
                for &quot;search my approvals&quot; / &quot;search the audit log.&quot;
              </Body>
            </Card>
          </section>

          {/* ---------------- More primitives ---------------- */}
          <section>
            <SectionLabel tone="terra">Went back for more — session 345, not indexed on the first pass</SectionLabel>
            <Headline size={24}>Two more that change the shape of this</Headline>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 16, marginTop: 20 }}>
              <PrimitiveCard title="LongRunningIntent + ProgressReportingIntent" tag="Architecture, not cosmetic" sourceHref="https://developer.apple.com/videos/play/wwdc2026/345/" sourceLabel="WWDC26 · Session 345">
                Starting an agent run via Siri doesn&apos;t need a hand-built Live Activity — a{" "}
                <code style={{ color: C.ink700 }}>LongRunningIntent</code> conforming to{" "}
                <code style={{ color: C.ink700 }}>ProgressReportingIntent</code>{" "}
                gets the system to generate one automatically, stop button included, with{" "}
                <code style={{ color: C.ink700 }}>CancellableIntent</code> handling cleanup. Doesn&apos;t replace the
                app&apos;s own rich Live Activity (status dots, cost, banded approvals — far more detail than a
                generic progress bar) for app-initiated sessions — but is the right shape for a
                Siri-initiated &quot;start Claude Code on mac-studio,&quot; where no session exists yet to build a
                custom activity around.
              </PrimitiveCard>
              <PrimitiveCard title="RelevantEntities" tag="Proactive surfacing" sourceHref="https://developer.apple.com/videos/play/wwdc2026/345/" sourceLabel="WWDC26 · Session 345">
                Hints Siri/Spotlight to surface an entity before anyone asks for it — not search, not a donation, a
                direct &quot;this matters right now&quot; signal. Register the pending{" "}
                <code style={{ color: C.ink700 }}>ApprovalEntity</code> the moment it&apos;s created, clear it the
                moment it resolves. Directly serves the brand spine — &quot;the thing that needs you comes
                first&quot; — as a system-level surfacing mechanism, not just an in-app one.
              </PrimitiveCard>
            </div>
            <Card style={{ marginTop: 16, padding: "14px 16px", background: C.surfaceField }}>
              <Body style={{ margin: 0, fontSize: 12.5 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Two smaller ones, settled not designed:</span>{" "}
                <code style={{ color: C.ink700 }}>ExecutionTargets</code> — CommandGateway-backed intents need
                daemon/relay network access, so they want <code style={{ color: C.ink700 }}>.main</code>, not{" "}
                <code style={{ color: C.ink700 }}>.widgetKitExtension</code> — settles a question rather than raising
                one. <code style={{ color: C.ink700 }}>SyncableEntity</code> — Lancer&apos;s run/approval/host IDs are
                already server-assigned UUIDs from the daemon, not locally generated, so cross-device Siri continuity
                (phone ↔ a future Mac companion) is likely already free — worth confirming, not redesigning.
              </Body>
            </Card>
            <Card style={{ marginTop: 16, padding: "14px 16px" }}>
              <Body style={{ margin: 0, fontSize: 12.5 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Adjacent, deliberately not folded in:</span>{" "}
                the Foundation Models framework got server-side{" "}
                <code style={{ color: C.ink700 }}>PrivateCloudComputeLanguageModel</code> access (32K context,
                reasoning, free under 2M downloads) and can now call Claude/Gemini through the same Swift API. That&apos;s
                a real opportunity for Lancer — e.g. summarizing a diff or explaining why a command is risky using
                Apple&apos;s model instead of burning the user&apos;s own agent budget — but it&apos;s a different
                product surface from Siri readiness, not a rename of anything on this page.
              </Body>
            </Card>
          </section>

          {/* ---------------- Entities ---------------- */}
          <section>
            <SectionLabel tone="terra">Foundational — everything else depends on this</SectionLabel>
            <Headline size={24}>Entities to model</Headline>
            <Body style={{ maxWidth: 640, margin: "10px 0 20px" }}>
              Every entity needs a <code style={{ color: C.ink700 }}>DisplayRepresentation</code> (title/subtitle/image)
              — it&apos;s reused everywhere: Siri&apos;s spoken/visual responses, disambiguation lists, Spotlight, and
              Shortcuts. Get this right once, inherit it in four places.
            </Body>
            <Card style={{ padding: 4 }}>
              <div style={{ padding: "0 16px" }}>
                <PlanRow title="RunEntity" status="foundational">
                  A running/paused agent session. Display: title = agent name, subtitle = &quot;host · status&quot;.
                  Transient/real-time — probably <em>not</em> a Spotlight-indexed entity (nothing to search for
                  &quot;my session from last week&quot; today), but open question if session-history search becomes a
                  feature later.
                </PlanRow>
                <PlanRow title="ApprovalEntity" status="foundational">
                  A pending approval. Display: title = command/action summary, subtitle = &quot;host · risk&quot;.
                  Conforms to <code style={{ color: C.ink700 }}>OwnershipProvidingEntity</code> — ownership{" "}
                  <code style={{ color: C.ink700 }}>.shared</code>{" "}
                  for team-shared hosts forces Siri&apos;s auto-confirmation on anything that acts on it. This is the
                  entity the whole approve-via-Siri safety story hangs off of.
                </PlanRow>
                <PlanRow title="HostEntity" status="not-started">
                  A paired machine. Display: title = host name, subtitle = &quot;3 running · 1 pending&quot;. Stable,
                  named, small set — good <code style={{ color: C.ink700 }}>IndexedEntity</code>{" "}
                  candidate for
                  Spotlight (&quot;open mac-studio in Lancer&quot;).
                </PlanRow>
              </div>
            </Card>
          </section>

          {/* ---------------- Display representations ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 1, worked through — first pass</SectionLabel>
            <Headline size={24}>Entity display representations</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              Same title/subtitle/icon data, two very different renderings. Apple owns the chrome on the left — we
              only supply the three values. The right is the one place we get full visual control: a custom{" "}
              <code style={{ color: C.ink700 }}>SnippetIntent</code> view, using the same dark/branded language as the
              Live Activity work.
            </Body>
            <Card style={{ padding: 18 }}>
              <EntitySection
                name="RunEntity"
                note="Icon reuses AgentAvatarTile directly — same identity across Live Activity, Siri, and Spotlight."
                icon={<AgentAvatarTile size={30} agent="claude" />}
                title="Claude Code"
                subtitle="mac-studio · running"
                snippetTitle="Claude Code"
                snippetSubtitle="mac-studio · running"
              />
              <EntitySection
                name="ApprovalEntity"
                note="Title is the action itself, not a generic label — matches the brand's 'concrete over generic' copy rule. Icon carries the requesting agent + risk via the corner dot, same pattern as the Live Activity band."
                icon={<AgentAvatarTile size={30} agent="claude" dot={{ tone: "danger", pulse: false }} />}
                title="rm -rf ./build"
                subtitle="mac-studio · high risk"
                snippetTitle="rm -rf ./build"
                snippetSubtitle="mac-studio · high risk"
              />
              <EntitySection
                name="HostEntity"
                note="New tile — hosts don't have a vendor accent like agents do, so identity comes from connection-status tint instead (sage/amber/idle), not a fixed color."
                icon={<HostIconTile size={30} tone="sage" />}
                title="mac-studio"
                subtitle="3 running · 1 pending"
                snippetTitle="mac-studio"
                snippetSubtitle="3 running · 1 pending"
              />
            </Card>
            <Card style={{ marginTop: 16, padding: "14px 16px", background: C.surfaceField }}>
              <Body style={{ margin: 0, fontSize: 12.5 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Open question, not answered here:</span>{" "}
                does the system list row render our icon as-supplied, or does it re-render/re-tint it to match system
                appearance (light/dark mode, accent color settings)? If the latter, the terracotta/status-tint
                distinctions above might not survive into the system-rendered context — needs a real device check
                before this is trusted.
              </Body>
            </Card>
          </section>

          {/* ---------------- Step 2: searchInApp ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 2, worked through — the cheap win</SectionLabel>
            <Headline size={24}>Adopting .system.searchInApp</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 20px" }}>
              No entity modeling, no new UI — a single intent that takes Siri&apos;s search text and routes it into
              Lancer&apos;s existing in-app search. Validates the whole App Intents pipeline (discovery → invocation →
              foreground) end-to-end before anything safety-sensitive touches it.
            </Body>
            <Card style={{ padding: 18 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
                <div style={{ flex: 1, minWidth: 200 }}>
                  <SectionLabel>Person says</SectionLabel>
                  <p className={serif.className} style={{ fontSize: 17, color: C.terra500, marginTop: 6 }}>
                    &quot;search Lancer for force push&quot;
                  </p>
                </div>
                <div className={mono.className} style={{ fontSize: 20, color: C.ink150 }}>→</div>
                <div style={{ flex: 1, minWidth: 200 }}>
                  <SectionLabel>Lancer opens to</SectionLabel>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 8 }}>
                    <HostIconTile size={26} tone="idle" />
                    <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.ink900 }}>
                      Audit log — &quot;force push&quot; prefilled
                    </span>
                  </div>
                </div>
              </div>
            </Card>
          </section>

          {/* ---------------- Step 3: Result snippets ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 3, worked through — the fastest demoable thing</SectionLabel>
            <Headline size={24}>Status &amp; pending-approvals snippets</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              Both are <em>Result</em> type — outcome only, single &quot;Done&quot; button, no side effects. Top-anchored
              overlay per Apple&apos;s rule, larger type than the Live Activity cards for readability at a glance.
            </Body>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 40 }}>
              <SiriSnippetFrame label="AgentStatusQuerySnippet" dialog="1 agent is running. Codex on vps-fra and Kimi on kimi-box need you.">
                <AgentStatusQuerySnippetView />
              </SiriSnippetFrame>
              <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <SiriSnippetFrame label="PendingApprovalsSnippet" dialog="2 approvals are waiting.">
                  <PendingApprovalsSnippetView />
                </SiriSnippetFrame>
                <Card style={{ padding: "14px 16px", maxWidth: 300 }}>
                  <Body style={{ margin: 0, fontSize: 12 }}>
                    <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Per Apple&apos;s rule:</span>{" "}
                    tapping a row hands off to <code style={{ color: C.ink700 }}>ApproveSnippet</code> — a Confirmation
                    type — which <em>replaces</em> this Result snippet entirely. Built below, step 5.
                  </Body>
                </Card>
              </div>
            </div>
          </section>

          {/* ---------------- Step 4: Pause/Stop confirmation ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 4, worked through — where CommandGateway gets consumed</SectionLabel>
            <Headline size={24}>Pause/Stop confirmation snippet</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              Confirmation type — action verb, not &quot;OK.&quot; Left: one run active, resolved either by voice or a{" "}
              <code style={{ color: C.ink700 }}>View Annotation</code> on the foregrounded session — no disambiguation
              needed. Right: nothing on-screen to resolve against and &gt;1 run active — falls back to{" "}
              <code style={{ color: C.ink700 }}>requestChoice</code>.
            </Body>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 40 }}>
              <SiriSnippetFrame label="PauseStopSnippet — resolved" dialog="Claude Code has been running on mac-studio for 4 minutes.">
                <PauseStopSnippetView disambiguate={false} />
              </SiriSnippetFrame>
              <SiriSnippetFrame label="PauseStopSnippet — disambiguating" dialog="Which agent do you want to stop?">
                <PauseStopSnippetView disambiguate={true} />
              </SiriSnippetFrame>
            </div>
          </section>

          {/* ---------------- Step 5: Approve/Deny confirmation ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 5, worked through — highest-trust surface, built last on purpose</SectionLabel>
            <Headline size={24}>Approve/Deny confirmation snippet</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              <code style={{ color: C.ink700 }}>OwnershipProvidingEntity</code> forces this exact tap regardless of how
              it was reached — voice, a tapped row in <code style={{ color: C.ink700 }}>PendingApprovalsSnippet</code>,
              or <code style={{ color: C.ink700 }}>RelevantEntities</code> proactively surfacing it. Same banded-header
              language as the Live Activity — amber for routine, danger for high-risk — so both surfaces read as one
              system.
            </Body>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 40 }}>
              <SiriSnippetFrame label="ApproveSnippet — routine" dialog="Codex wants to run a command on vps-fra.">
                <ApproveSnippetView highRisk={false} />
              </SiriSnippetFrame>
              <SiriSnippetFrame label="ApproveSnippet — high risk" dialog="Codex wants to force-push to main on vps-fra. This is high risk.">
                <ApproveSnippetView highRisk={true} />
              </SiriSnippetFrame>
            </div>
          </section>

          {/* ---------------- RelevantEntities ---------------- */}
          <section>
            <SectionLabel tone="terra">Sketched — the proactive half of the brand spine</SectionLabel>
            <Headline size={24}>Surfacing before anyone asks</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              Same system chrome constraint as the entity representations earlier — Apple owns the Spotlight
              empty-state UI, we only register the entity. Modeled on the &quot;recent/popular before you type&quot;
              pattern (Tripadvisor, Uber Eats) since Mobbin has no genuine <code style={{ color: C.ink700 }}>RelevantEntities</code>{" "}
              captures to reference — closest real analog available.
            </Body>
            <div style={{ maxWidth: 320 }}>
              <SpotlightSuggestedRow />
            </div>
          </section>

          {/* ---------------- LongRunningIntent comparison ---------------- */}
          <section>
            <SectionLabel tone="terra">Sketched — honest about what we don&apos;t control</SectionLabel>
            <Headline size={24}>System-generated vs. our own</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 24px" }}>
              The system-generated activity is deliberately plain — this is what &quot;start Claude Code on
              mac-studio&quot; gets from <code style={{ color: C.ink700 }}>LongRunningIntent</code> alone, before any
              session exists to build a custom activity around. It hands off to our real Live Activity the moment the
              session starts.
            </Body>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 32, alignItems: "center" }}>
              <div style={{ maxWidth: 320 }}>
                <SectionLabel>System-generated (LongRunningIntent)</SectionLabel>
                <div style={{ marginTop: 8 }}>
                  <SystemGeneratedActivity />
                </div>
              </div>
              <span className={mono.className} style={{ fontSize: 18, color: C.ink150 }}>→</span>
              <div style={{ maxWidth: 320 }}>
                <SectionLabel>Ours, once the session exists</SectionLabel>
                <div style={{ marginTop: 8, borderRadius: 24, background: "rgba(13,12,11,.85)", border: "1px solid rgba(244,239,230,.08)", padding: "13px 16px", display: "flex", alignItems: "center", gap: 12 }}>
                  <AgentAvatarTile size={30} dot={{ tone: "sage", pulse: true }} />
                  <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                    <span className={display.className} style={{ fontSize: 14, fontWeight: 700, color: C.cream }}>Claude Code</span>
                    <span className={mono.className} style={{ fontSize: 11, color: "rgba(244,239,230,.55)" }}>mac-studio · running</span>
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* ---------------- View Annotations ---------------- */}
          <section>
            <SectionLabel tone="terra">Step 6, worked through — real app screens, not mockups</SectionLabel>
            <Headline size={24}>Where View Annotations go</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 20px" }}>
              Checked against session 344&apos;s code-along:{" "}
              <code style={{ color: C.ink700 }}>.appEntityIdentifier()</code>/<code style={{ color: C.ink700 }}>.userActivity()</code>{" "}
              only ever appeared on in-app SwiftUI views (list rows, detail views) — never inside a widget extension.
              Consistent with the main-app-only assumption below, not a definitive confirmation either way — Apple&apos;s
              docs don&apos;t explicitly rule out widget extensions.
            </Body>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 24, alignItems: "flex-start", marginBottom: 20 }}>
              <Card style={{ padding: 12, maxWidth: 300 }}>
                <SectionLabel>Home / Inbox — annotated</SectionLabel>
                <div style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
                  {[
                    { label: "Claude Code — mac-studio", entity: "RunEntity", agent: "claude" as const },
                    { label: "git push --force — vps-fra", entity: "ApprovalEntity", agent: "codex" as const },
                    { label: "kimi-box", entity: "HostEntity", agent: "kimi" as const },
                  ].map((r) => (
                    <div key={r.entity} style={{ position: "relative", border: `1.5px dashed ${C.terra500}`, borderRadius: 12, padding: 2 }}>
                      <SystemListRow icon={<AgentAvatarTile size={26} agent={r.agent} />} title={r.label} subtitle="" />
                      <span
                        className={mono.className}
                        style={{ position: "absolute", top: -8, right: 8, background: C.terra500, color: "#fff", fontSize: 8.5, fontWeight: 700, padding: "2px 6px", borderRadius: 5, letterSpacing: ".02em" }}
                      >
                        {r.entity}
                      </span>
                    </div>
                  ))}
                </div>
              </Card>
              <Body style={{ maxWidth: 300, margin: 0, fontSize: 12.5 }}>
                The dashed outline and tag aren&apos;t real UI — they mark, for this plan, which entity type each
                real row would carry once annotated. Every row becomes independently referenceable: &quot;approve
                that one&quot; while scrolled past it, &quot;pause this&quot; while looking at it.
              </Body>
            </div>
            <Card style={{ padding: 4 }}>
              <div style={{ padding: "0 16px" }}>
                <PlanRow title="Session list rows (Home / Inbox)" status="sketched">
                  Annotate with <code style={{ color: C.ink700 }}>RunEntity</code> via{" "}
                  <code style={{ color: C.ink700 }}>forSelectionType:</code>{" "}
                  on the list — &quot;pause this&quot;
                  resolves from a scrolled list without opening anything.
                </PlanRow>
                <PlanRow title="ApprovalCard rows" status="sketched">
                  Annotate with <code style={{ color: C.ink700 }}>ApprovalEntity</code>, same list-annotation pattern —
                  wherever it renders (Home attention list, Inbox).
                </PlanRow>
                <PlanRow title="MachineCard / Fleet rows" status="sketched">
                  Annotate with <code style={{ color: C.ink700 }}>HostEntity</code>.
                </PlanRow>
                <PlanRow title="Live session detail (one open thread)" status="sketched">
                  <code style={{ color: C.ink700 }}>.userActivity(...)</code> single-primary-entity pattern, not list
                  annotation — this screen is dedicated to one <code style={{ color: C.ink700 }}>RunEntity</code>.
                </PlanRow>
              </div>
            </Card>
          </section>

          {/* ---------------- Snippets ---------------- */}
          <section>
            <SectionLabel tone="terra">Reuses the Live Activity visual language directly</SectionLabel>
            <Headline size={24}>Interactive Snippets to design</Headline>
            <Body style={{ maxWidth: 640, margin: "10px 0 20px" }}>
              Apple&apos;s rule: <em>Result</em> snippets show an outcome, end in a single &quot;Done&quot;.{" "}
              <em>Confirmation</em>{" "}
              snippets need a tap before acting, button says the verb (&quot;Stop&quot;, &quot;Approve&quot;,
              &quot;Deny&quot;). Max 340pt tall, no scrolling.
            </Body>
            <Card style={{ padding: 4 }}>
              <div style={{ padding: "0 16px" }}>
                <SnippetRow title="AgentStatusQuerySnippet" kind="Result" sketched>
                  &quot;3 running · 1 needs you&quot; — direct reuse of the FleetBanner concept from the Live Activity
                  page.
                </SnippetRow>
                <SnippetRow title="PendingApprovalsSnippet" kind="Result" sketched>
                  Lists 1-3 pending approvals, each row tappable to drill into its own confirmation.
                </SnippetRow>
                <SnippetRow title="ApproveSnippet" kind="Confirmation" sketched>
                  Reuses the ApprovalCard banded design. Reachable by tapping a row above, or by voice — either way,{" "}
                  <code style={{ color: C.ink700 }}>OwnershipProvidingEntity</code> forces this exact tap regardless of
                  how it was reached.
                </SnippetRow>
                <SnippetRow title="PauseStopSnippet" kind="Confirmation" sketched>
                  <code style={{ color: C.ink700 }}>requestChoice</code>{" "}
                  disambiguation when &gt;1 run is active and nothing is on-screen to resolve against; auto-resolved
                  via View Annotation when the app is foregrounded on a specific session.
                </SnippetRow>
                <SnippetRow title="DenyLatestSnippet" kind="Confirmation">
                  Folded into ApproveSnippet above — Deny is the secondary button on the same Confirmation snippet,
                  not a separate one. Removed as its own row; kept here struck through so the plan&apos;s history is
                  visible.
                </SnippetRow>
              </div>
            </Card>
          </section>

          {/* ---------------- Testing ---------------- */}
          <section>
            <SectionLabel tone="terra">Corrected on this pass — the real API, and a real gap</SectionLabel>
            <Headline size={24}>Testing strategy, updated</Headline>
            <Body style={{ maxWidth: 680, margin: "10px 0 16px" }}>
              Earlier draft of this section overclaimed — &quot;covers disambiguation logic&quot; wasn&apos;t
              accurate. The real API, from WWDC26 session 295:
            </Body>
            <Card style={{ padding: "14px 16px", background: "#1c1c1e", marginBottom: 16 }}>
              <pre className={mono.className} style={{ margin: 0, fontSize: 11.5, lineHeight: 1.6, color: "#c9c1b4", whiteSpace: "pre-wrap" }}>
{`let definitions = IntentDefinitions(bundleIdentifier: "dev.lancer.mobile")
let stop = definitions.intents["StopRunIntent"]
let result = try await stop.makeIntent(run: "mac-studio").run()
XCTAssertEqual(try result.value.status, "stopped")`}
              </pre>
            </Card>
            <Card style={{ padding: "16px 18px" }}>
              <Body style={{ margin: 0 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>What it actually covers:</span>{" "}
                entity resolution (<code style={{ color: C.ink700 }}>.entities(matching:)</code>), Spotlight indexing
                (<code style={{ color: C.ink700 }}>.spotlightQuery()</code>), View Annotations
                (<code style={{ color: C.ink700 }}>.viewAnnotations()</code>), and single-match execution — all
                cross-process against the real App Intents stack, no mocks, same-signing-team XCUITest bundle, no
                app-code import needed.{" "}
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>The gap:</span> the
                session never demonstrates testing a disambiguation prompt or a confirmation-dialog flow — exactly the
                two mechanisms{" "}
                <code style={{ color: C.ink700 }}>PauseStopSnippet</code> and{" "}
                <code style={{ color: C.ink700 }}>ApproveSnippet</code> depend on. That stays an open question, not an
                assumption to build on.
              </Body>
            </Card>
            <Card style={{ marginTop: 16, padding: "16px 18px" }}>
              <Body style={{ margin: 0 }}>
                <span className={body.className} style={{ fontWeight: 700, color: C.ink700 }}>Still real-device:</span>{" "}
                actual voice recognition/dialog quality, on-screen View Annotation resolution while physically looking
                at the app, the full AirPods/audio path, and now — confirmed by the gap above —{" "}
                disambiguation/confirmation UX itself.
              </Body>
            </Card>
          </section>

          {/* ---------------- Build order ---------------- */}
          <section>
            <SectionLabel tone="terra">Go one by one, in this order</SectionLabel>
            <Headline size={24}>Suggested build order</Headline>
            <div style={{ marginTop: 24 }}>
              <OrderStep n={1} sketched title="Model RunEntity / ApprovalEntity / HostEntity + DisplayRepresentation">
                Foundational — Siri responses, disambiguation, Spotlight, and Shortcuts all read from this. Nothing
                else below can start until this exists.
              </OrderStep>
              <OrderStep n={2} sketched title="Adopt .system.searchInApp">
                Cheapest possible win. Validates the whole App Intents pipeline end-to-end (indexing, discovery,
                invocation) with minimal risk before touching anything safety-sensitive.
              </OrderStep>
              <OrderStep n={3} sketched title="Status-query + pending-approvals Result snippets">
                Read-only, lowest risk, and the visual language already exists (FleetBanner, ApprovalCard). Fastest
                path to something demoable.
              </OrderStep>
              <OrderStep n={4} sketched title="Pause/Stop confirmation snippet + View Annotations on session views">
                Snippet sketched above, both resolved and disambiguating states. Ties directly into the engineering
                plan&apos;s CommandGateway — this is where that Part 1 work actually gets consumed by a real surface.
                The View Annotations half is real Swift work, not a mockup — still open.
              </OrderStep>
              <OrderStep n={5} sketched title="Approve/Deny confirmation snippets with OwnershipProvidingEntity">
                Snippet sketched above, routine and high-risk states. Highest-trust surface — built last on purpose,
                once the confirmation-snippet pattern was proven on steps 3-4 first.
              </OrderStep>
              <OrderStep n={6} title="Roll View Annotations out to every remaining list (ApprovalCard, MachineCard rows)">
                Full on-screen resolution coverage — last because it's the widest-reaching, most mechanical step once
                the pattern from step 4 is settled.
              </OrderStep>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
