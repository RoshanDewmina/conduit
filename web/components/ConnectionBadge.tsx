import type { ConnectionState } from "@/lib/relay/types";

const dotClass: Record<ConnectionState, string> = {
  disconnected: "bg-[--cc-text4]",
  pairing: "bg-[--cc-warn]",
  connected: "bg-[--cc-ok]",
  error: "bg-[--cc-danger]",
};

export function ConnectionBadge({ state }: { state: ConnectionState }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-xs font-mono text-muted-foreground capitalize">
      <span className={`inline-block w-1.5 h-1.5 rounded-full ${dotClass[state]}`} />
      {state}
    </span>
  );
}
