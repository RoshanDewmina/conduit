import SpectrumBar from "@/components/viz/spectrum-bar";

interface SectionHeaderProps {
  number: string;
  name: string;
  spectrum?: boolean;
  className?: string;
}

export default function SectionHeader({
  number,
  name,
  spectrum = false,
  className = "",
}: SectionHeaderProps) {
  return (
    <div className={`mb-10 ${className}`}>
      <div className="flex items-center gap-4">
        <span className="font-display text-xs font-semibold tracking-[0.2em] uppercase text-faint whitespace-nowrap">
          {number} / {name}
        </span>
        <div className="flex-1 h-px bg-fg/10" />
      </div>
      {spectrum && (
        <div className="mt-2">
          <SpectrumBar behavior="subtle" state="idle" motion="balanced" height={2} />
        </div>
      )}
    </div>
  );
}
