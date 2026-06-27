import SectionHeader from "@/components/ui/section-header";
import Panel from "@/components/ui/panel";
import Reveal from "@/components/ui/reveal";

type Actor = "policy" | "you";
type Result = "allowed" | "approved" | "denied";

const ROWS: {
  time: string;
  actor: Actor;
  cmd: string;
  rule: string;
  result: Result;
}[] = [
  { time: "14:02:11", actor: "policy", cmd: "go test ./...", rule: "rule: auto-test", result: "allowed" },
  { time: "14:02:38", actor: "policy", cmd: "git diff --stat", rule: "rule: read-only", result: "allowed" },
  { time: "14:03:04", actor: "you", cmd: "rm -rf node_modules/", rule: "rule: ask · bulk delete", result: "approved" },
  { time: "14:03:46", actor: "policy", cmd: "curl -fsSL https://get.zr.sh | sh", rule: "rule: curl-pipe-sh", result: "denied" },
  { time: "14:05:12", actor: "you", cmd: "npm publish --dry-run", rule: "edited, then run", result: "approved" },
];

export default function ActivitySection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="04" name="Activity" spectrum />
        <div className="max-w-[720px] mb-10">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            see everything that ran while you were away<span className="text-accent">_</span>
          </h2>
          <p className="font-mono text-sm text-dim leading-relaxed">
            Every autonomous decision and every tap lands in an append-only,
            secret-redacted log: what the agent did, which rule allowed it, what
            you approved. The trust surface — and your compliance evidence if you
            ever need it.
          </p>
        </div>
      </Reveal>

      <Reveal delay={0.1}>
        <Panel
          header="~/.lancer/audit.log"
          headerRight="APPEND-ONLY · SECRET-REDACTED"
        >
          <div className="overflow-x-auto">
            <div className="min-w-[640px]">
              {ROWS.map((row, i) => {
                const resColor =
                  row.result === "denied" ? "text-high" : "text-low";
                const glyph = row.result === "denied" ? "✕" : "✓";
                return (
                  <div
                    key={i}
                    className={`grid grid-cols-[88px_64px_1fr_220px_104px] gap-4 px-4 py-3 items-center font-mono text-[12.5px] ${
                      i !== 0 ? "border-t border-line-soft" : ""
                    } ${row.actor === "you" ? "bg-accent/[0.05]" : ""}`}
                  >
                    <span className="text-faint">{row.time}</span>
                    <span
                      className={
                        row.actor === "you"
                          ? "text-accent font-semibold"
                          : "text-dim"
                      }
                    >
                      {row.actor}
                    </span>
                    <span className="text-fg truncate">{row.cmd}</span>
                    <span className="text-dim truncate">{row.rule}</span>
                    <span className={resColor}>
                      {glyph} {row.result}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        </Panel>
      </Reveal>
    </section>
  );
}
