export default function Glyph({
  name,
  size = 22,
  c = 'currentColor',
  sw = 1.7,
}: {
  name: string;
  size?: number;
  c?: string;
  sw?: number;
}) {
  const p = { fill: 'none', stroke: c, strokeWidth: sw, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };
  const g: Record<string, React.ReactNode> = {
    sessions: <g {...p}><path d="M3 5l5 5-5 5"/><path d="M11 16h8"/></g>,
    hosts: <g {...p}><rect x="3" y="4" width="18" height="7" rx="1"/><rect x="3" y="13" width="18" height="7" rx="1"/><path d="M7 7.5h.01M7 16.5h.01"/></g>,
    inbox: <g {...p}><path d="M3 13l3-9h12l3 9v5a1 1 0 01-1 1H4a1 1 0 01-1-1z"/><path d="M3 13h5l1.5 2.5h5L16 13h5"/></g>,
    settings: <g {...p}><circle cx="12" cy="12" r="3.2"/><path d="M12 2v3M12 19v3M22 12h-3M5 12H2M19 5l-2 2M7 17l-2 2M19 19l-2-2M7 7L5 5"/></g>,
    plus: <g {...p}><path d="M12 5v14M5 12h14"/></g>,
    branch: <g {...p}><circle cx="6" cy="6" r="2.4"/><circle cx="6" cy="18" r="2.4"/><circle cx="18" cy="8" r="2.4"/><path d="M6 8.4v7.2M8.4 6h4.2a3 3 0 013 3v-1"/></g>,
    check: <g {...p}><path d="M4 12l5 5L20 6"/></g>,
    x: <g {...p}><path d="M6 6l12 12M18 6L6 18"/></g>,
    chevron: <g {...p}><path d="M9 5l7 7-7 7"/></g>,
    chevdown: <g {...p}><path d="M5 9l7 7 7-7"/></g>,
    back: <g {...p}><path d="M15 5l-7 7 7 7"/></g>,
    search: <g {...p}><circle cx="11" cy="11" r="7"/><path d="M16 16l5 5"/></g>,
    signal: <g><rect x="1" y="9" width="3" height="5" rx="1" fill={c} stroke="none"/><rect x="6" y="6" width="3" height="8" rx="1" fill={c} stroke="none"/><rect x="11" y="3" width="3" height="11" rx="1" fill={c} stroke="none"/><rect x="16" y="1" width="3" height="13" rx="1" fill={c} stroke="none" opacity=".4"/></g>,
    wifi: <g {...p}><path d="M2 7a14 14 0 0118 0"/><path d="M5 10.5a9 9 0 0112 0"/><path d="M8.5 14a4 4 0 015 0"/><circle cx="11" cy="17" r=".6" fill={c}/></g>,
    bolt: <g><path d="M13 2L4 14h6l-1 8 9-12h-6z" fill={c} stroke="none"/></g>,
    boltslash: <g {...p}><path d="M13 2L4 14h4"/><path d="M11 11l-2 11 7-9"/><path d="M4 4l16 16"/></g>,
    term: <g {...p}><path d="M5 7l4 4-4 4"/><path d="M12 16h6"/></g>,
    play: <g><path d="M7 4l12 8-12 8z" fill={c} stroke="none"/></g>,
    warn: <g {...p}><path d="M12 3l9 16H3z"/><path d="M12 10v4M12 17h.01"/></g>,
    refresh: <g {...p}><path d="M21 12a9 9 0 11-3-6.7L21 8"/><path d="M21 3v5h-5"/></g>,
    cloud: <g {...p}><path d="M6 17a4 4 0 010-8 5.5 5.5 0 0110.5-1.5A4.2 4.2 0 0118 17z"/></g>,
    key: <g {...p}><circle cx="8" cy="8" r="4"/><path d="M11 11l8 8M16 16l2-2M19 19l2-2"/></g>,
    snippet: <g {...p}><path d="M4 6h10M4 12h16M4 18h8"/><path d="M18 5l2 2-2 2"/></g>,
    card: <g {...p}><rect x="2" y="5" width="20" height="14" rx="1"/><path d="M2 9h20"/></g>,
    star: <g {...p}><circle cx="12" cy="12" r="9"/><path d="M12 8l1.3 2.6 2.7.4-2 1.9.5 2.7L12 14.8 9.5 16l.5-2.7-2-1.9 2.7-.4z"/></g>,
    server: <g {...p}><rect x="3" y="4" width="18" height="7" rx="1"/><rect x="3" y="13" width="18" height="7" rx="1"/><path d="M7 7.5h.01M7 16.5h.01"/></g>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0 }}>
      {g[name]}
    </svg>
  );
}
