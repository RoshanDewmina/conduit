import SectionHeader from "@/components/ui/section-header";
import Button from "@/components/ui/button";
import Reveal from "@/components/ui/reveal";

const STEPS = [
  {
    num: "01",
    title: "Install the bridge",
    body: "On your host: lancerd runs in the background and survives reboots. It enforces your policy and relays approval requests to your phone.",
  },
  {
    num: "02",
    title: "Point your agent's hook",
    body: "One line per agent — Claude Code, Codex, or opencode — so Lancer sees what they're about to do before they do it.",
  },
  {
    num: "03",
    title: "Pair your phone",
    body: "Install the app, scan the pairing code, and pick a caution preset. No account needed.",
  },
  {
    num: "04",
    title: "Go do something else",
    body: "Next time an agent hits something risky, your phone buzzes. You tap. It resumes. Everything's logged.",
  },
];

export default function HowItWorksSection() {
  return (
    <section id="how-it-works" className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="05" name="How it works" spectrum />
        <div className="max-w-[720px] mb-14">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            four steps to a governed agent<span className="text-accent">_</span>
          </h2>
        </div>
      </Reveal>

      <div className="grid md:grid-cols-2 gap-x-14 gap-y-10">
        {STEPS.map((s, i) => (
          <Reveal key={s.num} delay={i * 0.08}>
            <div className="flex gap-5">
              <span className="font-display text-2xl font-bold text-accent shrink-0 leading-none mt-0.5">
                {s.num}
              </span>
              <div>
                <h3 className="font-display text-lg font-semibold text-fg mb-2">
                  {s.title}
                </h3>
                <p className="font-mono text-sm text-dim leading-relaxed">
                  {s.body}
                </p>
              </div>
            </div>
          </Reveal>
        ))}
      </div>

      <Reveal delay={0.3} className="mt-12 text-center">
        <Button href="/download" variant="ghost">
          Read the getting-started guide →
        </Button>
      </Reveal>
    </section>
  );
}
