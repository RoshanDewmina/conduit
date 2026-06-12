import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const VENDORS = [
  { code: "CC", name: "Claude Code" },
  { code: "CX", name: "Codex" },
  { code: "OC", name: "opencode" },
];

export default function CrossVendorSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="05" name="Cross-vendor" spectrum />
        <div className="max-w-[720px] mx-auto text-center mb-12">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            one layer over every agent you run<span className="text-accent">_</span>
          </h2>
          <p className="font-mono text-sm text-dim leading-relaxed">
            Claude Code, Codex, and opencode each have their own permission
            system. Conduit is the single policy, approval, and audit layer
            across all three — so you set the rules once, not three times.
          </p>
        </div>
      </Reveal>

      <Reveal delay={0.1} className="max-w-[820px] mx-auto">
        <div className="grid grid-cols-3 gap-4">
          {VENDORS.map((v) => (
            <div
              key={v.code}
              className="border border-line bg-raised px-4 py-5 text-center"
            >
              <div className="font-mono text-[11px] font-semibold text-accent">
                {v.code}
              </div>
              <div className="font-display text-sm font-semibold text-fg mt-1.5">
                {v.name}
              </div>
              <div className="font-mono text-[11px] text-faint mt-1">
                its own permission system
              </div>
            </div>
          ))}
        </div>

        {/* converging connector */}
        <div className="w-2/3 mx-auto h-6 border-l border-r border-b border-line" />
        <div className="w-px h-6 mx-auto bg-line" />

        <div className="max-w-[420px] mx-auto border border-accent bg-raised px-6 py-5 text-center">
          <div className="font-display text-lg font-bold text-fg">
            conduit<span className="text-accent">_</span>
          </div>
          <div className="font-mono text-[11px] tracking-[0.08em] text-accent mt-1">
            one policy · one inbox · one audit log
          </div>
        </div>
      </Reveal>
    </section>
  );
}
