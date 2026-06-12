import SectionHeader from "@/components/ui/section-header";
import Panel from "@/components/ui/panel";
import Reveal from "@/components/ui/reveal";

const HOSTS = [
  { dot: "var(--color-med)", host: "m2-max.local", agent: "claude code ×2", status: "waiting on you", statusColor: "text-med" },
  { dot: "var(--color-low)", host: "build-box", agent: "codex", status: "idle", statusColor: "text-dim" },
  { dot: "var(--color-high)", host: "hetzner-01", agent: "opencode", status: "blocked by policy", statusColor: "text-high" },
];

export default function FleetSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20 grid md:grid-cols-2 gap-14 items-center">
      <Reveal>
        <SectionHeader number="08" name="Fleet" spectrum />
        <h2 className="font-display font-bold text-2xl md:text-3xl leading-[1.15] text-fg mb-6">
          a glance across every machine<span className="text-accent">_</span>
        </h2>
        <p className="font-mono text-sm text-dim leading-relaxed">
          Idle, waiting on you, or blocked — see your whole fleet and what
          it&apos;s costing, in one place.
        </p>
      </Reveal>

      <Reveal delay={0.1}>
        <Panel>
          {HOSTS.map((h, i) => (
            <div
              key={h.host}
              className={`flex items-center gap-3 px-5 py-3.5 font-mono text-[12.5px] ${
                i !== 0 ? "border-t border-line-soft" : ""
              }`}
            >
              <span
                className="w-[7px] h-[7px] rounded-full shrink-0"
                style={{ background: h.dot }}
              />
              <span className="text-fg">{h.host}</span>
              <span className="text-faint">{h.agent}</span>
              <span className="flex-1" />
              <span className={h.statusColor}>{h.status}</span>
            </div>
          ))}
        </Panel>
      </Reveal>
    </section>
  );
}
