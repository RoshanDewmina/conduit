import Button from "@/components/ui/button";
import MonoTag from "@/components/ui/mono-tag";
import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const TIERS = [
  {
    name: "Free",
    price: "$0",
    period: "",
    cta: "Join the beta",
    ctaVariant: "ghost" as const,
    foundingPitch: null,
    features: [
      "Self-host: unlimited approvals",
      "Cloud relay: 3 sessions / mo",
      "Policy + audit log",
      "Cross-vendor support",
    ],
    missing: [
      "Unlimited cloud relay",
      "Fleet dashboard",
    ],
  },
  {
    name: "Pro",
    price: "$9",
    period: "/mo or $79/yr",
    cta: "Join the beta",
    ctaVariant: "primary" as const,
    foundingPitch: "Founding Pro $49/yr — first 500 only — lifetime lock",
    features: [
      "Unlimited approvals (cloud + self-host)",
      "Policy + audit log",
      "Fleet dashboard",
      "Cross-vendor support",
    ],
    missing: [],
  },
  {
    name: "Teams",
    price: "[PLANNED]",
    period: "",
    cta: "Talk to us",
    ctaVariant: "ghost" as const,
    foundingPitch: null,
    features: [
      "Shared team policies",
      "Signed audit export",
      "On-prem relay",
      "Priority support",
    ],
    missing: [
      "Pricing not yet set",
    ],
  },
];

export default function PricingSection() {
  return (
    <section id="pricing" className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="09" name="Pricing" spectrum />
        <div className="max-w-[640px] mb-14">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            free to run. pay once if you want more<span className="text-accent">_</span>
          </h2>
          <p className="font-mono text-sm text-dim leading-relaxed">
            No account required to start. All tiers include policy engine, audit
            log, and cross-vendor support. Founding Pro is a one-time purchase
            that never expires.
          </p>
        </div>
      </Reveal>

      <div className="grid md:grid-cols-3 gap-6 items-start">
        {TIERS.map((t, i) => (
          <Reveal key={t.name} delay={i * 0.1}>
            <div
              className={`border p-6 flex flex-col h-full ${
                i === 1
                  ? "border-accent bg-accent/[0.04]"
                  : "border-line bg-raised"
              } ${i === 2 ? "opacity-70" : ""}`}
            >
              <div className="mb-6">
                <h3 className="font-display text-xl font-bold text-fg mb-1">
                  {t.name}
                </h3>
                <div className="flex items-baseline gap-1.5">
                  <span className="font-display text-3xl font-bold text-fg">
                    {t.price}
                  </span>
                  {t.period && (
                    <span className="font-mono text-xs text-dim">{t.period}</span>
                  )}
                  {i === 2 && (
                    <span className="font-mono text-xs text-med">not set</span>
                  )}
                </div>
                {t.foundingPitch && (
                  <div className="mt-2">
                    <MonoTag tone="accent">{t.foundingPitch}</MonoTag>
                  </div>
                )}
              </div>

              <ul className="space-y-3 mb-8 flex-1">
                {t.features.map((f) => (
                  <li
                    key={f}
                    className="font-mono text-xs text-dim flex items-start gap-2"
                  >
                    <span className="text-low shrink-0 mt-0.5">✓</span>
                    {f}
                  </li>
                ))}
                {t.missing.map((f) => (
                  <li
                    key={f}
                    className="font-mono text-xs text-faint flex items-start gap-2"
                  >
                    <span className="text-faint shrink-0 mt-0.5">—</span>
                    {f}
                  </li>
                ))}
              </ul>

              <Button
                href="/download"
                variant={t.ctaVariant}
                className="w-full text-center"
              >
                {t.cta}
              </Button>
            </div>
          </Reveal>
        ))}
      </div>

      <Reveal delay={0.35}>
        <p className="mt-10 font-mono text-xs text-faint text-center max-w-lg mx-auto leading-relaxed">
          Founding Pro is a limited one-time purchase for the first 500
          subscribers — $49/year, locked in for life, never a subscription.
        </p>
      </Reveal>
    </section>
  );
}
