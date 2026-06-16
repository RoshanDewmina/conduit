import Link from "next/link";
import type { AgentStatus, LoopUpdate } from "@/lib/relay/types";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { StatusChip } from "./StatusChip";

export function AgentCard({ agent, loop }: { agent: AgentStatus; loop?: LoopUpdate }) {
  return (
    <Link href={`/agent/${agent.agent}`}>
      <Card className="hover:bg-[--cc-surface2] transition-colors cursor-pointer">
        <CardHeader>
          <div className="flex items-center justify-between">
            <span className="font-display text-sm font-semibold text-foreground">{agent.agent}</span>
            <Badge variant="secondary" className="text-[10px]">
              {agent.sessionCount} {agent.sessionCount === 1 ? "session" : "sessions"}
            </Badge>
          </div>
          {agent.model && (
            <p className="text-xs font-mono text-muted-foreground mt-0.5">{agent.model}</p>
          )}
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-2">
            {loop && <StatusChip status={loop.status} />}
            {loop?.currentStep && (
              <span className="text-xs font-mono text-muted-foreground truncate max-w-40">{loop.currentStep}</span>
            )}
            {(agent.usageUSD ?? loop?.spendUSD) !== undefined && (
              <span className="text-xs font-mono text-muted-foreground ml-auto">
                ${((agent.usageUSD ?? loop?.spendUSD ?? 0)).toFixed(2)}
              </span>
            )}
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
