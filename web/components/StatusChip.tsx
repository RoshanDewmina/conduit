import { Badge } from "@/components/ui/badge";

const chip: Record<string, { bg: string; text: string }> = {
  running: { bg: "bg-[--cc-okSoft]", text: "text-[--cc-ok]" },
  idle: { bg: "bg-muted", text: "text-muted-foreground" },
  blocked: { bg: "bg-[--cc-warnSoft]", text: "text-[--cc-warn]" },
};

export function StatusChip({ status }: { status: string }) {
  const c = chip[status] ?? { bg: "bg-[--cc-accentSoft]", text: "text-[--cc-accentInk]" };
  return (
    <Badge variant="outline" className={`border-0 text-[10px] ${c.bg} ${c.text}`}>
      {status}
    </Badge>
  );
}
