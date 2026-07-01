import Link from "next/link"
import { PhoneFrame } from "@/components/phone-frame"

interface RefShot {
  app: string
  caption: string
  imageUrl: string
  mobbinUrl: string
}

interface Pattern {
  trigger: string
  tag: string
  refs: RefShot[]
  wireframeLabel: string
  wireframe: React.ReactNode
  note: string
}

const REF_IMG = "h-[280px] w-auto rounded-xl border border-white/10 object-cover"

function RefCard({ shot }: { shot: RefShot }) {
  return (
    <a
      href={shot.mobbinUrl}
      target="_blank"
      rel="noreferrer"
      className="group flex flex-col items-center gap-2 shrink-0"
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={shot.imageUrl} alt={`${shot.app} reference`} className={REF_IMG} />
      <span className="text-[11px] text-white/40 group-hover:text-blue-400 transition-colors">
        {shot.app} ↗
      </span>
    </a>
  )
}

function ProSheet({
  title,
  body,
}: {
  title: string
  body: string
}) {
  return (
    <div className="flex flex-col h-full bg-[#050810]">
      <div className="flex-1" />
      <div className="rounded-t-3xl bg-[#0e1420] border-t border-white/10 px-5 pt-4 pb-6">
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-white/15" />
        <div className="flex items-center gap-2 mb-2">
          <div className="w-7 h-7 rounded-full bg-orange-500/15 border border-orange-500/30 flex items-center justify-center text-orange-400 text-[13px]">
            ★
          </div>
          <span className="text-[11px] font-mono uppercase tracking-widest text-orange-400">
            Pro feature
          </span>
        </div>
        <h3 className="text-[16px] font-bold text-white mb-1.5 leading-snug">{title}</h3>
        <p className="text-[12.5px] text-white/50 leading-relaxed mb-5">{body}</p>
        <button className="w-full rounded-xl bg-orange-500 text-white text-[13px] font-semibold py-3 mb-2">
          Upgrade Now
        </button>
        <button className="w-full text-[12.5px] text-white/40 py-1">Dismiss</button>
      </div>
    </div>
  )
}

const PATTERNS: Pattern[] = [
  {
    tag: "Trigger 1 — scale friction",
    trigger: "Pairing a 3rd host (over the free fleet cap)",
    refs: [
      {
        app: "Dropbox — Manage Devices",
        caption: "device cap + inline upgrade",
        imageUrl: "https://mobbin.com/api/mcp/short/SK37y6CU",
        mobbinUrl: "https://mobbin.com/screens/49139448-64ad-4e64-b701-c34c3ddf2bdf",
      },
    ],
    wireframeLabel: "machines — host cap reached",
    wireframe: (
      <div className="flex flex-col h-full bg-[#050810] px-5 py-4">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-[18px] font-bold text-white">Machines</h2>
          <span className="text-[11px] font-mono text-white/30">2 / 2 paired</span>
        </div>
        <div className="flex flex-col gap-2 mb-4">
          {["MacBook Pro", "hermes-box"].map((name) => (
            <div
              key={name}
              className="flex items-center justify-between rounded-xl border border-white/[0.06] bg-white/[0.02] px-3 py-3"
            >
              <div className="flex items-center gap-2.5">
                <span className="w-2 h-2 rounded-full bg-green-400" />
                <span className="text-[13px] text-white/85">{name}</span>
              </div>
              <span className="text-[11px] text-white/30 border border-white/10 rounded-md px-2 py-1">
                Unpair
              </span>
            </div>
          ))}
        </div>
        <div className="mt-auto rounded-2xl border border-orange-500/25 bg-orange-500/[0.06] p-4">
          <p className="text-[12.5px] text-white/70 leading-relaxed mb-3">
            You&apos;ve paired 2 of 2 hosts on Free. Unpair one above, or go Pro
            for unlimited hosts.
          </p>
          <button className="w-full rounded-xl bg-orange-500 text-white text-[13px] font-semibold py-2.5">
            Upgrade to Pro — unlimited hosts
          </button>
        </div>
      </div>
    ),
    note: "The upgrade CTA lives inline with the device-management action itself, not as a takeover — matches Dropbox's \"Manage Devices\" shape more closely than a generic full-screen paywall.",
  },
  {
    tag: "Trigger 2 — tap a Pro feature",
    trigger: "Tapping Policy Presets / Audit Export / Cross-provider matrix",
    refs: [
      {
        app: "Todoist — Labels",
        caption: "\"Labels are a Premium feature\"",
        imageUrl: "https://mobbin.com/api/mcp/short/5BGgyBUM",
        mobbinUrl: "https://mobbin.com/screens/02a22fdc-a7b8-4842-9eab-349913d6ff52",
      },
      {
        app: "Todoist — Reminders",
        caption: "\"Reminders are a Premium feature\"",
        imageUrl: "https://mobbin.com/api/mcp/short/BqooW32A",
        mobbinUrl: "https://mobbin.com/screens/7dd74770-25d9-495b-9c3d-e5ea482b662a",
      },
    ],
    wireframeLabel: "policy presets — pro sheet",
    wireframe: (
      <ProSheet
        title="Policy Presets is a Pro feature"
        body="Save a reusable approval rule once and apply it across every paired host in one tap — instead of configuring each host by hand."
      />
    ),
    note: "Small dismissible sheet, named to the exact feature, benefit-framed copy — never \"unlock X\", always what it does for the user. Wire this to the existing (currently dead) showingPaywall / paywallFeatureName state in AppRoot.swift.",
  },
  {
    tag: "Trigger 3 — persistent / ambient",
    trigger: "Settings row — always visible, never intrusive",
    refs: [
      {
        app: "Raycast — Pro banner + meter",
        caption: "\"50 AI Messages Left\" live meter",
        imageUrl: "https://mobbin.com/api/mcp/short/3lm7vxqK",
        mobbinUrl: "https://mobbin.com/screens/ce01e84e-b5d5-4e57-ad14-0b4acd421369",
      },
      {
        app: "Claude — soft usage upsell",
        caption: "\"Want more Claude?\"",
        imageUrl: "https://mobbin.com/api/mcp/short/G6p2cgg9",
        mobbinUrl: "https://mobbin.com/screens/3c3f21a3-f1fc-45f4-a9c0-f30fb8b9abd3",
      },
    ],
    wireframeLabel: "settings — live fleet meter",
    wireframe: (
      <div className="flex flex-col h-full bg-[#050810] px-5 py-4">
        <h2 className="text-[18px] font-bold text-white mb-4">Settings</h2>
        <div className="rounded-xl border border-white/[0.06] bg-white/[0.02] px-4 py-3 mb-3">
          <div className="flex items-center justify-between mb-2">
            <span className="text-[13px] text-white/85">Fleet</span>
            <span className="text-[11px] font-mono text-amber-400">2 / 2 hosts paired</span>
          </div>
          <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
            <div className="h-full w-full bg-amber-400/80 rounded-full" />
          </div>
        </div>
        <div className="rounded-xl border border-orange-500/25 bg-orange-500/[0.06] px-4 py-3 flex items-center justify-between">
          <div>
            <p className="text-[13px] text-white/90 font-medium">Lancer Pro</p>
            <p className="text-[11px] text-white/45 mt-0.5">
              Unlimited hosts, automation &amp; audit export
            </p>
          </div>
          <span className="text-[11px] text-orange-400 font-semibold">Upgrade →</span>
        </div>
      </div>
    ),
    note: "Not a static \"Free plan · upgrade\" link — a live capacity indicator (2/2, amber near cap), same idea as Raycast's shrinking meter and Manus's credits row. Framed as \"more\", per Claude's copy, never \"you're locked out.\"",
  },
  {
    tag: "Trigger 4 — transparency in the sheet",
    trigger: "The paywall sheet itself shows what Free already includes",
    refs: [
      {
        app: "Vibecode — Free plan detail",
        caption: "checklist of what's already included",
        imageUrl: "https://mobbin.com/api/mcp/short/ntG0CDDX",
        mobbinUrl: "https://mobbin.com/screens/e6aa4a61-920a-4717-929a-5c8e8d4744b1",
      },
    ],
    wireframeLabel: "paywallsheet — redesigned",
    wireframe: (
      <div className="flex flex-col h-full bg-[#050810] px-5 py-5 overflow-y-auto">
        <h2 className="text-[20px] font-bold text-white mb-1">Lancer Pro</h2>
        <p className="text-[12px] text-white/40 mb-4">No subscriptions, ever. Pay once, yours forever.</p>

        <p className="text-[11px] font-mono uppercase tracking-widest text-white/30 mb-2">
          Already in Free
        </p>
        <div className="flex flex-col gap-1.5 mb-4">
          {["Emergency stop", "Approve / deny / audit view", "APNs push approvals", "2 paired hosts"].map((f) => (
            <div key={f} className="flex items-center gap-2 text-[12.5px] text-white/60">
              <span className="text-green-400">✓</span>
              {f}
            </div>
          ))}
        </div>

        <p className="text-[11px] font-mono uppercase tracking-widest text-orange-400/80 mb-2">
          Pro unlocks
        </p>
        <div className="flex flex-col gap-1.5 mb-5">
          {["Unlimited hosts", "Policy presets & auto-rules", "Audit export + verify", "Cross-provider policy matrix", "Fleet drift remediation"].map((f) => (
            <div key={f} className="flex items-center gap-2 text-[12.5px] text-white/85">
              <span className="text-orange-400">✓</span>
              {f}
            </div>
          ))}
        </div>

        <button className="w-full rounded-xl bg-orange-500 text-white text-[14px] font-semibold py-3 mb-2">
          Unlock Pro — $24.99 once
        </button>
        <button className="w-full text-[12px] text-white/40 py-1">Restore Purchase</button>
      </div>
    ),
    note: "Vibecode lists what Free already includes before pitching the upgrade — reduces the adversarial feel of a paywall. Adopt this copy structure in PaywallSheet.swift.",
  },
]

const ANTI_PATTERNS: RefShot[] = [
  {
    app: "Apple Invites — hard block",
    caption: "\"A subscription is required\" — no dismiss, blocks a core action",
    imageUrl: "https://mobbin.com/api/mcp/short/HfwRwnE5",
    mobbinUrl: "https://mobbin.com/screens/15a97b42-8d83-4a19-b6e1-fbfc69b38e42",
  },
  {
    app: "AllTrails — onboarding paywall",
    caption: "trial-with-urgency before any value is shown",
    imageUrl: "https://mobbin.com/api/mcp/short/ZP5HgZ9t",
    mobbinUrl: "https://mobbin.com/screens/eaf65c3d-c201-4aa0-9d0e-2020f3f1396f",
  },
]

const MATRIX_ROWS = [
  ["Adds 3rd host (over cap)", "Machines list, inline", "Soft, value-framed", "Best-converting scale-friction moment"],
  ["Taps a Pro feature", "Contextual sheet naming the feature", "Soft", "Todoist pattern — never generic"],
  ["Persistent", "Settings row, live meter", "Passive, ambient", "Raycast / Manus pattern, not a static link"],
  ["After a value moment (first lock-screen approve)", "One-time gentle prompt", "Soft, once", "Post-value converts better"],
  ["Onboarding / first launch", "NONE", "—", "Anti-pattern for this audience (AllTrails)"],
  ["Emergency stop / approval / audit view", "NEVER gate", "—", "Safety — confirmed by every reputable trust app"],
]

export default function MonetizationPage() {
  return (
    <div className="min-h-screen px-8 py-16">
      <div className="max-w-6xl mx-auto">
        <Link href="/" className="text-xs text-white/40 hover:text-blue-400 transition-colors">
          ← back to board
        </Link>

        <p className="text-xs tracking-widest text-orange-400 mt-6 mb-3 uppercase font-mono">
          Research · not an app-screen redesign
        </p>
        <h1 className="text-4xl font-bold text-white mb-3">Monetization Trigger Timing</h1>
        <p className="text-white/50 text-base max-w-3xl leading-relaxed mb-4">
          Lancer already ships the payment plumbing — StoreKit 2 one-time <code className="text-white/70">dev.lancer.mobile.pro</code>{" "}
          non-consumable, <code className="text-white/70">PaywallSheet</code>, <code className="text-white/70">BillingView</code> — but{" "}
          <code className="text-white/70">showingPaywall</code> in <code className="text-white/70">AppRoot.swift</code> is declared and consumed
          by a sheet and never set <code className="text-white/70">true</code>. No feature currently checks{" "}
          <code className="text-white/70">isPro</code>. The gap is <em>when and how to show it</em>, not the payments code. Each pattern below
          pairs a real reference screen (via Mobbin, click through to the source) with a wireframe of the equivalent Lancer screen.
        </p>
        <p className="text-white/30 text-sm max-w-3xl mb-16">
          Free tier stays exactly as generous as today — emergency stop, approve/deny, audit view, and the app-closed push-approval loop are never gated.
          Pro is the one-time unlock for scale (unlimited hosts) and automation/power tooling, per{" "}
          <code className="text-white/60">docs/design-audit/_archive/2026-06-pre-workflows/11-monetization-and-upgrade-strategy.md</code>.
        </p>

        <div className="flex flex-col gap-20">
          {PATTERNS.map((p) => (
            <section key={p.trigger}>
              <p className="text-[11px] font-mono uppercase tracking-widest text-blue-400 mb-1">{p.tag}</p>
              <h2 className="text-2xl font-bold text-white mb-4">{p.trigger}</h2>

              <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-10 items-start">
                <div className="flex flex-col gap-4">
                  <p className="text-[11px] font-mono uppercase tracking-widest text-white/30">Reference (Mobbin)</p>
                  <div className="flex flex-wrap gap-4">
                    {p.refs.map((r) => (
                      <RefCard key={r.mobbinUrl} shot={r} />
                    ))}
                  </div>
                  <p className="text-sm text-white/50 leading-relaxed max-w-md mt-2">{p.note}</p>
                </div>

                <div className="flex flex-col items-center gap-2">
                  <p className="text-[11px] font-mono uppercase tracking-widest text-white/30 self-start">
                    Lancer wireframe
                  </p>
                  <PhoneFrame label={p.wireframeLabel}>{p.wireframe}</PhoneFrame>
                </div>
              </div>
            </section>
          ))}

          <section>
            <p className="text-[11px] font-mono uppercase tracking-widest text-red-400 mb-1">Anti-patterns</p>
            <h2 className="text-2xl font-bold text-white mb-4">Confirmed — do not do these</h2>
            <div className="flex flex-wrap gap-6">
              {ANTI_PATTERNS.map((a) => (
                <div
                  key={a.mobbinUrl}
                  className="flex flex-col items-center gap-2 rounded-2xl border border-red-500/20 bg-red-500/[0.03] p-4"
                >
                  <a href={a.mobbinUrl} target="_blank" rel="noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={a.imageUrl} alt={a.app} className={REF_IMG} />
                  </a>
                  <span className="text-[12px] text-white/70 font-medium">{a.app}</span>
                  <span className="text-[11px] text-white/40 text-center max-w-[220px]">{a.caption}</span>
                </div>
              ))}
            </div>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-white mb-4">Trigger matrix — summary</h2>
            <div className="overflow-x-auto rounded-xl border border-white/[0.06]">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-white/[0.03] text-left text-white/40 text-[11px] uppercase tracking-wider">
                    <th className="px-4 py-3 font-medium">Trigger</th>
                    <th className="px-4 py-3 font-medium">Surface</th>
                    <th className="px-4 py-3 font-medium">Tone</th>
                    <th className="px-4 py-3 font-medium">Why</th>
                  </tr>
                </thead>
                <tbody>
                  {MATRIX_ROWS.map((row, i) => (
                    <tr key={i} className="border-t border-white/[0.06]">
                      {row.map((cell, j) => (
                        <td
                          key={j}
                          className={`px-4 py-3 ${j === 0 ? "text-white/85 font-medium" : "text-white/50"}`}
                        >
                          {cell}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
