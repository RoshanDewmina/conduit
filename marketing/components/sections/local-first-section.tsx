import Link from "next/link";
import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

export default function LocalFirstSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20 grid md:grid-cols-2 gap-14 items-center">
      <Reveal>
        <SectionHeader number="06" name="Local-first" spectrum />
        <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
          your code stays on your machine<span className="text-accent">_</span>
        </h2>
        <p className="font-mono text-sm text-dim leading-relaxed mb-4">
          A small bridge —{" "}
          <span className="font-mono text-fg bg-input border border-line px-1">
            conduitd
          </span>{" "}
          — runs on your host and enforces the policy <em>you</em> set. Conduit
          never gets your source or your credentials; the approval relay carries
          only the action metadata you choose to send. You own the bridge.
        </p>
        <p className="font-mono text-[13px] text-faint italic leading-relaxed">
          End-to-end encryption of the relay and an open-source bridge are
          [PLANNED] —{" "}
          <Link href="/trust" className="text-accent not-italic">
            see Trust
          </Link>
          .
        </p>
      </Reveal>

      <Reveal delay={0.1}>
        <div className="border border-line bg-raised p-6 space-y-3">
          {/* host */}
          <div className="border border-line bg-input p-4">
            <div className="font-mono text-[10px] tracking-[0.18em] text-faint">
              YOUR HOST
            </div>
            <div className="flex flex-wrap gap-1.5 mt-2.5">
              {["claude code", "codex", "opencode"].map((c) => (
                <span
                  key={c}
                  className="font-mono text-[11px] px-2 py-1 border border-line bg-raised text-dim"
                >
                  {c}
                </span>
              ))}
              <span className="font-mono text-[11px] px-2 py-1 border border-accent bg-accent text-white">
                conduitd
              </span>
            </div>
            <div className="font-mono text-[11.5px] text-low mt-3">
              ⌂ source code · credentials — stay here
            </div>
          </div>

          {/* connector */}
          <div className="flex items-center gap-2.5 ml-7">
            <span className="w-px h-7 border-l border-dashed border-fg/30" />
            <span className="font-mono text-[10.5px] text-faint">
              approval metadata only ↓ — command · paths · risk
            </span>
          </div>

          {/* relay */}
          <div className="border border-dashed border-line p-4">
            <div className="font-mono text-[10px] tracking-[0.18em] text-faint">
              RELAY
            </div>
            <div className="font-mono text-[11.5px] text-dim mt-1.5">
              no source · no credentials · E2EE [PLANNED]
            </div>
          </div>

          {/* connector */}
          <div className="flex items-center gap-2.5 ml-7">
            <span className="w-px h-7 border-l border-dashed border-fg/30" />
            <span className="font-mono text-[10.5px] text-faint">push ↓</span>
          </div>

          {/* phone */}
          <div className="border border-line bg-input p-4">
            <div className="font-mono text-[10px] tracking-[0.18em] text-faint">
              YOUR PHONE
            </div>
            <div className="font-mono text-[11.5px] text-dim mt-1.5">
              approve · deny · edit — one tap
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
