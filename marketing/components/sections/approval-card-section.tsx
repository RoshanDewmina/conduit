import SectionHeader from "@/components/ui/section-header";
import MonoTag from "@/components/ui/mono-tag";
import Panel from "@/components/ui/panel";
import Reveal from "@/components/ui/reveal";
import Glyph from "@/components/viz/glyph";

export default function ApprovalCardSection() {
  return (
    <section
      id="card"
      className="max-w-[1152px] mx-auto px-6 md:px-8 py-20 grid md:grid-cols-2 gap-14 items-center"
    >
      {/* Left: copy */}
      <Reveal>
        <SectionHeader number="02" name="The Approval Card" spectrum />
        <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
          the whole product is one card<span className="text-accent">_</span>
        </h2>
        <p className="font-mono text-sm text-dim leading-relaxed mb-8">
          When an agent wants to do something risky, it pauses. You get a push
          with the exact command, the files it touches, a risk read, and which
          rule matched. Approve, deny, edit-then-run, or &apos;always allow
          this in this repo.&apos; It resumes in a second — even if the app was
          closed.
        </p>
        <div className="flex flex-wrap gap-2">
          <MonoTag tone="allow">Allow</MonoTag>
          <MonoTag tone="deny">Deny</MonoTag>
          <MonoTag tone="neutral">Edit-then-run</MonoTag>
          <MonoTag tone="accent">Always-allow</MonoTag>
        </div>
      </Reveal>

      {/* Right: approval card mockup */}
      <Reveal delay={0.1}>
        <div className="relative">
          <Panel
            header="~/dev/atlas · main"
            headerRight={<MonoTag tone="ask">ASK</MonoTag>}
            className="max-w-sm"
          >
            {/* Agent badge + intent */}
            <div className="px-3 pt-3 pb-2 border-b border-line flex items-center gap-2">
              <span className="font-mono text-[10px] border border-accent/40 bg-accent/10 text-accent px-1.5 py-0.5">
                CX Codex
              </span>
              <span className="font-mono text-xs text-dim">
                wants to run a command
              </span>
            </div>

            {/* Command */}
            <div className="px-3 py-3 border-b border-line bg-block">
              <div className="flex items-center gap-2 font-mono text-xs">
                <span className="text-accent">$</span>
                <span className="text-fg">git push origin main</span>
              </div>
            </div>

            {/* Rule match */}
            <div className="px-3 py-2 border-b border-line">
              <p className="font-mono text-[10px] text-faint">
                matched:{" "}
                <span className="text-med">ask · git remote</span>
              </p>
            </div>

            {/* Blast radius */}
            <div className="px-3 py-2 border-b border-line">
              <p className="font-display text-[9px] tracking-[0.14em] uppercase text-faint mb-1.5">
                Blast Radius
              </p>
              <ul className="space-y-1">
                {[
                  "3 commits, 847 lines",
                  "touches: src/, tests/",
                  "remote: github.com/dev/atlas",
                ].map((item) => (
                  <li key={item} className="font-mono text-[11px] text-dim flex items-center gap-1.5">
                    <Glyph name="chevron" size={9} c="#565963" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>

            {/* Action buttons */}
            <div className="grid grid-cols-3 divide-x divide-line">
              <button className="py-2.5 font-display text-[11px] font-semibold text-high hover:bg-high/5 transition-colors">
                Deny
              </button>
              <button className="py-2.5 font-display text-[11px] font-semibold text-dim hover:bg-fg/5 transition-colors">
                Edit
              </button>
              <button className="py-2.5 font-display text-[11px] font-semibold text-low hover:bg-low/5 transition-colors">
                Allow
              </button>
            </div>
          </Panel>

          {/* Annotation lines */}
          <div className="absolute -right-2 top-12 flex flex-col gap-4 pointer-events-none hidden lg:flex">
            {[
              { label: "the exact command", top: "56px" },
              { label: "a risk read + the rule", top: "116px" },
              { label: "what it touches", top: "160px" },
              { label: "one tap", top: "216px" },
            ].map((a) => (
              <p
                key={a.label}
                className="font-mono text-[10px] text-faint"
                style={{ position: "absolute", right: "-130px", top: a.top }}
              >
                ← {a.label}
              </p>
            ))}
          </div>

          <p className="mt-3 font-mono text-[10px] text-ghost text-center">
            A real approval, mid-decision. [SCREENSHOT — owner to supply]
          </p>
        </div>
      </Reveal>
    </section>
  );
}
