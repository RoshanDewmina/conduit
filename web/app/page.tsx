"use client";

import Link from "next/link";
import { useConduitStore } from "@/lib/store/useConduitStore";
import { ConnectionBadge } from "@/components/ConnectionBadge";
import { AgentCard } from "@/components/AgentCard";
import { EmptyState } from "@/components/EmptyState";

export default function FleetPage() {
  const connection = useConduitStore((s) => s.connection);
  const agents = useConduitStore((s) => s.agents);
  const loops = useConduitStore((s) => s.loops);
  const pending = useConduitStore((s) => s.pending);

  const entries = Object.values(agents);

  return (
    <div className="flex-1 flex flex-col p-6 max-w-5xl mx-auto w-full gap-4">
      <div className="flex items-center gap-4">
        <ConnectionBadge state={connection} />
        {pending.length > 0 && (
          <Link
            href="/inbox"
            className="text-xs font-mono text-[--cc-warn] hover:text-[--cc-warn] underline-offset-2 hover:underline"
          >
            {pending.length} pending approval{pending.length !== 1 ? "s" : ""}
          </Link>
        )}
      </div>

      <h1 className="font-display text-lg font-semibold text-foreground">Fleet</h1>

      {entries.length === 0 ? (
        <EmptyState message="No agents connected. Pair a daemon to see your fleet." />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {entries.map((agent) => (
            <AgentCard key={agent.agent} agent={agent} loop={loops[agent.agent]} />
          ))}
        </div>
      )}
    </div>
  );
}
