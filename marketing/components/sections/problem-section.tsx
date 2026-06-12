import SectionHeader from "@/components/ui/section-header";
import Reveal from "@/components/ui/reveal";

export default function ProblemSection() {
  return (
    <section className="max-w-[780px] mx-auto px-6 md:px-8 py-20 text-center">
      <Reveal>
        <SectionHeader number="01" name="The Problem" spectrum />
        <h2 className="font-display font-bold text-3xl md:text-4xl leading-[1.1] text-fg mb-6">
          you can&apos;t watch an agent every second. you can&apos;t let it run
          blind either.
        </h2>
        <p className="font-mono text-sm text-dim leading-relaxed">
          Approve every action and it&apos;s death by a thousand taps. Approve
          nothing and you&apos;re one{" "}
          <span className="font-mono text-high bg-high/10 border border-high/20 px-1.5 py-0.5 text-xs">
            rm -rf
          </span>{" "}
          from a bad afternoon. And every vendor wants its own unrestricted
          access to your repo. There&apos;s no layer that sits above all of
          them and answers one question: can this safely proceed while I&apos;m
          away?
        </p>
      </Reveal>
    </section>
  );
}
