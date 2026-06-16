"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useConduitStore } from "@/lib/store/useConduitStore";
import { ConnectionBadge } from "@/components/ConnectionBadge";
import { StatusChip } from "@/components/StatusChip";
import { ApprovalCard } from "@/components/ApprovalCard";
import { Card, CardContent } from "@/components/ui/card";

export default function AgentDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const agents = useConduitStore((s) => s.agents);
  const loops = useConduitStore((s) => s.loops);
  const pending = useConduitStore((s) => s.pending);
  const connection = useConduitStore((s) => s.connection);

  const agent = agents[id];
  const agentLoop = loops[id];
  const agentPending = pending.filter((p) => p.agent === id);

  if (!agent) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-4 p-6">
        <p className="text-sm font-mono text-muted-foreground">
          Agent &quot;{id}&quot; not found.
        </p>
        <Link href="/" className="text-xs font-mono text-[--cc-accentInk] hover:underline">
          Back to Fleet
        </Link>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col p-6 max-w-3xl mx-auto w-full gap-4">
      <Link
        href="/"
        className="text-xs font-mono text-muted-foreground hover:text-foreground"
      >
        &larr; Fleet
      </Link>

      <div className="flex items-center gap-3">
        <h1 className="font-display text-lg font-semibold text-foreground">
          {agent.agent}
        </h1>
        <ConnectionBadge state={connection} />
      </div>
      {agent.model && (
        <p className="text-xs font-mono text-muted-foreground -mt-2">{agent.model}</p>
      )}

      {agentLoop && (
        <Card>
          <CardContent className="flex items-center gap-2">
            <StatusChip status={agentLoop.status} />
            {agentLoop.currentStep && (
              <span className="text-xs font-mono text-muted-foreground truncate max-w-60">
                {agentLoop.currentStep}
              </span>
            )}
            {agentLoop.spendUSD !== undefined && (
              <span className="text-xs font-mono text-muted-foreground ml-auto">
                ${agentLoop.spendUSD.toFixed(2)}
              </span>
            )}
          </CardContent>
        </Card>
      )}

      {agentPending.length > 0 && (
        <div>
          <h2 className="text-sm font-display font-semibold text-foreground mb-2">
            Pending Approvals
          </h2>
          <div className="flex flex-col gap-2">
            {agentPending.map((approval) => (
              <ApprovalCard key={approval.approvalID} approval={approval} />
            ))}
          </div>
        </div>
      )}

      <Card className="bg-[--cc-sunk] border-0">
        <CardContent>
          <p className="text-xs font-mono text-muted-foreground">
            Live block transcript is available on the phone. Full transcript replay is
            coming to web.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
