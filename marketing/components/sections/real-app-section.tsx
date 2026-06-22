import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

const SCREENS = [
  { src: "/screens/app-sessions.png", caption: "sessions" },
  { src: "/screens/app-inbox.png", caption: "inbox" },
  { src: "/screens/app-settings.png", caption: "settings" },
];

export default function RealAppSection() {
  return (
    <section className="max-w-[1152px] mx-auto px-6 md:px-8 py-20">
      <Reveal>
        <SectionHeader number="07" name="The Real App" spectrum />
        <div className="max-w-[720px] mb-12">
          <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
            this is the actual app<span className="text-accent">_</span>
          </h2>
          <p className="font-mono text-sm text-dim leading-relaxed">
            No mockups. Sessions, inbox, and settings as they ship in the
            TestFlight build today.
          </p>
        </div>
      </Reveal>

      <Reveal delay={0.1}>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 max-w-[820px] mx-auto">
          {SCREENS.map((s) => (
            <div key={s.src} className="flex flex-col items-center gap-3">
              <div className="border border-line bg-block overflow-hidden">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={s.src}
                  alt={`Lancer app — ${s.caption}`}
                  className="block w-full h-auto"
                  loading="lazy"
                />
              </div>
              <span className="font-mono text-[11px] tracking-[0.14em] uppercase text-faint">
                {s.caption}
              </span>
            </div>
          ))}
        </div>
      </Reveal>
    </section>
  );
}
