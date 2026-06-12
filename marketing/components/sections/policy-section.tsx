import SectionHeader from "@/components/ui/section-header";
import MonoTag from "@/components/ui/mono-tag";
import Panel from "@/components/ui/panel";
import Reveal from "@/components/ui/reveal";

type Verdict = "allow" | "ask" | "never";

const RULES: { cmd: string; verdict: Verdict; label: string }[] = [
  { cmd: "go test ./...", verdict: "allow", label: "AUTO-ALLOW" },
  { cmd: "edits inside working tree", verdict: "allow", label: "AUTO-ALLOW" },
  { cmd: "npm install left-pad", verdict: "ask", label: "ASK" },
  { cmd: "git push origin main", verdict: "ask", label: "ASK" },
  { cmd: "cat .env", verdict: "ask", label: "ASK" },
  { cmd: "rm -rf /", verdict: "never", label: "NEVER" },
  { cmd: "read ~/.ssh/id_ed25519", verdict: "never", label: "NEVER" },
];

const toneFor: Record<Verdict, "allow" | "ask" | "never"> = {
  allow: "allow",
  ask: "ask",
  never: "never",
};

export default function PolicySection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20 grid md:grid-cols-2 gap-14 items-center">
      <Reveal>
        <SectionHeader number="03" name="Policy" spectrum />
        <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
          most actions should never reach your phone<span className="text-accent">_</span>
        </h2>
        <p className="font-mono text-sm text-dim leading-relaxed mb-8">
          Start from a preset — Cautious, Balanced, or Bypass — then tighten per
          repo. Reads, tests, and edits inside the working tree auto-allow.
          Lockfiles,{" "}
          <span className="font-mono text-fg bg-input border border-line px-1">
            git push
          </span>
          , anything touching{" "}
          <span className="font-mono text-fg bg-input border border-line px-1">
            .env
          </span>{" "}
          or{" "}
          <span className="font-mono text-fg bg-input border border-line px-1">
            ~/.ssh
          </span>
          , network installs — those ask.{" "}
          <span className="font-mono text-high bg-high/10 border border-high/20 px-1">
            rm -rf /
          </span>{" "}
          and credential reads — those never run. You&apos;re in control
          precisely because you&apos;re not asked about everything.
        </p>
        <div className="flex flex-wrap gap-2">
          <span className="font-display text-xs font-semibold lowercase tracking-[.02em] border border-line text-dim px-4 py-2">
            cautious
          </span>
          <span className="font-display text-xs font-semibold lowercase tracking-[.02em] bg-accent border border-accent text-white px-4 py-2">
            balanced
          </span>
          <span className="font-display text-xs font-semibold lowercase tracking-[.02em] border border-line text-dim px-4 py-2">
            bypass
          </span>
        </div>
      </Reveal>

      <Reveal delay={0.1}>
        <Panel header="~/dev/atlas/.conduit/policy.yaml">
          <div>
            {RULES.map((r, i) => (
              <div
                key={r.cmd}
                className={`flex items-center justify-between gap-3 px-4 py-2.5 ${
                  i !== 0 ? "border-t border-line-soft" : ""
                }`}
              >
                <span className="font-mono text-[13px] text-fg min-w-0 truncate">
                  {r.cmd}
                </span>
                <MonoTag tone={toneFor[r.verdict]}>{r.label}</MonoTag>
              </div>
            ))}
          </div>
          <div className="border-t border-line px-4 py-3 font-mono text-[11px] text-faint">
            deny &gt; ask &gt; allow · default: ask · fail-closed
          </div>
        </Panel>
      </Reveal>
    </section>
  );
}
