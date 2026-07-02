// Conduit "Editorial · Sand" — the real product design system (see
// ~/Downloads/Conduit Design System/). Ported as constants + inline style
// rather than the source .jsx components, to match this repo's existing
// convention (raw hex via Tailwind arbitrary values, no CSS-var indirection).
// Shared across every page using this design direction — extend here, not
// per-page, so pages stay in sync.
import { Bricolage_Grotesque, Hanken_Grotesk, Instrument_Serif, JetBrains_Mono } from "next/font/google"

export const display = Bricolage_Grotesque({ subsets: ["latin"], weight: ["700", "800"] })
export const body = Hanken_Grotesk({ subsets: ["latin"], weight: ["400", "500", "600", "700"] })
export const serif = Instrument_Serif({ subsets: ["latin"], weight: "400", style: "italic" })
export const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["400", "500", "600"] })

export const C = {
  paperCanvas: "#e7e5df",
  paperGradTop: "#F1EDE5",
  paperGradBot: "#EAE5DB",
  surfaceCard: "#fcfbf8",
  surfaceField: "#F4F1EA",
  ink900: "#23201c",
  ink700: "#3f3a32",
  ink600: "#4a443b",
  ink500: "#5d564b",
  ink350: "#8a8076",
  ink250: "#9a9182",
  ink150: "#a8a092",
  line: "#ece6da",
  lineStrong: "#e4ded2",
  terra500: "#C05B36",
  terra700: "#8a4f30",
  terraTint: "#F6D8C5",
  sage500: "#5B7A5B",
  sageTint: "#e7efe7",
  sageTint2: "#eef0ea",
  amber500: "#C8843C",
  amber600: "#9a6a2c",
  amberTint: "#F6E7D2",
  danger500: "#b5483f",
  dangerTint: "#fbeaea",
  // On-dark variants (Live Activity / Siri Snippet cards are OS chrome —
  // always dark/translucent per Apple convention, never warm paper) — from
  // the system's own .theme-midnight scope.
  termBg: "#0d0c0b",
  termBg2: "#1d1a17",
  cream: "#f4efe6",
  sageOnDark: "#7fae7f",
  amberOnDark: "#E0A45C",
}

export const KEYFRAMES = `
  @keyframes cds-pulse-sage { 0%,100% { box-shadow: 0 0 0 0 rgba(127,174,127,.5) } 50% { box-shadow: 0 0 0 5px rgba(127,174,127,0) } }
  @keyframes cds-pulse-amber { 0%,100% { box-shadow: 0 0 0 0 rgba(224,164,92,.55) } 50% { box-shadow: 0 0 0 5px rgba(224,164,92,0) } }
`

export function SectionLabel({ children, tone = "muted" }: { children: React.ReactNode; tone?: "muted" | "terra" }) {
  return (
    <p
      className={mono.className}
      style={{
        fontSize: 10,
        fontWeight: 500,
        letterSpacing: ".12em",
        textTransform: "uppercase",
        color: tone === "terra" ? C.terra700 : C.ink150,
        margin: 0,
      }}
    >
      {children}
    </p>
  )
}

export function Eyebrow({ children, tone = "terra" }: { children: React.ReactNode; tone?: "terra" | "sage" }) {
  return (
    <p
      className={serif.className}
      style={{ fontSize: 17, lineHeight: 1, color: tone === "sage" ? C.sage500 : C.terra500, margin: 0 }}
    >
      {children}
    </p>
  )
}

export function Headline({ children, size = 27 }: { children: React.ReactNode; size?: number }) {
  return (
    <h2
      className={display.className}
      style={{ fontWeight: 700, fontSize: size, letterSpacing: "-0.02em", lineHeight: 1.04, color: C.ink900, margin: "5px 0 0" }}
    >
      {children}
    </h2>
  )
}

export function Body({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <p className={body.className} style={{ fontSize: 15, lineHeight: 1.5, color: C.ink500, ...style }}>
      {children}
    </p>
  )
}

export function Card({ children, style, accent = false }: { children: React.ReactNode; style?: React.CSSProperties; accent?: boolean }) {
  return (
    <div
      style={{
        background: C.surfaceCard,
        border: accent ? `1.5px solid ${C.terra500}` : `1px solid ${C.line}`,
        borderRadius: 16,
        boxShadow: accent ? "0 2px 10px -5px rgba(192,91,54,.35)" : "0 2px 10px -6px rgba(0,0,0,.10)",
        ...style,
      }}
    >
      {children}
    </div>
  )
}

export function Badge({ tone, children }: { tone: "healthy" | "warn" | "high" | "low"; children: React.ReactNode }) {
  const tones = {
    healthy: { background: C.sageTint, color: C.sage500 },
    low: { background: C.sageTint2, color: C.sage500 },
    warn: { background: C.amberTint, color: C.amber600 },
    high: { background: C.dangerTint, color: C.danger500 },
  }[tone]
  return (
    <span
      className={mono.className}
      style={{
        display: "inline-flex",
        alignItems: "center",
        fontSize: 9.5,
        fontWeight: 600,
        letterSpacing: ".08em",
        padding: "3px 7px",
        borderRadius: 6,
        textTransform: "uppercase",
        ...tones,
      }}
    >
      {children}
    </span>
  )
}

export function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={body.className}
      style={{
        padding: "7px 12px",
        borderRadius: 11,
        fontSize: 12.5,
        fontWeight: 600,
        background: active ? C.ink900 : C.surfaceField,
        color: active ? "#fff" : C.ink500,
        border: active ? "1px solid transparent" : `1px solid ${C.lineStrong}`,
        cursor: "pointer",
        transition: "filter .18s cubic-bezier(.22,1,.36,1)",
      }}
    >
      {children}
    </button>
  )
}

// Status dot — sage (running/online) · amber (waiting) · danger (blocked) ·
// idle (faint). No blue anywhere, per brand.
export function StatusDot({ tone, pulse = false, size = 8 }: { tone: "sage" | "amber" | "danger" | "idle"; pulse?: boolean; size?: number }) {
  const color = tone === "sage" ? C.sageOnDark : tone === "amber" ? C.amberOnDark : tone === "danger" ? "#d97a70" : "rgba(244,239,230,.28)"
  return (
    <span
      style={{
        display: "inline-block",
        width: size,
        height: size,
        borderRadius: "50%",
        flexShrink: 0,
        background: color,
        animation: pulse ? `cds-pulse-${tone === "sage" ? "sage" : "amber"} 2s infinite` : "none",
      }}
    />
  )
}

// AgentAvatar — the system's real agent-identity component: an initial tile
// ("C" for Claude Code, terracotta-filled), not a plain status dot. Corner
// presence dot carries the live status signal. Claude gets the accent-filled
// tile (the brand's "hero" vendor); the other three vendors Lancer supports
// get a quiet dark tile instead — matches AgentAvatar.jsx's claude:accent=true
// / others:accent=false exactly.
export const AGENT_MAP: Record<string, { ini: string; accent: boolean }> = {
  claude: { ini: "C", accent: true },
  codex: { ini: "Cx", accent: false },
  opencode: { ini: "O", accent: false },
  kimi: { ini: "K", accent: false },
}

export function AgentAvatarTile({ size = 30, agent = "claude", dot }: { size?: number; agent?: string; dot?: { tone: "sage" | "amber" | "danger" | "idle"; pulse: boolean } }) {
  const dotSize = Math.max(8, Math.round(size * 0.34))
  const spec = AGENT_MAP[agent] ?? AGENT_MAP.claude
  return (
    <span style={{ position: "relative", display: "inline-flex", flexShrink: 0 }}>
      <span
        className={display.className}
        style={{
          width: size,
          height: size,
          borderRadius: Math.round(size * 0.27),
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          background: spec.accent ? C.terra500 : "rgba(244,239,230,.12)",
          color: spec.accent ? "#fff" : "rgba(244,239,230,.75)",
          fontSize: Math.round(size * (spec.ini.length > 1 ? 0.36 : 0.45)),
          fontWeight: 700,
        }}
      >
        {spec.ini}
      </span>
      {dot && (
        <span
          style={{
            position: "absolute",
            bottom: -2,
            right: -2,
            width: dotSize,
            height: dotSize,
            borderRadius: "50%",
            background: dot.tone === "sage" ? C.sageOnDark : dot.tone === "amber" ? C.amberOnDark : dot.tone === "danger" ? "#d97a70" : "rgba(244,239,230,.3)",
            border: "2px solid rgba(13,12,11,.92)",
            animation: dot.pulse ? `cds-pulse-${dot.tone === "sage" ? "sage" : "amber"} 2s infinite` : "none",
          }}
        />
      )}
    </span>
  )
}

export const REF_IMG = "h-[220px] w-auto rounded-xl object-cover"

// HostIconTile — machine identity, same square-tile shape as AgentAvatarTile
// so the two read as one family. Tinted by connection status rather than a
// fixed accent, since a host's "identity" (unlike an agent vendor) doesn't
// have a brand color of its own.
export function HostIconTile({ size = 30, tone = "sage" }: { size?: number; tone?: "sage" | "amber" | "idle" }) {
  const bg = tone === "sage" ? "rgba(127,174,127,.16)" : tone === "amber" ? "rgba(224,164,92,.16)" : "rgba(244,239,230,.08)"
  const fg = tone === "sage" ? "#7fae7f" : tone === "amber" ? "#E0A45C" : "rgba(244,239,230,.4)"
  return (
    <span
      style={{
        width: size,
        height: size,
        borderRadius: Math.round(size * 0.27),
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        background: bg,
        color: fg,
        flexShrink: 0,
      }}
    >
      <svg width={Math.round(size * 0.5)} height={Math.round(size * 0.5)} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="3" width="20" height="6" rx="1.5" />
        <rect x="2" y="15" width="20" height="6" rx="1.5" />
        <line x1="6" y1="6" x2="6.01" y2="6" />
        <line x1="6" y1="18" x2="6.01" y2="18" />
      </svg>
    </span>
  )
}
