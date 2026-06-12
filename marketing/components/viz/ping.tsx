export default function Ping({ c = '#36c26b', size = 8 }: { c?: string; size?: number }) {
  return (
    <span style={{ position: 'relative', width: size, height: size, display: 'inline-block', flexShrink: 0 }}>
      <i style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: c }} />
      <i style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: c, animation: 'cdPing 1.8s ease-out infinite' }} />
    </span>
  );
}
