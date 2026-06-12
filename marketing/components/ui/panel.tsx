import type { ReactNode } from "react";

interface PanelProps {
  children: ReactNode;
  header?: string;
  headerRight?: ReactNode;
  className?: string;
}

export default function Panel({ children, header, headerRight, className = "" }: PanelProps) {
  return (
    <div className={`border border-line bg-raised ${className}`}>
      {header && (
        <div className="flex items-center justify-between px-3 py-2 bg-block border-b border-line">
          <span className="font-mono text-[11px] text-dim">{header}</span>
          {headerRight && (
            <span className="font-mono text-[10px] text-faint">{headerRight}</span>
          )}
        </div>
      )}
      <div>{children}</div>
    </div>
  );
}
