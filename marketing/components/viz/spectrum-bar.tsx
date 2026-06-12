'use client';

import { useRef, useEffect } from 'react';

type Behavior = 'static' | 'subtle' | 'activity' | 'progress' | 'risk' | 'pertab';
type State = 'idle' | 'connecting' | 'thinking' | 'working' | 'error' | 'done';
type Motion = 'restrained' | 'balanced' | 'expressive';

const SPEC_RGB: [number, number, number][] = [
  [200, 66, 59], [226, 102, 44], [240, 146, 46], [242, 193, 78],
  [199, 123, 166], [126, 79, 181], [84, 96, 200],
];
const RGB: Record<string, [number, number, number]> = {
  blue: [47, 67, 255], green: [54, 194, 107], red: [224, 83, 63],
  amber: [240, 169, 59], grey: [86, 89, 99], white: [255, 255, 255],
};
const MOTION: Record<Motion, { spd: number; amp: number }> = {
  restrained: { spd: 0.55, amp: 0.55 },
  balanced:   { spd: 1.0,  amp: 1.0  },
  expressive: { spd: 1.6,  amp: 1.35 },
};
const mix = (a: [number, number, number], b: [number, number, number], t: number): [number, number, number] =>
  [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
const rgba = (c: [number, number, number], a: number) =>
  `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;

export default function SpectrumBar({
  behavior = 'activity',
  state = 'idle',
  motion = 'balanced',
  height = 4,
  gap = 1.5,
  progress = 0,
  risk = 0,
  tab = null,
  glow = true,
  className,
  style = {},
}: {
  behavior?: Behavior;
  state?: State;
  motion?: Motion;
  height?: number;
  gap?: number;
  progress?: number;
  risk?: number;
  tab?: string | null;
  glow?: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const t0 = useRef(0);
  const stateStart = useRef(0);
  const props = useRef({ behavior, state, motion, progress, risk, tab, glow });

  useEffect(() => {
    props.current = { behavior, state, motion, progress, risk, tab, glow };
  });

  useEffect(() => { stateStart.current = performance.now(); }, [state, behavior, tab]);

  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const ctx = cv.getContext('2d')!;
    t0.current = performance.now();
    if (stateStart.current === 0) stateStart.current = performance.now();
    let raf: number;
    let W = 0, H = 0;
    const dpr = Math.min(2, window.devicePixelRatio || 1);

    const resize = () => {
      const r = cv.getBoundingClientRect();
      W = Math.max(1, r.width);
      H = Math.max(1, r.height);
      cv.width = W * dpr;
      cv.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(cv);

    const n = SPEC_RGB.length;
    const draw = (now: number) => {
      const p = props.current;
      const m = MOTION[p.motion as Motion] || MOTION.balanced;
      const t = ((now - t0.current) / 1000) * m.spd;
      const ts = ((now - stateStart.current) / 1000) * m.spd;
      ctx.clearRect(0, 0, W, H);
      const segW = (W - gap * (n - 1)) / n;

      let beh = p.behavior as Behavior;
      let st = p.state as State;
      const prog = p.progress;
      const rk = p.risk;

      if (beh === 'pertab') {
        if (p.tab === 'inbox') { beh = 'risk'; }
        else if (p.tab === 'hosts') { beh = 'activity'; st = (st === 'error' ? 'error' : st === 'connecting' ? 'connecting' : 'idle'); }
        else if (p.tab === 'settings') { beh = 'activity'; st = 'thinking'; }
        else { beh = 'activity'; }
      }

      let overlay: { type: string } | null = null;

      for (let i = 0; i < n; i++) {
        let rgb = SPEC_RGB[i] as [number, number, number];
        let a = 1;
        const frac = i / (n - 1);
        void frac;

        if (beh === 'static') {
          a = 0.75;
        } else if (beh === 'subtle') {
          a = 0.55 + 0.32 * m.amp * (0.5 + 0.5 * Math.sin(t * 0.9 - i * 0.55));
        } else if (beh === 'progress') {
          const fillEdge = (prog ?? 0) * n;
          if (i + 1 <= fillEdge) { a = 0.95; }
          else if (i < fillEdge) { a = 0.4 + 0.55 * (fillEdge - i) + 0.12 * Math.sin(t * 5); }
          else { rgb = mix(SPEC_RGB[i], RGB.grey, 0.7); a = 0.16; }
        } else if (beh === 'risk') {
          const lit = (rk ?? 0) * n;
          if (i < lit - 1) { a = 0.9; }
          else if (i < lit) { a = 0.45 + 0.5 * (0.5 + 0.5 * Math.sin(t * 3.2)); }
          else { rgb = mix(SPEC_RGB[i], RGB.grey, 0.72); a = 0.15; }
          rgb = mix(rgb, RGB.red, clamp((rk ?? 0) - 0.45) * 0.5);
        } else {
          switch (st) {
            case 'idle':
              rgb = mix(SPEC_RGB[i], RGB.grey, 0.45);
              a = 0.34 + 0.05 * Math.sin(t * 0.8 + i * 0.5);
              break;
            case 'connecting':
              rgb = mix(SPEC_RGB[i], RGB.blue, 0.45);
              a = 0.4;
              overlay = { type: 'scan' };
              break;
            case 'thinking':
              a = 0.45 + 0.42 * m.amp * (0.5 + 0.5 * Math.sin(t * 1.25 + i * 0.72));
              break;
            case 'working': {
              const s = 0.5 + 0.5 * Math.sin(2 * Math.PI * (t / 1.05 - i * 0.105));
              a = 0.42 + 0.58 * m.amp * s;
              break;
            }
            case 'error': {
              rgb = mix(SPEC_RGB[i], RGB.red, 0.78);
              const flash = Math.sin(ts * 6.5 / m.spd * m.spd) > 0.1 ? 1 : 0.34;
              a = (0.45 + 0.2 * Math.sin(t * 3 + i)) * flash;
              break;
            }
            case 'done': {
              const settle = clamp(ts * 1.1);
              rgb = mix(SPEC_RGB[i], RGB.green, settle * 0.9);
              a = clamp(0.5 + 0.45 * settle + 0.08 * Math.sin(t * 1.4 + i * 0.4));
              break;
            }
            default: a = 0.6;
          }
        }

        const x = i * (segW + gap);
        ctx.globalAlpha = clamp(a);
        if (p.glow && a > 0.7) {
          ctx.shadowColor = rgba(rgb, 0.9);
          ctx.shadowBlur = Math.min(6, height * 1.4);
        } else {
          ctx.shadowBlur = 0;
        }
        ctx.fillStyle = rgba(rgb, 1);
        ctx.fillRect(x, 0, segW, H);
      }
      ctx.globalAlpha = 1;
      ctx.shadowBlur = 0;

      if (overlay && overlay.type === 'scan') {
        const band = Math.max(8, W * 0.13);
        const tp = (ts / 1.2) % 1;
        const xx = tp * (W + band) - band;
        const grad = ctx.createLinearGradient(xx, 0, xx + band, 0);
        grad.addColorStop(0, 'rgba(255,255,255,0)');
        grad.addColorStop(0.5, 'rgba(255,255,255,0.92)');
        grad.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = grad;
        ctx.fillRect(xx, 0, band, H);
      }

      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => { cancelAnimationFrame(raf); ro.disconnect(); };
  }, [gap, height, glow]);

  return (
    <canvas
      ref={ref}
      className={className}
      style={{ display: 'block', width: '100%', height, ...style }}
    />
  );
}
