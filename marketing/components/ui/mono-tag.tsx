type Tone = "allow" | "deny" | "ask" | "never" | "neutral" | "accent";

interface MonoTagProps {
  tone?: Tone;
  children: React.ReactNode;
  className?: string;
}

const toneClasses: Record<Tone, string> = {
  allow: "text-low border-low/40 bg-low/10",
  deny: "text-high border-high/40 bg-high/10",
  ask: "text-med border-med/40 bg-med/10",
  never: "text-high border-high/60 bg-high/15",
  neutral: "text-dim border-line bg-transparent",
  accent: "text-accent border-accent/40 bg-accent/10",
};

export default function MonoTag({
  tone = "neutral",
  children,
  className = "",
}: MonoTagProps) {
  return (
    <span
      className={`inline-flex items-center font-mono text-[10px] tracking-[.08em] uppercase border px-2 py-0.5 ${toneClasses[tone]} ${className}`}
    >
      {children}
    </span>
  );
}
