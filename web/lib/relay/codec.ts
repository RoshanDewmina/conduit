import type { ApprovalResponse, InboundAppMessage, EncryptedFrame } from "./types";
import { encryptFrame, decryptFrame, textEncode, textDecode } from "./crypto";

export function encodeApprovalResponse(resp: ApprovalResponse, key: Uint8Array): string {
  const plaintext = JSON.stringify({ type: "approvalResponse", approvalID: resp.approvalID, decision: resp.decision, ...(resp.editedToolInput ? { editedToolInput: resp.editedToolInput } : {}) });
  const frame: EncryptedFrame = encryptFrame(textEncode(plaintext), key);
  return JSON.stringify({ type: "message", target: "daemon", payload: JSON.stringify(frame) });
}

export function decodeInbound(payloadStr: string, key: Uint8Array): InboundAppMessage | null {
  const frame: EncryptedFrame = JSON.parse(payloadStr);
  const plain = JSON.parse(textDecode(decryptFrame(frame, key)));
  const t = plain.type;
  if (t === "approvalPending" || t === "agentStatus" || t === "loopUpdate") {
    const payload = plain.payload ?? plain;
    return { type: t, payload } as InboundAppMessage;
  }
  return null;
}
