import { cn } from "@/lib/utils"

type Status = "decision" | "blocked" | "running" | "done" | "failed" | "idle"

const statusConfig: Record<Status, { color: string; pulse: boolean }> = {
  decision: { color: "bg-[var(--lancer-red)]", pulse: true },
  blocked: { color: "bg-[var(--lancer-amber)]", pulse: true },
  running: { color: "bg-[var(--lancer-blue)]", pulse: true },
  done: { color: "bg-[var(--lancer-green)]", pulse: false },
  failed: { color: "bg-[var(--lancer-red)]", pulse: false },
  idle: { color: "bg-white/20", pulse: false },
}

export function StatusDot({ status }: { status: Status }) {
  const { color, pulse } = statusConfig[status]
  return (
    <span className="relative flex size-2">
      {pulse && (
        <span
          className={cn("animate-ping absolute inline-flex size-full rounded-full opacity-75", color)}
        />
      )}
      <span className={cn("relative inline-flex rounded-full size-2", color)} />
    </span>
  )
}
