import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const GUARANTEES = [
  {
    title: "Your source stays put",
    body: "Code and credentials never leave your host. The relay carries only the action metadata you send for a decision.",
  },
  {
    title: "A deny means deny",
    body: "The policy holds even when an agent is launched with --dangerously-skip-permissions. It can't talk its way around the rule.",
  },
  {
    title: "Everything is logged",
    body: "An append-only, secret-redacted record of every autonomous decision and every human tap, on your machine.",
  },
];

const VENDORS = ["Claude Code", "Codex", "opencode"];

export default function ProofBandSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="07" name="What Lancer guarantees" />
        <div className="grid md:grid-cols-3 gap-6 mb-14">
          {GUARANTEES.map((g, i) => (
            <div
              key={g.title}
              className="border border-line bg-raised p-6 text-center"
            >
              <span className="font-display text-xs tracking-[0.18em] uppercase text-accent mb-3 block">
                guarantee
              </span>
              <h3 className="font-display text-lg font-semibold text-fg mb-3">
                {g.title}
              </h3>
              <p className="font-mono text-sm text-dim leading-relaxed">
                {g.body}
              </p>
            </div>
          ))}
        </div>

        <div className="flex flex-wrap items-center justify-center gap-3 border-t border-line pt-10">
          <span className="font-mono text-[11px] text-faint uppercase tracking-wider">
            Works with
          </span>
          {VENDORS.map((v) => (
            <span
              key={v}
              className="font-mono text-[11px] border border-line text-dim px-2 py-1"
            >
              {v}
            </span>
          ))}
        </div>
      </Reveal>
    </section>
  );
}
