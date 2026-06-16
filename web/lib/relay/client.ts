import type { ConnectionState, InboundAppMessage, ApprovalResponse } from "./types";
import { generateKeyPair, deriveSessionKey, b64uEncode } from "./crypto";
import { encodeApprovalResponse, decodeInbound } from "./codec";

export class RelayClient {
  private ws: WebSocket | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private key: Uint8Array | null = null;
  private ownPubB64: string;
  private ownPriv: Uint8Array;

  readonly opts: {
    relayBase: string;
    code: string;
    onMessage: (m: InboundAppMessage) => void;
    onState: (s: ConnectionState) => void;
  };

  constructor(opts: { relayBase: string; code: string; onMessage: (m: InboundAppMessage) => void; onState: (s: ConnectionState) => void }) {
    this.opts = opts;
    const kp = generateKeyPair();
    this.ownPriv = kp.priv;
    this.ownPubB64 = b64uEncode(kp.pub);
  }

  connect(): void {
    const url = `${this.opts.relayBase}/ws/relay?role=phone&code=${encodeURIComponent(this.opts.code)}&publicKey=${encodeURIComponent(this.ownPubB64)}`;
    this.opts.onState("pairing");
    this.ws = new WebSocket(url);

    this.ws.onmessage = (event: MessageEvent) => {
      try {
        const msg = JSON.parse(event.data as string);

        if (msg.type === "waiting") {
          this.opts.onState("error");
          this.ws?.close();
          return;
        }

        if (msg.type === "peer_joined" && msg.role === "daemon") {
          this.key = deriveSessionKey(this.ownPriv, msg.peerPublicKey, this.ownPubB64);
          this.opts.onState("connected");
          this.startPing();
          return;
        }

        if (msg.type === "ping") {
          this.ws?.send(JSON.stringify({ type: "pong" }));
          return;
        }

        if (msg.type === "close") {
          this.opts.onState("disconnected");
          this.close();
          return;
        }

        if (msg.type === "message" && this.key) {
          const appMsg = decodeInbound(msg.payload, this.key);
          if (appMsg) {
            this.opts.onMessage(appMsg);
          }
          return;
        }
      } catch {
        // ignore malformed frames
      }
    };

    this.ws.onclose = () => {
      this.opts.onState("disconnected");
      this.stopPing();
    };

    this.ws.onerror = () => {
      this.opts.onState("error");
    };
  }

  sendApprovalResponse(resp: ApprovalResponse): void {
    if (!this.key || !this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("RelayClient not connected");
    }
    this.ws.send(encodeApprovalResponse(resp, this.key));
  }

  disconnect(): void {
    this.close();
    this.opts.onState("disconnected");
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: "ping" }));
      }
    }, 30000);
  }

  private stopPing(): void {
    if (this.pingTimer !== null) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private close(): void {
    this.stopPing();
    this.ws?.close();
    this.ws = null;
    this.key = null;
  }
}
