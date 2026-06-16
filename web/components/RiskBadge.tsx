import { riskTier, type RiskTier } from "@/lib/relay/types";
import { Badge } from "@/components/ui/badge";

const color: Record<RiskTier, string> = {
  low: "text-[--cc-rLow]",
  medium: "text-[--cc-rMed]",
  high: "text-[--cc-rHigh]",
  critical: "text-[--cc-rCrit]",
};

export function RiskBadge({ risk }: { risk: number }) {
  const tier = riskTier(risk);
  return (
    <Badge variant="outline" className={`border-0 uppercase text-[10px] tracking-wider ${color[tier]}`}>
      {tier}
    </Badge>
  );
}
