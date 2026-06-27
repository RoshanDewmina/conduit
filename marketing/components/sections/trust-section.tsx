import Link from "next/link";
import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const POINTS = [
  {
    label: "Security model",
    body: "SSH transport, local unix socket for policy enforcement, TOFU host verification, platform secure storage for credentials.",
    href: "/trust",
  },
  {
    label: "Privacy policy",
    body: "No account required. No behavioural analytics. Keys stored in iOS Keychain — never synced, never transmitted to Lancer servers.",
    href: "/privacy",
  },
  {
    label: "Self-hosted relay",
    body: "Run your own push relay. No mandatory Lancer cloud in the approval loop. End-to-end encryption of the relay is [PLANNED].",
    href: "/trust",
  },
];

export default function TrustSection() {
  return (
    <section id="trust" className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="08" name="Trust & Privacy" spectrum />
        <div className="max-w-[720px] mb-14">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            your code stays your code<span className="text-accent">_</span>
          </h2>
          <p className="font-mono text-sm text-dim leading-relaxed">
            Lancer is designed so that you never have to trust a cloud. The
            bridge runs on your machine. Credentials stay in your keychain.
            Source never leaves your host. Everything else is a verifiable
            choice.
          </p>
        </div>
      </Reveal>

      <div className="grid md:grid-cols-3 gap-6">
        {POINTS.map((p, i) => (
          <Reveal key={p.label} delay={i * 0.1}>
            <div className="border border-line bg-raised p-6 h-full flex flex-col">
              <h3 className="font-display text-lg font-semibold text-fg mb-3">
                {p.label}
              </h3>
              <p className="font-mono text-sm text-dim leading-relaxed flex-1 mb-4">
                {p.body}
              </p>
              <Link
                href={p.href}
                className="font-mono text-xs text-accent hover:text-accent/80 underline underline-offset-2"
              >
                Learn more →
              </Link>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
