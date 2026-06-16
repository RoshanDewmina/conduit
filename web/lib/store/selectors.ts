import type { ApprovalPending, AgentStatus, LoopUpdate } from "@/lib/relay/types";

export const selectPendingCount = (s: { pending: ApprovalPending[] }) =>
  s.pending.length;

export const selectAgentList = (s: {
  agents: Record<string, AgentStatus>;
}) => Object.values(s.agents);

export const selectLoopList = (s: { loops: Record<string, LoopUpdate> }) =>
  Object.values(s.loops);

export const selectCriticalPending = (s: { pending: ApprovalPending[] }) =>
  s.pending.filter((p) => p.risk >= 3);
