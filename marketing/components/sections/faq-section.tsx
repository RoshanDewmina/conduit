import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const FAQS = [
  {
    q: "Does my code go through your servers?",
    a: "No. Source and credentials stay on your host. The relay only carries the approval metadata you send. End-to-end encryption of the relay is [PLANNED].",
  },
  {
    q: "How is this different from Claude's or OpenAI's mobile app?",
    a: "Those are single-vendor (Claude-only / Codex-only), and Anthropic's isn't available to Team/Enterprise. Lancer governs all your agents, with your code on your host.",
  },
  {
    q: "Will it constantly interrupt me?",
    a: "No — policy auto-handles the safe majority. You tune how cautious it is from a preset.",
  },
  {
    q: "Which agents are supported?",
    a: "Claude Code, Codex, and opencode today.",
  },
  {
    q: "Is it available?",
    a: "TestFlight beta now; App Store release is [PLANNED].",
  },
  {
    q: "What does it cost?",
    a: "Free to use. Self-host and cloud (3 sessions/mo) are $0. Pro is $9/mo or $79/yr. Founding Pro is $49/yr — a one-time purchase for the first 500 subscribers. Team/self-host pricing is [PLANNED].",
  },
];

export default function FaqSection() {
  return (
    <section className="max-w-[800px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="FAQ" name="Questions" />
        <div>
          {FAQS.map((f, i) => (
            <details
              key={i}
              className="group border-b border-line py-5"
            >
              <summary className="flex items-center justify-between gap-4">
                <span className="font-display text-lg md:text-xl font-semibold text-fg">
                  {f.q}
                </span>
                <span className="font-mono text-lg text-faint group-open:rotate-45 transition-transform">
                  +
                </span>
              </summary>
              <p className="font-mono text-sm text-dim leading-relaxed mt-3 max-w-[640px]">
                {f.a}
              </p>
            </details>
          ))}
        </div>
      </Reveal>
    </section>
  );
}
