import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const PROPS = [
  {
    title: "Cross-vendor, not single-vendor",
    body: "Claude's and OpenAI's mobile control each govern only their own agent. Conduit is the one policy, approval, and audit layer across Claude Code, Codex, and opencode.",
  },
  {
    title: "Local-first, not cloud-run",
    body: "Your agents run on your own machine. Only the approval metadata you choose to send ever leaves your host. End-to-end encryption of the relay is [PLANNED].",
  },
  {
    title: "Enforcement you can trust",
    body: "Conduit's hook returns a hard deny that holds even under --dangerously-skip-permissions. Default is fail-closed: if the bridge isn't reachable, mutating actions hold rather than auto-run.",
  },
];

export default function WhyConduitSection() {
  return (
    <section id="why-conduit" className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="06" name="Why Conduit" spectrum />
        <div className="max-w-[720px] mb-14">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            not a terminal. not a cloud ide.
            <br />
            the missing approval layer<span className="text-accent">_</span>
          </h2>
        </div>
      </Reveal>

      <div className="grid md:grid-cols-3 gap-6">
        {PROPS.map((p, i) => (
          <Reveal key={p.title} delay={i * 0.1}>
            <div className="border border-line bg-raised p-6 h-full flex flex-col">
              <span className="font-display text-xs tracking-[0.18em] uppercase text-accent mb-3">
                0{i + 1}
              </span>
              <h3 className="font-display text-lg font-semibold text-fg mb-3 leading-snug">
                {p.title}
              </h3>
              <p className="font-mono text-sm text-dim leading-relaxed flex-1">
                {p.body}
              </p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
