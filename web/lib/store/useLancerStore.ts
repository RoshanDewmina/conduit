import { create } from "zustand";
import type {
  ApprovalPending,
  AgentStatus,
  LoopUpdate,
  ApprovalResponse,
  Decision,
  ConnectionState,
  InboundAppMessage,
} from "@/lib/relay/types";
import { riskTier } from "@/lib/relay/types";
import { verifyPresence } from "@/lib/auth/webauthn";

export interface ApprovalSender {
  sendApprovalResponse: (resp: ApprovalResponse) => void;
}

interface LancerState {
  connection: ConnectionState;
  agents: Record<string, AgentStatus>;
  loops: Record<string, LoopUpdate>;
  pending: ApprovalPending[];
  sender: ApprovalSender | null;
  lastError: string | null;

  setConnection: (s: ConnectionState) => void;
  setSender: (s: ApprovalSender | null) => void;
  ingest: (m: InboundAppMessage) => void;
  decide: (approvalID: string, decision: Decision) => Promise<void>;
  clearError: () => void;
}

export const useLancerStore = create<LancerState>((set, get) => ({
  connection: "disconnected",
  agents: {},
  loops: {},
  pending: [],
  sender: null,
  lastError: null,

  setConnection: (s) => set({ connection: s }),

  setSender: (s) => set({ sender: s }),

  ingest: (m) => {
    switch (m.type) {
      case "approvalPending": {
        const dp = m.payload;
        set((s) => {
          const filtered = s.pending.filter(
            (p) => p.approvalID !== dp.approvalID
          );
          return { pending: [dp, ...filtered] };
        });
        break;
      }
      case "agentStatus":
        set((s) => ({
          agents: { ...s.agents, [m.payload.agent]: m.payload },
        }));
        break;
      case "loopUpdate":
        set((s) => ({
          loops: { ...s.loops, [m.payload.loopID]: m.payload },
        }));
        break;
    }
  },

  decide: async (approvalID, decision) => {
    const { pending, sender } = get();
    const approval = pending.find((p) => p.approvalID === approvalID);
    if (!approval) {
      set({ lastError: "Approval not found" });
      return;
    }
    if (riskTier(approval.risk) === "critical") {
      try {
        await verifyPresence();
      } catch {
        set({ lastError: "Biometric verification failed" });
        return;
      }
    }
    if (!sender) {
      set({ lastError: "No relay connection" });
      return;
    }
    const resp: ApprovalResponse = { approvalID, decision };
    sender.sendApprovalResponse(resp);
    set((s) => ({
      pending: s.pending.filter((p) => p.approvalID !== approvalID),
    }));
  },

  clearError: () => set({ lastError: null }),
}));
