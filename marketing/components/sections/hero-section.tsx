import HeroPhone from "@/components/hero/hero-phone";
import Button from "@/components/ui/button";
import Reveal from "@/components/ui/reveal";

export default function HeroSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 pt-20 pb-10 text-center">
      <Reveal>
        <p className="font-display text-[11px] tracking-[0.2em] uppercase text-faint mb-6">
          Works with Claude Code · Codex · opencode
        </p>
        <h1 className="font-display font-bold text-4xl md:text-6xl lg:text-7xl leading-[1.0] text-fg mb-2">
          approve your agents.
        </h1>
        <h1 className="font-display font-bold text-4xl md:text-6xl lg:text-7xl leading-[1.0] text-fg mb-8">
          keep your code<span className="text-accent">_</span>
        </h1>

        <p className="font-mono text-sm md:text-base text-dim max-w-[640px] mx-auto leading-relaxed mb-8">
          Lancer puts everything risky your AI coding agents try — across Claude Code,
          Codex, and opencode — into one inbox on your phone. Approve, deny, or edit in
          a tap. Set a policy and most actions never reach you. Your code never leaves
          your machine.
        </p>

        <div className="flex flex-wrap items-center justify-center gap-3 mb-8">
          <Button href="/download" variant="primary">
            Join the TestFlight beta
          </Button>
          <Button href="#how-it-works" variant="ghost">
            See how it works ↓
          </Button>
        </div>

        <p className="font-mono text-[10px] tracking-[0.14em] uppercase text-faint">
          No account required · Your code stays on your machine
        </p>
      </Reveal>

      <Reveal delay={0.15} className="mt-14 flex justify-center">
        <HeroPhone />
      </Reveal>

      {/* VENDOR CHIPS */}
      <Reveal delay={0.25} className="mt-10 flex flex-col items-center gap-4">
        <p className="font-display text-[10px] tracking-[0.2em] uppercase text-faint">
          Works With
        </p>
        <div className="flex items-center gap-3">
          <span className="font-mono text-[11px] border border-line text-dim px-2 py-1">
            <span className="text-accent font-semibold">CC</span> Claude Code
          </span>
          <span className="font-mono text-[11px] border border-line text-dim px-2 py-1">
            <span className="text-accent font-semibold">CX</span> Codex
          </span>
          <span className="font-mono text-[11px] border border-line text-dim px-2 py-1">
            <span className="text-accent font-semibold">OC</span> opencode
          </span>
        </div>
      </Reveal>
    </section>
  );
}
