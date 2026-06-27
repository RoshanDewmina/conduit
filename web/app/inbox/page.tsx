"use client";

import { useLancerStore } from "@/lib/store/useLancerStore";
import { ApprovalCard } from "@/components/ApprovalCard";
import { EmptyState } from "@/components/EmptyState";
import { Button } from "@/components/ui/button";

export default function InboxPage() {
  const pending = useLancerStore((s) => s.pending);
  const lastError = useLancerStore((s) => s.lastError);
  const clearError = useLancerStore((s) => s.clearError);

  return (
    <div className="flex-1 flex flex-col p-6 max-w-3xl mx-auto w-full gap-4">
      <h1 className="font-display text-lg font-semibold text-foreground">Inbox</h1>

      {lastError && (
        <div className="flex items-center gap-2 bg-[--cc-dangerSoft] border border-[--cc-danger] rounded px-3 py-2">
          <span className="text-xs font-mono text-[--cc-danger] flex-1">{lastError}</span>
          <Button variant="ghost" size="xs" onClick={clearError}>
            Clear
          </Button>
        </div>
      )}

      {pending.length === 0 ? (
        <EmptyState message="No pending approvals." />
      ) : (
        <div className="flex flex-col gap-2">
          {pending.map((approval) => (
            <ApprovalCard key={approval.approvalID} approval={approval} />
          ))}
        </div>
      )}
    </div>
  );
}
