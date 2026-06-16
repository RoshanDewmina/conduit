// web/lib/relay/types.ts — shared contract for the Conduit web dashboard.
// Mirrors daemon relay payloads (ConduitCore/E2ERelayMessage.swift + daemon/push-backend/PAIRING_PROTOCOL.md).

export type RiskTier = "low" | "medium" | "high" | "critical";

/** Canonical mapping — matches DesignSystem/Components/InboxCards.swift:290. */
export function riskTier(r: number): RiskTier {
  return r >= 3 ? "critical" : r === 2 ? "high" : r === 1 ? "medium" : "low";
}

export type Decision = "approve" | "deny" | "approveAlways";

export interface ApprovalPending {
  approvalID: string;
  agent: string;
  kind: string;
  command?: string;
  risk: number;
  cwd?: string;
  toolName?: string;
}

export interface AgentStatus {
  agent: string;
  model?: string;
  sessionCount: number;
  usageUSD?: number;
}

export interface LoopUpdate {
  loopID: string;
  status: string;
  currentStep?: string;
  spendUSD?: number;
}

export interface ApprovalResponse {
  approvalID: string;
  decision: Decision;
  editedToolInput?: string;
}

/** Encrypted relay frame (ChaCha20-Poly1305). base64url no-pad fields. */
export interface EncryptedFrame {
  version: 1;
  nonce: string;
  ciphertext: string; // WITHOUT the 16-byte tag
  tag: string;        // 16-byte Poly1305 tag
}

export type RelayControl =
  | { type: "paired"; role: string }
  | { type: "waiting"; role?: string }
  | { type: "peer_joined"; role: string; peerPublicKey: string }
  | { type: "ping" }
  | { type: "pong" }
  | { type: "message"; from?: string; target?: string; payload: string }
  | { type: "close" };

export type InboundAppMessage =
  | { type: "approvalPending"; payload: ApprovalPending }
  | { type: "agentStatus"; payload: AgentStatus }
  | { type: "loopUpdate"; payload: LoopUpdate };

export type ConnectionState = "disconnected" | "pairing" | "connected" | "error";
