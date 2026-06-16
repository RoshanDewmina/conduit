"use client";

import { useState } from "react";
import type { ApprovalPending } from "@/lib/relay/types";
import { riskTier } from "@/lib/relay/types";
import { useConduitStore } from "@/lib/store/useConduitStore";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { RiskBadge } from "./RiskBadge";

export function ApprovalCard({ approval }: { approval: ApprovalPending }) {
  const decide = useConduitStore((s) => s.decide);
  const [working, setWorking] = useState(false);
  const tier = riskTier(approval.risk);

  async function handle(decision: "approve" | "deny" | "approveAlways") {
    setWorking(true);
    try {
      await decide(approval.approvalID, decision);
    } finally {
      setWorking(false);
    }
  }

  return (
    <Card>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between gap-2">
          <span className="text-sm font-mono text-foreground">{approval.agent}</span>
          <RiskBadge risk={approval.risk} />
        </div>
        <span className="text-xs font-mono text-muted-foreground block">{approval.kind}</span>
        {approval.command && (
          <div className="bg-[--cc-sunk] rounded px-2 py-1 overflow-hidden">
            <code className="text-xs font-mono text-foreground truncate block">$ {approval.command}</code>
          </div>
        )}
        {approval.cwd && (
          <p className="text-xs font-mono text-muted-foreground truncate">{approval.cwd}</p>
        )}
        <div className="flex items-center gap-2 pt-1">
          <Button variant="ghost" size="xs" disabled={working} onClick={() => handle("deny")}>
            Deny
          </Button>
          {tier === "critical" && working ? (
            <Button variant="default" size="xs" disabled>
              Verify…
            </Button>
          ) : (
            <Button variant="default" size="xs" disabled={working} onClick={() => handle("approve")}>
              Approve
            </Button>
          )}
          <Button variant="outline" size="xs" disabled={working} onClick={() => handle("approveAlways")}>
            Always
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
