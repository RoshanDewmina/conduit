import Button from "@/components/ui/button";
import Reveal from "@/components/ui/reveal";

export default function FinalCtaSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <div className="relative bg-accent overflow-hidden px-8 md:px-12 py-20 text-center">
          <div
            className="absolute inset-0 pointer-events-none opacity-[0.07]"
            style={{
              backgroundImage:
                "linear-gradient(to right, #fff 1px, transparent 1px), linear-gradient(to bottom, #fff 1px, transparent 1px)",
              backgroundSize: "48px 48px",
            }}
          />
          <h2 className="relative font-display font-bold text-3xl md:text-5xl leading-[1.05] text-white mb-4">
            let your agents run.
            <br />
            we&apos;ll get you when it matters<span className="text-white/60">_</span>
          </h2>
          <p className="relative font-mono text-sm text-white/75 mb-8">
            Join the TestFlight beta — no account required.
          </p>
          <div className="relative flex justify-center">
            <Button href="/download" variant="light">
              Get Lancer
            </Button>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
